-- CustomersInfoV2DevEx module (Add/Edit/Update, no delete -- isActive is a
-- show/hide indicator only). Dedicated read/write objects per this module's
-- own table lifecycle -- does not touch func_viewCustomer / spitcr_addCust,
-- which the legacy CustomersInfoDevEx form still uses.

-- ============================================================================
-- dbo.Customers.CustomerID had no uniqueness backstop at all (only
-- CustomerKey is a PK) -- verified 09/10/2026 there are zero existing
-- duplicates/blanks on CORECSERP_002_DEV, so this is safe to add. Without
-- it, spitcr_addCustV2's pre-write EXISTS check is a TOCTOU race: two
-- concurrent Adds with the same CustomerID can both pass the check before
-- either commits.
-- ============================================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.Customers') AND name = 'UQ_Customers_CustomerID'
)
    CREATE UNIQUE NONCLUSTERED INDEX UQ_Customers_CustomerID
        ON dbo.Customers (CustomerID);
GO

-- ============================================================================
-- dbo.func_viewCustomerV2 -- read shape for the grid, includes CustomerType
-- (which func_viewCustomer never exposed). @parmbranchcode = '' returns all
-- branches; otherwise filters to one branch.
-- ============================================================================
IF OBJECT_ID('dbo.func_viewCustomerV2', 'IF') IS NOT NULL
    EXEC sp_rename 'dbo.func_viewCustomerV2', 'func_viewCustomerV2_OLD_09102026120000';
GO

CREATE FUNCTION dbo.func_viewCustomerV2 (@parmbranchcode VARCHAR(100))
RETURNS TABLE
AS
RETURN
(
    SELECT
        CustomerKey,
        CustomerID,
        CustomerName,
        CustomerEmail,
        CustomerContactNo,
        CustomerAddress,
        CustomerBirthDate,
        CustomerCreditLimit,
        CustomerType,
        BranchCode,
        Term,
        isActive,
        DateAdded,
        AddedBy,
        UpdatedBy,
        AccountOfficer,
        TinNo
    FROM dbo.Customers
    WHERE @parmbranchcode = '' OR BranchCode = @parmbranchcode
);
GO

-- ============================================================================
-- dbo.spitcr_addCustV2 -- insert (@parmcmd='1') or update (@parmcmd='2').
-- Fixes a bug present in spitcr_addCust: its UPDATE branch overwrote
-- DateAdded/AddedBy on every edit. Here those stay untouched on update --
-- only UpdatedBy moves. The CustomerID EXISTS check runs again immediately
-- before the write, inside the transaction, to shrink (not eliminate) the
-- race window; UQ_Customers_CustomerID above is the real backstop, and a
-- violation of it is caught below and re-thrown as the same friendly message.
-- ============================================================================
IF OBJECT_ID('dbo.spitcr_addCustV2', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.spitcr_addCustV2', 'spitcr_addCustV2_OLD_09102026120000';
GO

CREATE PROCEDURE dbo.spitcr_addCustV2
    @CustomerKey        CHAR(8),
    @CustomerID         VARCHAR(150),
    @CustomerName       VARCHAR(150),
    @CustomerEmail      VARCHAR(50),
    @CustomerContactNo  VARCHAR(50),
    @CustomerAddress    VARCHAR(1000),
    @CustomerBirthDate  DATE,
    @CustomerCreditLimit MONEY,
    @CustomerType       VARCHAR(100),
    @BranchCode         VARCHAR(100),
    @Term               FLOAT,
    @isActive           BIT,
    @AccountOfficer     VARCHAR(50),
    @TinNo              VARCHAR(50),
    @ActingUser         VARCHAR(50), -- on insert this becomes both AddedBy and UpdatedBy; on update, only UpdatedBy
    @parmcmd            CHAR(1)
AS
/*
    @parmcmd = '1' -> INSERT a new customer (CustomerKey/CustomerID must not
                       already exist).
    @parmcmd = '2' -> UPDATE an existing customer identified by CustomerKey.
                       DateAdded/AddedBy are preserved -- only mutable fields
                       and UpdatedBy change.
    Callers: HOFormsDevEx/CustomersInfoV2DevEx.cs
*/
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF @parmcmd NOT IN ('1', '2')
            THROW 50000, 'Invalid command.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.Branches WHERE BranchCode = @BranchCode)
            THROW 50000, 'Invalid branch.', 1;

        IF @parmcmd = '1'
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerKey = @CustomerKey)
                THROW 50000, 'This Customer Key already exists.', 1;

            BEGIN TRANSACTION;

            IF EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerID = @CustomerID)
                THROW 50000, 'This Customer ID already exists.', 1;

            INSERT INTO dbo.Customers
            (
                CustomerKey, CustomerID, CustomerName, CustomerEmail,
                CustomerContactNo, CustomerAddress, CustomerBirthDate,
                CustomerCreditLimit, CustomerType, BranchCode, Term, isActive,
                DateAdded, AddedBy, UpdatedBy, AccountOfficer, TinNo
            )
            VALUES
            (
                @CustomerKey, @CustomerID, @CustomerName, @CustomerEmail,
                @CustomerContactNo, @CustomerAddress, @CustomerBirthDate,
                @CustomerCreditLimit, @CustomerType, @BranchCode, @Term, @isActive,
                CAST(GETDATE() AS DATE), @ActingUser, @ActingUser, @AccountOfficer, @TinNo
            );

            COMMIT TRANSACTION;
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerKey = @CustomerKey)
                THROW 50000, 'Customer not found.', 1;

            BEGIN TRANSACTION;

            IF EXISTS (SELECT 1 FROM dbo.Customers
                       WHERE CustomerID = @CustomerID AND CustomerKey <> @CustomerKey)
                THROW 50000, 'This Customer ID already exists.', 1;

            UPDATE dbo.Customers SET
                CustomerID          = @CustomerID,
                CustomerName        = @CustomerName,
                CustomerEmail       = @CustomerEmail,
                CustomerContactNo   = @CustomerContactNo,
                CustomerAddress     = @CustomerAddress,
                CustomerBirthDate   = @CustomerBirthDate,
                CustomerCreditLimit = @CustomerCreditLimit,
                CustomerType        = @CustomerType,
                BranchCode          = @BranchCode,
                Term                = @Term,
                isActive            = @isActive,
                UpdatedBy           = @ActingUser,
                AccountOfficer      = @AccountOfficer,
                TinNo               = @TinNo
            WHERE CustomerKey = @CustomerKey;

            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        -- UQ_Customers_CustomerID violation -> surface the same friendly
        -- message the pre-check gives, instead of a raw constraint error.
        IF ERROR_NUMBER() IN (2601, 2627) AND ERROR_MESSAGE() LIKE '%UQ_Customers_CustomerID%'
            THROW 50000, 'This Customer ID already exists.', 1;

        THROW;
    END CATCH
END
GO
