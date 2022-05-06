DatabaseGrowthHTMLReport.sql
--Source: https://gist.github.com/lionofdezert/3168718
/*
 Script to send an alert through mail, with information that how many drive 
 space is required from next databases growth on a specific instance and how many
 space is available. 



 Script By: Amna Asif for ConnectSQL.blogspot.com
 */


 DECLARE @dbName varchar(200),
    @Qry Nvarchar(max)
 DECLARE @dbsize VARCHAR(50),
    @logsize VARCHAR(50),
    @reservedpages VARCHAR(50),
    @usedpages VARCHAR(50),
    @pages VARCHAR(50)



 SET @dbName = ''


---Get LOG File Spaces of All Databases--
 CREATE TABLE #LogSpaceStats
    (
      RowID INT IDENTITY
                PRIMARY KEY,
      dbName SYSNAME,
      Totallogspace DEC(20, 2),
      UsedLogSpace DEC(20, 2),
      Status CHAR(1)
    ) 
    
 INSERT #LogSpaceStats
        ( dbName, Totallogspace, UsedLogSpace, Status )
        EXEC ( 'DBCC sqlperf(logspace) WITH NO_INFOMSGS'
            ) 
     
--Get Info of All Drives
 DECLARE @ServerDrives TABLE
    (
      RowID int IDENTITY
                PRIMARY KEY,
      Drive char,
      DriveSpace varchar(100),
      Required_Space varchar(100)
    ) 
 INSERT INTO @ServerDrives
        ( Drive, DriveSpace )
        EXEC master.sys.xp_fixeddrives 
--Temporary Table to hold requried data
 CREATE TABLE #ServerFileStats
    (
      RowID INT IDENTITY
                PRIMARY KEY,
      dbName SYSNAME,
      Database_DSize varchar(100),
      Allocated_Space varchar(100),
      Unallocated_Space varchar(100),
      Unused varchar(100),
      Database_LSize varchar(100),
      UsedLogSpace DEC(20, 2),
      FreeLogSpace DEC(20, 2),
      FDataFileGrowth DEC(20, 2),
      FLogFileGrowth DEC(20, 2),
      DataFileDrive char,
      LogFileDrive char
    ) 
   
