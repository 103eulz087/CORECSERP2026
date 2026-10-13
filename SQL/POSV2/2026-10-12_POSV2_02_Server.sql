/* ================================================================
   POS V2 phases 1-5 (2026-10-12 / 13) - 02: server tables and procedures
   ================================================================
   Plan: docs/plans/2026-10-12_POS_V2_Hybrid_Plan.md (user: all 5 recommendations).
   Needs 01 (types). New objects only: nothing existing changes, the old POS
   (POS/PointOfSale.cs, BatchSales*) is untouched.

   How a sale flows: the terminal saves the whole sale locally (one transaction),
   then its sync worker calls spu_POSV2_PostSale as soon as the server is reachable.
   That procedure is idempotent by SaleGUID (a retry after a dropped connection is
   reported DUPLICATE, nothing is posted twice) and deducts branch stock through the
   FIFO engine (spu_InvFIFO_Deduct, AUTO by sequence, any eligible lot).

   Short stock (user Q3, 2026-10-12): the sale happened, so it is always posted. Under
   the engine's own per-product locks, each line takes what the branch has (in line
   order); the rest is recorded in POSV2_Shortage (Status OPEN) for review, and the
   sale is flagged HasShortage.

   Phase 2 (folded in, 2026-10-12):
     * discounts: POSV2_DiscountType (configurable: senior / PWD 20% VAT-exempt, senior / PWD
       5% basic necessities, other %, one-time amount), POSV2_SaleDiscount (who, ID no.), and
       per line DiscountAmount + VatExemptAmount. The server re-checks every discount line;
     * void after payment: spu_POSV2_VoidSale gives the lots back (spu_InvFIFO_Restore),
       idempotent by SaleGUID like the post;
     * lines removed before payment are counted on the sale (for the Z-reading, phase 3).

   Phase 3 (folded in, 2026-10-13):
     * shifts: POSV2_Shift. The cashier opens a shift on the terminal (beginning cash, even
       offline), every sale belongs to one, and the Z-reading closes it (cash counted). The
       terminal sends SHIFTOPEN / SALE / VOID / SHIFTCLOSE in order; spu_POSV2_CloseShift
       re-derives every figure from the server's own rows and refuses the close if the
       terminal's sale count / void count / net amount differ (a sale still missing);
     * GL once per shift (user Q2): spu_POSV2_PostShiftGL books ONE ticket (mnemonic
       POSV2-SHIFT, every account from JournalEntryMapping, all VAT-exempt per the GL rule),
       legs netted per account. A GL failure (e.g. the month is closed, 59900) never undoes
       the close: the shift is left GLStatus FAILED and spu_POSV2_PostPendingShiftGL (called
       by the terminal's sync every 30 min) tries again;
     * supervisor approval: POSV2_Supervisor (PIN as a PBKDF2 hash, set by an admin). A void,
       a discount type marked RequiresApproval, a cleared sale and a no-sale drawer opening
       need a supervisor's PIN on the terminal (checked offline against the downloaded
       hashes); the server records who approved and refuses an unknown approver;
     * a void is only possible while the sale's shift is open (after the Z-reading: a return,
       phase 4).

   Phase 4 (folded in, 2026-10-13; user: supervisor override over the credit limit, refunds "same as paid"):
     * payments CASH / CARD / CHARGE, split in any mix. Change comes only out of cash. CARD keeps
       its reference (card, last 4, approval code). CHARGE needs the customer: the sale writes the
       AR invoice (TransactionChargeSales, PaymentType CREDIT, InvoiceNo = the OR no.) and its
       ClientLedger debit at once, so Client Payments can collect it; the GL AR leg posts with the
       shift. A charge over the credit limit needs a supervisor (CreditApprovedBy), else it is
       posted with NeedsReview;
     * returns: spu_POSV2_PostReturn, a RETURN event with its own number series (<prefix>-R...).
       Any posted sale of the branch, part or all of a line, with a supervisor. Stock goes back to
       the lots the sale took (newest first; spu_InvFIFO_Restore, ledger 'POS RETURN ...'); a qty
       the sale never deducted (short) closes its shortage instead. Refund "same as paid": to the
       customer's account first (up to the invoice's open balance), then card, then cash from the
       current drawer;
     * a charge sale can be voided only while nothing was paid on its invoice;
     * the shift GL gains CARD (DR 101030105), CHARGE (DR 101030101), and the returns (DR 401 gross
       / CR 40103 discounts / restock DR 101040201 CR 501); the expected cash drops by cash refunds;
     * cash short goes to the new expense 60340 CASH SHORTAGE - POS (user + accountant 2026-10-13).

   Not yet: scanning a stickered lot (LOT mode); reports / BIR (phase 5).
   Errors 61001-61099 (61010+ are permanent refusals: the terminal sets the event aside).
   ================================================================ */

SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;   -- the filtered unique index on POSV2_Shift needs these when the procs are created (sp-reviewer S4)
SET ANSI_NULLS ON;
SET NOCOUNT ON;

IF TYPE_ID('dbo.tt_POSV2_SaleLine') IS NULL OR TYPE_ID('dbo.tt_POSV2_Payment') IS NULL OR TYPE_ID('dbo.tt_POSV2_SaleDiscount') IS NULL
   OR TYPE_ID('dbo.tt_POSV2_ReturnLine') IS NULL
    THROW 61000, 'Run SQL/POSV2/2026-10-12_POSV2_01_Types.sql first.', 1;
IF OBJECT_ID('dbo.spu_InvFIFO_Deduct', 'P') IS NULL OR OBJECT_ID('dbo.sp_InvFIFO_LockProducts', 'P') IS NULL
    THROW 61000, 'The FIFO engine (spu_InvFIFO_Deduct / sp_InvFIFO_LockProducts) is missing.', 1;
IF OBJECT_ID('dbo.GetTicketNumber', 'P') IS NULL OR OBJECT_ID('dbo.JournalEntryMapping', 'U') IS NULL
    THROW 61000, 'GetTicketNumber / JournalEntryMapping is missing.', 1;
IF (SELECT COUNT(DISTINCT AccountCode) FROM dbo.ChartOfAccounts WHERE AccountCode IN ('10101', '401', '40103', '501', '101040201', '404', '101030105', '101030101', '603', '20115')) <> 10
    THROW 61000, 'An account of the POSV2-SHIFT mapping (10101, 401, 40103, 501, 101040201, 404, 101030105, 101030101, 20115, parent 603) is not in ChartOfAccounts.', 1;
IF OBJECT_ID('dbo.TransactionChargeSales', 'U') IS NULL OR OBJECT_ID('dbo.ClientLedger', 'U') IS NULL OR OBJECT_ID('dbo.spu_InvFIFO_Restore', 'P') IS NULL
    THROW 61000, 'TransactionChargeSales / ClientLedger / spu_InvFIFO_Restore is missing.', 1;
IF OBJECT_ID('dbo.POSV2_Sale', 'U') IS NOT NULL
    THROW 61000, 'POS V2 phase 1 is already installed here (POSV2_Sale exists).', 1;
GO

BEGIN TRANSACTION;

-- ── tables ────────────────────────────────────────────────────────
CREATE TABLE dbo.POSV2_Terminal
(
    TerminalID   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_POSV2_Terminal PRIMARY KEY,
    BranchCode   VARCHAR(10)  NOT NULL,
    TerminalCode VARCHAR(50)  NOT NULL,            -- the machine name
    ORPrefix     VARCHAR(12)  NOT NULL,            -- e.g. 001T01: the terminal's own OR series
    MIN          VARCHAR(50)  NULL,                -- not used: the BIR data is POSInfoDetails' (below)
    BIRMachine   VARCHAR(50)  NULL,                -- phase 5: this terminal's POSInfoDetails.MachineUsed on its branch (BIR registration)
    IsActive     BIT          NOT NULL CONSTRAINT DF_POSV2_Terminal_IsActive DEFAULT (1),
    RegisteredAt DATETIME2(0) NOT NULL CONSTRAINT DF_POSV2_Terminal_RegisteredAt DEFAULT (SYSDATETIME()),
    RegisteredBy VARCHAR(60)  NOT NULL,
    LastSeenAt   DATETIME2(0) NULL,
    CONSTRAINT UQ_POSV2_Terminal_Machine UNIQUE (BranchCode, TerminalCode),
    CONSTRAINT UQ_POSV2_Terminal_Prefix UNIQUE (ORPrefix)
);

