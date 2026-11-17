/*==============================================================
  文件名称：JOB_SapProductInventorySync_Create.sql
  功能说明：创建 SQL Server 代理作业，每天凌晨 02:00 执行
            dbo.APISyncU_SapProductInventorySync 同步 SAP 产品库存
  执行库  ：msdb
  前置条件：1) 当前登录需具备 sysadmin 权限
            2) SQL Server 代理服务已启动
  脚本特性：可重复执行，同名作业/调度已存在时先删除后重建
  作    者：MES 开发
  修改记录：
      2026-11-11  新建
==============================================================*/
USE [msdb];
GO

SET NOCOUNT ON;
GO

/*--------------------------------------------------------------
  1. 权限与前置校验
--------------------------------------------------------------*/
IF IS_SRVROLEMEMBER('sysadmin') = 0
BEGIN
    RAISERROR(N'当前登录不是 sysadmin，无法创建/修改 SQL Server 代理作业，请联系 DBA 执行本脚本。', 16, 1);
    RETURN;
END
GO

DECLARE @JobName      SYSNAME        = N'JOB_SapProductInventorySync';           -- 作业名称
DECLARE @ScheduleName SYSNAME        = N'SCHED_SapProductInventorySync_Daily0200'; -- 调度名称
DECLARE @StepName     SYSNAME        = N'S1_同步SAP产品库存';
DECLARE @DatabaseName SYSNAME        = N'OrBitMOM';                              -- 目标库：生产 OrBitMOM / 开发 OrBitMOMTestBack
DECLARE @ServerName   SYSNAME        = CONVERT(SYSNAME, SERVERPROPERTY('ServerName'));
DECLARE @StartDate    INT            = CONVERT(INT, CONVERT(VARCHAR(8), GETDATE(), 112)); -- 生效日期=今天，避免建完立即补跑
DECLARE @JobId        UNIQUEIDENTIFIER;
DECLARE @ScheduleId   INT;
DECLARE @Command      NVARCHAR(MAX);

/*--------------------------------------------------------------
  2. 参数非空与合法性校验
--------------------------------------------------------------*/
IF @JobName IS NULL OR LTRIM(RTRIM(@JobName)) = N''
BEGIN
    RAISERROR(N'作业名称不能为空。', 16, 1);
    RETURN;
END

IF @ScheduleName IS NULL OR LTRIM(RTRIM(@ScheduleName)) = N''
BEGIN
    RAISERROR(N'调度名称不能为空。', 16, 1);
    RETURN;
END

IF @DatabaseName IS NULL OR LTRIM(RTRIM(@DatabaseName)) = N''
BEGIN
    RAISERROR(N'目标数据库名不能为空。', 16, 1);
    RETURN;
END

-- 目标库必须存在
IF DB_ID(@DatabaseName) IS NULL
BEGIN
    RAISERROR(N'目标数据库 [%s] 不存在，请修改 @DatabaseName 后重试。', 16, 1, @DatabaseName);
    RETURN;
END

-- 目标存储过程必须存在，避免作业建好后才在夜间报错
IF OBJECT_ID(QUOTENAME(@DatabaseName) + N'.dbo.APISyncU_SapProductInventorySync') IS NULL
BEGIN
    RAISERROR(N'目标库 [%s] 中不存在 dbo.APISyncU_SapProductInventorySync，请确认后重试。', 16, 1, @DatabaseName);
    RETURN;
END

/*--------------------------------------------------------------
  3. 删除同名旧作业（幂等重建）
--------------------------------------------------------------*/
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    -- @delete_unused_schedule = 1：同时删除不再被任何作业引用的调度
    EXEC msdb.dbo.sp_delete_job
         @job_name              = @JobName,
         @delete_unused_schedule = 1;
END

-- 清理残留同名调度（若仍被其他作业共享，需人工确认后再删除）
IF EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = @ScheduleName)
BEGIN
    EXEC msdb.dbo.sp_delete_schedule
         @schedule_name = @ScheduleName;
END

/*--------------------------------------------------------------
  4. 组装作业步骤命令
     步骤内对返回消息做非空校验，无返回内容时主动报错，
     使作业标记为失败，便于告警与追溯。
--------------------------------------------------------------*/
SET @Command = N'
DECLARE @msg NVARCHAR(MAX) = N'''';

-- 调用 SAP 产品库存同步接口
EXEC dbo.APISyncU_SapProductInventorySync
     @I_ReturnMessage = @msg OUTPUT,
     @Batch           = 1,
     @ItemName        = N''U_ProductInventory_JAVA'',
     @ProductName     = N'''',
     @WorkcenterName  = N'''';

-- 无返回消息视为异常，抛错让作业步骤失败
IF @msg IS NULL OR LTRIM(RTRIM(@msg)) = N''''
BEGIN
    RAISERROR(N''APISyncU_SapProductInventorySync 未返回任何消息，请检查同步结果。'', 16, 1);
    RETURN;
