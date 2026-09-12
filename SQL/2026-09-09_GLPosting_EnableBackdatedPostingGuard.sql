-- Re-enable the LatestPostingDate guard in GLPosting, disabled for testing.
-- Fixes the NULL-handling bug in the original (commented-out) condition:
-- "is null OR @Postdate<@LatestPostingDate" would have blocked every branch's
-- very first post (LatestPostingDate starts NULL for every branch). Correct
-- semantics: NULL means "never posted, anything is safe" -> only block when
-- a prior posting date actually exists AND the new date is earlier than it.
-- Without this guard, reposting an earlier date deletes GLSummary rows for
-- every later date already posted for that branch (see GLPosting's
-- "delete from glsummary where BranchCode=@Branch and PostingDate>@PostDate").
--
-- Also fixed per sp-reviewer findings:
-- - PostingDateControl write-back is now an upsert (IF EXISTS UPDATE ELSE
--   INSERT) instead of a blind UPDATE, so the guard doesn't silently go
--   permanently blind (LatestPostingDate stuck NULL forever) for any branch
--   that never had a PostingDateControl row to begin with.
-- - RAISERROR now includes Branch/PostDate/LatestPostingDate so the error
--   is diagnosable without querying the DB, since GLPostingDevEx.cs's
--   backgroundWorker loops all branches with only one generic message box
--   on failure.
-- Verified safe re: transaction nesting: sp_GLPosting (DB-side, not in this
-- repo) loops EXEC GLPosting per day with no ambient BEGIN TRANSACTION of
-- its own, and GLPostingDevEx.cs opens no SqlTransaction either -- so the
-- unqualified "rollback tran" here only ever unwinds GLPosting's own
-- "BEGIN TRANSACTION GLPosting", same as the pre-existing lock-timeout
-- branch right above it.

IF OBJECT_ID('dbo.GLPosting', 'P') IS NOT NULL
    EXEC sp_rename 'dbo.GLPosting', 'GLPosting_OLD_09092026130000';
GO

/****** Object:  Stored Procedure dbo.GLPosting    Script Date: 6/10/99 5:03:59 PM ******/
CREATE Procedure [dbo].[GLPosting]
-- Input parameters
	@Branch				varchar(5),
	@PPostDate			varchar(10),
	@PSupplementary			varchar(3)
As
SET LOCK_TIMEOUT 240000
BEGIN TRANSACTION GLPosting
select * from aaplock with (TABLOCKX)
IF @@ERROR <> 0
begin
	Rollback Transaction
	return -1
end
ELSE
BEGIN
	DECLARE @Postdate		datetime
	DECLARE @Supplementary		tinyint
	DECLARE	@LatestPostingDate	datetime
	select @Postdate=convert(datetime,@PPostDate)
	select @Supplementary=convert(tinyint,@PSupplementary)
	select @LatestPostingDate=LatestPostingDate from PostingDateControl where BranchCode=@Branch
	if @LatestPostingDate is not null and @Postdate<@LatestPostingDate
	begin
		DECLARE @LatestPostingDateStr varchar(20) = CONVERT(varchar(20),@LatestPostingDate,120)
		rollback tran
		RAISERROR('GLPosting: Branch %s PostDate %s is earlier than LatestPostingDate %s',11,1,@Branch,@PPostDate,@LatestPostingDateStr);
		return -2
	end
	else
	BEGIN