-- phase 3: one cashier shift on one terminal, opened with the beginning cash and closed by the
-- Z-reading (cash counted). The figures are the server's own, re-derived from its sale rows at close.
CREATE TABLE dbo.POSV2_Shift
(
    ShiftGUID          UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_POSV2_Shift PRIMARY KEY,
    TerminalID         INT           NOT NULL CONSTRAINT FK_POSV2_Shift_Terminal REFERENCES dbo.POSV2_Terminal (TerminalID),
    BranchCode         VARCHAR(10)   NOT NULL,
    ZNo                INT           NOT NULL,          -- the terminal's Z-reading counter (never resets)
    CashierUserID      VARCHAR(50)   NOT NULL,
    CashierName        VARCHAR(100)  NULL,
    OpenedAt           DATETIME2(0)  NOT NULL,          -- terminal clock
    BusinessDate       DATE          NOT NULL,          -- the opening day: the GL ticket's date
    BeginningCash      DECIMAL(18,2) NOT NULL,
    Status             VARCHAR(10)   NOT NULL CONSTRAINT DF_POSV2_Shift_Status DEFAULT ('OPEN'),   -- OPEN / CLOSED
    ClosedAt           DATETIME2(0)  NULL,              -- terminal clock
    ClosedBy           VARCHAR(60)   NULL,
    CloseApprovedBy    VARCHAR(60)   NULL,              -- supervisor, when someone else closed the cashier's shift
    ForcedBy           VARCHAR(60)   NULL,              -- admin who forced it closed (spu_POSV2_ForceCloseShift)
    ForceReason        VARCHAR(300)  NULL,
    CountedCash        DECIMAL(18,2) NULL,
    ExpectedCash       DECIMAL(18,2) NULL,              -- beginning + cash sales
    OverShort          DECIMAL(18,2) NULL,              -- counted - expected (negative = short)
    SaleCount          INT           NULL,              -- every OR of the shift, voided included
    VoidCount          INT           NULL,
    VoidAmount         DECIMAL(18,2) NULL,
    GrossAmount        DECIMAL(18,2) NULL,              -- the figures below: sales not voided
    DiscountAmount     DECIMAL(18,2) NULL,              -- discounts proper (20%, 5%, other, one-time)
    VatExemptAmount    DECIMAL(18,2) NULL,              -- VAT removed for senior / PWD
    NetAmount          DECIMAL(18,2) NULL,
    VatableSales       DECIMAL(18,2) NULL,
    VatAmount          DECIMAL(18,2) NULL,
    VatExemptSales     DECIMAL(18,2) NULL,
    ZeroRatedSales     DECIMAL(18,2) NULL,
    CashSales          DECIMAL(18,2) NULL,              -- cash received less change
    CardSales          DECIMAL(18,2) NULL,              -- phase 4: card payments of the sales not voided
    ChargeSales        DECIMAL(18,2) NULL,              -- phase 4: charged to customers' accounts (AR)
    ReturnCount        INT           NULL,              -- phase 4: returns made in this shift (of any earlier sale)
    ReturnGross        DECIMAL(18,2) NULL,
    ReturnDiscount     DECIMAL(18,2) NULL,              -- discount + VAT exemption of the returned part
    ReturnNet          DECIMAL(18,2) NULL,              -- refunded
    ReturnCost         DECIMAL(18,2) NULL,              -- cost of the lots restocked
    CashRefunds        DECIMAL(18,2) NULL,
    CardRefunds        DECIMAL(18,2) NULL,
    ChargeRefunds      DECIMAL(18,2) NULL,              -- credited to customers' invoices (up to their open balance)
    CustomerCredit     DECIMAL(18,2) NULL,              -- a charge refund above the invoice's open balance (CR 20115, NeedsReview)
    ReturnVatable      DECIMAL(18,2) NULL,              -- phase 5 (BIR): returns split like the sales: VATable net of VAT, its VAT, VAT-exempt
    ReturnVat          DECIMAL(18,2) NULL,
    ReturnExempt       DECIMAL(18,2) NULL,
    AccumulatedBefore  DECIMAL(18,2) NULL,              -- phase 5 (BIR): the terminal's accumulated grand total before / after this Z-reading
    AccumulatedAfter   DECIMAL(18,2) NULL,              -- (never resets; + the shift's net sales; returns and voids don't lower it)
    TerminalAccumulatedAfter DECIMAL(18,2) NULL,        -- what the terminal printed on its Z-reading (a difference is listed in Needs attention)
    BIRMachine         VARCHAR(50)   NULL,              -- the terminal's BIR machine at close: filed months don't move if the mapping is edited later
    CostTotal        DECIMAL(18,2) NULL,              -- cost of the lots taken
    CancelledLineCount  INT           NULL,
    CancelledLineAmount DECIMAL(18,2) NULL,
    ClearedSaleCount   INT           NULL,              -- whole sales cleared before payment (terminal's count)
    ClearedSaleAmount  DECIMAL(18,2) NULL,
    DrawerOpenCount    INT           NULL,              -- no-sale drawer openings (terminal's count)
    FirstORNo          VARCHAR(30)   NULL,
    LastORNo           VARCHAR(30)   NULL,
    GLStatus           VARCHAR(10)   NOT NULL CONSTRAINT DF_POSV2_Shift_GLStatus DEFAULT ('NONE'),  -- NONE (open) / PENDING / POSTED / FAILED
    GLTicketNumber     VARCHAR(20)   NULL,
    GLPostedAt         DATETIME2(0)  NULL,
    GLMessage          NVARCHAR(1000) NULL,
    OpenPostedAt       DATETIME2(0)  NOT NULL CONSTRAINT DF_POSV2_Shift_OpenPostedAt DEFAULT (SYSDATETIME()),
    ClosePostedAt      DATETIME2(0)  NULL,
    CONSTRAINT UQ_POSV2_Shift_Z UNIQUE (TerminalID, ZNo),
    CONSTRAINT CK_POSV2_Shift_Status CHECK (Status IN ('OPEN', 'CLOSED')),
    CONSTRAINT CK_POSV2_Shift_GLStatus CHECK (GLStatus IN ('NONE', 'PENDING', 'POSTED', 'FAILED'))
);
-- at most one open shift per terminal
CREATE UNIQUE INDEX UX_POSV2_Shift_OneOpen ON dbo.POSV2_Shift (TerminalID) WHERE Status = 'OPEN';
CREATE INDEX IX_POSV2_Shift_GL ON dbo.POSV2_Shift (GLStatus, Status);
CREATE INDEX IX_POSV2_Shift_BusinessDate ON dbo.POSV2_Shift (BusinessDate) INCLUDE (Status, GLStatus);   -- BIR reports, the month-close guard

CREATE TABLE dbo.POSV2_Sale
(
    SaleGUID        UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_POSV2_Sale PRIMARY KEY,
    TerminalID      INT           NOT NULL CONSTRAINT FK_POSV2_Sale_Terminal REFERENCES dbo.POSV2_Terminal (TerminalID),
    ShiftGUID       UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_POSV2_Sale_Shift REFERENCES dbo.POSV2_Shift (ShiftGUID),   -- phase 3
    DiscountApprovedBy VARCHAR(60) NULL,             -- phase 3: supervisor for a discount type that needs approval
    VoidApprovedBy  VARCHAR(60)   NULL,
    NeedsReview     BIT           NOT NULL CONSTRAINT DF_POSV2_Sale_NeedsReview DEFAULT (0),   -- phase 3: posted although a rule changed since the sale
    CreditApprovedBy VARCHAR(60)  NULL,              -- phase 4: supervisor for a charge over the credit limit
    ARReferenceNo   VARCHAR(10)   NULL,              -- phase 4: the charge invoice's TransactionChargeSales.ReferenceNo (P + 9 digits)
    ReviewNote      VARCHAR(300)  NULL,
    BranchCode      VARCHAR(10)   NOT NULL,
    ORNo            VARCHAR(30)   NOT NULL,
    SaleDateTime    DATETIME2(0)  NOT NULL,          -- terminal clock, when the sale was paid
    CashierUserID   VARCHAR(50)   NOT NULL,
    CashierName     VARCHAR(100)  NULL,
    CustomerKey     VARCHAR(20)   NULL,
    ItemCount       INT           NOT NULL,
    GrossAmount     DECIMAL(18,2) NOT NULL,          -- sum of Qty x UnitPrice
    DiscountAmount  DECIMAL(18,2) NOT NULL,          -- Gross - Net
    NetAmount       DECIMAL(18,2) NOT NULL,          -- what the customer pays (VAT inclusive)
    VatableSales    DECIMAL(18,2) NOT NULL,          -- VAT items, net of VAT
    VatAmount       DECIMAL(18,2) NOT NULL,
    VatExemptSales  DECIMAL(18,2) NOT NULL,
    ZeroRatedSales  DECIMAL(18,2) NOT NULL,
    AmountTendered  DECIMAL(18,2) NOT NULL,
    ChangeAmount    DECIMAL(18,2) NOT NULL,
    Status          VARCHAR(15)   NOT NULL CONSTRAINT DF_POSV2_Sale_Status DEFAULT ('POSTED'),   -- POSTED / VOIDED
    WasOffline      BIT           NOT NULL,          -- saved while the server was unreachable
    HasShortage     BIT           NOT NULL CONSTRAINT DF_POSV2_Sale_HasShortage DEFAULT (0),
    CancelledLineCount  INT           NOT NULL CONSTRAINT DF_POSV2_Sale_CancelledLineCount DEFAULT (0),    -- removed before payment
    CancelledLineAmount DECIMAL(18,2) NOT NULL CONSTRAINT DF_POSV2_Sale_CancelledLineAmount DEFAULT (0),
    VoidedAt        DATETIME2(0)  NULL,              -- terminal clock
    VoidReason      VARCHAR(300)  NULL,
    VoidedBy        VARCHAR(60)   NULL,
    VoidPostedAt    DATETIME2(0)  NULL,
    TerminalSavedAt DATETIME2(0)  NOT NULL,
    PostedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_POSV2_Sale_PostedAt DEFAULT (SYSDATETIME()),
    PostedBy        VARCHAR(60)   NOT NULL,
    CONSTRAINT UQ_POSV2_Sale_OR UNIQUE (TerminalID, ORNo)
);
CREATE INDEX IX_POSV2_Sale_BranchDate ON dbo.POSV2_Sale (BranchCode, SaleDateTime);
CREATE INDEX IX_POSV2_Sale_Shift ON dbo.POSV2_Sale (ShiftGUID);
-- phase 4 (sp-reviewer B2): the charge invoice's reference must fit the AR screens' 10 characters
-- (splist_ARAccounts OrderNo, ARPaymentDetails.PONumber + its C# parameter are varchar(10)); the OR no. stays in InvoiceNo
CREATE SEQUENCE dbo.seq_POSV2_ARRef AS BIGINT START WITH 1 INCREMENT BY 1 NO CYCLE;

CREATE TABLE dbo.POSV2_SaleLine
(
    SaleGUID     UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_POSV2_SaleLine_Sale REFERENCES dbo.POSV2_Sale (SaleGUID),
    [LineNo]     INT           NOT NULL,
    ProductCode  VARCHAR(50)   NOT NULL,
    Barcode      VARCHAR(150)  NULL,
    Description  VARCHAR(300)  NULL,
    Qty          DECIMAL(18,3) NOT NULL,
    PriceLevel   VARCHAR(10)   NOT NULL,
    UnitPrice    DECIMAL(18,2) NOT NULL,
    LineDiscount DECIMAL(18,2) NOT NULL,
    LineTotal    DECIMAL(18,2) NOT NULL,
    IsVat        BIT           NOT NULL,
    VatAmount    DECIMAL(18,2) NOT NULL,
    DiscNo          INT           NULL,
    DiscountCode    VARCHAR(10)   NULL,
    DiscountAmount  DECIMAL(18,2) NOT NULL CONSTRAINT DF_POSV2_SaleLine_DiscountAmount DEFAULT (0),
    VatExemptAmount DECIMAL(18,2) NOT NULL CONSTRAINT DF_POSV2_SaleLine_VatExemptAmount DEFAULT (0),
    QtyDeducted  DECIMAL(18,3) NOT NULL CONSTRAINT DF_POSV2_SaleLine_QtyDeducted DEFAULT (0),
    QtyShort     DECIMAL(18,3) NOT NULL CONSTRAINT DF_POSV2_SaleLine_QtyShort DEFAULT (0),
    CostTotal    DECIMAL(18,2) NOT NULL CONSTRAINT DF_POSV2_SaleLine_CostTotal DEFAULT (0),   -- of the lots taken
    CONSTRAINT PK_POSV2_SaleLine PRIMARY KEY (SaleGUID, [LineNo])
);

CREATE TABLE dbo.POSV2_SaleLot
(
    SaleLotID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_POSV2_SaleLot PRIMARY KEY,
    SaleGUID       UNIQUEIDENTIFIER NOT NULL,
    [LineNo]       INT           NOT NULL,
    InventorySeqNo INT           NOT NULL,
    Qty            DECIMAL(18,3) NOT NULL,
    Cost           DECIMAL(18,2) NOT NULL,
    CONSTRAINT FK_POSV2_SaleLot_Line FOREIGN KEY (SaleGUID, [LineNo]) REFERENCES dbo.POSV2_SaleLine (SaleGUID, [LineNo])
);
CREATE INDEX IX_POSV2_SaleLot_Sale ON dbo.POSV2_SaleLot (SaleGUID);

CREATE TABLE dbo.POSV2_Payment
(
    SaleGUID    UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_POSV2_Payment_Sale REFERENCES dbo.POSV2_Sale (SaleGUID),
    PayNo       INT           NOT NULL,
    PaymentType VARCHAR(20)   NOT NULL,
    Amount      DECIMAL(18,2) NOT NULL,
    Reference   VARCHAR(100)  NULL,
    CONSTRAINT PK_POSV2_Payment PRIMARY KEY (SaleGUID, PayNo)
);

CREATE TABLE dbo.POSV2_Shortage
(
    ShortageID  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_POSV2_Shortage PRIMARY KEY,
    SaleGUID    UNIQUEIDENTIFIER NOT NULL,
    [LineNo]    INT           NOT NULL,
    BranchCode  VARCHAR(10)   NOT NULL,
    ProductCode VARCHAR(50)   NOT NULL,
    QtySold     DECIMAL(18,3) NOT NULL,
    QtyDeducted DECIMAL(18,3) NOT NULL,
    QtyShort    DECIMAL(18,3) NOT NULL,
    CreatedAt   DATETIME2(0)  NOT NULL CONSTRAINT DF_POSV2_Shortage_CreatedAt DEFAULT (SYSDATETIME()),
    Status      VARCHAR(10)   NOT NULL CONSTRAINT DF_POSV2_Shortage_Status DEFAULT ('OPEN'),
    ResolvedBy  VARCHAR(60)   NULL,
    ResolvedAt  DATETIME2(0)  NULL,
    Remarks     VARCHAR(500)  NULL,
    CONSTRAINT FK_POSV2_Shortage_Line FOREIGN KEY (SaleGUID, [LineNo]) REFERENCES dbo.POSV2_SaleLine (SaleGUID, [LineNo])
);
CREATE INDEX IX_POSV2_Shortage_Open ON dbo.POSV2_Shortage (Status, BranchCode);

-- phase 4: returns of posted sales (any earlier shift / terminal of the branch), with their own number series
CREATE TABLE dbo.POSV2_Return
(
    ReturnGUID      UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_POSV2_Return PRIMARY KEY,
    TerminalID      INT           NOT NULL CONSTRAINT FK_POSV2_Return_Terminal REFERENCES dbo.POSV2_Terminal (TerminalID),
    ShiftGUID       UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_POSV2_Return_Shift REFERENCES dbo.POSV2_Shift (ShiftGUID),   -- the shift that paid it back
    BranchCode      VARCHAR(10)   NOT NULL,
    ReturnNo        VARCHAR(30)   NOT NULL,          -- <terminal prefix>-R<seq>
    OrigSaleGUID    UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_POSV2_Return_Sale REFERENCES dbo.POSV2_Sale (SaleGUID),
    ReturnDateTime  DATETIME2(0)  NOT NULL,          -- terminal clock
    CashierUserID   VARCHAR(50)   NOT NULL,
    CashierName     VARCHAR(100)  NULL,
    ApprovedBy      VARCHAR(60)   NOT NULL,
    Reason          VARCHAR(300)  NOT NULL,
    GrossAmount     DECIMAL(18,2) NOT NULL,
    DiscountAmount  DECIMAL(18,2) NOT NULL,          -- discount + VAT exemption of the returned part
    NetAmount       DECIMAL(18,2) NOT NULL,          -- refunded = cash + card + charge refunds
    VatAmount       DECIMAL(18,2) NOT NULL,
    CashRefund      DECIMAL(18,2) NOT NULL,
    CardRefund      DECIMAL(18,2) NOT NULL,
    ChargeRefund    DECIMAL(18,2) NOT NULL,          -- refunded to the customer's account: taken off the invoice ...
    ChargeExcess    DECIMAL(18,2) NOT NULL CONSTRAINT DF_POSV2_Return_ChargeExcess DEFAULT (0),   -- ... except what was above its open balance (customer credit, 20115)
    CostTotal       DECIMAL(18,2) NOT NULL CONSTRAINT DF_POSV2_Return_CostTotal DEFAULT (0),   -- of the lots restocked
    NeedsReview     BIT           NOT NULL CONSTRAINT DF_POSV2_Return_NeedsReview DEFAULT (0),
    ReviewNote      VARCHAR(300)  NULL,
    TerminalSavedAt DATETIME2(0)  NOT NULL,
    PostedAt        DATETIME2(0)  NOT NULL CONSTRAINT DF_POSV2_Return_PostedAt DEFAULT (SYSDATETIME()),
    PostedBy        VARCHAR(60)   NOT NULL,
    CONSTRAINT UQ_POSV2_Return_No UNIQUE (TerminalID, ReturnNo)
);
CREATE INDEX IX_POSV2_Return_Shift ON dbo.POSV2_Return (ShiftGUID);
CREATE INDEX IX_POSV2_Return_Sale ON dbo.POSV2_Return (OrigSaleGUID);
CREATE INDEX IX_POSV2_Return_Date ON dbo.POSV2_Return (ReturnDateTime) INCLUDE (BranchCode);

CREATE TABLE dbo.POSV2_ReturnLine
(
    ReturnGUID      UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_POSV2_ReturnLine_Return REFERENCES dbo.POSV2_Return (ReturnGUID),
    [LineNo]        INT           NOT NULL,
    OrigLineNo      INT           NOT NULL,
    ProductCode     VARCHAR(50)   NOT NULL,
    Qty             DECIMAL(18,3) NOT NULL,
    GrossAmount     DECIMAL(18,2) NOT NULL,
    DiscountAmount  DECIMAL(18,2) NOT NULL,
    VatExemptAmount DECIMAL(18,2) NOT NULL,
    NetAmount       DECIMAL(18,2) NOT NULL,
    VatAmount       DECIMAL(18,2) NOT NULL,
    QtyRestocked    DECIMAL(18,3) NOT NULL CONSTRAINT DF_POSV2_ReturnLine_QtyRestocked DEFAULT (0),   -- back on the sale's lots
    QtyUnshorted    DECIMAL(18,3) NOT NULL CONSTRAINT DF_POSV2_ReturnLine_QtyUnshorted DEFAULT (0),   -- a qty never deducted: its shortage closes
    CostTotal       DECIMAL(18,2) NOT NULL CONSTRAINT DF_POSV2_ReturnLine_CostTotal DEFAULT (0),
    CONSTRAINT PK_POSV2_ReturnLine PRIMARY KEY (ReturnGUID, [LineNo])
);

CREATE TABLE dbo.POSV2_ReturnLot
(
    ReturnLotID    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_POSV2_ReturnLot PRIMARY KEY,
    ReturnGUID     UNIQUEIDENTIFIER NOT NULL,
    [LineNo]       INT           NOT NULL,
    OrigSaleGUID   UNIQUEIDENTIFIER NOT NULL,
    OrigLineNo     INT           NOT NULL,
    InventorySeqNo INT           NOT NULL,
    Qty            DECIMAL(18,3) NOT NULL,
    Cost           DECIMAL(18,2) NOT NULL,          -- the lot's unit cost at the sale
    CostAmount     DECIMAL(18,2) NOT NULL,          -- this piece's cost (the piece that empties a lot takes what is left of its sale cost)
    CONSTRAINT FK_POSV2_ReturnLot_Line FOREIGN KEY (ReturnGUID, [LineNo]) REFERENCES dbo.POSV2_ReturnLine (ReturnGUID, [LineNo])
);
CREATE INDEX IX_POSV2_ReturnLot_Orig ON dbo.POSV2_ReturnLot (OrigSaleGUID, OrigLineNo);

-- phase 4 (user + accountant 2026-10-13): a cash short is an expense; the chart had no account for it
IF NOT EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE AccountCode = '60340')
    INSERT INTO dbo.ChartOfAccounts (AccountCode, Description, AccountType, LevelNumber, SummaryAccount, GLSL, BranchCode, YearEndIndicator, Nature)
    SELECT '60340', 'CASH SHORTAGE - POS', p.AccountType, p.LevelNumber, p.SummaryAccount, p.GLSL, p.BranchCode, p.YearEndIndicator, p.Nature
    FROM dbo.ChartOfAccounts AS p WHERE p.AccountCode = '60339';   -- same placement as its sibling under 603

-- phase 2: discounts. The types are configuration (the accountant may change rates / add types);
-- the terminal downloads them with the products.
CREATE TABLE dbo.POSV2_DiscountType
(
    DiscountCode VARCHAR(10)  NOT NULL CONSTRAINT PK_POSV2_DiscountType PRIMARY KEY,
    Name         VARCHAR(100) NOT NULL,
    Kind         VARCHAR(10)  NOT NULL CONSTRAINT CK_POSV2_DiscountType_Kind CHECK (Kind IN ('PCT', 'PCT_OPEN', 'AMOUNT')),
    [Percent]    DECIMAL(9,4) NOT NULL CONSTRAINT DF_POSV2_DiscountType_Percent DEFAULT (0),   -- PCT: fixed rate
    VatExempt    BIT          NOT NULL CONSTRAINT DF_POSV2_DiscountType_VatExempt DEFAULT (0), -- VAT removed first (senior / PWD)
    RequiresID   BIT          NOT NULL CONSTRAINT DF_POSV2_DiscountType_RequiresID DEFAULT (0),
    IsActive     BIT          NOT NULL CONSTRAINT DF_POSV2_DiscountType_IsActive DEFAULT (1),
    SortOrder    INT          NOT NULL CONSTRAINT DF_POSV2_DiscountType_SortOrder DEFAULT (0),
    RequiresApproval BIT      NOT NULL CONSTRAINT DF_POSV2_DiscountType_RequiresApproval DEFAULT (0)   -- phase 3: supervisor PIN
);
INSERT INTO dbo.POSV2_DiscountType (DiscountCode, Name, Kind, [Percent], VatExempt, RequiresID, SortOrder, RequiresApproval) VALUES
    ('SC20',    'Senior citizen 20% (VAT-exempt)',            'PCT',      20, 1, 1, 10, 0),
    ('PWD20',   'PWD 20% (VAT-exempt)',                       'PCT',      20, 1, 1, 20, 0),
    ('SC5',     'Senior citizen 5% (basic necessities)',      'PCT',       5, 0, 1, 30, 0),
    ('PWD5',    'PWD 5% (basic necessities)',                 'PCT',       5, 0, 1, 40, 0),
    ('OTHER',   'Other discount (%)',                         'PCT_OPEN',  0, 0, 0, 50, 1),
    ('ONETIME', 'One-time discount (amount)',                 'AMOUNT',    0, 0, 0, 60, 1);

-- phase 3: who may approve on a terminal. The PIN is never stored, only its PBKDF2 hash
-- (Classes/PasswordHasher, same as the login passwords); terminals download the hashes so an
-- approval works offline. A PIN is separate from the login password on purpose: a copied
-- terminal database exposes POS approvals only, never a login.
CREATE TABLE dbo.POSV2_Supervisor
(
    UserID        VARCHAR(50)    NOT NULL CONSTRAINT PK_POSV2_Supervisor PRIMARY KEY,
    BranchCode    VARCHAR(10)    NULL,                 -- NULL = every branch
    PinHash       VARBINARY(32)  NOT NULL,
    PinSalt       VARBINARY(16)  NOT NULL,
    PinIterations INT            NOT NULL,
    IsActive      BIT            NOT NULL CONSTRAINT DF_POSV2_Supervisor_IsActive DEFAULT (1),
    UpdatedAt     DATETIME2(0)   NOT NULL CONSTRAINT DF_POSV2_Supervisor_UpdatedAt DEFAULT (SYSDATETIME()),
    UpdatedBy     VARCHAR(60)    NOT NULL
);
-- every supervisor change, with what the server itself knows about the caller (sp-reviewer B2)
CREATE TABLE dbo.POSV2_SupervisorLog
(
    LogID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_POSV2_SupervisorLog PRIMARY KEY,
    UserID     VARCHAR(50)   NOT NULL,
    BranchCode VARCHAR(10)   NULL,            -- as asked: NULL = kept, '' = every branch
    IsActive   BIT           NOT NULL,
    PinChanged BIT           NOT NULL,
    ChangedBy  VARCHAR(60)   NOT NULL,        -- the app user (sent by the client)
    LoginName  NVARCHAR(128) NOT NULL CONSTRAINT DF_POSV2_SupervisorLog_Login DEFAULT (SUSER_SNAME()),
    HostName   NVARCHAR(128) NULL CONSTRAINT DF_POSV2_SupervisorLog_Host DEFAULT (HOST_NAME()),
    ChangedAt  DATETIME2(0)  NOT NULL CONSTRAINT DF_POSV2_SupervisorLog_At DEFAULT (SYSDATETIME())
);

-- phase 3 / 4: the shift's GL ticket (user Q2: once per shift). Every leg's account is configuration
-- (CLAUDE.md: never hard-coded in a proc); the accountant may repoint any row. All VAT-exempt
-- (the GL rule since 2026-10-01: VAT only on the printed receipt). Amount types, per shift, sales
-- not voided:
--   CASH      cash counted - beginning cash (= cash sales - cash refunds + over - short)
--   CARD      card payments - card refunds  CHARGE  charged to accounts - charge refunds (AR)
--   DISCOUNT  discounts proper              VATEXEMPT  VAT removed for senior / PWD (user 2026-10-13: 40103)
--   GROSS     sales at price                COST       cost of the lots taken
--   RETGROSS  returned sales at price       RETDISC    discount + VAT exemption of the returned part
--   RETCOST   cost of the lots restocked
--   CUSTCREDIT a charge refund above the invoice's open balance (the customer's credit, 20115)
--   SHORT     expected - counted, if short (user + accountant 2026-10-13: an expense, 60340)
--   OVER      counted - expected, if over
-- DR CASH + CARD + CHARGE + DISCOUNT + VATEXEMPT + RETGROSS + SHORT + COST + RETCOST
--  = CR GROSS + RETDISC + CUSTCREDIT + OVER + COST + RETCOST.
-- Each row is added only when missing (Origin, Mnemonic, Seq), so an accountant's repointing is kept.
DECLARE @Map TABLE (Seq TINYINT, DC CHAR(1), Acct VARCHAR(50), AcctDesc VARCHAR(200), Cond BIT, Notes VARCHAR(500), AmtType VARCHAR(30));
INSERT INTO @Map VALUES
    ( 1, 'D', '10101',     'Cash on Hand',               0, 'Cash counted less beginning cash', 'CASH'),
    ( 2, 'D', '40103',     'Sales Discount',             0, 'Discounts given (senior / PWD 20% or 5%, other, one-time)', 'DISCOUNT'),
    ( 3, 'D', '40103',     'Sales Discount',             0, 'VAT removed for senior / PWD (the GL is VAT-exempt)', 'VATEXEMPT'),
    ( 4, 'C', '401',       'Sales - VAT Exempt',         0, 'Sales at price, voided sales excluded', 'GROSS'),
    ( 5, 'D', '501',       'COS - VAT Exempt',           0, 'Cost of the lots taken by the shift''s sales', 'COST'),
    ( 6, 'C', '101040201', 'Inventory - VAT Exempt',     0, 'Cost of the lots taken by the shift''s sales', 'COST'),
    ( 7, 'D', '60340',     'Cash Shortage - POS',        1, 'Cash short (an expense: user + accountant 2026-10-13)', 'SHORT'),
    ( 8, 'C', '404',       'Other Income',               1, 'Cash over', 'OVER'),
    ( 9, 'D', '101030105', 'AR - Credit Card',           1, 'Card payments less card refunds', 'CARD'),
    (10, 'D', '101030101', 'AR - Trade',                 1, 'Charged to customers'' accounts less charge refunds (TransactionChargeSales)', 'CHARGE'),
    (11, 'D', '401',       'Sales - VAT Exempt',         1, 'Returned sales at price (same as sales-order returns)', 'RETGROSS'),
    (12, 'C', '40103',     'Sales Discount',             1, 'Discount + VAT exemption of the returned part', 'RETDISC'),
    (13, 'D', '101040201', 'Inventory - VAT Exempt',     1, 'Cost of the lots restocked by returns', 'RETCOST'),
    (14, 'C', '501',       'COS - VAT Exempt',           1, 'Cost of the lots restocked by returns', 'RETCOST'),
    (15, 'C', '20115',     'Customer Advances / Overpayments', 1, 'A charge refund above the invoice''s open balance: the customer''s credit (as sales-order returns)', 'CUSTCREDIT');
INSERT INTO dbo.JournalEntryMapping
    (Origin, Mnemonic, Description, Seq, DebitCredit, AccountCode, AccountDescription, IsConditional, IsAmountFromSource, IsActive, Notes, AmountType)
SELECT 'POSV2', 'POSV2-SHIFT', 'POS V2 shift sales + COGS (Z-reading)', m.Seq, m.DC, m.Acct, m.AcctDesc, m.Cond, 1, 1, m.Notes, m.AmtType
FROM @Map AS m
WHERE NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping AS j WHERE j.Origin = 'POSV2' AND j.Mnemonic = 'POSV2-SHIFT' AND j.Seq = m.Seq);

CREATE TABLE dbo.POSV2_SaleDiscount
(
    SaleGUID        UNIQUEIDENTIFIER NOT NULL CONSTRAINT FK_POSV2_SaleDiscount_Sale REFERENCES dbo.POSV2_Sale (SaleGUID),
    DiscNo          INT           NOT NULL,
    DiscountCode    VARCHAR(10)   NOT NULL CONSTRAINT FK_POSV2_SaleDiscount_Type REFERENCES dbo.POSV2_DiscountType (DiscountCode),
    [Percent]       DECIMAL(9,4)  NOT NULL,
    Amount          DECIMAL(18,2) NOT NULL,
    VatExemptAmount DECIMAL(18,2) NOT NULL,
    CustomerName    VARCHAR(150)  NULL,
    IDNo            VARCHAR(50)   NULL,
    TIN             VARCHAR(30)   NULL,
    Remarks         VARCHAR(300)  NULL,
    CONSTRAINT PK_POSV2_SaleDiscount PRIMARY KEY (SaleGUID, DiscNo)
);
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── terminal registration ─────────────────────────────────────────
CREATE PROCEDURE dbo.spu_POSV2_RegisterTerminal
    @BranchCode   VARCHAR(10),
    @TerminalCode VARCHAR(50),
    @User         VARCHAR(60),
    @BIRMachine   VARCHAR(50) = NULL    -- phase 5: this machine's POSInfoDetails.MachineUsed (blank = keep)
