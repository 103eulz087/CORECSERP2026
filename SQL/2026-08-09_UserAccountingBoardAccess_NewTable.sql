SET NOCOUNT ON;
PRINT '=== User Access Control: Accounting Board accordion-item access (AccountingBoard.cs) ===';
GO

-- =============================================
-- WHY A NEW TABLE (not another pipe-delimited column on UserMenuAccess):
--   UserMenuAccess already governs Ribbon-page-level visibility (isAccounting
--   controls whether the ACCOUNTING ribbon page shows up at all). This is a
--   different, finer-grained concern -- which items are clickable *inside* the
--   Accounting Board (AccountingDevEx/AccountingBoard.cs) once you're already
--   on that page. Keeping it as its own UserID/MenuKey junction table avoids
--   conflating the two concerns and avoids the pipe-delimited-string parsing
--   UserMenuAccess/UserAccessDevEx.cs already relies on.
--
-- DEFAULT-ACCESS SEMANTICS (enforced in AccountingBoard.cs, not here):
--   A user with ZERO rows here has full access to every accordion item (safe
--   rollout -- nothing changes for existing users until someone explicitly
--   restricts them). Rows only ever narrow access for a user, never widen it.
-- =============================================

IF OBJECT_ID('dbo.UserAccountingBoardAccess', 'U') IS NOT NULL DROP TABLE dbo.UserAccountingBoardAccess;
GO

CREATE TABLE dbo.UserAccountingBoardAccess
(
    UserID   VARCHAR(50) NOT NULL,
    MenuKey  VARCHAR(50) NOT NULL,
    CONSTRAINT PK_UserAccountingBoardAccess PRIMARY KEY (UserID, MenuKey)
);
GO

PRINT 'DEPLOYMENT COMPLETE: UserAccountingBoardAccess.';
