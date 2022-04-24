Alert-TempDb-Files-Space-Usage.sql

https://github.com/imajaydwivedi/SQLDBA-SSMS-Solution/blob/master/TempDb-Issues/Alert-TempDb-Files-Space-Usage.sql

set nocount on;
DECLARE @p_DataFileUsedSpaceThreshold_gb numeric(20,2);
DECLARE @p_LogFileUsedSpaceThreshold_gb numeric(20,2);
DECLARE @p_VersionStoreThreshold_gb numeric(20,2);
DECLARE @verbose BIT = 0;

SET @p_DataFileUsedSpaceThreshold_gb = 80.0;
SET @p_LogFileUsedSpaceThreshold_gb = 90.0;
SET @p_VersionStoreThreshold_gb = 200;
/*
	For Log File => with oldest transaction of 134 minutes, Space Used was 55 GB
	For Data File => check allocation of internal objects, version_store etc
*/
/*
--DROP TABLE DBA.dbo.DatabaseFileSpaceUsage
CREATE TABLE DBA.dbo.DatabaseFileSpaceUsage
(
	srvName VARCHAR(125) NOT NULL,
	dbName VARCHAR(125) NOT NULL,
	logical_file_name VARCHAR(125) NOT NULL,
	type_desc char(4) NOT NULL,
	physical_name VARCHAR(255) NOT NULL,
	size_gb numeric(20,2) NOT NULL,
	spaceUsed_gb numeric(20,2) NOT NULL,
	freeSpace_gb numeric(20,2) NOT NULL,
	collection_time smalldatetime NOT NULL default getdate()
);

alter table DBA.dbo.DatabaseFileSpaceUsage add primary key (collection_time,dbName,physical_name);

--	drop table [DBA].[dbo].[DatabaseOpenTransactions]
CREATE TABLE [DBA].[dbo].[DatabaseOpenTransactions]
(
	ID BIGINT IDENTITY(1,1),
	[dbID] [int] NULL,
	[dbName] varchar(125) NULL,
	[session_id] [int] NOT NULL,
	[host_name] varchar(125) NULL,
	[login_name] varchar(125) NULL,
	[transaction_begin_time] [smalldatetime] NOT NULL,
	[TransactionTime(Minutes)] bigint NULL,
	[sql_text] text NULL,
	[transaction_id] [bigint] NOT NULL,
	[transaction_name] varchar(32) NOT NULL,
	[transaction_type] [varchar](100) NULL,
	[transaction_state] [varchar](100) NULL,
	[dtc_state] [varchar](30) NULL,
	[transaction_status] [int] NOT NULL,
	[transaction_status2] [int] NOT NULL,
	[dtc_status] [int] NOT NULL,
	[dtc_isolation_level] [int] NOT NULL,
	collection_time smalldatetime default getdate()
	--[IsActive] bit default 1
);

CREATE CLUSTERED INDEX CI_DatabaseOpenTransactions__collection_time__session_id ON DBA.dbo.DatabaseOpenTransactions (collection_time,[TransactionTime(Minutes)] DESC, session_id);

--	DROP TABLE [DBA].[dbo].[DatabaseFileSpaceUsage_Internals]
CREATE TABLE [DBA].[dbo].[DatabaseFileSpaceUsage_Internals]
(
	dbName varchar(125) NOT NULL,
	[DMV] [varchar](50) NOT NULL,
	[usr_obj_kb] [bigint] NULL,
	[internal_obj_kb] [bigint] NULL,
	[version_store_kb] [bigint] NULL,
	[version_store_gb] [bigint] NULL,
	[freespace_kb] [bigint] NULL,
	[mixedextent_kb] [bigint] NULL,
	[collection_time] smalldatetime default getdate() not null
);

CREATE CLUSTERED INDEX CI_DatabaseFileSpaceUsage_Internals__collection_time ON DBA.dbo.[DatabaseFileSpaceUsage_Internals] (collection_time);


--	DROP TABLE [DBA].[dbo].[VersionStoreActiveTransactions]
CREATE TABLE [DBA].[dbo].[VersionStoreActiveTransactions]
(
	[collection_time] [smalldatetime] NOT NULL,
	[elapsed_time_minutes] [bigint] NULL,
	[transaction_id] [bigint] NULL,
	[transaction_sequence_num] [bigint] NULL,
	[commit_sequence_num] [bigint] NULL,
	[session_id] [int] NULL,
	[is_snapshot] [bit] NULL,
	[first_snapshot_sequence_num] [bigint] NULL,
	[max_version_chain_traversed] [int] NULL,
	[average_version_chain_traversed] [float] NULL,
	[elapsed_time_seconds] [bigint] NULL,
	[kpid] [smallint] NULL,
	[blocked] [smallint] NULL,
	[lastwaittype] [nchar](32) NULL,
	[waitresource] [nchar](256) NULL,
	[database_name] [nvarchar](128) NULL,
	[cpu] [int] NULL,
	[physical_io] [bigint] NULL,
	[memusage] [int] NULL,
	[login_time] [smalldatetime] NULL,
	[last_batch] [smalldatetime] NULL,
	[open_tran] [smallint] NULL,
	[status] [nchar](30) NULL,
	[hostname] [nchar](128) NULL,
	[Program_name] [nvarchar](138) NULL,
	[cmd] [nchar](16) NULL,
	[loginame] [nchar](128) NULL,
	[request_id] [int] NULL
);

CREATE CLUSTERED INDEX CI_VersionStoreActiveTransactions__collection_time ON DBA.dbo.[VersionStoreActiveTransactions] (collection_time);

*/