AS
/*  Returns the terminal's ID and OR prefix, registering it on first use. LastORSeq =
    the highest OR sequence this terminal has posted, so a reinstalled terminal can
    resume its series. Caller: POSV2 PosSyncService. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @BranchCode = LTRIM(RTRIM(ISNULL(@BranchCode, '')));
    SET @TerminalCode = LTRIM(RTRIM(ISNULL(@TerminalCode, '')));
    IF @BranchCode = '' OR @TerminalCode = '' THROW 61001, 'Branch and terminal are required.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchCode = @BranchCode)
        THROW 61002, 'Unknown branch.', 1;

    BEGIN TRAN;
    DECLARE @lock INT;
    EXEC @lock = sp_getapplock @Resource = 'POSV2TERMINAL', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
    IF @lock < 0 THROW 61003, 'The server is busy registering another terminal; try again.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.POSV2_Terminal WHERE BranchCode = @BranchCode AND TerminalCode = @TerminalCode)
    BEGIN
        DECLARE @n INT = 1 + (SELECT COUNT(*) FROM dbo.POSV2_Terminal WHERE BranchCode = @BranchCode);
        DECLARE @prefix VARCHAR(12) = @BranchCode + 'T' + RIGHT('0' + CAST(@n AS VARCHAR(5)), 2);
        WHILE EXISTS (SELECT 1 FROM dbo.POSV2_Terminal WHERE ORPrefix = @prefix)
        BEGIN
            SET @n += 1;
            SET @prefix = @BranchCode + 'T' + RIGHT('0' + CAST(@n AS VARCHAR(5)), 2);
        END
        INSERT INTO dbo.POSV2_Terminal (BranchCode, TerminalCode, ORPrefix, RegisteredBy)
        VALUES (@BranchCode, @TerminalCode, @prefix, LEFT(ISNULL(@User, ''), 60));
    END

    UPDATE dbo.POSV2_Terminal SET LastSeenAt = SYSDATETIME(), BIRMachine = ISNULL(NULLIF(LTRIM(RTRIM(@BIRMachine)), ''), BIRMachine)
    WHERE BranchCode = @BranchCode AND TerminalCode = @TerminalCode;
    COMMIT TRAN;

    DECLARE @tid INT, @pfx VARCHAR(12);
    SELECT @tid = TerminalID, @pfx = ORPrefix FROM dbo.POSV2_Terminal WHERE BranchCode = @BranchCode AND TerminalCode = @TerminalCode;
    DECLARE @last BIGINT = ISNULL((SELECT MAX(TRY_CAST(SUBSTRING(ORNo, LEN(@pfx) + 2, 30) AS BIGINT))
                                   FROM dbo.POSV2_Sale WHERE TerminalID = @tid), 0);

    -- phase 3: the Z counter resumes too, and a reinstalled terminal learns about a shift still open here
    DECLARE @lastZ INT = ISNULL((SELECT MAX(ZNo) FROM dbo.POSV2_Shift WHERE TerminalID = @tid), 0);
    -- phase 4: the return series resumes too (UI review S4)
    DECLARE @lastR BIGINT = ISNULL((SELECT MAX(TRY_CAST(SUBSTRING(ReturnNo, LEN(@pfx) + 3, 30) AS BIGINT)) FROM dbo.POSV2_Return WHERE TerminalID = @tid), 0);

    SELECT t.TerminalID, t.BranchCode, t.TerminalCode, t.ORPrefix, t.MIN, t.IsActive, @last AS LastORSeq, @lastZ AS LastZNo, @lastR AS LastReturnSeq,
           -- phase 5: the accumulated grand total resumes too, and the BIR registration printed on receipts and Z-readings
           ISNULL((SELECT TOP 1 s2.AccumulatedAfter FROM dbo.POSV2_Shift AS s2 WHERE s2.TerminalID = t.TerminalID AND s2.Status = 'CLOSED' AND s2.AccumulatedAfter IS NOT NULL ORDER BY s2.ZNo DESC), 0) AS LastAccumulated,
           t.BIRMachine, b.BusinessName, b.BusinessAddress, b.TINNo, b.MINNo, b.SerialNo, b.AccreditationNo, b.DateIssued, b.PermitNumber, b.DatePermitStart, b.DatePermitEnd,
           o.ShiftGUID AS OpenShiftGUID, o.ZNo AS OpenShiftZNo, o.CashierUserID AS OpenShiftCashier
    FROM dbo.POSV2_Terminal AS t
    OUTER APPLY (SELECT TOP 1 i.BusinessName, i.BusinessAddress, i.TINNo, i.MINNo, i.SerialNo, i.AccreditationNo, i.DateIssued, i.PermitNumber, i.DatePermitStart, i.DatePermitEnd
                 FROM dbo.POSInfoDetails AS i WHERE i.BranchCode = t.BranchCode AND i.MachineUsed = t.BIRMachine ORDER BY i.DatePermitEnd DESC, i.DateIssued DESC) AS b
    OUTER APPLY (SELECT TOP 1 s.ShiftGUID, s.ZNo, s.CashierUserID FROM dbo.POSV2_Shift AS s
                 WHERE s.TerminalID = t.TerminalID AND s.Status = 'OPEN') AS o
    WHERE t.TerminalID = @tid;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── master data for the terminal ──────────────────────────────────
CREATE PROCEDURE dbo.sp_POSV2_GetProducts
    @BranchCode VARCHAR(10)
AS
/*  The branch's products and prices for the terminal's local copy. VAT follows the
    product's category, as the old POS did (sp_AddSalesInvoice), else the product flag. */
BEGIN
    SET NOCOUNT ON;
    SELECT p.ProductCode, p.Description, ISNULL(p.Barcode, '') AS Barcode,
           CAST(ISNULL(p.SellingPrice, 0) AS DECIMAL(18,2)) AS SellingPrice,
           CAST(ISNULL(p.Price1, 0) AS DECIMAL(18,2)) AS Price1,
           CAST(ISNULL(p.Price2, 0) AS DECIMAL(18,2)) AS Price2,
           CAST(ISNULL(p.Price3, 0) AS DECIMAL(18,2)) AS Price3,
           CAST(ISNULL(p.Price4, 0) AS DECIMAL(18,2)) AS Price4,
           CAST(ISNULL(c.isVat, ISNULL(p.isVat, 0)) AS BIT) AS IsVat,
           p.ProductCategoryCode AS CategoryCode
    FROM dbo.Products AS p
    LEFT JOIN dbo.ProductCategory AS c ON c.ProductCategoryID = p.ProductCategoryCode
    WHERE p.BranchCode = @BranchCode
    ORDER BY p.ProductCode;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.sp_POSV2_GetStock
    @BranchCode VARCHAR(10)
AS
/*  What the branch can still sell, per product (lots the FIFO engine may take). For the
    terminal's warning only: the server deducts from live stock when the sale posts. */
BEGIN
    SET NOCOUNT ON;
    SELECT i.Product AS ProductCode, CAST(SUM(i.Available) AS DECIMAL(18,3)) AS Available
    FROM dbo.fn_InvEligibleLots(@BranchCode) AS e
    INNER JOIN dbo.Inventory AS i ON i.SequenceNumber = e.SequenceNumber
    WHERE i.Available > 0 AND i.IsWarehouse = 1
    GROUP BY i.Product;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.sp_POSV2_GetDiscountTypes
AS
/*  The active discount types, for the terminal's local copy (phase 2). */
BEGIN
    SET NOCOUNT ON;
    SELECT DiscountCode, Name, Kind, [Percent], VatExempt, RequiresID, SortOrder, RequiresApproval
    FROM dbo.POSV2_DiscountType
    WHERE IsActive = 1
    ORDER BY SortOrder, DiscountCode;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── post one sale ─────────────────────────────────────────────────
CREATE PROCEDURE dbo.spu_POSV2_PostSale
    @SaleGUID        UNIQUEIDENTIFIER,
    @TerminalID      INT,
    @ORNo            VARCHAR(30),
    @SaleDateTime    DATETIME2(0),
    @CashierUserID   VARCHAR(50),
    @CashierName     VARCHAR(100),
    @CustomerKey     VARCHAR(20) = NULL,
    @GrossAmount     DECIMAL(18,2),
    @DiscountAmount  DECIMAL(18,2),
    @NetAmount       DECIMAL(18,2),
    @VatableSales    DECIMAL(18,2),
    @VatAmount       DECIMAL(18,2),
    @VatExemptSales  DECIMAL(18,2),
    @ZeroRatedSales  DECIMAL(18,2),
    @AmountTendered  DECIMAL(18,2),
    @ChangeAmount    DECIMAL(18,2),
    @WasOffline      BIT,
    @TerminalSavedAt DATETIME2(0),
    @Lines           dbo.tt_POSV2_SaleLine READONLY,
    @Payments        dbo.tt_POSV2_Payment READONLY,
    @User            VARCHAR(60),
    @Discounts       dbo.tt_POSV2_SaleDiscount READONLY,   -- phase 2 (empty = no discount)
    @CancelledLineCount  INT = 0,                          -- phase 2: lines removed before payment
    @CancelledLineAmount DECIMAL(18,2) = 0,
    @ShiftGUID           UNIQUEIDENTIFIER = NULL,          -- phase 3: required (a sale outside a shift never reaches the GL)
    @DiscountApprovedBy  VARCHAR(60) = NULL,               -- phase 3: supervisor, when a discount type needs approval
    @CreditApprovedBy    VARCHAR(60) = NULL                -- phase 4: supervisor, when a charge goes over the credit limit