--Cursor Used to get each database size on given instance
 DECLARE cur_dbName CURSOR
    FOR SELECT  NAME
        FROM    SYS.DATABASES
        WHERE   state_desc = 'ONLINE'
                AND is_read_only = 0 
 OPEN cur_dbName
 FETCH NEXT FROM cur_dbName into @dbName 
 WHILE @@FETCH_Status = 0 
    BEGIN 
        SELECT  @Qry = ' SELECT @dbsizeOUT = sum(convert(bigint,
                              case when status & 64 = 0 then size 
                              else 0 end)) 
                              ,@logsizeOUT = sum(convert(bigint,
                                    case when status & 64 <> 0 then size 
                                    else 0 end))  
                                       FROM [' + @dbName + '].dbo.sysfiles '
                              
        EXEC sp_executesql @Qry,
            N'@dbsizeOUT  nvarchar(50) OUTPUT,@logsizeOUT  nvarchar(50) OUTPUT',
            @dbsizeOUT = @dbsize OUTPUT, @logsizeOUT = @logsize OUTPUT ;  



        SELECT  @Qry = ' SELECT @reservedpagesOUT = sum(a.total_pages)
                                 ,@usedpagesOUT = sum(a.used_pages)
                      FROM [' + @dbName + '].sys.partitions p join [' + @dbName
                + '].sys.allocation_units a on p.partition_id = a.container_id  
                      LEFT JOIN [' + @dbName
                + '].sys.internal_tables it on p.object_id = it.object_id' 



        EXEC sp_executesql @Qry,
     N'@reservedpagesOUT  nvarchar(50) OUTPUT,@usedpagesOUT nvarchar(50) OUTPUT',
            @reservedpagesOUT = @reservedpages OUTPUT,
            @usedpagesOUT = @usedpages OUTPUT ;  
        
        SELECT  @Qry = ' INSERT INTO #ServerFileStats                 
                         SELECT DB_size.Database_Name
                         , DB_size.Database_DSize
                         , DB_size.Allocated_Space
                         , DB_size.Unallocated_Space
                         , DB_size.Unused
                         , DB_size.Database_LSize
             , (lss.TotalLogSpace*(lss.UsedLogSpace/100)) UsedLogSpace
             , (TotalLogSpace-(TotalLogSpace*(UsedLogSpace/100))) FreeLogSpace
             ,CASE mfD.is_percent_growth 
              WHEN 0 THEN CONVERT(DEC(15,2),(mfD.growth* 8192 / 1048576)) 
              ELSE CONVERT(DEC(15,2),(CONVERT(DEC(15,2),REPLACE(DB_size.Database_DSize,'' MB'',''''))
                              *mfD.growth/100)) END  FDataFileGrowth
                          ,
                          CASE mfL.is_percent_growth WHEN 0 THEN CONVERT(DEC(15,2),(mfL.growth* 8192 / 1048576)) 
                          ELSE CONVERT(DEC(15,2),(CONVERT(DEC(15,2),REPLACE(DB_size.Database_DSize,'' MB'',''''))
                          *mfL.growth/100)) END  FLogFileGrowth
                         ,LEFT(mfD.physical_name,1) DataFileDrive
                         ,LEFT(mfL.physical_name,1) LogFileDrive
                         FROM
                         (
                          SELECT Database_Name = ''' + @dbName
                + '''
, Database_DSize = ltrim(str((convert (dec (15,2),'
       + @dbsize
       + '))* 8192 / 1048576,15,2) + '' MB'')
, ''Allocated_Space''=ltrim(str((CASE WHEN '
       + @dbsize + ' >= ' + @reservedpages
       + ' 
THEN convert (DEC (15,2),'
                + @reservedpages
                + ')* 8192 / 1048576 
ELSE 0 end),15,2) + '' MB'')  
                                    , ''Unallocated_Space'' = ltrim(str((CASE WHEN '
               + @dbsize + ' >= ' + @reservedpages
                + ' 
THEN  (convert (DEC (15,2),'
                + @dbsize + ') - convert (DEC (15,2),' + @reservedpages
                + '))* 8192 / 1048576 
ELSE 0 end),15,2) + '' MB'')
                                    , ''Unused'' =ltrim(str((CAST(('
                + @reservedpages + ' - ' + @usedpages
                + ')AS BIGINT) * 8192 / 1024.)/1024,15,2) + '' MB'')  
                , Database_LSize = ltrim(str((convert (dec (15,2),'
                + @logsize
                + '))* 8192 / 1048576,15,2) + '' MB'')
  )DB_size LEFT JOIN #LogSpaceStats AS lss on lss.dbName=DB_size.Database_Name
                          INNER JOIN ' + @dbName
                + '.sys.databases db ON DB.name=DB_size.Database_Name
                          INNER JOIN ' + @dbName
                + '.sys.master_files mfD on mfD.database_id=DB.database_id AND mfD.type_desc=''ROWS''
                          INNER JOIN ' + @dbName
                + '.sys.master_files mfL on mfL.database_id=DB.database_id AND mfL.type_desc=''LOG'''



        EXEC ( @Qry



            )
  FETCH NEXT FROM cur_dbName into @dbName 
    END 
 CLOSE cur_dbName 
 DEALLOCATE cur_dbName 



 UPDATE @ServerDrives
 SET    Required_Space = SumDriveS.sumofdrivespcae
 FROM   ( SELECT    SUM(CONVERT(DEC(20, 2), sumofdrivespcae)) sumofdrivespcae,
                    DRIVE AS DRIVE
          FROM      ( SELECT    SUM(CONVERT(DEC(20, 2), REPLACE(fss.FDataFileGrowth, ' MB', ''))) 
                                                sumofdrivespcae,
                                fss.DataFileDrive AS DRIVE
                      FROM      #ServerFileStats fss
                      GROUP BY  fss.DataFileDrive
                      UNION
                      SELECT    SUM(CONVERT(DEC(20, 2), REPLACE(fss.FLogFileGrowth, ' MB', ''))) 
                                                sumofdrivespcae,
                                fss.LogFileDrive AS DRIVE
                      FROM      #ServerFileStats fss
                      GROUP BY  fss.LogFileDrive ) SumDrive
          GROUP BY  SumDrive.DRIVE ) SumDriveS
        LEFT OUTER JOIN @ServerDrives sd on SumDriveS.Drive = sd.Drive


------------------------------------------------------------------------------
-----------------------------------------Report Mailing-----------------------
DECLARE @Loop int
 DECLARE @Subject varchar(100)
 DECLARE @strMsg varchar(4000)



 SELECT @Subject = 'SQL Monitor Alert: ' + @@SERVERNAME + '        '
        + Convert(varchar, GETDATE())
  Declare @Body varchar(max),
    @TableHead varchar(1000),
    @TableTail varchar(1000),
    @TableHead2 varchar(1000),
    @Body2 varchar(3000)
 Set NoCount On ;
-- Create HTML mail body
 Set @TableTail = '</table></body></html>' ;
  Set @TableHead = '<html><head>' + '<style>'
    + 'td {border: solid black 1px;padding-left:3px;padding-right:3px;padding-top:2px;padding-bottom:2px;font-size:10pt;} '
    + '</style>' + '</head>'
    + '<body><table cellpadding=0 cellspacing=0 border=0>'
    + '<tr><td align=center bgcolor=#E6E6FA><b>Row ID</b></td>'
    + '<td align=center bgcolor=#E6E6FA><b>Database Name</b></td>'
    + '<td align=center bgcolor=#E6E6FA><b>File Group</b></td>'
    + '<td align=center bgcolor=#5F9EA0><b>DF Total Space</b></td>'
    + '<td align=center bgcolor=#5F9EA0><b>DF Allocated Space</b></td>'
    + '<td align=center bgcolor=#5F9EA0><b>DF Unallocated Space</b></td>'
    + '<td align=center bgcolor=#E6E6FA><b>DF Unused</b></td>'
    + '<td align=center bgcolor=#5F9EA0><b>LF Total Space</b></td>'
    + '<td align=center bgcolor=#5F9EA0><b>LF Used Space</b></td>'
    + '<td align=center bgcolor=#5F9EA0><b>LF Unused Space</b></td>'
    + '<td align=center bgcolor=#E6E6FA><b>DF FileGrowth</b></td>'
    + '<td align=center bgcolor=#E6E6FA><b>LF FileGrowth</b></td>'
    + '<td align=center bgcolor=#E6E6FA><b>DF Drive</b></td>'
    + '<td align=center bgcolor=#E6E6FA><b> LF Drive </b></td></tr>' ;



  Select @Body = ( SELECT    td = CONVERT(VARCHAR, ROW_NUMBER() OVER ( ORDER BY dbName ))
                            + CHAR(10),
                            td = ISNULL(dbName, 'Unknown') + CHAR(10),
                            td = ISNULL('Data/LOG', 'Unknown') + CHAR(10),
                            td = ISNULL(Database_DSize, '0.00') + CHAR(10),
                            td = ISNULL(Allocated_Space, '0.00') + CHAR(10),
                            td = ISNULL(Unallocated_Space, '0.00') + CHAR(10),
                            td = ISNULL(Unused, '0.00') + CHAR(10), '',
                            td = ISNULL(Database_LSize, '0.00') + CHAR(10),
                            td = ISNULL(convert(varchar, UsedLogSpace), '0.00')
                            + ' MB' + CHAR(10),
                            td = ISNULL(convert(varchar, FreeLogSpace), '0.00')
                            + ' MB' + CHAR(10),
                            td = ISNULL(convert(varchar, FDataFileGrowth),
                                        '0.00') + ' MB' + CHAR(10), '',
                            td = ISNULL(convert(varchar, FLogFileGrowth),
                                        '0.00') + ' MB' + CHAR(10), '',
                            td = ISNULL(DataFileDrive, '0') + CHAR(10), '',
                            td = ISNULL(LogFileDrive, '0') + CHAR(10), ''
                  FROM      #ServerFileStats
                  ORDER BY  dbName 
        FOR       XML RAW('tr'),
                      ELEMENTS )


-- Replace the entity codes and row numbers
 Set @Body = Replace(@Body, '_x0020_', space(1))
 Set @Body = Replace(@Body, '_x003D_', '=')
 Set @Body = Replace(@Body, '<tr><TRRow>1</TRRow>', '<tr bgcolor=#C6CFFF>')
 Set @Body = Replace(@Body, '<TRRow>0</TRRow>', '')



 DECLARE @flag BIT
 SELECT @flag = 1
 FROM   @ServerDrives
 WHERE  convert(dec(15, 2), DriveSpace) < convert(dec(15, 2), Required_Space)
        * 2
 SET @flag = ISNULL(@flag, 0)



 SET @TableHead2 = '<html><head>' + '<style>'
    + 'td {border: solid black 1px;padding-left:1px;padding-right:1px;padding-top:1px;padding-bottom:1px;font-size:8pt;} '
    + '</style>' + '</head>'
    + '<body><table cellpadding=0 cellspacing=0 border=0>'
    + '<tr><td align=center bgcolor=#E6E6FA><b>Row ID</b></td>'
    + '<td align=center bgcolor=#E6E6FA><b>Drive</b></td>'
    + '<td align=center bgcolor=#E6E6FA><b>Drive Space</b></td> ' 


 IF ( @flag = 0 ) 
    set @TableHead2 = @TableHead2
     + '<td align=center bgcolor=#E6E6FA><b>Required Drive Space</b></td></tr>' ;
 ELSE 
    set @TableHead2 = @TableHead2
     + '<td align=center bgcolor=#FF7F50><b>Required Drive Space</b></td></tr>' ;
          
 Select @Body2 = ( SELECT   td = ROW_NUMBER() OVER ( ORDER BY Drive ),
                            td = ISNULL(Drive, 'Unknown') + char(10),
                            td = ISNULL(DriveSpace + ' MB', 0) + char(10),
                            td = ISNULL(Required_Space + ' MB', 0)
                   FROM     @ServerDrives sd 
        For        XML RAW('tr'),
                       Elements )



 Select @Body = @TableHead2 + @Body2 + @TableTail + '<br/><br/><br/><br/>'
        + @TableHead + @Body + @TableTail
-- Send mail 
 EXEC msdb.dbo.sp_send_dbmail 
      @recipients = 'abc@xyz.com',
    @subject = @Subject, 
    @profile_name = 'MyMailProfileName', 
    @body = @Body,
    @body_format = 'HTML' ;


 --Drop Temporary Tables When Not Required
 DROP TABLE #ServerFileStats
 DROP TABLE #LogSpaceStats