DECLARE @_collection_time smalldatetime;
DECLARE @_collect_whoIsActive_ResultSets bit;
DECLARE @_isLogSizeCrossed bit;
DECLARE @_isDataSizeCrossed bit;
DECLARE @_isVersionStoreIssue bit;
DECLARE @_dataFileCurrentSpaceUsed numeric(20,2);
DECLARE @_logFileCurrentSpaceUsed numeric(20,2);
DECLARE @_dataFileGrowthInLast2Hours numeric(20,2);
DECLARE @_logFileGrowthInLast2Hours numeric(20,2);
SET @_collection_time = GETDATE();
SET @_collect_whoIsActive_ResultSets = 0;
SET @_isLogSizeCrossed = 0;
SET @_isDataSizeCrossed = 0;
SET @_isVersionStoreIssue = 0;

DELETE FROM DBA..DatabaseFileSpaceUsage WHERE collection_time < DATEADD(DAY,-60,GETDATE());
DELETE FROM [DBA].[dbo].[DatabaseFileSpaceUsage_Internals] WHERE collection_time < DATEADD(DAY,-60,GETDATE());
DELETE FROM DBA..DatabaseOpenTransactions WHERE collection_time < DATEADD(DAY,-60,GETDATE());
DELETE FROM [DBA]..[VersionStoreActiveTransactions] WHERE collection_time < DATEADD(DAY,-60,GETDATE());

use tempdb;
INSERT DBA.dbo.DatabaseFileSpaceUsage (srvName, dbName,logical_file_name, type_desc, physical_name, size_gb, spaceUsed_gb, freeSpace_gb, collection_time)
SELECT @@servername, db_name(), df.name, df.type_desc, df.physical_name, size_gb = (df.size*8.0/1024/1024), CAST(FILEPROPERTY(df.name, 'SpaceUsed') as BIGINT)/128.0/1024 AS SpaceUsed_gb
		,(size/128.0 -CAST(FILEPROPERTY(name,'SpaceUsed') AS INT)/128.0)/1024 AS FreeSpace_GB ,@_collection_time
from tempdb.sys.database_files as df;