AS
/*  Posts one sale saved on a terminal and deducts the branch's FIFO stock, all or
    nothing. Idempotent by @SaleGUID: a sale already posted returns Result DUPLICATE and
    changes nothing. Returns one row: Result (POSTED / DUPLICATE), ShortLines, Message.
    Validation errors (61010-61020) are permanent: the terminal marks the outbox entry
    as needing attention instead of retrying. Caller: POSV2 PosSyncService. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @msg NVARCHAR(400), @Branch VARCHAR(10), @Prefix VARCHAR(12), @Active BIT;

    -- already posted: nothing to do (also covers a retry after a lost reply)
    IF EXISTS (SELECT 1 FROM dbo.POSV2_Sale WHERE SaleGUID = @SaleGUID)
    BEGIN
        SELECT 'DUPLICATE' AS Result, (SELECT COUNT(*) FROM dbo.POSV2_Shortage WHERE SaleGUID = @SaleGUID) AS ShortLines,
               'Already posted.' AS Message;
        RETURN;
    END

    SELECT @Branch = BranchCode, @Prefix = ORPrefix, @Active = IsActive FROM dbo.POSV2_Terminal WHERE TerminalID = @TerminalID;
    IF @Branch IS NULL THROW 61010, 'Unknown terminal.', 1;
    IF @Active = 0 THROW 61011, 'This terminal is deactivated on the server.', 1;
    IF ISNULL(@ORNo, '') NOT LIKE @Prefix + '-%'
    BEGIN
        SET @msg = N'OR number ' + ISNULL(@ORNo, N'(none)') + N' is not in this terminal''s series (' + @Prefix + N'-...).';
        THROW 61012, @msg, 1;
    END
    IF NOT EXISTS (SELECT 1 FROM @Lines) THROW 61013, 'A sale needs at least one line.', 1;
    IF EXISTS (SELECT 1 FROM @Lines WHERE Qty <= 0 OR UnitPrice < 0 OR LineDiscount < 0 OR LineTotal < 0)
        THROW 61014, 'A line has a zero / negative quantity or a negative amount.', 1;
    -- phase 3: the money identities are exact (the terminal rounds the same way), so a shift's gross - discounts = net = cash always holds at close
    IF EXISTS (SELECT 1 FROM @Lines WHERE ROUND(Qty * UnitPrice, 2) - LineDiscount <> LineTotal)
        THROW 61015, 'A line total is not quantity x price - discount.', 1;

    -- header = its lines (VAT-inclusive prices: VATable sales are net of VAT)
    DECLARE @sumGross DECIMAL(18,2), @sumNet DECIMAL(18,2), @sumVat DECIMAL(18,2), @sumVatable DECIMAL(18,2), @sumExempt DECIMAL(18,2), @cnt INT;
    SELECT @sumGross = SUM(ROUND(Qty * UnitPrice, 2)), @sumNet = SUM(LineTotal),
           @sumVat = SUM(CASE WHEN IsVat = 1 THEN VatAmount ELSE 0 END),
           @sumVatable = SUM(CASE WHEN IsVat = 1 THEN LineTotal - VatAmount ELSE 0 END),
           @sumExempt = SUM(CASE WHEN IsVat = 0 THEN LineTotal ELSE 0 END),
           @cnt = COUNT(*)
    FROM @Lines;
    IF @sumGross <> @GrossAmount OR @sumNet <> @NetAmount OR @GrossAmount - @NetAmount <> @DiscountAmount
        THROW 61016, 'The sale totals don''t match its lines.', 1;
    -- phase 5 review (S1 / S10): exact, so the shift's (and BIR's) VATable + VAT + exempt always = net. A line has no
    -- zero-rated flag, so POS V2 has no zero-rated sales (the terminal sends 0); a return can't mis-split one.
    IF @sumVat <> @VatAmount OR @sumVatable <> @VatableSales OR @sumExempt <> @VatExemptSales OR ISNULL(@ZeroRatedSales, -1) <> 0
        THROW 61017, 'The VAT breakdown doesn''t match the lines (VATable = lines net of VAT, VAT = lines'' VAT, exempt = non-VAT lines, zero-rated = 0).', 1;
    IF (SELECT ISNULL(SUM(Amount), 0) FROM @Payments) <> @AmountTendered
       OR @AmountTendered < @NetAmount OR @AmountTendered - @NetAmount <> @ChangeAmount
        THROW 61018, 'The payment doesn''t cover the sale, or the change is wrong.', 1;
    -- phase 4: CASH / CARD / CHARGE in any mix; change only out of cash; one charge, to a customer; a card keeps its reference
    DECLARE @payCash DECIMAL(18,2), @payCard DECIMAL(18,2), @payCharge DECIMAL(18,2);
    SELECT @payCash = ISNULL(SUM(CASE WHEN PaymentType = 'CASH' THEN Amount END), 0),
           @payCard = ISNULL(SUM(CASE WHEN PaymentType = 'CARD' THEN Amount END), 0),
           @payCharge = ISNULL(SUM(CASE WHEN PaymentType = 'CHARGE' THEN Amount END), 0)
    FROM @Payments;
    IF EXISTS (SELECT 1 FROM @Payments WHERE PaymentType NOT IN ('CASH', 'CARD', 'CHARGE') OR Amount <= 0)
        THROW 61019, 'A payment is not CASH / CARD / CHARGE, or its amount is not positive.', 1;
    IF @ChangeAmount > @payCash
        THROW 61019, 'Change can only come out of cash (a card or charge payment can''t be more than what is left to pay).', 1;
    IF (SELECT COUNT(*) FROM @Payments WHERE PaymentType = 'CHARGE') > 1
        THROW 61019, 'A sale takes one charge payment.', 1;
    IF EXISTS (SELECT 1 FROM @Payments WHERE PaymentType = 'CARD' AND ISNULL(LTRIM(Reference), '') = '')
        THROW 61036, 'A card payment needs its reference (card, last 4 digits, approval code).', 1;
    SET @CustomerKey = NULLIF(LTRIM(RTRIM(@CustomerKey)), '');
    IF @payCharge > 0 AND @CustomerKey IS NULL
        THROW 61034, 'A charge payment needs the customer.', 1;
    DECLARE @custActive BIT, @custLimit DECIMAL(18,2), @custTerm INT, @custName VARCHAR(150);
    IF @payCharge > 0
    BEGIN
        SELECT @custActive = ISNULL(isActive, 0), @custLimit = ISNULL(CustomerCreditLimit, 0), @custTerm = ISNULL(Term, 0), @custName = CustomerName
        FROM dbo.Customers WHERE CustomerKey = @CustomerKey;
        IF @custActive IS NULL THROW 61035, 'The charge customer is not on the server.', 1;
    END
    SET @CreditApprovedBy = NULLIF(LTRIM(RTRIM(@CreditApprovedBy)), '');

    -- ── phase 2: discounts, re-checked line by line ──────────────
    IF EXISTS (SELECT 1 FROM @Lines WHERE DiscountAmount < 0 OR VatExemptAmount < 0 OR DiscountAmount + VatExemptAmount <> LineDiscount)
        THROW 61022, 'A line''s discount + VAT exemption is not its total line discount.', 1;
    IF EXISTS (SELECT 1 FROM @Lines AS l WHERE (l.LineDiscount > 0 OR l.DiscNo IS NOT NULL)
                                          AND NOT EXISTS (SELECT 1 FROM @Discounts AS d WHERE d.DiscNo = l.DiscNo AND d.DiscountCode = l.DiscountCode))
        THROW 61023, 'A discounted line doesn''t point to one of the sale''s discounts.', 1;
    -- Phase 3 (sp-reviewer B3): configuration that may have changed since an offline sale (a type deactivated, a fixed
    -- rate changed, an ID or an approval newly required) does NOT refuse the sale: refusing would strand it, and its
    -- shift's close, for good. The sale is posted with NeedsReview = 1 and the reason. The arithmetic stays exact (61027 / 61028).
    DECLARE @review VARCHAR(300) = '';
    IF EXISTS (SELECT 1 FROM @Discounts AS d LEFT JOIN dbo.POSV2_DiscountType AS t ON t.DiscountCode = d.DiscountCode WHERE t.DiscountCode IS NULL)
        THROW 61024, 'A discount type is unknown on the server.', 1;
    IF EXISTS (SELECT 1 FROM @Discounts AS d INNER JOIN dbo.POSV2_DiscountType AS t ON t.DiscountCode = d.DiscountCode WHERE t.IsActive = 0)
        SET @review += 'discount type no longer active; ';
    IF EXISTS (SELECT 1 FROM @Discounts AS d INNER JOIN dbo.POSV2_DiscountType AS t ON t.DiscountCode = d.DiscountCode
               WHERE t.RequiresID = 1 AND (ISNULL(LTRIM(d.CustomerName), '') = '' OR ISNULL(LTRIM(d.IDNo), '') = ''))
        SET @review += 'senior / PWD discount without the customer''s name or ID no.; ';
    -- the rate: 0-100 for PCT / PCT_OPEN, none for AMOUNT (refused: never a configuration change); a PCT rate other
    -- than the type's current one is flagged; the base is the VAT-exclusive price when the type is VAT-exempt
    IF EXISTS (SELECT 1 FROM @Discounts AS d INNER JOIN dbo.POSV2_DiscountType AS t ON t.DiscountCode = d.DiscountCode
               WHERE (t.Kind IN ('PCT', 'PCT_OPEN') AND (d.[Percent] <= 0 OR d.[Percent] > 100)) OR (t.Kind = 'AMOUNT' AND d.[Percent] <> 0))
        THROW 61026, 'A discount rate is out of range for its type.', 1;
    IF EXISTS (SELECT 1 FROM @Discounts AS d INNER JOIN dbo.POSV2_DiscountType AS t ON t.DiscountCode = d.DiscountCode
               WHERE t.Kind = 'PCT' AND d.[Percent] <> t.[Percent])
        SET @review += 'discount rate differs from the type''s current rate; ';
    IF EXISTS (SELECT 1
               FROM @Lines AS l
               INNER JOIN @Discounts AS d ON d.DiscNo = l.DiscNo
               INNER JOIN dbo.POSV2_DiscountType AS t ON t.DiscountCode = d.DiscountCode
               CROSS APPLY (SELECT ROUND(l.Qty * l.UnitPrice, 2) AS Gross) AS g
               WHERE (t.VatExempt = 1 AND l.VatExemptAmount > 0
                      AND (l.IsVat = 1 OR ABS(ROUND(g.Gross / 1.12, 2) - (g.Gross - l.VatExemptAmount)) > 0.01
                           OR ABS(ROUND((g.Gross - l.VatExemptAmount) * d.[Percent] / 100, 2) - l.DiscountAmount) > 0.01))
                  OR (t.Kind <> 'AMOUNT' AND l.VatExemptAmount = 0 AND ABS(ROUND(g.Gross * d.[Percent] / 100, 2) - l.DiscountAmount) > 0.01)
                  OR (t.VatExempt = 0 AND l.VatExemptAmount <> 0))
        THROW 61027, 'A discounted line is not computed by its discount''s rule.', 1;
    IF EXISTS (SELECT 1 FROM @Discounts AS d
               OUTER APPLY (SELECT SUM(DiscountAmount) AS A, SUM(VatExemptAmount) AS V FROM @Lines AS l WHERE l.DiscNo = d.DiscNo) AS s
               WHERE ABS(ISNULL(s.A, 0) - d.Amount) > 0.01 OR ABS(ISNULL(s.V, 0) - d.VatExemptAmount) > 0.01)
        THROW 61028, 'A discount''s total is not the sum of its lines.', 1;
    IF @CancelledLineCount < 0 OR @CancelledLineAmount < 0
        THROW 61029, 'The cancelled-line count / amount can''t be negative.', 1;

    -- ── phase 3: the shift and the approver ──────────────────────
    IF @ShiftGUID IS NULL THROW 61030, 'A sale needs its shift (open a shift on the terminal first).', 1;
    SET @DiscountApprovedBy = NULLIF(LTRIM(RTRIM(@DiscountApprovedBy)), '');
    -- the terminal asks for the PIN by its own copy of the types; a type switched to "needs approval" since is flagged (B3)
    IF @DiscountApprovedBy IS NULL
       AND EXISTS (SELECT 1 FROM @Discounts AS d INNER JOIN dbo.POSV2_DiscountType AS t ON t.DiscountCode = d.DiscountCode WHERE t.RequiresApproval = 1)
        SET @review += 'discount needing approval posted without an approver; ';
    -- the approver must be a supervisor on record for this branch (an approver deactivated after an offline approval still is)
    IF @DiscountApprovedBy IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.POSV2_Supervisor WHERE UserID = @DiscountApprovedBy AND (BranchCode IS NULL OR BranchCode = @Branch))
        THROW 61033, 'The discount''s approver is not a POS supervisor of this branch on the server.', 1;
    IF @CreditApprovedBy IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.POSV2_Supervisor WHERE UserID = @CreditApprovedBy AND (BranchCode IS NULL OR BranchCode = @Branch))
        THROW 61037, 'The credit approver is not a POS supervisor of this branch on the server.', 1;

    BEGIN TRY
        BEGIN TRAN;

        -- lock order everywhere: shift -> sale -> stock (sp-reviewer S1). The shift: this terminal's, still open; the close waits for it.
        DECLARE @shTerm INT, @shStatus VARCHAR(10);
        SELECT @shTerm = TerminalID, @shStatus = Status FROM dbo.POSV2_Shift WITH (UPDLOCK, HOLDLOCK) WHERE ShiftGUID = @ShiftGUID;

        -- a concurrent post of the same sale: the second one waits here and then sees it
        IF EXISTS (SELECT 1 FROM dbo.POSV2_Sale WITH (UPDLOCK, HOLDLOCK) WHERE SaleGUID = @SaleGUID)
        BEGIN
            COMMIT TRAN;
            SELECT 'DUPLICATE' AS Result, (SELECT COUNT(*) FROM dbo.POSV2_Shortage WHERE SaleGUID = @SaleGUID) AS ShortLines,
                   'Already posted.' AS Message;
            RETURN;
        END
        IF EXISTS (SELECT 1 FROM dbo.POSV2_Sale WITH (UPDLOCK, HOLDLOCK) WHERE TerminalID = @TerminalID AND ORNo = @ORNo)
        BEGIN
            SET @msg = N'OR number ' + @ORNo + N' is already used by another sale of this terminal.';
            THROW 61020, @msg, 1;
        END

        IF @shTerm IS NULL OR @shTerm <> @TerminalID THROW 61030, 'The sale''s shift is not one of this terminal''s shifts on the server.', 1;
        IF @shStatus <> 'OPEN' THROW 61031, 'The sale''s shift is already closed (Z-read) on the server.', 1;

        -- phase 4: a charge over the customer's credit limit (live AR balance, under lock) needs the approver,
        -- otherwise it is posted for review (the customer already left with the goods); an inactive customer too
        IF @payCharge > 0
        BEGIN
            -- read without a lock (sp-reviewer S7): Client Payments locks the ledger first, then the account; this only decides a review flag
            DECLARE @arBal DECIMAL(18,2) = (SELECT AccountBalance FROM dbo.ClientAccounts WHERE AccountKey = @CustomerKey);
            IF @arBal IS NULL SET @review += 'charge customer has no ClientAccounts row (its balance isn''t tracked); ';
            SET @arBal = ISNULL(@arBal, 0);
            IF @custActive = 0 SET @review += 'charge customer is inactive; ';
            -- a credit limit of 0 = unlimited (user, 2026-10-13): only a positive limit is checked
            IF @custLimit > 0 AND @arBal + @payCharge > @custLimit AND @CreditApprovedBy IS NULL
                SET @review += 'charge over the credit limit without approval; ';
        END

        INSERT INTO dbo.POSV2_Sale
            (SaleGUID, TerminalID, ShiftGUID, DiscountApprovedBy, CreditApprovedBy, NeedsReview, ReviewNote, BranchCode, ORNo, SaleDateTime, CashierUserID, CashierName, CustomerKey, ItemCount,
             GrossAmount, DiscountAmount, NetAmount, VatableSales, VatAmount, VatExemptSales, ZeroRatedSales,
             AmountTendered, ChangeAmount, WasOffline, TerminalSavedAt, PostedBy, CancelledLineCount, CancelledLineAmount)
        VALUES
            (@SaleGUID, @TerminalID, @ShiftGUID, LEFT(@DiscountApprovedBy, 60), LEFT(@CreditApprovedBy, 60), CASE WHEN @review = '' THEN 0 ELSE 1 END, NULLIF(@review, ''), @Branch, @ORNo, @SaleDateTime, @CashierUserID, @CashierName, NULLIF(@CustomerKey, ''), @cnt,
             @GrossAmount, @DiscountAmount, @NetAmount, @VatableSales, @VatAmount, @VatExemptSales, @ZeroRatedSales,
             @AmountTendered, @ChangeAmount, @WasOffline, @TerminalSavedAt, LEFT(ISNULL(@User, ''), 60),
             ISNULL(@CancelledLineCount, 0), ISNULL(@CancelledLineAmount, 0));

        INSERT INTO dbo.POSV2_SaleDiscount (SaleGUID, DiscNo, DiscountCode, [Percent], Amount, VatExemptAmount, CustomerName, IDNo, TIN, Remarks)
        SELECT @SaleGUID, DiscNo, DiscountCode, [Percent], Amount, VatExemptAmount, CustomerName, IDNo, TIN, Remarks
        FROM @Discounts;

        INSERT INTO dbo.POSV2_SaleLine
            (SaleGUID, [LineNo], ProductCode, Barcode, Description, Qty, PriceLevel, UnitPrice, LineDiscount, LineTotal, IsVat, VatAmount,
             DiscNo, DiscountCode, DiscountAmount, VatExemptAmount)
        SELECT @SaleGUID, [LineNo], ProductCode, Barcode, Description, Qty, PriceLevel, UnitPrice, LineDiscount, LineTotal, IsVat, VatAmount,
               DiscNo, DiscountCode, DiscountAmount, VatExemptAmount
        FROM @Lines;

        INSERT INTO dbo.POSV2_Payment (SaleGUID, PayNo, PaymentType, Amount, Reference)
        SELECT @SaleGUID, PayNo, PaymentType, Amount, Reference FROM @Payments;

        -- phase 4: the charge is an AR invoice now (Client Payments collects it), with its client-ledger debit;
        -- the GL AR leg posts with the shift (POSV2-SHIFT CHARGE). Keys: InvoiceNo = the OR no.; ReferenceNo = 'P' + 9 digits (fits the AR
        -- screens' varchar(10), sp-reviewer B2), kept on POSV2_Sale.ARReferenceNo. The ledger's MAX(seq) is read before anything else of
        -- the customer is locked: the same order as Client Payments (ledger first, then its trigger updates ClientAccounts; S7)
        IF @payCharge > 0
        BEGIN
            DECLARE @saleDay DATE = CAST(@SaleDateTime AS DATE), @clSeq DECIMAL(7,0),
                    @arRef VARCHAR(10) = 'P' + RIGHT('000000000' + CAST(NEXT VALUE FOR dbo.seq_POSV2_ARRef AS VARCHAR(19)), 9);
            UPDATE dbo.POSV2_Sale SET ARReferenceNo = @arRef WHERE SaleGUID = @SaleGUID;
            INSERT INTO dbo.TransactionChargeSales
                (CustomerKey, BranchCode, TransactionDate, ReferenceNo, InvoiceNo, TotalAmount, PaymentType, Balance, AmountPaid, PayStatus, DueDate, Remarks)
            VALUES
                (@CustomerKey, LEFT(@Branch, 3), @saleDay, @arRef, @ORNo, @payCharge, 'CREDIT', @payCharge, 0, 'UNPAID', DATEADD(DAY, @custTerm, @saleDay),
                 'POS V2 charge sale');
            SELECT @clSeq = ISNULL(MAX(TRN_SEQ_NO), 0) + 1 FROM dbo.ClientLedger WITH (UPDLOCK, HOLDLOCK) WHERE AccountKey = @CustomerKey;
            INSERT INTO dbo.ClientLedger
                (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch, Description, TransCode,
                 TransactionDate, ReferenceNumber, ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
                 EndingBalance, ORNumber, TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
            VALUES
                (@clSeq, @CustomerKey, @CustomerKey, SYSDATETIME(), LEFT(@Branch, 3), 'POS V2 charge sale OR ' + @ORNo, 'POSV2-CHARGE',
                 @saleDay, @arRef, @ORNo, @ORNo, 0, @payCharge, 0,
                 0, @ORNo, LEFT(ISNULL(@User, ''), 50), LEFT(ISNULL(@CreditApprovedBy, '*'), 50), 'POS charge sale', @payCharge, 0, NULL);
        END

        -- ── stock: the engine's per-product locks first (same order as every engine caller),
        --    then what the branch has, then each line takes what is left, in line order
        CREATE TABLE #InvLockKeys (ProductCode VARCHAR(10) NOT NULL PRIMARY KEY);
        INSERT INTO #InvLockKeys (ProductCode) SELECT DISTINCT LEFT(ProductCode, 10) FROM @Lines;
        EXEC dbo.sp_InvFIFO_LockProducts @BranchCode = @Branch;

        SELECT i.Product AS ProductCode, SUM(i.Available) AS Available
        INTO #Avail
        FROM dbo.fn_InvEligibleLots(@Branch) AS e
        INNER JOIN dbo.Inventory AS i WITH (UPDLOCK, ROWLOCK) ON i.SequenceNumber = e.SequenceNumber
        WHERE i.Product IN (SELECT ProductCode FROM #InvLockKeys) AND i.Available > 0 AND i.IsWarehouse = 1
        GROUP BY i.Product;

        SELECT l.[LineNo], LEFT(l.ProductCode, 10) AS ProductCode, l.Qty,
               CAST(CASE WHEN ISNULL(a.Available, 0) - ISNULL(prev.Used, 0) <= 0 THEN 0
                         WHEN ISNULL(a.Available, 0) - ISNULL(prev.Used, 0) >= l.Qty THEN l.Qty
                         ELSE ISNULL(a.Available, 0) - ISNULL(prev.Used, 0) END AS DECIMAL(18,3)) AS Take
        INTO #Take
        FROM @Lines AS l
        LEFT JOIN #Avail AS a ON a.ProductCode = LEFT(l.ProductCode, 10)
        OUTER APPLY (SELECT SUM(x.Qty) AS Used FROM @Lines AS x
                     WHERE LEFT(x.ProductCode, 10) = LEFT(l.ProductCode, 10) AND x.[LineNo] < l.[LineNo]) AS prev;

        DECLARE @Req dbo.tt_InvDeductLine;
        INSERT INTO @Req (LineID, ProductCode, Qty, Mode)
        SELECT [LineNo], ProductCode, Take, 'AUTO' FROM #Take WHERE Take > 0;

        CREATE TABLE #InvAlloc (
            LineID INT NOT NULL, InventorySeqNo INT NOT NULL, ProductCode VARCHAR(10) NOT NULL, Description VARCHAR(300) NULL,
            Barcode VARCHAR(35) NULL, ShipmentNo VARCHAR(10) NULL, ReferenceCode VARCHAR(100) NULL, Qty DECIMAL(18,3) NOT NULL,
            Cost DECIMAL(18,2) NOT NULL, IsVat BIT NOT NULL, BegQty DECIMAL(18,3) NOT NULL, EndQty DECIMAL(18,3) NOT NULL);

        IF EXISTS (SELECT 1 FROM @Req)
        BEGIN
            DECLARE @remarks VARCHAR(500) = 'POS SALE OR#' + @ORNo;
            EXEC dbo.spu_InvFIFO_Deduct @BranchCode = @Branch, @Lines = @Req, @LedgerRemarks = @remarks,
                                        @User = @User, @SkipBarcodedLots = 0;
        END

        INSERT INTO dbo.POSV2_SaleLot (SaleGUID, [LineNo], InventorySeqNo, Qty, Cost)
        SELECT @SaleGUID, LineID, InventorySeqNo, Qty, Cost FROM #InvAlloc;

        UPDATE sl
        SET QtyDeducted = ISNULL(a.Qty, 0),
            QtyShort    = sl.Qty - ISNULL(a.Qty, 0),
            CostTotal   = ISNULL(a.CostTotal, 0)
        FROM dbo.POSV2_SaleLine AS sl
        LEFT JOIN (SELECT LineID, SUM(Qty) AS Qty, CAST(SUM(ROUND(Qty * Cost, 2)) AS DECIMAL(18,2)) AS CostTotal
                   FROM #InvAlloc GROUP BY LineID) AS a ON a.LineID = sl.[LineNo]
        WHERE sl.SaleGUID = @SaleGUID;

        INSERT INTO dbo.POSV2_Shortage (SaleGUID, [LineNo], BranchCode, ProductCode, QtySold, QtyDeducted, QtyShort)
        SELECT SaleGUID, [LineNo], @Branch, ProductCode, Qty, QtyDeducted, QtyShort
        FROM dbo.POSV2_SaleLine WHERE SaleGUID = @SaleGUID AND QtyShort > 0;
        DECLARE @short INT = @@ROWCOUNT;

        IF @short > 0 UPDATE dbo.POSV2_Sale SET HasShortage = 1 WHERE SaleGUID = @SaleGUID;
        UPDATE dbo.POSV2_Terminal SET LastSeenAt = SYSDATETIME() WHERE TerminalID = @TerminalID;

        -- post-check: every line is fully accounted for (deducted + short = sold)
        IF EXISTS (SELECT 1 FROM dbo.POSV2_SaleLine WHERE SaleGUID = @SaleGUID AND QtyDeducted + QtyShort <> Qty)
            THROW 61021, 'Post-check: a line''s deducted + short quantity is not its sold quantity; nothing was posted.', 1;

        COMMIT TRAN;

        SELECT 'POSTED' AS Result, @short AS ShortLines,
               CASE WHEN @short = 0 THEN 'Posted.' ELSE 'Posted; ' + CAST(@short AS VARCHAR(10)) + ' line(s) short of stock (see POS shortages).' END
               + CASE WHEN @review = '' THEN '' ELSE ' Needs review: ' + @review END AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── phase 2: void a posted sale ───────────────────────────────────
CREATE PROCEDURE dbo.spu_POSV2_VoidSale
    @SaleGUID   UNIQUEIDENTIFIER,
    @TerminalID INT,
    @Reason     VARCHAR(300),
    @VoidedAt   DATETIME2(0),
    @User       VARCHAR(60),
    @ApprovedBy VARCHAR(60) = NULL     -- phase 3: the supervisor (required)
AS
/*  Voids a posted sale: gives back exactly the lots it took (spu_InvFIFO_Restore, ledger
    'POS VOID OR#...'), marks it VOIDED and its open shortages VOIDED. Idempotent: a sale
    already voided returns DUPLICATE. The terminal sends the VOID after the sale's own SALE
    event, so the sale is on the server first. Errors 61041-61043 are permanent.
    Returns one row: Result (VOIDED / DUPLICATE), Message. Caller: POSV2 PosSyncService. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISNULL(LTRIM(@Reason), '') = '' THROW 61043, 'A void needs a reason.', 1;
    SET @ApprovedBy = NULLIF(LTRIM(RTRIM(@ApprovedBy)), '');

    BEGIN TRY
        BEGIN TRAN;

        -- lock order everywhere: shift -> sale -> stock (sp-reviewer S1); the shift's ID is read unlocked first
        DECLARE @Branch VARCHAR(10), @OR VARCHAR(30), @Status VARCHAR(15), @Term INT, @Shift UNIQUEIDENTIFIER, @ShiftStatus VARCHAR(10);
        SET @Shift = (SELECT ShiftGUID FROM dbo.POSV2_Sale WHERE SaleGUID = @SaleGUID);
        SELECT @ShiftStatus = Status FROM dbo.POSV2_Shift WITH (UPDLOCK, HOLDLOCK) WHERE ShiftGUID = @Shift;
        SELECT @Branch = BranchCode, @OR = ORNo, @Status = Status, @Term = TerminalID
        FROM dbo.POSV2_Sale WITH (UPDLOCK, HOLDLOCK) WHERE SaleGUID = @SaleGUID;

        IF @OR IS NULL THROW 61041, 'The sale to void is not on the server.', 1;
        IF @Term <> @TerminalID THROW 61042, 'The sale to void belongs to another terminal.', 1;
        -- already voided first: a retry after a lost reply must stay DUPLICATE whatever changed since (sp-reviewer S7)
        IF @Status = 'VOIDED'
        BEGIN
            COMMIT TRAN;
            SELECT 'DUPLICATE' AS Result, 'Already voided.' AS Message;
            RETURN;
        END
        IF @ApprovedBy IS NULL THROW 61045, 'A void needs a supervisor''s approval.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.POSV2_Supervisor WHERE UserID = @ApprovedBy AND (BranchCode IS NULL OR BranchCode = @Branch))
            THROW 61046, 'The void''s approver is not a POS supervisor of this branch on the server.', 1;
        -- after the Z-reading the shift's GL is booked: a void would leave it wrong (a return, phase 4)
        IF @ShiftStatus <> 'OPEN'
            THROW 61044, 'The sale''s shift is already closed (Z-read); it can''t be voided any more.', 1;

        -- phase 4 (sp-reviewer B1): a sale with a return can't be voided as well (stock, AR and the GL would go back twice)
        IF EXISTS (SELECT 1 FROM dbo.POSV2_Return WHERE OrigSaleGUID = @SaleGUID)
            THROW 61048, 'Part of this sale was already returned: it can''t be voided (return the rest instead).', 1;

        -- phase 4: a charge sale's invoice goes too, only while nothing was paid on it (else: a return)
        DECLARE @vCharge DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM dbo.POSV2_Payment WHERE SaleGUID = @SaleGUID AND PaymentType = 'CHARGE'), 0),
                @vCust CHAR(8) = (SELECT CustomerKey FROM dbo.POSV2_Sale WHERE SaleGUID = @SaleGUID),
                @vRef VARCHAR(10) = (SELECT ARReferenceNo FROM dbo.POSV2_Sale WHERE SaleGUID = @SaleGUID);
        IF @vCharge > 0
        BEGIN
            DECLARE @tcsSettled DECIMAL(18,2), @tcsTotal DECIMAL(18,2);
            SELECT @tcsSettled = ISNULL(AmountPaid, 0) + ISNULL(EWTAmount, 0) + ISNULL(DiscountAmount, 0) + ISNULL(OffsetAmount, 0), @tcsTotal = TotalAmount
            FROM dbo.TransactionChargeSales WITH (UPDLOCK, HOLDLOCK)
            WHERE CustomerKey = @vCust AND BranchCode = LEFT(@Branch, 3) AND InvoiceNo = @OR AND ReferenceNo = @vRef;
            IF @tcsTotal IS NULL THROW 61047, 'The charge sale''s invoice is not on the server.', 1;
            IF @tcsSettled > 0 THROW 61047, 'A payment was already applied to this charge sale''s invoice: return the items instead of voiding.', 1;
            UPDATE dbo.TransactionChargeSales SET TotalAmount = 0, Balance = 0, PayStatus = 'CANCELLED', Remarks = LEFT('POS V2 charge sale, voided: ' + @Reason, 520)
            WHERE CustomerKey = @vCust AND BranchCode = LEFT(@Branch, 3) AND InvoiceNo = @OR AND ReferenceNo = @vRef;
            IF @@ROWCOUNT <> 1 THROW 61047, 'The charge sale''s invoice is not exactly one row on the server.', 1;   -- S9
            DECLARE @vSeq DECIMAL(7,0);
            SELECT @vSeq = ISNULL(MAX(TRN_SEQ_NO), 0) + 1 FROM dbo.ClientLedger WITH (UPDLOCK, HOLDLOCK) WHERE AccountKey = @vCust;
            INSERT INTO dbo.ClientLedger
                (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch, Description, TransCode,
                 TransactionDate, ReferenceNumber, ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
                 EndingBalance, ORNumber, TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
            SELECT @vSeq, @vCust, @vCust, SYSDATETIME(), LEFT(@Branch, 3), 'POS V2 void OR ' + @OR, 'POSV2-VOID',
                   CAST(SaleDateTime AS DATE), @vRef, @OR, @OR, 0, 0, @vCharge,
                   0, @OR, LEFT(ISNULL(@User, ''), 50), LEFT(@ApprovedBy, 50), 'POS charge sale voided', @vCharge, 0, NULL
            FROM dbo.POSV2_Sale WHERE SaleGUID = @SaleGUID;
        END

        DECLARE @Lots dbo.tt_InvRestoreLot;
        INSERT INTO @Lots (InventorySeqNo, Qty)
        SELECT InventorySeqNo, SUM(Qty) FROM dbo.POSV2_SaleLot WHERE SaleGUID = @SaleGUID GROUP BY InventorySeqNo;

        IF EXISTS (SELECT 1 FROM @Lots)
        BEGIN
            DECLARE @remarks VARCHAR(500) = 'POS VOID OR#' + @OR;
            EXEC dbo.spu_InvFIFO_Restore @BranchCode = @Branch, @Lots = @Lots, @LedgerRemarks = @remarks, @User = @User;
        END

        UPDATE dbo.POSV2_Sale
        SET Status = 'VOIDED', VoidedAt = @VoidedAt, VoidReason = LEFT(@Reason, 300), VoidedBy = LEFT(ISNULL(@User, ''), 60),
            VoidPostedAt = SYSDATETIME(), VoidApprovedBy = LEFT(@ApprovedBy, 60)
        WHERE SaleGUID = @SaleGUID;

        UPDATE dbo.POSV2_Shortage
        SET Status = 'VOIDED', ResolvedBy = LEFT(ISNULL(@User, ''), 60), ResolvedAt = SYSDATETIME(), Remarks = 'Sale voided: ' + LEFT(@Reason, 280)
        WHERE SaleGUID = @SaleGUID AND Status = 'OPEN';

        COMMIT TRAN;
        SELECT 'VOIDED' AS Result, 'Voided; stock given back.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── phase 4: a return / refund ────────────────────────────────────
CREATE PROCEDURE dbo.spu_POSV2_PostReturn
    @ReturnGUID      UNIQUEIDENTIFIER,
    @TerminalID      INT,
    @ShiftGUID       UNIQUEIDENTIFIER,      -- the open shift that pays it back
    @ReturnNo        VARCHAR(30),           -- <terminal prefix>-R<seq>
    @OrigSaleGUID    UNIQUEIDENTIFIER,
    @ReturnDateTime  DATETIME2(0),
    @CashierUserID   VARCHAR(50),
    @CashierName     VARCHAR(100),
    @ApprovedBy      VARCHAR(60),
    @Reason          VARCHAR(300),
    @CashRefund      DECIMAL(18,2),
    @CardRefund      DECIMAL(18,2),
    @ChargeRefund    DECIMAL(18,2),
    @TerminalSavedAt DATETIME2(0),
    @Lines           dbo.tt_POSV2_ReturnLine READONLY,
    @User            VARCHAR(60)
AS
/*  Posts a return of part or all of a posted sale of the branch (any earlier shift or terminal),
    all or nothing. Idempotent by @ReturnGUID (DUPLICATE).
    Stock: each returned qty goes back to the lots its original line took, newest lot first, never
    more than the line took less what earlier returns gave back (spu_InvFIFO_Restore, ledger
    'POS RETURN <no> OR#<or>'); a qty the sale never deducted (short) closes that much of its
    shortage instead. Refunds "same as paid" (user 2026-10-13), as decided on the terminal: CHARGE
    comes off the customer's invoice up to its open balance (any excess = customer credit, 20115,
    and NeedsReview), CARD and CASH as given. What a stale terminal couldn't know (more returned
    than sold, a refund split beyond what was paid that way) posts with NeedsReview, never a
    refusal: the money already left the drawer. The GL posts with the shift (POSV2-SHIFT RETGROSS /
    RETDISC / RETCOST / refunds). Errors 61067-61079 are permanent.
    Returns one row: Result (POSTED / DUPLICATE), Message. Caller: POSV2 PosSyncService. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.POSV2_Return WHERE ReturnGUID = @ReturnGUID)
    BEGIN
        SELECT 'DUPLICATE' AS Result, 'Already posted.' AS Message;
        RETURN;
    END

    DECLARE @msg NVARCHAR(400), @Branch VARCHAR(10), @Prefix VARCHAR(12), @Active BIT;
    SELECT @Branch = BranchCode, @Prefix = ORPrefix, @Active = IsActive FROM dbo.POSV2_Terminal WHERE TerminalID = @TerminalID;
    IF @Branch IS NULL THROW 61010, 'Unknown terminal.', 1;
    IF @Active = 0 THROW 61011, 'This terminal is deactivated on the server.', 1;
    IF ISNULL(@ReturnNo, '') NOT LIKE @Prefix + '-R%' THROW 61070, 'The return no. is not in this terminal''s return series.', 1;
    IF NOT EXISTS (SELECT 1 FROM @Lines) THROW 61071, 'A return needs at least one line.', 1;
    IF EXISTS (SELECT 1 FROM @Lines WHERE Qty <= 0 OR GrossAmount < 0 OR DiscountAmount < 0 OR VatExemptAmount < 0 OR NetAmount < 0
                                       OR GrossAmount - DiscountAmount - VatExemptAmount <> NetAmount)
        THROW 61072, 'A return line has a zero quantity, a negative amount, or a net that is not gross - discount - VAT exemption.', 1;
    IF (SELECT COUNT(*) FROM @Lines) <> (SELECT COUNT(DISTINCT OrigLineNo) FROM @Lines)
        THROW 61067, 'A sale line appears twice in the return.', 1;
    IF ISNULL(@CashRefund, -1) < 0 OR ISNULL(@CardRefund, -1) < 0 OR ISNULL(@ChargeRefund, -1) < 0
       OR @CashRefund + @CardRefund + @ChargeRefund <> (SELECT SUM(NetAmount) FROM @Lines)
        THROW 61073, 'The refunds (cash + card + charge) are not the returned net amount.', 1;
    IF ISNULL(LTRIM(@Reason), '') = '' THROW 61074, 'A return needs a reason.', 1;
    SET @ApprovedBy = NULLIF(LTRIM(RTRIM(@ApprovedBy)), '');
    IF @ApprovedBy IS NULL THROW 61075, 'A return needs a supervisor''s approval.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.POSV2_Supervisor WHERE UserID = @ApprovedBy AND (BranchCode IS NULL OR BranchCode = @Branch))
        THROW 61076, 'The return''s approver is not a POS supervisor of this branch on the server.', 1;

    BEGIN TRY
        BEGIN TRAN;

        -- lock order: shift -> sale / return -> customer AR -> stock
        DECLARE @shTerm INT, @shStatus VARCHAR(10);
        SELECT @shTerm = TerminalID, @shStatus = Status FROM dbo.POSV2_Shift WITH (UPDLOCK, HOLDLOCK) WHERE ShiftGUID = @ShiftGUID;
        IF EXISTS (SELECT 1 FROM dbo.POSV2_Return WITH (UPDLOCK, HOLDLOCK) WHERE ReturnGUID = @ReturnGUID)
        BEGIN
            COMMIT TRAN;
            SELECT 'DUPLICATE' AS Result, 'Already posted.' AS Message;
            RETURN;
        END
        IF @shTerm IS NULL OR @shTerm <> @TerminalID THROW 61077, 'The return''s shift is not one of this terminal''s shifts on the server.', 1;
        IF @shStatus <> 'OPEN' THROW 61077, 'The return''s shift is already closed (Z-read) on the server.', 1;
        IF EXISTS (SELECT 1 FROM dbo.POSV2_Return WITH (UPDLOCK, HOLDLOCK) WHERE TerminalID = @TerminalID AND ReturnNo = @ReturnNo)
        BEGIN
            SET @msg = N'Return no. ' + @ReturnNo + N' is already used by another return of this terminal.';
            THROW 61079, @msg, 1;
        END

        DECLARE @oBranch VARCHAR(10), @oStatus VARCHAR(15), @oOR VARCHAR(30), @oCust VARCHAR(20), @oRef VARCHAR(10);
        SELECT @oBranch = BranchCode, @oStatus = Status, @oOR = ORNo, @oCust = CustomerKey, @oRef = ARReferenceNo
        FROM dbo.POSV2_Sale WITH (UPDLOCK, HOLDLOCK) WHERE SaleGUID = @OrigSaleGUID;
        IF @oOR IS NULL THROW 61078, 'The sale to return is not on the server.', 1;
        IF @oBranch <> @Branch THROW 61078, 'The sale to return belongs to another branch.', 1;
        IF @oStatus <> 'POSTED' THROW 61078, 'The sale to return was voided.', 1;
        IF EXISTS (SELECT 1 FROM @Lines AS l WHERE NOT EXISTS (SELECT 1 FROM dbo.POSV2_SaleLine AS s WHERE s.SaleGUID = @OrigSaleGUID AND s.[LineNo] = l.OrigLineNo))
            THROW 61067, 'A returned line is not a line of the sale.', 1;
        -- phase 5 review (S10): the return's VAT feeds BIR (Z-reading less returns), so it must fit its sale line
        IF EXISTS (SELECT 1 FROM @Lines AS l INNER JOIN dbo.POSV2_SaleLine AS s ON s.SaleGUID = @OrigSaleGUID AND s.[LineNo] = l.OrigLineNo
                   WHERE l.VatAmount < 0 OR l.VatAmount > l.NetAmount OR (s.IsVat = 0 AND l.VatAmount <> 0))
            THROW 61072, 'A returned line''s VAT is negative, above its amount, or on a line sold without VAT.', 1;

        -- what earlier returns already took back, per original line, and per payment kind
        SELECT rl.OrigLineNo, SUM(rl.Qty) AS Qty, SUM(rl.NetAmount) AS Net, SUM(rl.VatAmount) AS Vat
        INTO #Prev
        FROM dbo.POSV2_ReturnLine AS rl INNER JOIN dbo.POSV2_Return AS r ON r.ReturnGUID = rl.ReturnGUID
        WHERE r.OrigSaleGUID = @OrigSaleGUID
        GROUP BY rl.OrigLineNo;

        DECLARE @review VARCHAR(300) = '';
        IF EXISTS (SELECT 1 FROM @Lines AS l INNER JOIN dbo.POSV2_SaleLine AS s ON s.SaleGUID = @OrigSaleGUID AND s.[LineNo] = l.OrigLineNo
                   LEFT JOIN #Prev AS p ON p.OrigLineNo = l.OrigLineNo
                   WHERE l.Qty + ISNULL(p.Qty, 0) > s.Qty OR l.NetAmount + ISNULL(p.Net, 0) > s.LineTotal)
            SET @review += 'more returned than sold on a line; ';
        DECLARE @paidCard DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM dbo.POSV2_Payment WHERE SaleGUID = @OrigSaleGUID AND PaymentType = 'CARD'), 0),
                @paidCharge DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM dbo.POSV2_Payment WHERE SaleGUID = @OrigSaleGUID AND PaymentType = 'CHARGE'), 0),
                @prevCard DECIMAL(18,2), @prevCharge DECIMAL(18,2);
        SELECT @prevCard = ISNULL(SUM(CardRefund), 0), @prevCharge = ISNULL(SUM(ChargeRefund), 0) FROM dbo.POSV2_Return WHERE OrigSaleGUID = @OrigSaleGUID;
        IF @CardRefund > @paidCard - @prevCard SET @review += 'card refund above what was paid by card; ';
        IF @ChargeRefund > @paidCharge - @prevCharge SET @review += 'charge refund above what was charged; ';
        -- sp-reviewer S1: what the terminal computed is checked against the sale too (flags, not refusals: the money left)
        DECLARE @paidCash DECIMAL(18,2) = ISNULL((SELECT SUM(Amount) FROM dbo.POSV2_Payment WHERE SaleGUID = @OrigSaleGUID AND PaymentType = 'CASH'), 0)
                                        - (SELECT ChangeAmount FROM dbo.POSV2_Sale WHERE SaleGUID = @OrigSaleGUID),
                @prevCash DECIMAL(18,2) = ISNULL((SELECT SUM(CashRefund) FROM dbo.POSV2_Return WHERE OrigSaleGUID = @OrigSaleGUID), 0);
        IF @CashRefund > @paidCash - @prevCash SET @review += 'cash refund above what was paid in cash; ';
        -- each line's net: its share of the line (pro rata, 0.02 of rounding: gross, discount and exemption round apart; the last piece takes what is left)
        IF EXISTS (SELECT 1 FROM @Lines AS l
                   INNER JOIN dbo.POSV2_SaleLine AS s ON s.SaleGUID = @OrigSaleGUID AND s.[LineNo] = l.OrigLineNo
                   LEFT JOIN #Prev AS p ON p.OrigLineNo = l.OrigLineNo
                   WHERE CASE WHEN l.Qty + ISNULL(p.Qty, 0) >= s.Qty THEN s.LineTotal - ISNULL(p.Net, 0)
                              ELSE ROUND(s.LineTotal * l.Qty / s.Qty, 2) END - l.NetAmount NOT BETWEEN -0.02 AND 0.02)
            SET @review += 'a returned line''s amount is not its share of the sale line; ';
        -- and its VAT the same way (the last piece takes what is left of the line's VAT)
        IF EXISTS (SELECT 1 FROM @Lines AS l
                   INNER JOIN dbo.POSV2_SaleLine AS s ON s.SaleGUID = @OrigSaleGUID AND s.[LineNo] = l.OrigLineNo
                   LEFT JOIN #Prev AS p ON p.OrigLineNo = l.OrigLineNo
                   WHERE s.IsVat = 1
                     AND CASE WHEN l.Qty + ISNULL(p.Qty, 0) >= s.Qty THEN s.VatAmount - ISNULL(p.Vat, 0)
                              ELSE ROUND(s.VatAmount * l.Qty / s.Qty, 2) END - l.VatAmount NOT BETWEEN -0.02 AND 0.02)
            SET @review += 'a returned line''s VAT is not its share of the sale line; ';
        IF @ChargeRefund > 0 AND @oCust IS NULL THROW 61073, 'A charge refund needs the sale''s customer.', 1;

        -- the customer's invoice: the refund comes off its open balance; any excess is the customer's credit
        DECLARE @excess DECIMAL(18,2) = 0;
        IF @ChargeRefund > 0
        BEGIN
            DECLARE @tBal DECIMAL(18,2), @tPaid DECIMAL(18,2), @apply DECIMAL(18,2);
            SELECT @tBal = Balance, @tPaid = ISNULL(AmountPaid, 0) + ISNULL(EWTAmount, 0) + ISNULL(DiscountAmount, 0) + ISNULL(OffsetAmount, 0)
            FROM dbo.TransactionChargeSales WITH (UPDLOCK, HOLDLOCK)
            WHERE CustomerKey = @oCust AND BranchCode = LEFT(@Branch, 3) AND InvoiceNo = @oOR AND ReferenceNo = @oRef;
            SET @apply = CASE WHEN ISNULL(@tBal, 0) < @ChargeRefund THEN ISNULL(@tBal, 0) ELSE @ChargeRefund END;
            IF @apply < 0 SET @apply = 0;
            SET @excess = @ChargeRefund - @apply;
            IF @excess > 0 SET @review += 'charge refund ' + CONVERT(VARCHAR(30), @excess) + ' above the invoice''s open balance (customer credit 20115); ';
            IF @apply > 0
            BEGIN
                UPDATE dbo.TransactionChargeSales
                SET TotalAmount = TotalAmount - @apply, Balance = Balance - @apply,
                    PayStatus = CASE WHEN Balance - @apply > 0 THEN CASE WHEN @tPaid > 0 THEN 'PARTIAL' ELSE 'UNPAID' END
                                     WHEN @tPaid > 0 THEN 'FULLYPAID' ELSE 'RETURNED' END
                WHERE CustomerKey = @oCust AND BranchCode = LEFT(@Branch, 3) AND InvoiceNo = @oOR AND ReferenceNo = @oRef;
                IF @@ROWCOUNT <> 1 THROW 61069, 'The charge sale''s invoice is not exactly one row on the server.', 1;   -- S9
                DECLARE @rSeq DECIMAL(7,0);
                SELECT @rSeq = ISNULL(MAX(TRN_SEQ_NO), 0) + 1 FROM dbo.ClientLedger WITH (UPDLOCK, HOLDLOCK) WHERE AccountKey = @oCust;
                INSERT INTO dbo.ClientLedger
                    (TRN_SEQ_NO, AccountKey, AccountID, PostingDate, InitiatingBranch, Description, TransCode,
                     TransactionDate, ReferenceNumber, ReferenceKey, InvoiceNo, BeginningBalance, Debit, Credit,
                     EndingBalance, ORNumber, TransactedBy, ApprovedBy, Remarks, TotalAmount, ErrorCorrectTag, TicketReference)
                VALUES
                    (@rSeq, @oCust, @oCust, SYSDATETIME(), LEFT(@Branch, 3), 'POS V2 return ' + @ReturnNo + ' of OR ' + @oOR, 'POSV2-RETURN',
                     CAST(@ReturnDateTime AS DATE), @oRef, @ReturnNo, @oOR, 0, 0, @apply,
                     0, @oOR, LEFT(ISNULL(@User, ''), 50), LEFT(@ApprovedBy, 50), 'POS return', @apply, 0, NULL);
            END
        END

        INSERT INTO dbo.POSV2_Return
            (ReturnGUID, TerminalID, ShiftGUID, BranchCode, ReturnNo, OrigSaleGUID, ReturnDateTime, CashierUserID, CashierName, ApprovedBy, Reason,
             GrossAmount, DiscountAmount, NetAmount, VatAmount, CashRefund, CardRefund, ChargeRefund, ChargeExcess, TerminalSavedAt, PostedBy)
        SELECT @ReturnGUID, @TerminalID, @ShiftGUID, @Branch, @ReturnNo, @OrigSaleGUID, @ReturnDateTime, LEFT(@CashierUserID, 50), @CashierName,
               LEFT(@ApprovedBy, 60), LEFT(@Reason, 300),
               SUM(GrossAmount), SUM(DiscountAmount + VatExemptAmount), SUM(NetAmount), SUM(VatAmount),
               @CashRefund, @CardRefund, @ChargeRefund, @excess, @TerminalSavedAt, LEFT(ISNULL(@User, ''), 60)
        FROM @Lines;

        INSERT INTO dbo.POSV2_ReturnLine (ReturnGUID, [LineNo], OrigLineNo, ProductCode, Qty, GrossAmount, DiscountAmount, VatExemptAmount, NetAmount, VatAmount)
        SELECT @ReturnGUID, l.[LineNo], l.OrigLineNo, s.ProductCode, l.Qty, l.GrossAmount, l.DiscountAmount, l.VatExemptAmount, l.NetAmount, l.VatAmount
        FROM @Lines AS l INNER JOIN dbo.POSV2_SaleLine AS s ON s.SaleGUID = @OrigSaleGUID AND s.[LineNo] = l.OrigLineNo;

        -- stock: the lots each original line took (one row per lot), less what earlier returns gave back; newest lot first =
        -- the highest Inventory SequenceNumber (FIFO took the oldest first), deterministic (sp-reviewer S3). The cost of a
        -- piece is ROUND(qty x lot cost, 2), except the piece that empties a lot takes exactly what is left of that lot's
        -- sale cost, so repeated partial returns put back exactly what the sale took off (S4).
        SELECT l.[LineNo], l.OrigLineNo, sl.InventorySeqNo, sl.Cost, sl.CostAmt, l.Qty AS RetQty,
               sl.Qty - ISNULL(gb.Qty, 0) AS Avail, sl.CostAmt - ISNULL(gb.CostAmt, 0) AS CostLeft
        INTO #LotAvail
        FROM @Lines AS l
        INNER JOIN (SELECT [LineNo], InventorySeqNo, SUM(Qty) AS Qty, MAX(Cost) AS Cost, SUM(ROUND(Qty * Cost, 2)) AS CostAmt
                    FROM dbo.POSV2_SaleLot WHERE SaleGUID = @OrigSaleGUID GROUP BY [LineNo], InventorySeqNo) AS sl ON sl.[LineNo] = l.OrigLineNo
        OUTER APPLY (SELECT SUM(rt.Qty) AS Qty, SUM(rt.CostAmount) AS CostAmt FROM dbo.POSV2_ReturnLot AS rt
                     WHERE rt.OrigSaleGUID = @OrigSaleGUID AND rt.OrigLineNo = l.OrigLineNo AND rt.InventorySeqNo = sl.InventorySeqNo) AS gb;
        DELETE FROM #LotAvail WHERE Avail <= 0;

        SELECT a.[LineNo], a.OrigLineNo, a.InventorySeqNo, a.Cost, a.Avail, a.CostLeft,
               CAST(CASE WHEN a.RetQty - x.Before <= 0 THEN 0
                         WHEN a.RetQty - x.Before >= a.Avail THEN a.Avail
                         ELSE a.RetQty - x.Before END AS DECIMAL(18,3)) AS Qty
        INTO #Back
        FROM #LotAvail AS a
        CROSS APPLY (SELECT ISNULL(SUM(b.Avail), 0) AS Before FROM #LotAvail AS b
                     WHERE b.[LineNo] = a.[LineNo] AND b.InventorySeqNo > a.InventorySeqNo) AS x;   -- newer lots first
        DELETE FROM #Back WHERE Qty <= 0;

        INSERT INTO dbo.POSV2_ReturnLot (ReturnGUID, [LineNo], OrigSaleGUID, OrigLineNo, InventorySeqNo, Qty, Cost, CostAmount)
        SELECT @ReturnGUID, [LineNo], @OrigSaleGUID, OrigLineNo, InventorySeqNo, Qty, Cost,
               CASE WHEN Qty = Avail THEN CostLeft ELSE CAST(ROUND(Qty * Cost, 2) AS DECIMAL(18,2)) END
        FROM #Back;

        DECLARE @Lots dbo.tt_InvRestoreLot;
        INSERT INTO @Lots (InventorySeqNo, Qty) SELECT InventorySeqNo, SUM(Qty) FROM #Back GROUP BY InventorySeqNo;
        IF EXISTS (SELECT 1 FROM @Lots)
        BEGIN
            DECLARE @remarks VARCHAR(500) = 'POS RETURN ' + @ReturnNo + ' OR#' + @oOR;
            EXEC dbo.spu_InvFIFO_Restore @BranchCode = @Branch, @Lots = @Lots, @LedgerRemarks = @remarks, @User = @User;
        END

        UPDATE rl
        SET QtyRestocked = ISNULL(b.Qty, 0), CostTotal = ISNULL(b.Cost, 0)
        FROM dbo.POSV2_ReturnLine AS rl
        LEFT JOIN (SELECT [LineNo], SUM(Qty) AS Qty, SUM(CostAmount) AS Cost FROM dbo.POSV2_ReturnLot WHERE ReturnGUID = @ReturnGUID GROUP BY [LineNo]) AS b ON b.[LineNo] = rl.[LineNo]
        WHERE rl.ReturnGUID = @ReturnGUID;

        -- a qty the sale never deducted (sold short): that much of its open shortage closes instead
        UPDATE rl
        SET QtyUnshorted = CASE WHEN rl.Qty - rl.QtyRestocked < ISNULL(sh.QtyShort, 0) THEN rl.Qty - rl.QtyRestocked ELSE ISNULL(sh.QtyShort, 0) END
        FROM dbo.POSV2_ReturnLine AS rl
        LEFT JOIN dbo.POSV2_Shortage AS sh ON sh.SaleGUID = @OrigSaleGUID AND sh.[LineNo] = rl.OrigLineNo AND sh.Status = 'OPEN'
        WHERE rl.ReturnGUID = @ReturnGUID AND rl.Qty > rl.QtyRestocked;
        UPDATE sh
        SET QtyShort = sh.QtyShort - rl.QtyUnshorted,
            Status = CASE WHEN sh.QtyShort - rl.QtyUnshorted <= 0 THEN 'RETURNED' ELSE sh.Status END,
            ResolvedBy = CASE WHEN sh.QtyShort - rl.QtyUnshorted <= 0 THEN LEFT(ISNULL(@User, ''), 60) ELSE sh.ResolvedBy END,
            ResolvedAt = CASE WHEN sh.QtyShort - rl.QtyUnshorted <= 0 THEN SYSDATETIME() ELSE sh.ResolvedAt END,
            Remarks = LEFT(ISNULL(sh.Remarks + ' | ', '') + 'Returned ' + CONVERT(VARCHAR(30), rl.QtyUnshorted) + ' (' + @ReturnNo + ')', 500)
        FROM dbo.POSV2_Shortage AS sh
        INNER JOIN dbo.POSV2_ReturnLine AS rl ON rl.ReturnGUID = @ReturnGUID AND rl.OrigLineNo = sh.[LineNo]
        WHERE sh.SaleGUID = @OrigSaleGUID AND sh.Status = 'OPEN' AND rl.QtyUnshorted > 0;
        IF EXISTS (SELECT 1 FROM dbo.POSV2_ReturnLine WHERE ReturnGUID = @ReturnGUID AND Qty > QtyRestocked + QtyUnshorted)
            SET @review += 'returned more than the sale took from stock (not restocked); ';

        UPDATE dbo.POSV2_Return
        SET CostTotal = (SELECT ISNULL(SUM(CostTotal), 0) FROM dbo.POSV2_ReturnLine WHERE ReturnGUID = @ReturnGUID),
            NeedsReview = CASE WHEN @review = '' THEN 0 ELSE 1 END, ReviewNote = NULLIF(LEFT(@review, 300), '')
        WHERE ReturnGUID = @ReturnGUID;
        UPDATE dbo.POSV2_Terminal SET LastSeenAt = SYSDATETIME() WHERE TerminalID = @TerminalID;

        COMMIT TRAN;
        SELECT 'POSTED' AS Result,
               'Return posted.' + CASE WHEN @review = '' THEN '' ELSE ' Needs review: ' + @review END AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── phase 4: a sale for a return (another terminal's, or to check what is still returnable) ──
CREATE PROCEDURE dbo.sp_POSV2_GetSaleForReturn
    @BranchCode VARCHAR(10),
    @ORNo       VARCHAR(30)
AS
/*  Three result sets for the terminal's return screen: the sale (with its customer and the open
    balance of its charge invoice), its lines with what earlier returns already took back, and its
    payments with what was already refunded per kind. Read-only. */
