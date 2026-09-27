/* ================================================================
   2026-09-26: Item Costing Recon -- "View Related Tickets" per expense
   ================================================================
   Requested by user: from the Linked Expenses level of
   Reporting/ItemCostingReconReport (result set 2 of
   sp_rpt_ItemCostingRecon_List), open every GL ticket related to one
   expense.

   dbo.sp_rpt_ItemCostingRecon_ExpenseTickets (NEW, read-only), called on
   demand for ONE expense row -- sp_rpt_ItemCostingRecon_List is unchanged.

   Related tickets of a SINGLE expense (links verified on COREX001):
     1. EXPENSE POSTING -- TicketMaster.ReferenceNumber = es.ReferenceNumber
        AND ReferenceKey = es.InvoiceNo AND Mnemonic = 'SINGLE' (same link
        the List proc uses for InventoryCost).
     2. PAYMENT / PAYMENT REVERSAL -- APPaymentDetails rows with the
        expense's BatchReferenceID (78/78 expense-payment rows resolve),
        then TicketMaster.ReferenceNumber = d.ReferenceNumber AND
        ReferenceKey = d.VoucherID. Linked by voucher, not by
        APPaymentDetails.TicketNumber: one voucher can have several tickets
        (e.g. 12854 + 12855 for voucher 685) and sp_ReverseTicketsAP writes
        the reversal tickets under the same ReferenceNumber/ReferenceKey
        with Particulars '(REVERSAL) ...'.
        A voucher ticket is shown whole: when the voucher paid other
        invoices too, its lines include them.

   Deploy to COREX001 (DEV) first; STAGING only after the user confirms.
   ================================================================ */