END

-- 输出到作业历史（PRINT 内容会记录在 msdb.dbo.sysjobhistory 的 message 字段）
PRINT LEFT(@msg, 4000);
';

/*--------------------------------------------------------------
  5. 创建作业主体
--------------------------------------------------------------*/
EXEC msdb.dbo.sp_add_job
     @job_name              = @JobName,
     @enabled               = 1,
     @description           = N'每天凌晨02:00同步SAP产品库存(U_ProductInventory_JAVA)',
     @notify_level_eventlog = 2,          -- 2=仅失败时写入 Windows 事件日志
     @job_id                = @JobId OUTPUT;

IF @JobId IS NULL
BEGIN
    RAISERROR(N'作业创建失败，@JobId 为空，请检查 SQL Server 代理状态与权限。', 16, 1);
    RETURN;
END

/*--------------------------------------------------------------
  6. 添加作业步骤（TSQL，指定目标库，失败重试2次、间隔5分钟）
--------------------------------------------------------------*/
EXEC msdb.dbo.sp_add_jobstep
     @job_id            = @JobId,
     @step_id           = 1,
     @step_name         = @StepName,
     @subsystem         = N'TSQL',
     @database_name     = @DatabaseName,
     @command           = @Command,
     @retry_attempts    = 2,
     @retry_interval    = 5,
     @on_success_action = 1,              -- 1=退出并报告成功
     @on_fail_action    = 2;              -- 2=退出并报告失败

/*--------------------------------------------------------------
  7. 创建调度：每天 02:00 执行一次
     freq_type           = 1  -> 每天
     freq_interval       = 1  -> 每 1 天
     freq_subday_type    = 1  -> 在指定时间执行一次
     active_start_time   = 20000 -> HHMMSS 格式，即 02:00:00
--------------------------------------------------------------*/
EXEC msdb.dbo.sp_add_schedule
     @schedule_name        = @ScheduleName,
     @enabled              = 1,
     @freq_type            = 1,
     @freq_interval        = 1,
     @freq_subday_type     = 1,
     @freq_subday_interval = 0,
     @active_start_date    = @StartDate,
     @active_end_date      = 99991231,
     @active_start_time    = 20000,
     @active_end_time      = 235959,
     @schedule_id          = @ScheduleId OUTPUT;

IF @ScheduleId IS NULL
BEGIN
    RAISERROR(N'调度创建失败，@ScheduleId 为空。', 16, 1);
    RETURN;
END

/*--------------------------------------------------------------
  8. 绑定调度到作业，并指定目标服务器
--------------------------------------------------------------*/
EXEC msdb.dbo.sp_attach_schedule
     @job_id        = @JobId,
     @schedule_name = @ScheduleName;

EXEC msdb.dbo.sp_add_jobserver
     @job_id      = @JobId,
     @server_name = @ServerName;

/*--------------------------------------------------------------
  9. 结果校验：输出作业、调度与步骤信息
--------------------------------------------------------------*/
SELECT j.name                                            AS 作业名称,
       j.enabled                                         AS 是否启用,
       sc.name                                           AS 调度名称,
       N'每天'                                            AS 执行频率,
       STUFF(STUFF(RIGHT(N'000000' + CONVERT(VARCHAR(6), sc.active_start_time), 6), 5, 0, N':'), 3, 0, N':') AS 执行时间,
       st.step_id                                        AS 步骤号,
       st.step_name                                      AS 步骤名称,
       st.database_name                                  AS 目标库,
       st.retry_attempts                                 AS 重试次数
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules  sc ON sc.schedule_id = js.schedule_id
JOIN msdb.dbo.sysjobsteps   st ON st.job_id = j.job_id
WHERE j.name = @JobName;

PRINT N'作业 [' + @JobName + N'] 创建完成，将于每天 02:00:00 执行。';
PRINT N'如需立即验证，可执行：EXEC msdb.dbo.sp_start_job @job_name = N''' + @JobName + N''';';
PRINT N'查看执行历史：EXEC msdb.dbo.sp_help_jobhistory @job_name = N''' + @JobName + N''', @mode = ''FULL'';';
GO