BEGIN
    SET NOCOUNT ON;
    DECLARE @g UNIQUEIDENTIFIER = (SELECT TOP 1 SaleGUID FROM dbo.POSV2_Sale WHERE BranchCode = @BranchCode AND ORNo = @ORNo);
    SELECT s.SaleGUID, s.ORNo, s.SaleDateTime, s.CashierUserID, s.CashierName, s.CustomerKey, c.CustomerName, s.Status,
           s.GrossAmount, s.DiscountAmount, s.NetAmount,
           (SELECT t.Balance FROM dbo.TransactionChargeSales AS t
            WHERE t.CustomerKey = s.CustomerKey AND t.BranchCode = LEFT(s.BranchCode, 3) AND t.InvoiceNo = s.ORNo AND t.ReferenceNo = s.ARReferenceNo) AS ChargeBalance
    FROM dbo.POSV2_Sale AS s LEFT JOIN dbo.Customers AS c ON c.CustomerKey = s.CustomerKey
    WHERE s.SaleGUID = @g;
    SELECT l.[LineNo], l.ProductCode, l.Barcode, l.Description, l.Qty, l.PriceLevel, l.UnitPrice, l.LineDiscount, l.LineTotal, l.IsVat, l.VatAmount,
           l.DiscNo, l.DiscountCode, l.DiscountAmount, l.VatExemptAmount,
           ISNULL(p.Qty, 0) AS ReturnedQty, ISNULL(p.Gross, 0) AS ReturnedGross, ISNULL(p.Disc, 0) AS ReturnedDiscount,
           ISNULL(p.VatEx, 0) AS ReturnedVatExempt, ISNULL(p.Net, 0) AS ReturnedNet, ISNULL(p.Vat, 0) AS ReturnedVat
    FROM dbo.POSV2_SaleLine AS l
    OUTER APPLY (SELECT SUM(rl.Qty) AS Qty, SUM(rl.GrossAmount) AS Gross, SUM(rl.DiscountAmount) AS Disc, SUM(rl.VatExemptAmount) AS VatEx,
                        SUM(rl.NetAmount) AS Net, SUM(rl.VatAmount) AS Vat
                 FROM dbo.POSV2_ReturnLine AS rl INNER JOIN dbo.POSV2_Return AS r ON r.ReturnGUID = rl.ReturnGUID
                 WHERE r.OrigSaleGUID = l.SaleGUID AND rl.OrigLineNo = l.[LineNo]) AS p
    WHERE l.SaleGUID = @g
    ORDER BY l.[LineNo];
    SELECT p.PaymentType, SUM(p.Amount) AS Paid,
           CASE p.PaymentType WHEN 'CASH' THEN ISNULL(r.Cash, 0) WHEN 'CARD' THEN ISNULL(r.Card, 0) ELSE ISNULL(r.Charge, 0) END AS Refunded,
           (SELECT ChangeAmount FROM dbo.POSV2_Sale WHERE SaleGUID = @g) AS ChangeGiven
    FROM dbo.POSV2_Payment AS p
    OUTER APPLY (SELECT SUM(CashRefund) AS Cash, SUM(CardRefund) AS Card, SUM(ChargeRefund) AS Charge FROM dbo.POSV2_Return WHERE OrigSaleGUID = @g) AS r
    WHERE p.SaleGUID = @g
    GROUP BY p.PaymentType, r.Cash, r.Card, r.Charge;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── phase 4: customers for charge sales ───────────────────────────