-- If Log file cross threshold
IF EXISTS (SELECT * FROM DBA.dbo.DatabaseFileSpaceUsage as fu WHERE fu.type_desc = 'LOG' AND fu.spaceUsed_gb >= @p_LogFileUsedSpaceThreshold_gb AND collection_time = @_collection_time)
BEGIN
	SET @_collect_whoIsActive_ResultSets = 1;
	SET @_isLogSizeCrossed = 1;

	-- Record Long Running Transactions against TempDb database
	INSERT DBA..DatabaseOpenTransactions
	(dbID, dbName, session_id, host_name, login_name, transaction_begin_time, [TransactionTime(Minutes)], [sql_text], transaction_id, transaction_name, transaction_type, transaction_state, dtc_state, transaction_status, transaction_status2, dtc_status, dtc_isolation_level, collection_time)
	SELECT	tds.database_id AS [DATABASE ID]
			,DBs.name AS [dbName]
			,trans.session_id AS [SESSION ID]
			,ESes.host_name AS [HOST NAME]
			,login_name AS [Login NAME]
			,transaction_begin_time
			,DATEDIFF(MINUTE,transaction_begin_time,GETDATE()) AS [TransactionTime(Minutes)]
			,st.text as [sql_text]
			,trans.transaction_id AS [TRANSACTION ID]
			,tas.name AS [TRANSACTION NAME]		
			,case transaction_type 
					when 1 then '1 = Read/write transaction'
					when 2 then '2 = Read-only transaction'
					when 3 then '3 = System transaction'
					when 4 then '4 = Distributed transaction'
			end as transaction_type 
			,case transaction_state 
					when 0 then '0 = The transaction has not been completely initialized yet'
					when 1 then '1 = The transaction has been initialized but has not started'
					when 2 then '2 = The transaction is active'
					when 3 then '3 = The transaction has ended. This is used for read-only transactions'
					when 4 then '4 = The commit process has been initiated on the distributed transaction'
					when 5 then '5 = The transaction is in a prepared state and waiting resolution'
					when 6 then '6 = The transaction has been committed'
					when 7 then '7 = The transaction is being rolled back'
					when 8 then '8 = The transaction has been rolled back'
			end as transaction_state
			,case dtc_state 
					when 1 then '1 = ACTIVE'
					when 2 then '2 = PREPARED'
					when 3 then '3 = COMMITTED'
					when 4 then '4 = ABORTED'
					when 5 then '5 = RECOVERED'
			end as dtc_state 
			,transaction_status, transaction_status2,dtc_status, dtc_isolation_level
			,@_collection_time
	FROM sys.dm_tran_active_transactions tas
	JOIN sys.dm_tran_session_transactions trans ON (trans.transaction_id = tas.transaction_id)
	LEFT OUTER JOIN sys.dm_tran_database_transactions tds ON (tas.transaction_id = tds.transaction_id)
	LEFT OUTER JOIN sys.databases AS DBs ON tds.database_id = DBs.database_id
	LEFT OUTER JOIN sys.dm_exec_sessions AS ESes ON trans.session_id = ESes.session_id
	LEFT OUTER JOIN sys.dm_exec_requests as r on r.session_id = trans.session_id
	OUTER APPLY(SELECT text FROM sys.dm_exec_sql_text(r.sql_handle) as st ) AS st
	WHERE ESes.session_id IS NOT NULL
	AND DBs.name = 'tempdb'
	AND DATEDIFF(MINUTE,transaction_begin_time,GETDATE()) >= 30
	ORDER BY transaction_begin_time
END

