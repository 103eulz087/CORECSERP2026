/* ================================================================
   POS V2 (phases 1-4, 2026-10-12 / 13) - 01: table types
   ================================================================
   Plan: docs/plans/2026-10-12_POS_V2_Hybrid_Plan.md. Run BEFORE 02 (a table
   type created inside a transaction can't be used in that same transaction).
   New objects only. (User 2026-10-12: one STAGING update when everything works,
   so phase 2 is folded into these scripts instead of patch scripts.)
   ================================================================ */

SET NOCOUNT ON;

IF TYPE_ID('dbo.tt_POSV2_SaleLine') IS NULL
    CREATE TYPE dbo.tt_POSV2_SaleLine AS TABLE
    (
        [LineNo]        INT            NOT NULL PRIMARY KEY,
        ProductCode     VARCHAR(50)    NOT NULL,
        Barcode         VARCHAR(150)   NULL,
        Description     VARCHAR(300)   NULL,
        Qty             DECIMAL(18,3)  NOT NULL,
        PriceLevel      VARCHAR(10)    NOT NULL,   -- MAIN / PRICE1..PRICE4 / MANUAL
        UnitPrice       DECIMAL(18,2)  NOT NULL,   -- VAT inclusive
        LineDiscount    DECIMAL(18,2)  NOT NULL,   -- everything taken off the line = DiscountAmount + VatExemptAmount
        LineTotal       DECIMAL(18,2)  NOT NULL,   -- ROUND(Qty x UnitPrice, 2) - LineDiscount
        IsVat           BIT            NOT NULL,   -- taxed in this sale (a senior / PWD VAT-exempt line is 0)
        VatAmount       DECIMAL(18,2)  NOT NULL,
        DiscNo          INT            NULL,       -- the sale discount this line belongs to (tt_POSV2_SaleDiscount)
        DiscountCode    VARCHAR(10)    NULL,
        DiscountAmount  DECIMAL(18,2)  NOT NULL,   -- the discount proper (e.g. 20%)
        VatExemptAmount DECIMAL(18,2)  NOT NULL    -- VAT removed for a VAT-exempt discount (senior / PWD)
    );
GO

IF TYPE_ID('dbo.tt_POSV2_Payment') IS NULL
    CREATE TYPE dbo.tt_POSV2_Payment AS TABLE
    (
        PayNo        INT            NOT NULL PRIMARY KEY,
        PaymentType  VARCHAR(20)    NOT NULL,   -- CASH / CARD / CHARGE (phase 4)
        Amount       DECIMAL(18,2)  NOT NULL,   -- amount tendered in this payment
        Reference    VARCHAR(100)   NULL        -- CARD: card type, last 4 digits, approval code
    );
GO

IF TYPE_ID('dbo.tt_POSV2_SaleDiscount') IS NULL
    CREATE TYPE dbo.tt_POSV2_SaleDiscount AS TABLE
    (
        DiscNo          INT            NOT NULL PRIMARY KEY,
        DiscountCode    VARCHAR(10)    NOT NULL,   -- POSV2_DiscountType
        [Percent]       DECIMAL(9,4)   NOT NULL,   -- 20 = 20 %; 0 for an amount discount
        Amount          DECIMAL(18,2)  NOT NULL,   -- sum of its lines' DiscountAmount
        VatExemptAmount DECIMAL(18,2)  NOT NULL,   -- sum of its lines' VatExemptAmount
        CustomerName    VARCHAR(150)   NULL,       -- senior / PWD: required
        IDNo            VARCHAR(50)    NULL,       -- OSCA / PWD ID no.: required for senior / PWD
        TIN             VARCHAR(30)    NULL,
        Remarks         VARCHAR(300)   NULL
    );
GO

-- phase 4: one returned line (part or all of an original sale line)
IF TYPE_ID('dbo.tt_POSV2_ReturnLine') IS NULL
    CREATE TYPE dbo.tt_POSV2_ReturnLine AS TABLE
    (
        [LineNo]        INT            NOT NULL PRIMARY KEY,
        OrigLineNo      INT            NOT NULL,   -- the original sale's line
        Qty             DECIMAL(18,3)  NOT NULL,
        GrossAmount     DECIMAL(18,2)  NOT NULL,   -- its share of the line's ROUND(Qty x UnitPrice, 2)
        DiscountAmount  DECIMAL(18,2)  NOT NULL,   -- its share of the line's discount
        VatExemptAmount DECIMAL(18,2)  NOT NULL,   -- its share of the line's VAT exemption
        NetAmount       DECIMAL(18,2)  NOT NULL,   -- Gross - Discount - VatExempt: what is refunded
        VatAmount       DECIMAL(18,2)  NOT NULL
    );
GO

PRINT 'POS V2 types ready: tt_POSV2_SaleLine, tt_POSV2_Payment, tt_POSV2_SaleDiscount, tt_POSV2_ReturnLine.';