CREATE PROCEDURE dbo.sp_POSV2_GetCustomers
    @BranchCode VARCHAR(10)
AS
/*  The branch's active customers with their credit limit and AR balance, for the terminal's local
    copy (charge sales and the credit-limit check work offline on the last copy + the terminal's own
    unsent charges). */
BEGIN
    SET NOCOUNT ON;
    SELECT c.CustomerKey, c.CustomerName, c.BranchCode, CAST(ISNULL(c.CustomerCreditLimit, 0) AS DECIMAL(18,2)) AS CreditLimit,
           CAST(ISNULL(a.AccountBalance, 0) AS DECIMAL(18,2)) AS Balance
    FROM dbo.Customers AS c
    LEFT JOIN dbo.ClientAccounts AS a ON a.AccountKey = c.CustomerKey
    WHERE ISNULL(c.isActive, 0) = 1 AND c.BranchCode = @BranchCode
    ORDER BY c.CustomerName;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── phase 3: open a shift ─────────────────────────────────────────
CREATE PROCEDURE dbo.spu_POSV2_OpenShift
    @ShiftGUID     UNIQUEIDENTIFIER,
    @TerminalID    INT,
    @ZNo           INT,
    @CashierUserID VARCHAR(50),
    @CashierName   VARCHAR(100),
    @OpenedAt      DATETIME2(0),
    @BeginningCash DECIMAL(18,2),
    @User          VARCHAR(60)