-- If Data file cross threshold
IF EXISTS (SELECT * FROM DBA.dbo.DatabaseFileSpaceUsage as fu WHERE fu.type_desc = 'ROWS' AND fu.spaceUsed_gb >= @p_DataFileUsedSpaceThreshold_gb AND collection_time = @_collection_time)
BEGIN
	IF @_collect_whoIsActive_ResultSets = 0
		SET @_collect_whoIsActive_ResultSets = 1;
	SET @_isDataSizeCrossed = 1;

	-- Make note of TempDb allocations
	INSERT [DBA].[dbo].[DatabaseFileSpaceUsage_Internals]
	(dbName, [DMV], [usr_obj_kb], [internal_obj_kb], [version_store_kb], [version_store_gb], [freespace_kb], [mixedextent_kb], [collection_time])
	SELECT	dbName = DB_NAME(), 'sys.dm_db_file_space_usage' as DMV, SUM (user_object_reserved_page_count)*8 as usr_obj_kb,
			SUM (internal_object_reserved_page_count)*8 as internal_obj_kb,
			SUM (version_store_reserved_page_count)*8 as version_store_kb,
			SUM (version_store_reserved_page_count)*8/1024/1024 as version_store_gb,
			SUM (unallocated_extent_page_count)*8 as freespace_kb,
			SUM (mixed_extent_page_count)*8 as mixedextent_kb
			,@_collection_time AS [collection_time]
	FROM sys.dm_db_file_space_usage;

	-- If VersionStore usage is more than 30% of Total Data File Used space, or greater than @p_VersionStoreThreshold_gb
	IF EXISTS (	SELECT * FROM [DBA].[dbo].[DatabaseFileSpaceUsage_Internals] v 
				WHERE	v.collection_time = @_collection_time
					AND	(	v.version_store_gb >= @p_VersionStoreThreshold_gb
						OR	(	v.version_store_gb >= (SELECT SUM(spaceUsed_gb)*0.3 FROM DBA.dbo.DatabaseFileSpaceUsage s 
														WHERE s.collection_time = @_collection_time AND type_desc = 'ROWS' AND dbName = 'tempdb'
													  )
							)
						)
			  ) 
	BEGIN
		SET @_isVersionStoreIssue = 1;

		IF @verbose = 1
			PRINT 'Either @p_VersionStoreThreshold_gb is crossed, or the VersionStore space share is more than 30% of total tempdb data file size';

		INSERT [DBA]..[VersionStoreActiveTransactions]
		--	Find all the transactions currently maintaining an active version store
		select	@_collection_time AS collection_time, (a.elapsed_time_seconds/60) as elapsed_time_minutes, a.*,b.kpid,b.blocked,b.lastwaittype,b.waitresource,db_name(b.dbid) as database_name,
				b.cpu,b.physical_io,b.memusage,b.login_time,b.last_batch,b.open_tran,b.status,b.hostname,
				CASE LEFT(b.program_name,15)
					WHEN 'SQLAgent - TSQL' THEN 
					(     select top 1 'SQL Job = '+j.name from msdb.dbo.sysjobs (nolock) j
						  inner join msdb.dbo.sysjobsteps (nolock) s on j.job_id=s.job_id
						  where right(cast(s.job_id as nvarchar(50)),10) = RIGHT(substring(b.program_name,30,34),10) )
					WHEN 'SQL Server Prof' THEN 'SQL Server Profiler'
					ELSE b.program_name
					END as Program_name,
				b.cmd,b.loginame,request_id
		from sys.dm_tran_active_snapshot_database_transactions a inner join sys.sysprocesses b on a.session_id = b.spid
		where open_tran <> 0
		AND (a.elapsed_time_seconds/60) >= 180
		order by elapsed_time_minutes desc;
	END

END

SELECT	@_dataFileCurrentSpaceUsed = MAX((CASE WHEN f.type_desc = 'ROWS' THEN spaceUsed_gb ELSE 0 END)), @_logFileCurrentSpaceUsed = MAX((CASE WHEN f.type_desc = 'LOG' THEN spaceUsed_gb ELSE 0 END))
FROM	DBA.dbo.DatabaseFileSpaceUsage AS f
WHERE	f.collection_time = @_collection_time
AND		f.dbName = 'tempdb';