IF OBJECT_ID('dbo.sp_rpt_ItemCostingRecon_ExpenseTickets', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.sp_rpt_ItemCostingRecon_ExpenseTickets', 'sp_rpt_ItemCostingRecon_ExpenseTickets_OLD_09262026100000';
GO

CREATE PROCEDURE dbo.sp_rpt_ItemCostingRecon_ExpenseTickets
(
    @ReferenceNumber VARCHAR(10),
    @InvoiceNo       VARCHAR(150),
    @ShipmentNo      VARCHAR(10)
)
AS
/*
    Result set 1: Tickets -- one row per related ticket
        TicketNumber, ReferenceNumber (relation key with TicketNumber),
        ReferenceKey, TicketDate, Source (EXPENSE POSTING / PAYMENT /
        PAYMENT REVERSAL), VoucherType, Mnemonic, Status, Particulars,
        TotalDebit, TotalCredit
    Result set 2: Lines -- TicketDetails of those tickets
        TicketNumber, ReferenceNumber (relation key), BranchCode,
        Account (Code - Description), Debit, Credit, Particulars
    Scope: the SINGLE-mode ExpenseSummary row(s) of that ReferenceNumber +
    InvoiceNo + ShipmentNo -- the same rows sp_rpt_ItemCostingRecon_List
    puts in result set 2.
    Caller: Reporting/ItemCostingReconReport.cs (reads both result sets in
    this order).
*/
BEGIN
    SET NOCOUNT ON;

    SELECT es.ReferenceNumber, es.InvoiceNo, es.BatchReferenceID
    INTO #Exp
    FROM dbo.ExpenseSummary es
    WHERE es.ReferenceNumber = @ReferenceNumber
      AND es.InvoiceNo       = @InvoiceNo
      AND es.ShipmentNo      = @ShipmentNo
      AND es.PostingMode     = 'SINGLE';

    CREATE TABLE #Tix
    (
        TicketNumber    VARCHAR(50)  NOT NULL,
        ReferenceNumber VARCHAR(150) NOT NULL,
        ReferenceKey    VARCHAR(150) NULL,
        Source          VARCHAR(30)  NOT NULL,
        VoucherType     VARCHAR(20)  NULL,
        SortGroup       TINYINT      NOT NULL
    );

    -- 1. Expense posting ticket
    INSERT INTO #Tix (TicketNumber, ReferenceNumber, ReferenceKey, Source, VoucherType, SortGroup)
    SELECT DISTINCT tm.TicketNumber, tm.ReferenceNumber, tm.ReferenceKey, 'EXPENSE POSTING', NULL, 1
    FROM #Exp e
    JOIN dbo.TicketMaster tm
      ON tm.ReferenceNumber = e.ReferenceNumber
     AND tm.ReferenceKey    = e.InvoiceNo
     AND tm.Mnemonic        = 'SINGLE';

    -- 2. Payment vouchers that touched this expense, and their reversals
    ;WITH Vouchers AS (
        SELECT DISTINCT d.ReferenceNumber, d.VoucherID, d.VoucherType
        FROM #Exp e
        JOIN dbo.APPaymentDetails d ON d.BatchReferenceID = e.BatchReferenceID
    )
    INSERT INTO #Tix (TicketNumber, ReferenceNumber, ReferenceKey, Source, VoucherType, SortGroup)
    SELECT DISTINCT
        tm.TicketNumber, tm.ReferenceNumber, tm.ReferenceKey,
        CASE WHEN tm.Particulars LIKE '(REVERSAL)%' THEN 'PAYMENT REVERSAL' ELSE 'PAYMENT' END,
        v.VoucherType,
        CASE WHEN tm.Particulars LIKE '(REVERSAL)%' THEN 3 ELSE 2 END
    FROM Vouchers v
    JOIN dbo.TicketMaster tm
      ON tm.ReferenceNumber = v.ReferenceNumber
     AND tm.ReferenceKey    = v.VoucherID
    WHERE NOT EXISTS (SELECT 1 FROM #Tix x
                      WHERE x.TicketNumber = tm.TicketNumber
                        AND x.ReferenceNumber = tm.ReferenceNumber);

    -- Result set 1: Tickets
    SELECT
        t.TicketNumber,
        t.ReferenceNumber,
        t.ReferenceKey,
        tm.TicketDate,
        t.Source,
        t.VoucherType,
        tm.Mnemonic,
        tm.Status,
        tm.Particulars,
        CAST(ISNULL(tot.TotalDebit, 0)  AS DECIMAL(18,2)) AS TotalDebit,
        CAST(ISNULL(tot.TotalCredit, 0) AS DECIMAL(18,2)) AS TotalCredit
    FROM #Tix t
    CROSS APPLY (
        SELECT TOP (1) m.TicketDate, m.Mnemonic, m.Status, m.Particulars
        FROM dbo.TicketMaster m
        WHERE m.TicketNumber    = t.TicketNumber
          AND m.ReferenceNumber = t.ReferenceNumber
        ORDER BY m.TicketDate
    ) tm
    OUTER APPLY (
        SELECT SUM(ISNULL(td.Debit, 0))  AS TotalDebit,
               SUM(ISNULL(td.Credit, 0)) AS TotalCredit
        FROM dbo.TicketDetails td
        WHERE td.TicketNumber    = t.TicketNumber
          AND td.ReferenceNumber = t.ReferenceNumber
    ) tot
    ORDER BY t.SortGroup, tm.TicketDate, t.TicketNumber;

    -- Result set 2: Lines
    SELECT
        td.TicketNumber,
        td.ReferenceNumber,
        td.BranchCode,
        td.AccountCode + ISNULL(' - ' + coa.Description, '') AS Account,
        CAST(ISNULL(td.Debit, 0)  AS DECIMAL(18,2)) AS Debit,
        CAST(ISNULL(td.Credit, 0) AS DECIMAL(18,2)) AS Credit,
        td.Particulars
    FROM #Tix t
    JOIN dbo.TicketDetails td
      ON td.TicketNumber    = t.TicketNumber
     AND td.ReferenceNumber = t.ReferenceNumber
    LEFT JOIN dbo.ChartOfAccounts coa ON coa.AccountCode = td.AccountCode
    ORDER BY t.SortGroup, td.TicketNumber,
             CASE WHEN ISNULL(td.Debit, 0) <> 0 THEN 0 ELSE 1 END,
             td.AccountCode;
END
GO