AS
/*  Records a shift the terminal opened (possibly offline, so OpenedAt is the terminal's
    clock). Idempotent by @ShiftGUID (DUPLICATE). One open shift per terminal: the terminal
    sends the previous shift's SHIFTCLOSE before this, so a second open one means a
    reinstalled / restored terminal (61052, needs attention). Errors 61050-61053 are permanent.
    Returns one row: Result (OPENED / DUPLICATE), Message. Caller: POSV2 PosSyncService. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.POSV2_Shift WHERE ShiftGUID = @ShiftGUID)
    BEGIN
        SELECT 'DUPLICATE' AS Result, 'Already open.' AS Message;
        RETURN;
    END

    DECLARE @Branch VARCHAR(10), @Active BIT, @msg NVARCHAR(400);
    SELECT @Branch = BranchCode, @Active = IsActive FROM dbo.POSV2_Terminal WHERE TerminalID = @TerminalID;
    IF @Branch IS NULL THROW 61010, 'Unknown terminal.', 1;
    IF @Active = 0 THROW 61011, 'This terminal is deactivated on the server.', 1;
    IF ISNULL(@ZNo, 0) <= 0 OR ISNULL(LTRIM(@CashierUserID), '') = '' OR @OpenedAt IS NULL
        THROW 61050, 'A shift needs its Z no., cashier and opening time.', 1;
    IF ISNULL(@BeginningCash, -1) < 0 THROW 61051, 'The beginning cash can''t be negative.', 1;
    -- the opening day is the GL date: a terminal clock ahead of the server is refused (an offline terminal may be days behind)
    IF @OpenedAt > DATEADD(DAY, 1, SYSDATETIME())
        THROW 61050, 'The terminal''s clock is ahead of the server''s (shift opening time in the future); set the terminal''s date and time.', 1;

    BEGIN TRY
        BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM dbo.POSV2_Shift WITH (UPDLOCK, HOLDLOCK) WHERE ShiftGUID = @ShiftGUID)
        BEGIN
            COMMIT TRAN;
            SELECT 'DUPLICATE' AS Result, 'Already open.' AS Message;
            RETURN;
        END

        DECLARE @oz INT, @oc VARCHAR(50);
        SELECT @oz = ZNo, @oc = CashierUserID FROM dbo.POSV2_Shift WITH (UPDLOCK, HOLDLOCK) WHERE TerminalID = @TerminalID AND Status = 'OPEN';
        IF @oz IS NOT NULL
        BEGIN
            SET @msg = N'Shift Z#' + CAST(@oz AS NVARCHAR(10)) + N' of ' + @oc + N' is still open on the server for this terminal; close it first.';
            THROW 61052, @msg, 1;
        END
        IF EXISTS (SELECT 1 FROM dbo.POSV2_Shift WITH (UPDLOCK, HOLDLOCK) WHERE TerminalID = @TerminalID AND ZNo = @ZNo)
        BEGIN
            SET @msg = N'Z no. ' + CAST(@ZNo AS NVARCHAR(10)) + N' is already used by another shift of this terminal.';
            THROW 61053, @msg, 1;
        END

        INSERT INTO dbo.POSV2_Shift (ShiftGUID, TerminalID, BranchCode, ZNo, CashierUserID, CashierName, OpenedAt, BusinessDate, BeginningCash)
        VALUES (@ShiftGUID, @TerminalID, @Branch, @ZNo, LEFT(@CashierUserID, 50), @CashierName, @OpenedAt, CAST(@OpenedAt AS DATE), @BeginningCash);

        UPDATE dbo.POSV2_Terminal SET LastSeenAt = SYSDATETIME() WHERE TerminalID = @TerminalID;
        COMMIT TRAN;
        SELECT 'OPENED' AS Result, 'Shift opened.' AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── phase 3: the shift's GL ticket ────────────────────────────────
CREATE PROCEDURE dbo.spu_POSV2_PostShiftGL
    @ShiftGUID    UNIQUEIDENTIFIER,
    @User         VARCHAR(60),
    @TicketNumber VARCHAR(20) OUTPUT
AS
/*  Books ONE GL ticket for a closed shift (mnemonic POSV2-SHIFT, dated the shift's business
    day, on its branch): every leg from JournalEntryMapping, staged in #Legs and netted per
    account (CLAUDE.md compound-entry pattern), so a cash short that exceeds the sales still
    posts a clean entry. Idempotent: a shift already POSTED returns its ticket. A shift with
    nothing to book (no sales, no over / short) is marked POSTED with no ticket.
    Throws on any problem (mapping missing 61062, account not in the COA 61063, unbalanced
    61064, a closed GL month 59900, ...); callers record it on the shift and retry later.
    Callers: spu_POSV2_CloseShift, spu_POSV2_PostPendingShiftGL. No result set. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @TicketNumber = NULL;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @Status VARCHAR(10), @GLStatus VARCHAR(10), @Ticket VARCHAR(20), @Branch VARCHAR(10), @Date DATE, @ZNo INT,
                @Cashier VARCHAR(100), @Prefix VARCHAR(12), @First VARCHAR(30), @Last VARCHAR(30), @Sales INT,
                @Gross DECIMAL(18,2), @Disc DECIMAL(18,2), @VatEx DECIMAL(18,2), @Cash DECIMAL(18,2), @Cost DECIMAL(18,2), @OverShort DECIMAL(18,2),
                @Card DECIMAL(18,2), @Charge DECIMAL(18,2), @RetGross DECIMAL(18,2), @RetDisc DECIMAL(18,2), @RetCost DECIMAL(18,2), @CustCredit DECIMAL(18,2);
        SELECT @Status = s.Status, @GLStatus = s.GLStatus, @Ticket = s.GLTicketNumber, @Branch = s.BranchCode, @Date = s.BusinessDate,
               @ZNo = s.ZNo, @Cashier = ISNULL(s.CashierName, s.CashierUserID), @Prefix = t.ORPrefix, @First = s.FirstORNo, @Last = s.LastORNo,
               @Sales = ISNULL(s.SaleCount, 0) - ISNULL(s.VoidCount, 0),
               @Gross = ISNULL(s.GrossAmount, 0), @Disc = ISNULL(s.DiscountAmount, 0), @VatEx = ISNULL(s.VatExemptAmount, 0),
               @Cash = ISNULL(s.CountedCash, 0) - s.BeginningCash, @Cost = ISNULL(s.CostTotal, 0), @OverShort = ISNULL(s.OverShort, 0),
               @Card = ISNULL(s.CardSales, 0) - ISNULL(s.CardRefunds, 0), @Charge = ISNULL(s.ChargeSales, 0) - ISNULL(s.ChargeRefunds, 0),
               @RetGross = ISNULL(s.ReturnGross, 0), @RetDisc = ISNULL(s.ReturnDiscount, 0), @RetCost = ISNULL(s.ReturnCost, 0), @CustCredit = ISNULL(s.CustomerCredit, 0)
        FROM dbo.POSV2_Shift AS s WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = s.TerminalID
        WHERE s.ShiftGUID = @ShiftGUID;

        IF @Status IS NULL THROW 61060, 'Unknown shift.', 1;
        IF @Status <> 'CLOSED' THROW 61061, 'The shift is not closed (Z-read) yet.', 1;
        IF @GLStatus = 'POSTED'
        BEGIN
            SET @TicketNumber = @Ticket;
            COMMIT TRAN;
            RETURN;
        END

        CREATE TABLE #Amt (AmountType VARCHAR(30) NOT NULL PRIMARY KEY, Amount DECIMAL(18,2) NOT NULL);
        INSERT INTO #Amt (AmountType, Amount) VALUES
            ('CASH', @Cash), ('DISCOUNT', @Disc), ('VATEXEMPT', @VatEx), ('GROSS', @Gross), ('COST', @Cost),
            ('CARD', @Card), ('CHARGE', @Charge), ('RETGROSS', @RetGross), ('RETDISC', @RetDisc), ('RETCOST', @RetCost), ('CUSTCREDIT', @CustCredit),
            ('SHORT', CASE WHEN @OverShort < 0 THEN -@OverShort ELSE 0 END),
            ('OVER',  CASE WHEN @OverShort > 0 THEN @OverShort ELSE 0 END);

        IF NOT EXISTS (SELECT 1 FROM #Amt WHERE Amount <> 0)
        BEGIN
            UPDATE dbo.POSV2_Shift SET GLStatus = 'POSTED', GLTicketNumber = NULL, GLPostedAt = SYSDATETIME(),
                   GLMessage = N'Nothing to book (no sales, no over / short).'
            WHERE ShiftGUID = @ShiftGUID;
            COMMIT TRAN;
            RETURN;
        END

        DECLARE @msg NVARCHAR(400);
        SELECT TOP 1 @msg = N'No active JournalEntryMapping row for POSV2-SHIFT amount type ' + a.AmountType + N'.'
        FROM #Amt AS a
        WHERE a.Amount <> 0
          AND NOT EXISTS (SELECT 1 FROM dbo.JournalEntryMapping AS m
                          WHERE m.Origin = 'POSV2' AND m.Mnemonic = 'POSV2-SHIFT' AND m.IsActive = 1 AND m.AmountType = a.AmountType);
        IF @msg IS NOT NULL THROW 61062, @msg, 1;

        SELECT TOP 1 @msg = N'POSV2-SHIFT maps ' + m.AmountType + N' to account ' + m.AccountCode + N', which is not in ChartOfAccounts.'
        FROM dbo.JournalEntryMapping AS m
        WHERE m.Origin = 'POSV2' AND m.Mnemonic = 'POSV2-SHIFT' AND m.IsActive = 1
          AND EXISTS (SELECT 1 FROM #Amt AS a WHERE a.AmountType = m.AmountType AND a.Amount <> 0)   -- only the legs this shift uses (S8)
          AND NOT EXISTS (SELECT 1 FROM dbo.ChartOfAccounts AS c WHERE c.AccountCode = m.AccountCode);
        IF @msg IS NOT NULL THROW 61063, @msg, 1;

        -- every leg, then one netting pass per account (a negative amount simply nets to the other side)
        SELECT m.AccountCode,
               CAST(CASE WHEN m.DebitCredit = 'D' THEN a.Amount ELSE 0 END AS DECIMAL(18,2)) AS Debit,
               CAST(CASE WHEN m.DebitCredit = 'C' THEN a.Amount ELSE 0 END AS DECIMAL(18,2)) AS Credit
        INTO #Legs
        FROM dbo.JournalEntryMapping AS m
        INNER JOIN #Amt AS a ON a.AmountType = m.AmountType
        WHERE m.Origin = 'POSV2' AND m.Mnemonic = 'POSV2-SHIFT' AND m.IsActive = 1 AND a.Amount <> 0;

        IF (SELECT ABS(SUM(Debit) - SUM(Credit)) FROM #Legs) > 0.005
            THROW 61064, 'The POSV2-SHIFT entry doesn''t balance (DR <> CR); check the mapping rows (each amount type once per side).', 1;

        DECLARE @tn VARCHAR(20), @ref VARCHAR(150) = @Prefix + '-Z' + RIGHT('000000' + CAST(@ZNo AS VARCHAR(10)), 6),
                @key VARCHAR(150) = CAST(@ShiftGUID AS VARCHAR(36));
        EXEC dbo.GetTicketNumber @tn OUTPUT;

        INSERT INTO dbo.TicketMaster
            (TicketDate, SupplementaryNumber, BranchCode, Origin, TicketNumber, ReferenceNumber, ReferenceKey, Owner, Particulars,
             EnteredBy, CheckedBy, ApprovedBy, Status, Mnemonic, Product)
        VALUES
            (@Date, 0, @Branch, 'POSV2', @tn, @ref, @key, LEFT(@Cashier, 150),
             'POS V2 shift Z#' + CAST(@ZNo AS VARCHAR(10)) + ' terminal ' + @Prefix + ', cashier ' + @Cashier + ', '
                 + CAST(@Sales AS VARCHAR(10)) + ' sale(s)' + ISNULL(', OR ' + @First + ' to ' + @Last, ''),
             LEFT(ISNULL(@User, ''), 128), '*', '*', 'POSTED', 'POSV2-SHIFT', NULL);

        INSERT INTO dbo.TicketDetails
            (TicketDate, SupplementaryNumber, BranchCode, ReferenceKey, TicketNumber, ReferenceNumber, AccountCode, Debit, Credit, CostCenter)
        SELECT @Date, 0, @Branch, @key, @tn, @ref, AccountCode,
               CASE WHEN NetAmount > 0 THEN NetAmount ELSE 0 END,
               CASE WHEN NetAmount < 0 THEN -NetAmount ELSE 0 END, ''
        FROM (SELECT AccountCode, ROUND(SUM(Debit) - SUM(Credit), 2) AS NetAmount FROM #Legs GROUP BY AccountCode) AS n
        WHERE NetAmount <> 0;

        IF NOT EXISTS (SELECT 1 FROM dbo.TicketDetails WHERE TicketNumber = @tn)
           OR (SELECT SUM(Debit) - SUM(Credit) FROM dbo.TicketDetails WHERE TicketNumber = @tn) <> 0
            THROW 61064, 'Post-check: the shift ticket doesn''t balance; nothing was booked.', 1;

        UPDATE dbo.POSV2_Shift SET GLStatus = 'POSTED', GLTicketNumber = @tn, GLPostedAt = SYSDATETIME(), GLMessage = NULL
        WHERE ShiftGUID = @ShiftGUID;

        COMMIT TRAN;
        SET @TicketNumber = @tn;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── phase 3: close a shift (Z-reading) ────────────────────────────
CREATE PROCEDURE dbo.spu_POSV2_CloseShift
    @ShiftGUID        UNIQUEIDENTIFIER,
    @TerminalID       INT,
    @ClosedAt         DATETIME2(0),
    @CountedCash      DECIMAL(18,2),
    @SaleCount        INT,               -- the terminal's own Z figures: every OR of the shift ...
    @VoidCount        INT,               -- ... the voided ones ...
    @NetAmount        DECIMAL(18,2),     -- ... and the net of the ones not voided
    @ClearedSaleCount  INT = 0,
    @ClearedSaleAmount DECIMAL(18,2) = 0,
    @DrawerOpenCount   INT = 0,
    @ClosedBy         VARCHAR(60),
    @ApprovedBy       VARCHAR(60) = NULL,   -- supervisor, when @ClosedBy is not the shift's cashier
    @User             VARCHAR(60),
    @ClearedLineCount  INT = 0,             -- lines removed (Del) from sales that were then cleared (F8): on the Z too
    @ClearedLineAmount DECIMAL(18,2) = 0,
    @Force            BIT = 0,              -- admin only, through spu_POSV2_ForceCloseShift
    @ForceReason      VARCHAR(300) = NULL,
    @ReturnCount      INT = NULL,            -- phase 4: the terminal's returns in this shift (count and refunded net), checked too
    @ReturnNet        DECIMAL(18,2) = NULL,
    @TerminalAccumulatedAfter DECIMAL(18,2) = NULL   -- phase 5 review: the grand total the terminal printed; stored, a difference is listed (not refused)
AS
/*  Closes a shift: every figure is re-derived from the server's own sale rows, and the close is
    refused (61057, permanent) when the terminal's sale count / void count / net differ, i.e. a
    sale of the shift isn't on the server (refused earlier, needs attention). Then the GL ticket
    (spu_POSV2_PostShiftGL) in its own transaction: if it fails the shift stays CLOSED with
    GLStatus FAILED and the reason, and spu_POSV2_PostPendingShiftGL retries it later.
    @Force = 1 (spu_POSV2_ForceCloseShift, an admin): no comparison with the terminal; closes with
    the server's figures and records who and why (a shift stuck open on the server).
    Must not be called inside an outer transaction (the GL step's rollback would end it).
    Idempotent: a closed shift returns DUPLICATE. Errors 61054-61059, 61065, 61066 are permanent.
    Returns one row: Result (CLOSED / DUPLICATE), GLStatus, GLTicketNumber, OverShort, Message. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @msg NVARCHAR(1000), @Status VARCHAR(10), @Term INT, @Cashier VARCHAR(50), @Beg DECIMAL(18,2), @Branch VARCHAR(10), @Opened DATETIME2(0);
    SELECT @Status = Status, @Term = TerminalID, @Cashier = CashierUserID, @Beg = BeginningCash, @Branch = BranchCode, @Opened = OpenedAt
    FROM dbo.POSV2_Shift WHERE ShiftGUID = @ShiftGUID;
    IF @Status IS NULL THROW 61054, 'The shift to close is not on the server.', 1;
    IF @Term <> @TerminalID THROW 61055, 'The shift to close belongs to another terminal.', 1;
    IF @Status = 'CLOSED'
    BEGIN
        SELECT 'DUPLICATE' AS Result, GLStatus, GLTicketNumber, OverShort, 'Already closed.' AS Message FROM dbo.POSV2_Shift WHERE ShiftGUID = @ShiftGUID;
        RETURN;
    END
    IF @CountedCash IS NULL OR @CountedCash < 0 OR @ClosedAt IS NULL OR @ClosedAt < @Opened
        THROW 61056, 'A close needs the cash counted (not negative) and a closing time after the opening.', 1;
    IF ISNULL(@ClearedLineCount, 0) < 0 OR ISNULL(@ClearedLineAmount, 0) < 0
        THROW 61056, 'The cleared-line count / amount can''t be negative.', 1;
    SET @ApprovedBy = NULLIF(LTRIM(RTRIM(@ApprovedBy)), '');
    IF @Force = 1
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserID = @User AND isAdmin = 1) OR ISNULL(LTRIM(@ForceReason), '') = ''
            THROW 61066, 'Only an admin can force a shift closed, and only with a reason.', 1;
    END
    ELSE
    BEGIN
        IF ISNULL(@ClosedBy, '') <> @Cashier AND @ApprovedBy IS NULL
            THROW 61058, 'Someone else closing the cashier''s shift needs a supervisor''s approval.', 1;
        IF @ApprovedBy IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.POSV2_Supervisor WHERE UserID = @ApprovedBy AND (BranchCode IS NULL OR BranchCode = @Branch))
            THROW 61059, 'The close''s approver is not a POS supervisor of this branch on the server.', 1;
    END

    BEGIN TRY
        BEGIN TRAN;
        SELECT @Status = Status FROM dbo.POSV2_Shift WITH (UPDLOCK, HOLDLOCK) WHERE ShiftGUID = @ShiftGUID;
        IF @Status = 'CLOSED'
        BEGIN
            COMMIT TRAN;
            SELECT 'DUPLICATE' AS Result, GLStatus, GLTicketNumber, OverShort, 'Already closed.' AS Message FROM dbo.POSV2_Shift WHERE ShiftGUID = @ShiftGUID;
            RETURN;
        END

        DECLARE @sc INT, @vc INT, @va DECIMAL(18,2), @gross DECIMAL(18,2), @net DECIMAL(18,2), @vatable DECIMAL(18,2), @vat DECIMAL(18,2),
                @exempt DECIMAL(18,2), @zero DECIMAL(18,2), @cash DECIMAL(18,2), @clc INT, @cla DECIMAL(18,2), @first VARCHAR(30), @last VARCHAR(30);
        SELECT @sc = COUNT(*),
               @vc = SUM(CASE WHEN Status = 'VOIDED' THEN 1 ELSE 0 END),
               @va = SUM(CASE WHEN Status = 'VOIDED' THEN NetAmount ELSE 0 END),
               @gross = SUM(CASE WHEN Status <> 'VOIDED' THEN GrossAmount ELSE 0 END),
               @net = SUM(CASE WHEN Status <> 'VOIDED' THEN NetAmount ELSE 0 END),
               @vatable = SUM(CASE WHEN Status <> 'VOIDED' THEN VatableSales ELSE 0 END),
               @vat = SUM(CASE WHEN Status <> 'VOIDED' THEN VatAmount ELSE 0 END),
               @exempt = SUM(CASE WHEN Status <> 'VOIDED' THEN VatExemptSales ELSE 0 END),
               @zero = SUM(CASE WHEN Status <> 'VOIDED' THEN ZeroRatedSales ELSE 0 END),
               @clc = SUM(CancelledLineCount), @cla = SUM(CancelledLineAmount),
               @first = MIN(ORNo), @last = MAX(ORNo)
        FROM dbo.POSV2_Sale WHERE ShiftGUID = @ShiftGUID;

        -- what was paid by kind, sales not voided: cash less change, card, charge (phase 4)
        DECLARE @card DECIMAL(18,2), @charge DECIMAL(18,2);
        SELECT @cash = ISNULL(SUM(p.Cash - s.ChangeAmount), 0), @card = ISNULL(SUM(p.Card), 0), @charge = ISNULL(SUM(p.Charge), 0)
        FROM dbo.POSV2_Sale AS s
        CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN PaymentType = 'CASH' THEN Amount END), 0) AS Cash,
                            ISNULL(SUM(CASE WHEN PaymentType = 'CARD' THEN Amount END), 0) AS Card,
                            ISNULL(SUM(CASE WHEN PaymentType = 'CHARGE' THEN Amount END), 0) AS Charge
                     FROM dbo.POSV2_Payment WHERE SaleGUID = s.SaleGUID) AS p
        WHERE s.ShiftGUID = @ShiftGUID AND s.Status <> 'VOIDED';

        -- returns paid back in this shift (of any earlier sale)
        DECLARE @rc INT, @rGross DECIMAL(18,2), @rDisc DECIMAL(18,2), @rNet DECIMAL(18,2), @rCost DECIMAL(18,2),
                @rCash DECIMAL(18,2), @rCard DECIMAL(18,2), @rCharge DECIMAL(18,2), @rExcess DECIMAL(18,2);
        SELECT @rc = COUNT(*), @rGross = ISNULL(SUM(GrossAmount), 0), @rDisc = ISNULL(SUM(DiscountAmount), 0), @rNet = ISNULL(SUM(NetAmount), 0),
               @rCost = ISNULL(SUM(CostTotal), 0), @rCash = ISNULL(SUM(CashRefund), 0), @rCard = ISNULL(SUM(CardRefund), 0),
               @rCharge = ISNULL(SUM(ChargeRefund - ChargeExcess), 0), @rExcess = ISNULL(SUM(ChargeExcess), 0)
        FROM dbo.POSV2_Return WHERE ShiftGUID = @ShiftGUID;

        -- phase 5 (BIR): the returns split like the sales (by the original line's VAT), and the accumulated grand total
        DECLARE @rVatable DECIMAL(18,2), @rVat DECIMAL(18,2), @rExempt DECIMAL(18,2), @accBefore DECIMAL(18,2);
        SELECT @rVatable = ISNULL(SUM(CASE WHEN sl.IsVat = 1 THEN rl.NetAmount - rl.VatAmount END), 0),
               @rVat = ISNULL(SUM(CASE WHEN sl.IsVat = 1 THEN rl.VatAmount END), 0),
               @rExempt = ISNULL(SUM(CASE WHEN sl.IsVat = 0 THEN rl.NetAmount END), 0)
        FROM dbo.POSV2_ReturnLine AS rl
        INNER JOIN dbo.POSV2_Return AS r ON r.ReturnGUID = rl.ReturnGUID
        INNER JOIN dbo.POSV2_SaleLine AS sl ON sl.SaleGUID = r.OrigSaleGUID AND sl.[LineNo] = rl.OrigLineNo
        WHERE r.ShiftGUID = @ShiftGUID;
        SET @accBefore = ISNULL((SELECT TOP 1 p.AccumulatedAfter FROM dbo.POSV2_Shift AS p
                                 WHERE p.TerminalID = @TerminalID AND p.Status = 'CLOSED' AND p.AccumulatedAfter IS NOT NULL
                                   AND p.ZNo < (SELECT ZNo FROM dbo.POSV2_Shift WHERE ShiftGUID = @ShiftGUID)
                                 ORDER BY p.ZNo DESC), 0);
        DECLARE @bir VARCHAR(50) = (SELECT ISNULL(NULLIF(BIRMachine, ''), TerminalCode) FROM dbo.POSV2_Terminal WHERE TerminalID = @TerminalID);

        DECLARE @disc DECIMAL(18,2), @vatex DECIMAL(18,2), @cost DECIMAL(18,2);
        SELECT @disc = ISNULL(SUM(l.DiscountAmount), 0), @vatex = ISNULL(SUM(l.VatExemptAmount), 0), @cost = ISNULL(SUM(l.CostTotal), 0)
        FROM dbo.POSV2_SaleLine AS l INNER JOIN dbo.POSV2_Sale AS s ON s.SaleGUID = l.SaleGUID
        WHERE s.ShiftGUID = @ShiftGUID AND s.Status <> 'VOIDED';

        IF @Force = 0 AND (@sc <> ISNULL(@SaleCount, -1) OR ISNULL(@vc, 0) <> ISNULL(@VoidCount, -1) OR ISNULL(@net, 0) <> ISNULL(@NetAmount, -1)
                           OR @rc <> ISNULL(@ReturnCount, 0) OR @rNet <> ISNULL(@ReturnNet, 0))
        BEGIN
            SET @msg = N'The server has ' + CAST(@sc AS NVARCHAR(10)) + N' sale(s), ' + CAST(ISNULL(@vc, 0) AS NVARCHAR(10)) + N' voided, net '
                     + CONVERT(NVARCHAR(30), ISNULL(@net, 0)) + N'; the terminal''s Z-reading says ' + CAST(ISNULL(@SaleCount, 0) AS NVARCHAR(10))
                     + N', ' + CAST(ISNULL(@VoidCount, 0) AS NVARCHAR(10)) + N', ' + CONVERT(NVARCHAR(30), ISNULL(@NetAmount, 0))
                     + N'; returns: server ' + CAST(@rc AS NVARCHAR(10)) + N' / ' + CONVERT(NVARCHAR(30), @rNet) + N', terminal ' + CAST(ISNULL(@ReturnCount, 0) AS NVARCHAR(10))
                     + N' / ' + CONVERT(NVARCHAR(30), ISNULL(@ReturnNet, 0)) + N'. A sale or return of this shift is not on the server yet (see what needs attention).';
            THROW 61057, @msg, 1;
        END

        UPDATE dbo.POSV2_Shift
        SET Status = 'CLOSED', ClosedAt = @ClosedAt, ClosedBy = LEFT(CASE WHEN @Force = 1 THEN @User ELSE ISNULL(@ClosedBy, '') END, 60), CloseApprovedBy = LEFT(@ApprovedBy, 60),
            ForcedBy = CASE WHEN @Force = 1 THEN LEFT(@User, 60) END, ForceReason = CASE WHEN @Force = 1 THEN LEFT(@ForceReason, 300) END,
            CountedCash = @CountedCash, ExpectedCash = @Beg + @cash - @rCash, OverShort = @CountedCash - (@Beg + @cash - @rCash),
            SaleCount = @sc, VoidCount = ISNULL(@vc, 0), VoidAmount = ISNULL(@va, 0),
            GrossAmount = ISNULL(@gross, 0), DiscountAmount = @disc, VatExemptAmount = @vatex, NetAmount = ISNULL(@net, 0),
            VatableSales = ISNULL(@vatable, 0), VatAmount = ISNULL(@vat, 0), VatExemptSales = ISNULL(@exempt, 0), ZeroRatedSales = ISNULL(@zero, 0),
            CashSales = @cash, CardSales = @card, ChargeSales = @charge, CostTotal = @cost,
            ReturnCount = @rc, ReturnGross = @rGross, ReturnDiscount = @rDisc, ReturnNet = @rNet, ReturnCost = @rCost,
            CashRefunds = @rCash, CardRefunds = @rCard, ChargeRefunds = @rCharge, CustomerCredit = @rExcess,
            ReturnVatable = @rVatable, ReturnVat = @rVat, ReturnExempt = @rExempt,
            AccumulatedBefore = @accBefore, AccumulatedAfter = @accBefore + ISNULL(@net, 0),
            TerminalAccumulatedAfter = CASE WHEN @Force = 1 THEN NULL ELSE @TerminalAccumulatedAfter END, BIRMachine = @bir,
            CancelledLineCount = ISNULL(@clc, 0) + ISNULL(@ClearedLineCount, 0), CancelledLineAmount = ISNULL(@cla, 0) + ISNULL(@ClearedLineAmount, 0),
            ClearedSaleCount = ISNULL(@ClearedSaleCount, 0), ClearedSaleAmount = ISNULL(@ClearedSaleAmount, 0), DrawerOpenCount = ISNULL(@DrawerOpenCount, 0),
            FirstORNo = @first, LastORNo = @last, GLStatus = 'PENDING', ClosePostedAt = SYSDATETIME()
        WHERE ShiftGUID = @ShiftGUID;

        -- post-check: the GL identities hold on what was stored: gross - discounts = net = cash + card + charge;
        -- returned gross - discounts = refunded = cash + card + charge (incl. any customer credit)
        IF EXISTS (SELECT 1 FROM dbo.POSV2_Shift WHERE ShiftGUID = @ShiftGUID
                   AND (GrossAmount - DiscountAmount - VatExemptAmount <> NetAmount OR NetAmount <> CashSales + CardSales + ChargeSales
                        OR ReturnGross - ReturnDiscount <> ReturnNet OR ReturnNet <> CashRefunds + CardRefunds + ChargeRefunds + CustomerCredit
                        -- phase 5 review (S10): the BIR split adds up too (exact: each sale and return line is checked on posting)
                        OR VatableSales + VatAmount + VatExemptSales + ZeroRatedSales <> NetAmount
                        OR ReturnVatable + ReturnVat + ReturnExempt <> ReturnNet))
            THROW 61065, 'Post-check: the shift''s gross - discounts is not its net / payments (or its returns'' refunds), or its VAT split is not its net; nothing was closed.', 1;

        UPDATE dbo.POSV2_Terminal SET LastSeenAt = SYSDATETIME() WHERE TerminalID = @TerminalID;
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH

    -- the GL, separately: a failure never undoes the close
    DECLARE @tn VARCHAR(20);
    BEGIN TRY
        EXEC dbo.spu_POSV2_PostShiftGL @ShiftGUID = @ShiftGUID, @User = @User, @TicketNumber = @tn OUTPUT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        SET @msg = N'GL not booked yet (' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N'): ' + ERROR_MESSAGE();
        UPDATE dbo.POSV2_Shift SET GLStatus = 'FAILED', GLMessage = LEFT(@msg, 1000) WHERE ShiftGUID = @ShiftGUID AND GLStatus <> 'POSTED';
    END CATCH

    SELECT 'CLOSED' AS Result, GLStatus, GLTicketNumber, OverShort,
           CASE WHEN GLStatus = 'POSTED' THEN N'Shift closed; GL ticket ' + COALESCE(CAST(GLTicketNumber AS NVARCHAR(20)), N'(none: nothing to book)') + N'.'
                ELSE N'Shift closed. ' + COALESCE(GLMessage, N'') END AS Message
    FROM dbo.POSV2_Shift WHERE ShiftGUID = @ShiftGUID;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── phase 3: retry the GL of closed shifts ────────────────────────
CREATE PROCEDURE dbo.spu_POSV2_PostPendingShiftGL
    @TerminalID INT = NULL,          -- NULL = every terminal
    @User       VARCHAR(60)
AS
/*  Tries the GL of every closed shift still PENDING / FAILED (e.g. after an admin reopened a
    closed month or the accountant fixed a mapping row). One shift's failure doesn't stop the
    others. Returns one row per shift tried: ShiftGUID, ZNo, GLStatus, GLTicketNumber, GLMessage.
    Callers: POSV2 PosSyncService (its own terminal, every 30 minutes), or run by hand. */
BEGIN
    SET NOCOUNT ON;
    DECLARE @todo TABLE (ShiftGUID UNIQUEIDENTIFIER PRIMARY KEY);
    INSERT INTO @todo SELECT ShiftGUID FROM dbo.POSV2_Shift
    WHERE Status = 'CLOSED' AND GLStatus IN ('PENDING', 'FAILED') AND (@TerminalID IS NULL OR TerminalID = @TerminalID);

    DECLARE @g UNIQUEIDENTIFIER, @tn VARCHAR(20), @msg NVARCHAR(1000);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT ShiftGUID FROM @todo;
    OPEN c; FETCH NEXT FROM c INTO @g;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC dbo.spu_POSV2_PostShiftGL @ShiftGUID = @g, @User = @User, @TicketNumber = @tn OUTPUT;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRAN;
            SET @msg = N'GL not booked yet (' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N'): ' + ERROR_MESSAGE();
            UPDATE dbo.POSV2_Shift SET GLStatus = 'FAILED', GLMessage = LEFT(@msg, 1000) WHERE ShiftGUID = @g AND GLStatus <> 'POSTED';
        END CATCH
        FETCH NEXT FROM c INTO @g;
    END
    CLOSE c; DEALLOCATE c;

    SELECT s.ShiftGUID, s.ZNo, s.GLStatus, s.GLTicketNumber, s.GLMessage
    FROM dbo.POSV2_Shift AS s INNER JOIN @todo AS t ON t.ShiftGUID = s.ShiftGUID
    ORDER BY s.ZNo;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── phase 3: supervisors ──────────────────────────────────────────
CREATE PROCEDURE dbo.sp_POSV2_GetSupervisors
    @BranchCode VARCHAR(10)
AS
/*  The active supervisors who may approve on this branch's terminals, with their PIN hash
    (never the PIN), for the terminal's local copy: approvals work offline. */
BEGIN
    SET NOCOUNT ON;
    SELECT s.UserID, ISNULL(u.FullName, s.UserID) AS FullName, s.PinHash, s.PinSalt, s.PinIterations
    FROM dbo.POSV2_Supervisor AS s
    LEFT JOIN dbo.Users AS u ON u.UserID = s.UserID
    WHERE s.IsActive = 1 AND (s.BranchCode IS NULL OR s.BranchCode = @BranchCode)
    ORDER BY s.UserID;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.sp_POSV2_ListSupervisors
AS
/*  For the admin screen: every user, and whether / where each one is a POS supervisor. No hashes. */
BEGIN
    SET NOCOUNT ON;
    SELECT u.UserID, u.FullName, u.AssignedBranch,
           CAST(CASE WHEN s.UserID IS NULL THEN 0 ELSE 1 END AS BIT) AS IsSupervisor,
           ISNULL(s.BranchCode, CASE WHEN s.UserID IS NULL THEN NULL ELSE '(all)' END) AS SupervisorBranch,
           ISNULL(s.IsActive, 0) AS IsActive, s.UpdatedAt, s.UpdatedBy
    FROM dbo.Users AS u
    LEFT JOIN dbo.POSV2_Supervisor AS s ON s.UserID = u.UserID
    ORDER BY CASE WHEN s.UserID IS NULL THEN 1 ELSE 0 END, u.UserID;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.spu_POSV2_SetSupervisor
    @UserID        VARCHAR(50),
    @BranchCode    VARCHAR(10) = NULL,       -- NULL = keep the current branch (a new one: every branch); '' = every branch
    @PinHash       VARBINARY(32) = NULL,     -- NULL = keep the current PIN
    @PinSalt       VARBINARY(16) = NULL,
    @PinIterations INT = NULL,
    @IsActive      BIT,
    @User          VARCHAR(60)               -- must be an admin