;WITH T_DbFilesCollection_2Hours AS
(
	SELECT	[Data_Max_SpaceUsed_gb] = MAX((CASE WHEN f.type_desc = 'ROWS' THEN spaceUsed_gb ELSE 0 END))
			,[Data_Min_SpaceUsed_gb] = MIN((CASE WHEN f.type_desc = 'ROWS' THEN spaceUsed_gb ELSE 0 END))
			,[Log_Max_SpaceUsed_gb] = MAX((CASE WHEN f.type_desc = 'ROWS' THEN spaceUsed_gb ELSE 0 END))
			,[Log_Min_SpaceUsed_gb] = MIN((CASE WHEN f.type_desc = 'ROWS' THEN spaceUsed_gb ELSE 0 END))
	FROM	DBA.dbo.DatabaseFileSpaceUsage AS f WHERE f.collection_time >= DATEADD(HOUR,-2,@_collection_time) AND f.dbName = 'tempdb'
)
SELECT	@_dataFileGrowthInLast2Hours = [Data_Max_SpaceUsed_gb] - [Data_Min_SpaceUsed_gb]
		,@_logFileGrowthInLast2Hours = [Log_Max_SpaceUsed_gb] - [Log_Min_SpaceUsed_gb]
FROM	T_DbFilesCollection_2Hours AS f;

SET @_collection_time = GETDATE();
IF (@_isLogSizeCrossed = 1 OR @_isDataSizeCrossed = 1 OR @_isVersionStoreIssue = 1)
BEGIN
	DECLARE @_mailBody varchar(max);
	
	SET @_mailBody = 'Hi DBA,

Tempdb data or log files used space value has crossed below threshold values:-
'+(CASE WHEN @_isDataSizeCrossed = 1 THEN CHAR(13)+'    @p_DataFileUsedSpaceThreshold_gb = '+CAST(@p_DataFileUsedSpaceThreshold_gb AS VARCHAR(50)) ELSE '' END)
 +(CASE WHEN @_isDataSizeCrossed = 1 THEN CHAR(13)+'        Current Data File Size(gb) = '+CAST(@_dataFileCurrentSpaceUsed AS VARCHAR(50)) ELSE '' END)
 +(CASE WHEN @_isLogSizeCrossed = 1 THEN CHAR(13)+'    @p_LogFileUsedSpaceThreshold_gb = '+CAST(@p_LogFileUsedSpaceThreshold_gb AS VARCHAR(50)) ELSE '' END)
 +(CASE WHEN @_isLogSizeCrossed = 1 THEN CHAR(13)+'        Current Log File Size(gb) = '+CAST(@_logFileCurrentSpaceUsed AS VARCHAR(50)) ELSE '' END)
 +(CASE WHEN @_isVersionStoreIssue = 1 THEN CHAR(13)+'    @p_VersionStoreThreshold_gb = '+CAST(@p_VersionStoreThreshold_gb AS VARCHAR(50)) ELSE '' END)+'
'+(CASE WHEN @_isDataSizeCrossed = 1 THEN CHAR(13)+'    Data File Growth in last 2 Hours(gb) = '+CAST(@_dataFileGrowthInLast2Hours AS VARCHAR(50)) ELSE '' END)
 +(CASE WHEN @_isLogSizeCrossed = 1 THEN CHAR(13)+'    Log File Growth in last 2 Hours(gb) = '+CAST(@_logFileGrowthInLast2Hours AS VARCHAR(50)) ELSE '' END)+'


