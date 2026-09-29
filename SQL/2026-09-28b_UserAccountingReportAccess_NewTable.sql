/* ================================================================
   2026-09-28b: UserAccountingReportAccess -- per-user visibility of the
   report types in HOFormsDevEx/AccountingReportsFormV2.cs (the
   "Report Type" dropdown). Managed from HOFormsDevEx/UserAccessDevEx.cs
   ("Accounting Reports" tab), same pattern as UserAccountingBoardAccess
   (SQL/2026-08-09_UserAccountingBoardAccess_NewTable.sql).

   ReportKey = the stable ReportConfig.Key in AccountingReportsFormV2.cs
   (e.g. TRIAL_BALANCE) -- NOT the display name, so renaming a report's
   caption doesn't silently drop anyone's access.

   DEFAULT-ACCESS SEMANTICS (enforced in AccountingReportsFormV2.cs, not here):
     - A user with ZERO rows here sees every report (safe rollout --
       nothing changes for existing users until an admin restricts them).
     - Rows only ever narrow access, never widen it.
     - Global admins (Users.isAdmin) always see every report.

   Own table (not UserAccountingBoardAccess with prefixed keys): mixing the
   two would make "no rows" ambiguous -- a user restricted on the Board but
   never configured for reports would lose every report.

   Non-destructive: creates the table only if it doesn't exist.
   Deploy to COREX001 (DEV) first; CORECSJFC2026_STAGING only after the
   user confirms.
   ================================================================ */

SET NOCOUNT ON;

IF OBJECT_ID('dbo.UserAccountingReportAccess', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserAccountingReportAccess
    (
        UserID    VARCHAR(50) NOT NULL,
        ReportKey VARCHAR(50) NOT NULL,
        CONSTRAINT PK_UserAccountingReportAccess PRIMARY KEY (UserID, ReportKey)
    );
    PRINT 'Created dbo.UserAccountingReportAccess.';
END
ELSE
    PRINT 'dbo.UserAccountingReportAccess already exists -- no change.';
GO