AS
/*  Makes a user a POS supervisor, changes the branch / PIN, or deactivates one. The PIN is hashed
    on the admin's machine (Classes/PasswordHasher); only the hash arrives. Every change is logged in
    POSV2_SupervisorLog with the SQL login and machine. Errors 61080-61084.
    Trust model (sp-reviewer B2): like every proc of this ERP, @User is the app's logged-in user, sent by the
    client over the shared SQL login; the log's LoginName / HostName are what the server itself knows. */
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @BranchCode = LTRIM(RTRIM(@BranchCode));
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserID = @User AND isAdmin = 1)
        THROW 61083, 'Only an admin can change POS supervisors.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE UserID = @UserID)
        THROW 61080, 'Unknown user.', 1;
    IF NULLIF(@BranchCode, '') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchCode = @BranchCode)
        THROW 61084, 'Unknown branch.', 1;
    IF @PinHash IS NOT NULL AND (DATALENGTH(@PinHash) <> 32 OR DATALENGTH(@PinSalt) <> 16 OR ISNULL(@PinIterations, 0) < 100000)
        THROW 61082, 'The PIN hash is not in the expected form.', 1;

    BEGIN TRAN;
    INSERT INTO dbo.POSV2_SupervisorLog (UserID, BranchCode, IsActive, PinChanged, ChangedBy)
    VALUES (@UserID, @BranchCode, @IsActive, CASE WHEN @PinHash IS NULL THEN 0 ELSE 1 END, LEFT(@User, 60));
    IF EXISTS (SELECT 1 FROM dbo.POSV2_Supervisor WITH (UPDLOCK, HOLDLOCK) WHERE UserID = @UserID)
        UPDATE dbo.POSV2_Supervisor
        SET BranchCode = CASE WHEN @BranchCode IS NULL THEN BranchCode ELSE NULLIF(@BranchCode, '') END, IsActive = @IsActive,
            PinHash = ISNULL(@PinHash, PinHash), PinSalt = CASE WHEN @PinHash IS NULL THEN PinSalt ELSE @PinSalt END,
            PinIterations = CASE WHEN @PinHash IS NULL THEN PinIterations ELSE @PinIterations END,
            UpdatedAt = SYSDATETIME(), UpdatedBy = LEFT(@User, 60)
        WHERE UserID = @UserID;
    ELSE
    BEGIN
        IF @PinHash IS NULL
        BEGIN
            ROLLBACK TRAN;
            THROW 61081, 'A new supervisor needs a PIN.', 1;
        END
        INSERT INTO dbo.POSV2_Supervisor (UserID, BranchCode, PinHash, PinSalt, PinIterations, IsActive, UpdatedBy)
        VALUES (@UserID, NULLIF(@BranchCode, ''), @PinHash, @PinSalt, @PinIterations, @IsActive, LEFT(@User, 60));
    END
    COMMIT TRAN;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── phase 3: force a stuck shift closed (admin, run by hand) ──────
CREATE PROCEDURE dbo.spu_POSV2_ForceCloseShift
    @ShiftGUID   UNIQUEIDENTIFIER,
    @CountedCash DECIMAL(18,2),
    @Reason      VARCHAR(300),
    @User        VARCHAR(60)        -- must be an admin
AS
/*  Last resort (sp-reviewer B3) for a shift still OPEN on the server that its terminal can't close (the terminal was
    reinstalled / lost, or one of its sales can never post). Closes it with the server's own figures (no comparison
    with a terminal Z-reading), records ForcedBy / ForceReason and books the GL as a normal close. Anything the
    terminal sends for that shift afterwards is refused (61031 sales, 61044 voids) or DUPLICATE (its close).
    Same result row as spu_POSV2_CloseShift. */
BEGIN
    SET NOCOUNT ON;
    DECLARE @tid INT = (SELECT TerminalID FROM dbo.POSV2_Shift WHERE ShiftGUID = @ShiftGUID);
    IF @tid IS NULL THROW 61054, 'The shift to close is not on the server.', 1;
    DECLARE @now DATETIME2(0) = SYSDATETIME();
    EXEC dbo.spu_POSV2_CloseShift @ShiftGUID = @ShiftGUID, @TerminalID = @tid, @ClosedAt = @now, @CountedCash = @CountedCash,
         @SaleCount = NULL, @VoidCount = NULL, @NetAmount = NULL, @ClosedBy = @User, @User = @User, @Force = 1, @ForceReason = @Reason;
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

-- ── phase 5: reports ───────────────────────────────────────────────
-- One row per closed shift in the shape of the old POS Z-reading table (POSZReadingTransactions), so the BIR
-- reports (E-Sales, POS Sales Summary, 2550M) can add POS V2 next to the old POS (SQL/POSV2/..._03_BIRReports.sql).
-- Sales of the shift less the returns it paid back (by the original line's VAT). Voided sales are already out.
-- A shift belongs to its BusinessDate (the day it opened), like the old POS's DateExecute: sales after midnight of a
-- shift that crossed it count on the opening day here and in the GL ticket, while the sales journal lists each OR by
-- its own date. The machine is the one stored at close (BIRMachine), so editing the mapping later doesn't move filed
-- months. POS V2 has no zero-rated lines (the sale proc requires 0), so ZeroRatedSale is always 0.
CREATE FUNCTION dbo.fn_POSV2_ZReadings (@DateFrom DATE, @DateTo DATE)
RETURNS TABLE
AS
RETURN
    SELECT s.BranchCode, COALESCE(NULLIF(s.BIRMachine, ''), NULLIF(t.BIRMachine, ''), t.TerminalCode) AS MachineUsed, t.TerminalCode, t.ORPrefix,
           s.BusinessDate AS DateExecute, s.ZNo, s.ShiftGUID, s.CashierUserID, s.CashierName,
           CAST(s.VatExemptSales - ISNULL(s.ReturnExempt, 0) AS DECIMAL(18,2)) AS VatExemptSale,
           CAST(s.VatableSales - ISNULL(s.ReturnVatable, 0) AS DECIMAL(18,2)) AS VatableSale,
           CAST(s.VatAmount - ISNULL(s.ReturnVat, 0) AS DECIMAL(18,2)) AS VatInput,
           CAST(s.ZeroRatedSales AS DECIMAL(18,2)) AS ZeroRatedSale,
           s.GrossAmount, CAST(s.DiscountAmount + s.VatExemptAmount AS DECIMAL(18,2)) AS TotalDiscount,
           s.NetAmount AS NetSales, ISNULL(s.ReturnNet, 0) AS ReturnNet, CAST(s.NetAmount - ISNULL(s.ReturnNet, 0) AS DECIMAL(18,2)) AS NetOfReturns,
           s.VoidCount, s.VoidAmount, s.SaleCount, s.FirstORNo AS BeginningSINo, s.LastORNo AS EndingSINo,
           s.AccumulatedBefore, s.AccumulatedAfter
    FROM dbo.POSV2_Shift AS s
    INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = s.TerminalID
    WHERE s.Status = 'CLOSED' AND s.BusinessDate BETWEEN @DateFrom AND @DateTo;
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.sp_rpt_POSV2_Shifts
    @BranchCode VARCHAR(10) = NULL,      -- NULL = every branch
    @DateFrom   DATE,
    @DateTo     DATE
AS
/*  POS V2 Z-readings: one row per shift opened in the period (open ones too), with every figure the close stored,
    the GL ticket and its state. Numeric columns stay numeric. Read-only. Caller: POSV2 PosV2ReportsForm. */
BEGIN
    SET NOCOUNT ON;
    SELECT s.BranchCode, b.BranchName, t.TerminalCode, COALESCE(NULLIF(s.BIRMachine, ''), NULLIF(t.BIRMachine, ''), t.TerminalCode) AS BIRMachine, s.ZNo, s.Status,
           s.BusinessDate, s.OpenedAt, s.ClosedAt, s.CashierUserID, s.CashierName, s.ClosedBy, s.CloseApprovedBy, s.ForcedBy, s.ForceReason,
           s.FirstORNo, s.LastORNo, s.SaleCount, s.VoidCount, s.VoidAmount,
           s.GrossAmount, s.DiscountAmount, s.VatExemptAmount, s.NetAmount, s.VatableSales, s.VatAmount, s.VatExemptSales, s.ZeroRatedSales,
           s.CashSales, s.CardSales, s.ChargeSales, s.ReturnCount, s.ReturnNet, s.CashRefunds, s.CardRefunds, s.ChargeRefunds, s.CustomerCredit,
           s.BeginningCash, s.ExpectedCash, s.CountedCash, s.OverShort, s.CostTotal, s.ReturnCost,
           s.CancelledLineCount, s.CancelledLineAmount, s.ClearedSaleCount, s.ClearedSaleAmount, s.DrawerOpenCount,
           s.AccumulatedBefore, s.AccumulatedAfter, s.TerminalAccumulatedAfter, s.GLStatus, s.GLTicketNumber, s.GLMessage
    FROM dbo.POSV2_Shift AS s
    INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = s.TerminalID
    LEFT JOIN dbo.Branches AS b ON b.BranchCode = s.BranchCode
    WHERE s.BusinessDate BETWEEN @DateFrom AND @DateTo AND (@BranchCode IS NULL OR s.BranchCode = @BranchCode)
    ORDER BY s.BranchCode, t.TerminalCode, s.ZNo
    OPTION (RECOMPILE);
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.sp_rpt_POSV2_SalesJournal
    @BranchCode VARCHAR(10) = NULL,
    @DateFrom   DATE,
    @DateTo     DATE
AS
/*  POS V2 sales journal: one row per OR of the period (by sale date), voided ones included and marked, with the
    payments by kind (cash net of change), the customer of a charge and anything flagged for review. Read-only.
    By the OR's own date: for a shift that crossed midnight it can differ from the Z-reading / BIR reports, which
    count the whole shift on its opening day (fn_POSV2_ZReadings). */
BEGIN
    SET NOCOUNT ON;
    SELECT s.BranchCode, t.TerminalCode, s.ORNo, s.SaleDateTime, s.Status, sh.ZNo, s.CashierUserID, s.CashierName,
           s.CustomerKey, c.CustomerName, s.ItemCount,
           s.GrossAmount, s.DiscountAmount, s.NetAmount, s.VatableSales, s.VatAmount, s.VatExemptSales, s.ZeroRatedSales,
           CAST(ISNULL(p.Cash, 0) - s.ChangeAmount AS DECIMAL(18,2)) AS CashPaid, ISNULL(p.Card, 0) AS CardPaid, ISNULL(p.Charge, 0) AS ChargePaid,
           s.ARReferenceNo, p.CardRef, s.DiscountApprovedBy, s.CreditApprovedBy,
           s.VoidedAt, s.VoidReason, s.VoidApprovedBy, s.WasOffline, s.HasShortage, s.NeedsReview, s.ReviewNote, s.PostedAt,
           ISNULL(r.Returned, 0) AS ReturnedNet
    FROM dbo.POSV2_Sale AS s
    INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = s.TerminalID
    INNER JOIN dbo.POSV2_Shift AS sh ON sh.ShiftGUID = s.ShiftGUID
    LEFT JOIN dbo.Customers AS c ON c.CustomerKey = s.CustomerKey
    OUTER APPLY (SELECT SUM(CASE WHEN PaymentType = 'CASH' THEN Amount END) AS Cash, SUM(CASE WHEN PaymentType = 'CARD' THEN Amount END) AS Card,
                        SUM(CASE WHEN PaymentType = 'CHARGE' THEN Amount END) AS Charge, MAX(CASE WHEN PaymentType = 'CARD' THEN Reference END) AS CardRef
                 FROM dbo.POSV2_Payment WHERE SaleGUID = s.SaleGUID) AS p
    OUTER APPLY (SELECT SUM(NetAmount) AS Returned FROM dbo.POSV2_Return WHERE OrigSaleGUID = s.SaleGUID) AS r
    WHERE s.SaleDateTime >= @DateFrom AND s.SaleDateTime < DATEADD(DAY, 1, @DateTo) AND (@BranchCode IS NULL OR s.BranchCode = @BranchCode)
    ORDER BY s.BranchCode, t.TerminalCode, s.ORNo
    OPTION (RECOMPILE);
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.sp_rpt_POSV2_Returns
    @BranchCode VARCHAR(10) = NULL,
    @DateFrom   DATE,
    @DateTo     DATE
AS
/*  POS V2 returns of the period: one row per returned line, with the return slip, the original OR, the refund split
    and what went back to stock. Read-only. */
BEGIN
    SET NOCOUNT ON;
    SELECT r.BranchCode, t.TerminalCode, r.ReturnNo, r.ReturnDateTime, sh.ZNo, s.ORNo AS OrigORNo, s.SaleDateTime AS OrigSaleDate,
           r.CashierUserID, r.ApprovedBy, r.Reason, s.CustomerKey,
           rl.[LineNo], rl.ProductCode, sl.Description, rl.Qty, rl.QtyRestocked, rl.QtyUnshorted,
           rl.GrossAmount, rl.DiscountAmount, rl.VatExemptAmount, rl.NetAmount, rl.VatAmount, rl.CostTotal,
           r.CashRefund, r.CardRefund, r.ChargeRefund, r.ChargeExcess, r.NeedsReview, r.ReviewNote
    FROM dbo.POSV2_Return AS r
    INNER JOIN dbo.POSV2_ReturnLine AS rl ON rl.ReturnGUID = r.ReturnGUID
    INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = r.TerminalID
    INNER JOIN dbo.POSV2_Shift AS sh ON sh.ShiftGUID = r.ShiftGUID
    INNER JOIN dbo.POSV2_Sale AS s ON s.SaleGUID = r.OrigSaleGUID
    LEFT JOIN dbo.POSV2_SaleLine AS sl ON sl.SaleGUID = r.OrigSaleGUID AND sl.[LineNo] = rl.OrigLineNo
    WHERE r.ReturnDateTime >= @DateFrom AND r.ReturnDateTime < DATEADD(DAY, 1, @DateTo) AND (@BranchCode IS NULL OR r.BranchCode = @BranchCode)
    ORDER BY r.BranchCode, r.ReturnNo, rl.[LineNo]
    OPTION (RECOMPILE);
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

CREATE PROCEDURE dbo.sp_rpt_POSV2_NeedsAttention
    @BranchCode VARCHAR(10) = NULL
AS
/*  Everything of POS V2 someone has to look at, whatever its date: sales / returns posted with NeedsReview, open
    shortages, a customer credit from a charge refund (20115), shifts whose GL isn't booked, a printed grand total that
    differs from the server's, shifts open for more
    than a day, terminals with an open shift not seen for a day. One row per item: Kind, Branch, Terminal, Ref, When,
    Amount, Detail. Read-only (the Exception Center script runs the same checks as counts). */
BEGIN
    SET NOCOUNT ON;
    SELECT x.Kind, x.BranchCode, x.TerminalCode, x.Ref, x.[When], CAST(x.Amount AS DECIMAL(18,2)) AS Amount, x.Detail
    FROM (
        SELECT 'SALE NEEDS REVIEW' AS Kind, s.BranchCode, t.TerminalCode, s.ORNo AS Ref, s.SaleDateTime AS [When], s.NetAmount AS Amount, s.ReviewNote AS Detail
        FROM dbo.POSV2_Sale AS s INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = s.TerminalID WHERE s.NeedsReview = 1
        UNION ALL
        SELECT 'RETURN NEEDS REVIEW', r.BranchCode, t.TerminalCode, r.ReturnNo, r.ReturnDateTime, r.NetAmount, r.ReviewNote
        FROM dbo.POSV2_Return AS r INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = r.TerminalID WHERE r.NeedsReview = 1
        UNION ALL
        SELECT 'CUSTOMER CREDIT (20115)', r.BranchCode, t.TerminalCode, r.ReturnNo, r.ReturnDateTime, r.ChargeExcess,
               'Charge refund above the invoice''s open balance; customer ' + ISNULL(s.CustomerKey, '?')
        FROM dbo.POSV2_Return AS r INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = r.TerminalID
        INNER JOIN dbo.POSV2_Sale AS s ON s.SaleGUID = r.OrigSaleGUID WHERE r.ChargeExcess > 0
        UNION ALL
        SELECT 'SHORTAGE OPEN', sh.BranchCode, t.TerminalCode, s.ORNo, sh.CreatedAt, sh.QtyShort,
               sh.ProductCode + ': sold ' + CONVERT(VARCHAR(30), sh.QtySold) + ', deducted ' + CONVERT(VARCHAR(30), sh.QtyDeducted) + ' (qty short in Amount)'
        FROM dbo.POSV2_Shortage AS sh INNER JOIN dbo.POSV2_Sale AS s ON s.SaleGUID = sh.SaleGUID
        INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = s.TerminalID WHERE sh.Status = 'OPEN'
        UNION ALL
        SELECT 'SHIFT GL NOT BOOKED', s.BranchCode, t.TerminalCode, 'Z#' + CAST(s.ZNo AS VARCHAR(10)), s.ClosedAt, s.NetAmount,
               s.GLStatus + ISNULL(': ' + CAST(s.GLMessage AS VARCHAR(500)), '')
        FROM dbo.POSV2_Shift AS s INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = s.TerminalID
        WHERE s.Status = 'CLOSED' AND s.GLStatus <> 'POSTED'
        UNION ALL
        SELECT 'SHIFT OPEN > 1 DAY', s.BranchCode, t.TerminalCode, 'Z#' + CAST(s.ZNo AS VARCHAR(10)), s.OpenedAt, s.BeginningCash,
               'Cashier ' + s.CashierUserID + ISNULL('; terminal last seen ' + CONVERT(VARCHAR(16), t.LastSeenAt, 120), '')
        FROM dbo.POSV2_Shift AS s INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = s.TerminalID
        WHERE s.Status = 'OPEN' AND s.OpenedAt < DATEADD(DAY, -1, SYSDATETIME())
        UNION ALL
        -- phase 5 review: the grand total printed on the terminal's Z-reading is not the server's (BIR reads the server's)
        SELECT 'GRAND TOTAL DIFFERS', s.BranchCode, t.TerminalCode, 'Z#' + CAST(s.ZNo AS VARCHAR(10)), s.ClosedAt,
               s.TerminalAccumulatedAfter - s.AccumulatedAfter,
               'Printed ' + CONVERT(VARCHAR(30), s.TerminalAccumulatedAfter) + ', server ' + CONVERT(VARCHAR(30), s.AccumulatedAfter) + ' (difference in Amount)'
        FROM dbo.POSV2_Shift AS s INNER JOIN dbo.POSV2_Terminal AS t ON t.TerminalID = s.TerminalID
        WHERE s.Status = 'CLOSED' AND s.TerminalAccumulatedAfter IS NOT NULL AND s.TerminalAccumulatedAfter <> s.AccumulatedAfter
    ) AS x
    WHERE @BranchCode IS NULL OR x.BranchCode = @BranchCode
    ORDER BY x.Kind, x.BranchCode, x.[When];
END
GO
IF @@TRANCOUNT = 0 BEGIN RAISERROR('An earlier step failed; nothing more is run.', 16, 1); SET NOEXEC ON; END
GO

IF OBJECT_ID('dbo.spu_POSV2_OpenShift', 'P') IS NULL OR OBJECT_ID('dbo.spu_POSV2_CloseShift', 'P') IS NULL
   OR OBJECT_ID('dbo.spu_POSV2_PostShiftGL', 'P') IS NULL OR OBJECT_ID('dbo.spu_POSV2_PostPendingShiftGL', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_POSV2_GetSupervisors', 'P') IS NULL OR OBJECT_ID('dbo.spu_POSV2_SetSupervisor', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_POSV2_ListSupervisors', 'P') IS NULL OR OBJECT_ID('dbo.spu_POSV2_ForceCloseShift', 'P') IS NULL
   OR OBJECT_ID('dbo.POSV2_SupervisorLog', 'U') IS NULL
   OR OBJECT_ID('dbo.spu_POSV2_PostReturn', 'P') IS NULL OR OBJECT_ID('dbo.sp_POSV2_GetSaleForReturn', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_POSV2_GetCustomers', 'P') IS NULL OR OBJECT_ID('dbo.POSV2_ReturnLot', 'U') IS NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.ChartOfAccounts WHERE AccountCode = '60340') OR OBJECT_ID('dbo.seq_POSV2_ARRef', 'SO') IS NULL
   OR OBJECT_ID('dbo.fn_POSV2_ZReadings', 'IF') IS NULL OR OBJECT_ID('dbo.sp_rpt_POSV2_Shifts', 'P') IS NULL OR OBJECT_ID('dbo.sp_rpt_POSV2_SalesJournal', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_rpt_POSV2_Returns', 'P') IS NULL OR OBJECT_ID('dbo.sp_rpt_POSV2_NeedsAttention', 'P') IS NULL
   OR (SELECT COUNT(*) FROM dbo.JournalEntryMapping WHERE Origin = 'POSV2' AND Mnemonic = 'POSV2-SHIFT') < 15
BEGIN
    RAISERROR('Post-check (phases 3-5) failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO

IF OBJECT_ID('dbo.spu_POSV2_PostSale', 'P') IS NULL OR OBJECT_ID('dbo.spu_POSV2_RegisterTerminal', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_POSV2_GetProducts', 'P') IS NULL OR OBJECT_ID('dbo.sp_POSV2_GetStock', 'P') IS NULL
   OR OBJECT_ID('dbo.POSV2_Shortage', 'U') IS NULL
   OR OBJECT_ID('dbo.spu_POSV2_VoidSale', 'P') IS NULL OR OBJECT_ID('dbo.sp_POSV2_GetDiscountTypes', 'P') IS NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.POSV2_DiscountType)
BEGIN
    RAISERROR('Post-check failed; rolled back.', 16, 1);
    ROLLBACK TRANSACTION;
    SET NOEXEC ON;
END
GO
COMMIT TRANSACTION;
PRINT 'POS V2 server objects (phases 1-5) installed.';
GO
SET NOEXEC OFF;
GO