Kindly execute below queries to troubleshoot:-
'+(CASE WHEN @_isDataSizeCrossed = 1 OR @_isLogSizeCrossed = 1 THEN CHAR(13)+'    SELECT ''Current Files Usage'' as [QueryType], * FROM DBA.dbo.DatabaseFileSpaceUsage WHERE collection_time = '''+CAST(@_collection_time AS VARCHAR(30))+''';'+CHAR(13) ELSE '' END)
+(CASE WHEN @_isVersionStoreIssue = 1 OR @_isDataSizeCrossed = 1 OR @_isLogSizeCrossed = 1 THEN CHAR(13)+'    SELECT ''WhoIsActive ResultSet'' as QueryType, * FROM DBA.dbo.WhoIsActive_ResultSets r WHERE r.collection_time = (select min(i.collection_time) from DBA.dbo.WhoIsActive_ResultSets i where i.collection_time >= CAST('''+CAST(@_collection_time AS VARCHAR(30))+''' AS smalldatetime));'+CHAR(13) ELSE '' END)
+(CASE WHEN @_isVersionStoreIssue = 1 OR @_isDataSizeCrossed = 1 THEN CHAR(13)+'    SELECT ''TempDb Space Allocation Details'' as QueryType, * FROM DBA.dbo.DatabaseFileSpaceUsage_Internals WHERE collection_time = '''+CAST(@_collection_time AS VARCHAR(30))+''';'+CHAR(13) ELSE '' END)
+(CASE WHEN @_isLogSizeCrossed = 1 THEN CHAR(13)+'    SELECT ''Open Transactions on TempDb'' as QueryType, * FROM DBA.dbo.DatabaseOpenTransactions WHERE collection_time = '''+CAST(@_collection_time AS VARCHAR(30))+''';'+CHAR(13) ELSE '' END)
+(CASE WHEN @_isVersionStoreIssue = 1 THEN CHAR(13)+'    SELECT ''Open Transactions using VersionStore'' as QueryType, * FROM DBA.dbo.VersionStoreActiveTransactions WHERE collection_time = '''+CAST(@_collection_time AS VARCHAR(30))+''';'+CHAR(13) ELSE '' END)
+CHAR(13)+'

Thanks & Regards,
DBA Alerts,
-- Alert coming from job [DBA - TempDb - Space Utilization - Alert]
';

	IF @verbose = 1
		PRINT @_mailBody;

	EXEC msdb..sp_send_dbmail
			@profile_name = @@servername,
			@recipients = 'It-Ops-DBA@contso.com',
			--@recipients = 'ajay.dwivedi@contso.com',
			@subject = 'Alert - TempDb Files Size Crossed Threshold',
			@body = @_mailBody;
END

--	Collect data from sp_WhoIsActive
IF @_collect_whoIsActive_ResultSets = 1 AND DBA.dbo.fn_IsJobRunning('DBA - Log_With_sp_WhoIsActive') = 0
BEGIN
	IF @verbose = 1
		PRINT 'Trying to start job [DBA - Log_With_sp_WhoIsActive]';
	EXEC msdb..sp_start_job [DBA - Log_With_sp_WhoIsActive];
END
GO
/*
SELECT * FROM DBA.dbo.DatabaseFileSpaceUsage s WHERE s.collection_time = (select max(i.collection_time) from DBA.dbo.DatabaseFileSpaceUsage i);
SELECT * FROM DBA.dbo.DatabaseOpenTransactions t  WHERE t.collection_time = (select max(i.collection_time) from DBA.dbo.DatabaseOpenTransactions i);
SELECT * FROM [DBA]..[DatabaseFileSpaceUsage_Internals] t  WHERE t.collection_time = (select max(i.collection_time) from DBA.dbo.DatabaseFileSpaceUsage_Internals i);
SELECT * FROM [DBA]..[VersionStoreActiveTransactions] t  WHERE t.collection_time = (select max(i.collection_time) from DBA.dbo.VersionStoreActiveTransactions i);

SELECT * FROM DBA.dbo.WhoIsActive_ResultSets r WHERE r.collection_time = (select min(i.collection_time) from DBA.dbo.WhoIsActive_ResultSets i where i.collection_time >= '');
*/