-- Cursor declaration
		DECLARE Summary_Accounts CURSOR
			FOR select ChartOfAccounts.AccountCode,
				  ChartOfAccounts.SummaryAccount,
				  GLSummary.BeginningBalance,
				  GLSummary.Debits,
				  GLSummary.Credits
					from   ChartOfAccounts, GLSummary
					where ChartOfAccounts.AccountCode=GLSummary.AccountCode
			and ChartOfAccounts.LevelNumber > 0
			and GLSummary.BranchCode=@Branch
			and GLSummary.PostingDate=@PostDate
			and GLSummary.SupplementaryNumber=@Supplementary
					order by ChartOfAccounts.LevelNumber DESC, ChartOfAccounts.AccountCode DESC
	-- Variable declarations
		DECLARE @AccountCode               	varchar(20)
		DECLARE @BeginningBalance		money
		DECLARE @Debits			money
		DECLARE @Credits			money
		DECLARE @SummaryAccount		varchar(20)
	-- Set tickets for approval with same posting date as DISAPPROVED
		update tempticketmaster set status='Disapproved' where BranchCode=@Branch and TicketDate=@PostDate and status='For Approval'
	-- Clear GLSummary table from any records which has the same branch and date with that of records to be posted
		delete from glsummary
		where BranchCode=@Branch
			and PostingDate>@PostDate
		delete from glsummary
		where BranchCode=@Branch
			and PostingDate=@PostDate
			and SupplementaryNumber>=@Supplementary
	-- Create new records in GLSummary based on ChartOfAccounts w/ dates and branch codes that of input parameters
		insert glsummary
			select  @Branch,
			@PostDate,
			@Supplementary,
			AccountCode,
			0,
			0,
			0,
			0
			from ChartOfAccounts
	-- Forward previous records' ending balances to newly created records as beginning balances
		if @Supplementary=0
			update glsummary1
				set glsummary1.BeginningBalance=glsummary2.EndingBalance
				from glsummary glsummary1, glsummary glsummary2
	    			where glsummary1.accountcode=glsummary2.accountcode
	    			and glsummary1.branchcode=@branch
	    			and glsummary1.postingdate=@postdate
				and glsummary1.accountcode in (select accountcode from chartofaccounts
								where accounttype='D')
				and glsummary2.branchcode=@branch
	    			and glsummary2.postingdate=(select max(glsummary3.postingdate)
				      			   from glsummary glsummary3
							   where glsummary3.branchcode=@Branch
				       			   and glsummary3.postingdate < @PostDate)
				and glsummary2.supplementarynumber=(select max(glsummary3.supplementarynumber)
								   from glsummary glsummary3
								   where GLSummary3.BranchCode=@Branch
								   and glsummary3.postingdate=(select max(glsummary4.postingdate)
												from glsummary glsummary4
												where branchcode=@Branch
												and postingdate < @postdate))
		else
			update glsummary1
				set glsummary1.BeginningBalance=glsummary2.EndingBalance
				from glsummary glsummary1, glsummary glsummary2
	    			where glsummary1.accountcode=glsummary2.accountcode
	    			and glsummary1.branchcode=@branch
	    			and glsummary1.postingdate=@postdate
				and glsummary1.supplementarynumber=@supplementary
				and glsummary1.accountcode in (select accountcode from chartofaccounts
								where accounttype='D')
				and glsummary2.branchcode=@branch
	    			and glsummary2.postingdate=@postdate
				and glsummary2.supplementarynumber=(select max(glsummary3.supplementarynumber)
								   from glsummary glsummary3
								   where GLSummary3.BranchCode=@Branch
								   and glsummary3.postingdate=@Postdate
								   and glsummary3.SupplementaryNumber < @Supplementary)
	-- Generate ticket for due to/from netting
		DECLARE @DFRAccount	varchar(50)
		DECLARE @DTOAccount	varchar(50)
		DECLARE @DRDFR		money
		DECLARE @CRDFR		money
		DECLARE @DRDTO		money
		DECLARE @CRDTO		money
		DECLARE @DFRAmount	money
		DECLARE @DTOAmount	money
		DECLARE @BBDFR		money
		DECLARE @BBDTO		money
		DECLARE @EBDFR		money
		DECLARE @EBDTO		money
		DECLARE @Origin		money
		DECLARE @TktNumber	varchar(10)
		select @DFRAccount=accountcode from ChartOfAccounts where DueToFromIndicator='DFR'
		select @DTOAccount=accountcode from ChartOfAccounts where DueToFromIndicator='DTO'
		select @BBDFR=BeginningBalance from GLSummary where BranchCode=@Branch and PostingDate=@PostDate and SupplementaryNumber=@Supplementary and AccountCode=@DFRAccount
		select @BBDTO=BeginningBalance from GLSummary where BranchCode=@Branch and PostingDate=@PostDate and SupplementaryNumber=@Supplementary and AccountCode=@DTOAccount
		delete from TicketDetails where BranchCode=@Branch and TicketDate=@Postdate and SupplementaryNumber=@Supplementary and ticketnumber in (select ticketnumber from TicketMaster where BranchCode=@Branch and TicketDate=@Postdate and SupplementaryNumber=@Supplementary and EnteredBy='BOSNET')
		delete from TicketMaster where BranchCode=@Branch and TicketDate=@Postdate and SupplementaryNumber=@Supplementary and EnteredBy='BOSNET'
		Select @DRDFR=sum(Debit) from TicketDetails
			where BranchCode=@Branch and TicketDate=@PPostDate and SupplementaryNumber=@PSupplementary and
				  AccountCode = @DFRAccount
		Select @CRDFR=sum(Credit) from TicketDetails
			where BranchCode=@Branch and TicketDate=@PPostDate and SupplementaryNumber=@PSupplementary and
				  AccountCode = @DFRAccount
		Select @DRDTO=sum(Debit) from TicketDetails
			where BranchCode=@Branch and TicketDate=@PPostDate and SupplementaryNumber=@PSupplementary and
				  AccountCode = @DTOAccount
		Select @CRDTO=sum(Credit) from TicketDetails
			where BranchCode=@Branch and TicketDate=@PPostDate and SupplementaryNumber=@PSupplementary and
				  AccountCode = @DTOAccount
		if (@DRDFR is not null) or (@CRDTO is not null)
		begin
			set @EBDFR=abs(@BBDFR+@DRDFR-@CRDFR)
			set @EBDTO=abs(@BBDTO+@DRDTO-@CRDTO)
		--	select @origin=Origin from users where UserID='BOSNET'
			exec GetTicketNumber @TktNumber output
			if @EBDFR<@EBDTO
			begin
				insert into TicketDetails (TicketDate,SupplementaryNumber,BranchCode,ReferenceKey,TicketNumber,AccountCode,Debit,Credit,CostCenter) values(@Postdate,@Supplementary,@Branch,@Origin,@TktNumber,@DFRAccount,0,@EBDFR,null)
				insert into TicketDetails (TicketDate,SupplementaryNumber,BranchCode,ReferenceKey,TicketNumber,AccountCode,Debit,Credit,CostCenter) values(@Postdate,@Supplementary,@Branch,@Origin,@TktNumber,@DTOAccount,@EBDFR,0,null)
			end
			else
			begin
				if @EBDTO<@EBDFR
				begin
					insert into TicketDetails (TicketDate,SupplementaryNumber,BranchCode,ReferenceKey,TicketNumber,AccountCode,Debit,Credit,CostCenter) values(@Postdate,@Supplementary,@Branch,@Origin,@TktNumber,@DFRAccount,0,@EBDTO,null)
					insert into TicketDetails (TicketDate,SupplementaryNumber,BranchCode,ReferenceKey,TicketNumber,AccountCode,Debit,Credit,CostCenter) values(@Postdate,@Supplementary,@Branch,@Origin,@TktNumber,@DTOAccount,@EBDTO,0,null)
				end
				else
				set @DRDFR=null
			end
			insert into TicketMaster (TicketDate,SupplementaryNumber,BranchCode,Origin,TicketNumber,Particulars,EnteredBy,CheckedBy,ApprovedBy,Status,Mnemonic,Product)
							  values (@Postdate,@Supplementary,@Branch,@Origin,@TktNumber,'Computer generated ticket to net out Due From and Due To','BOSNET','BOSNET','BOSNET','Updated','','')
		end
	 --Post debit and credit tickets to lowest level accounts
		update glsummary
			set  glsummary.Debits=(select sum(ticketdetails.Debit)
						   from ticketdetails
						   where ticketdetails.AccountCode=glsummary.AccountCode
							   and ticketdetails.BranchCode=@Branch
										   and ticketdetails.TicketDate=@PostDate
							   and ticketdetails.SupplementaryNumber=@Supplementary),
				 glsummary.Credits=-(select sum(ticketdetails.Credit)
						   from ticketdetails
						   where ticketdetails.AccountCode=glsummary.AccountCode
							   and ticketdetails.BranchCode=@Branch
										   and ticketdetails.TicketDate=@PostDate
							   and ticketdetails.SupplementaryNumber=@Supplementary)
			from glsummary
			where glsummary.AccountCode in (select ticketdetails.AccountCode from ticketdetails
								 where ticketdetails.BranchCode=@Branch
									 and ticketdetails.TicketDate=@PostDate
						 and ticketdetails.SupplementaryNumber=@Supplementary)
				and glsummary.BranchCode=@Branch
				and glsummary.PostingDate=@PostDate
				and glsummary.SupplementaryNumber=@Supplementary
				and glsummary.AccountCode in (select AccountCode from ChartOfAccounts
								 where AccountType='D')
	-- Update parent accounts' debit and credit columns
		open Summary_Accounts
		fetch Summary_Accounts into @AccountCode, @SummaryAccount, @BeginningBalance, @Debits, @Credits
		while (@@fetch_status = 0)
			begin
					update glsummary
						set BeginningBalance=BeginningBalance+@BeginningBalance,
				  Debits=Debits+@Debits,
				  Credits=Credits+@Credits
					from glsummary
					where BranchCode=@Branch
			and PostingDate=@PostDate
			and SupplementaryNumber=@Supplementary
						and AccountCode=@SummaryAccount
				fetch Summary_Accounts into @AccountCode, @SummaryAccount, @BeginningBalance, @Debits, @Credits
			end
		deallocate Summary_Accounts

	-- Update new records' ending balances
		update glsummary
			set EndingBalance=BeginningBalance+Debits+Credits
			from glsummary
			where BranchCode=@Branch
				and PostingDate=@PostDate
				and SupplementaryNumber=@Supplementary
	-- Delete records w/ zero balances
		delete from glsummary where beginningbalance=0 and debits=0 and credits=0 and endingbalance=0
		if exists (select 1 from PostingDateControl where BranchCode=@Branch)
			Update PostingDateControl set LatestPostingDate=@Postdate where BranchCode=@Branch
		else
			Insert into PostingDateControl (BranchCode, LatestPostingDate) values (@Branch, @Postdate)
		 COMMIT TRANSACTION
		 return 0
	END
END
GO
