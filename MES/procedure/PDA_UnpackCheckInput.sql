SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:      <OrBit Team>
-- Create date: <2026/06/23>
-- Description: <PDA拆包装扫码记录>
-- Revision: 1.01
-- Update comment: 业务键由MOName改为LotSN，扫码流程为人员→批号→开始→结束
-- =============================================
ALTER PROCEDURE [dbo].[PDA_UnpackCheckInput]
@I_Sender NVARCHAR(200)='',              -- 客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  -- 返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT, -- 向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',               -- 客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',          -- 插件命令
@I_OrBitUserId CHAR(12)='',              -- 用户ID
@I_OrBitUserName NVARCHAR(100)='',       -- 用户名
@I_ResourceId CHAR(12)='',               -- 资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',        -- 资源名
@I_PKid CHAR(12) ='',                    -- 主键
@I_ParentPKId CHAR(12)='',               -- 父级主键
@I_Parameter NVARCHAR(100)='',           -- 插件参数
-- 以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.

@EmployeeNo NVARCHAR(50)='',             -- 人员工号
@LotSN VARCHAR(100)='',                  -- 批次条码
@InputScan VARCHAR(50)='',               -- 扫描输入
@Command VARCHAR(50)=''                  -- 当前指令
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10);
    DECLARE @RESULT INT=0;
    DECLARE @MOId IDType='';
    DECLARE @LotId IDType='';
    DECLARE @MOProductId IDType='';
    DECLARE @WorkcenterId IDType='';
    DECLARE @SpecificationId IDType='';
    DECLARE @WorkflowStepId IDType='';
    DECLARE @DataChainId IDType='';
    DECLARE @TxnCode VARCHAR(10)='MOVE';
    DECLARE @CurDate DATETIME=GETDATE();
    DECLARE @OpenRecordId IDType='';
    DECLARE @AffectedRows INT=0;

    -- 【初始化】统一清理输入参数空格，避免扫描枪回车导致的匹配失败
    SET @EmployeeNo = LTRIM(RTRIM(ISNULL(@EmployeeNo,'')));
    SET @LotSN = LTRIM(RTRIM(ISNULL(@LotSN,'')));
    SET @InputScan = LTRIM(RTRIM(ISNULL(@InputScan,'')));
    SET @Command = LTRIM(RTRIM(ISNULL(@Command,'')));
    SET @I_ReturnMessage = '';
    SET @I_ExceptionFieldName = '';

    IF @I_Sender='PageLoad'
    BEGIN
        SELECT '' AS InputScan,'' AS EmployeeNo,'' AS LotSN,'' AS Command,'请扫描[员工工号]!' AS Tips;
        RETURN 0;
    END

    -- 【扫码处理】仅在扫码失焦事件触发四步流程
    IF @I_Sender='InputScanDefocus'
    BEGIN
        -- 【空扫描处理】根据当前阶段返回下一步提示
        IF @InputScan=''
        BEGIN
            IF @EmployeeNo=''
            BEGIN
                SELECT '' AS InputScan,'' AS EmployeeNo,'' AS LotSN,'' AS Command,'请扫描[员工工号]!' AS Tips;
                RETURN 0;
            END;

            IF @LotSN=''
            BEGIN
                SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,'' AS LotSN,'' AS Command,'请扫描[批次条码]!' AS Tips;
                RETURN 0;
            END;

            SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,@LotSN AS LotSN,'' AS Command,'请扫描命令[CMDSTARTCB/CMDENDCB]!' AS Tips;
            RETURN 0;
        END;

        -- 【步骤1】扫描人员码
        IF @EmployeeNo=''
        BEGIN
            IF NOT EXISTS(SELECT 1 FROM SysUser WHERE EmployeeNo=@InputScan)
            BEGIN
                SET @I_ReturnMessage='ServerMessage:[员工工号]未维护，请重新扫描' + @Enter;
                SELECT '' AS InputScan,'' AS EmployeeNo,'' AS LotSN,'' AS Command,'请扫描[员工工号]!' AS Tips;
                RETURN -1;
            END;

            SET @EmployeeNo=@InputScan;
            SET @I_ReturnMessage='ServerMessage:[员工工号]已扫描' + @Enter;
            SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,'' AS LotSN,'' AS Command,'请扫描[批次条码]!' AS Tips;
            RETURN @RESULT;
        END;

        -- 【步骤2】扫描批次条码
        IF @LotSN=''
        BEGIN
            IF NOT EXISTS(SELECT 1 FROM MOItemLot WHERE LotSN=@InputScan)
            BEGIN
                SET @I_ReturnMessage='ServerMessage:[批次条码]['+@InputScan+']不正确，请重新扫描' + @Enter;
                SET @I_ExceptionFieldName='InputScan';
                SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,'' AS LotSN,'' AS Command,'请扫描[批次条码]!' AS Tips;
                RETURN -1;
            END;

            SELECT
                @LotId=LotId,
                @LotSN=LotSN,
                @MOId=MOId,
                @MOProductId=ProductId,
                @WorkcenterId=WorkcenterId,
                @SpecificationId=SpecificationId,
                @WorkflowStepId=WorkflowStepId
            FROM Lot
            WHERE LotSN=@InputScan;

            IF ISNULL(@LotId,'')='' 
            BEGIN
                SET @I_ReturnMessage='ServerMessage:[批次条码]['+@InputScan+']不存在，请重新扫描' + @Enter;
                SET @I_ExceptionFieldName='InputScan';
                SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,'' AS LotSN,'' AS Command,'请扫描[批次条码]!' AS Tips;
                RETURN -1;
            END;
            DECLARE @SpecificationName NVARCHAR(20)=''
            DECLARE @SpecificationCode NVARCHAR(20)=''
            SELECT @SpecificationName=SpecificationName,@SpecificationCode=SpecificationCode FROM Lot A
			INNER JOIN Specification B ON A.SpecificationId=B.SpecificationId
			INNER JOIN SpecificationRoot C ON B.SpecificationRootId=C.SpecificationRootId
			WHERE  A.LotId=@LotId
            IF ISNULL(@SpecificationCode,'') <>'UPACK'
            BEGIN
                SET @I_ReturnMessage='ServerMessage:工单批号['+@LotSN+']当前所在工序['+ISNULL(@SpecificationName,'')+']，不在当前工序节点!'+@Enter
                SET @I_ExceptionFieldName='InputScan';
                SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,'' AS LotSN,'' AS Command,'请扫描[批次条码]!' AS Tips;
                RETURN -1;
            END;
            

            SET @I_ReturnMessage='ServerMessage:[批次条码]已扫描' + @Enter;
            SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,@LotSN AS LotSN,'' AS Command,'请扫描开始命令[CMDSTARTCB]!' AS Tips;
            RETURN @RESULT;
        END;

        -- 【步骤3/4】扫描开始或结束命令
        SET @Command=@InputScan;

        -- 【命令校验】仅支持开始和结束命令
        IF @Command NOT IN ('CMDSTARTCB','CMDENDCB')
        BEGIN
            SET @I_ReturnMessage='ServerMessage:不可识别的操作指令，请扫描[CMDSTARTCB]或[CMDENDCB]' + @Enter;
            SET @I_ExceptionFieldName='InputScan';
            SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,@LotSN AS LotSN,'' AS Command,'请扫描命令[CMDSTARTCB/CMDENDCB]!' AS Tips;
            RETURN -1;
        END;

        -- 【基础校验】开始/结束前再次确认批号有效并刷新Lot信息
        SELECT
            @LotId=LotId,
            @MOId=MOId,
            @MOProductId=ProductId,
            @WorkcenterId=WorkcenterId,
            @SpecificationId=SpecificationId,
            @WorkflowStepId=WorkflowStepId
        FROM Lot
        WHERE LotSN=@LotSN;

        IF ISNULL(@LotId,'')=''
        BEGIN
            SET @I_ReturnMessage='ServerMessage:[批次条码]['+@InputScan+']不存在，请重新扫描' + @Enter;
            SET @I_ExceptionFieldName='InputScan';
            SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,'' AS LotSN,'' AS Command,'请扫描[批次条码]!' AS Tips;
            RETURN -1;
        END;

        -- 【开始记录】写入拆包装开始时间，禁止同人员同批号重复开始
        IF @Command='CMDSTARTCB'
        BEGIN
            IF EXISTS
            (
                SELECT 1
                FROM PUnpackRecord
                WHERE EmployeeNo=@EmployeeNo
                  AND LotSN=@LotSN
                  AND EndTime IS NULL
            )
            BEGIN
                SET @I_ReturnMessage='ServerMessage:该人员和批号已有未结束记录，请先扫描结束命令' + @Enter;
                SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,@LotSN AS LotSN,'' AS Command,'请扫描结束命令[CMDENDCB]!' AS Tips;
                RETURN -1;
            END;

            INSERT INTO PUnpackRecord
            (
                EmployeeNo,
                MOId,
                LotSN,
                StartTime,
                CreateUserId,
                ModifyDate
            )
            VALUES
            (
                @EmployeeNo,
                @MOId,
                @LotSN,
                GETDATE(),
                @I_OrBitUserId,
                GETDATE()
            );

            SET @I_ReturnMessage='ServerMessage:拆包装开始成功，请扫描结束命令[CMDENDCB]' + @Enter;
            SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,@LotSN AS LotSN,'' AS Command,'已开始拆包装，请扫描结束命令[CMDENDCB]!' AS Tips;
            RETURN @RESULT;
        END;

        -- 【结束记录】更新最近一条未结束记录并清空除人员外状态
        IF @Command='CMDENDCB'
        BEGIN
            -- 【结束校验】先定位最近一条未结束记录，不存在时禁止结束
            SELECT TOP 1 @OpenRecordId=UnpackRecordId
            FROM PUnpackRecord
            WHERE EmployeeNo=@EmployeeNo
              AND LotSN=@LotSN
              AND EndTime IS NULL
            ORDER BY StartTime DESC, CreateDate DESC;

            IF ISNULL(@OpenRecordId,'')=''
            BEGIN
                SET @I_ReturnMessage='ServerMessage:未找到可结束的开始记录，请先扫描开始命令' + @Enter;
                SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,@LotSN AS LotSN,'' AS Command,'请扫描开始命令[CMDSTARTCB]!' AS Tips;
                RETURN -1;
            END;

            -- 【事务处理】结束拆包装 + 插入数据链 + 传送LotSN到下一节点
            BEGIN TRANSACTION UNPACKEND;

            UPDATE PUnpackRecord
            SET EndTime=GETDATE(),
                ModifyDate=GETDATE()
            WHERE UnpackRecordId=@OpenRecordId
              AND EndTime IS NULL;

            SET @AffectedRows=@@ROWCOUNT;

            IF @AffectedRows=0
            BEGIN
                ROLLBACK TRANSACTION UNPACKEND;
                SET @I_ReturnMessage='ServerMessage:结束失败，开始记录状态已变化，请重试' + @Enter;
                RETURN -1;
            END;

            -- 【插入数据链】记录本次拆包装结束的主线数据链
            EXEC [dbo].[TxnBase_DataChainMainLine]
                   @DataChainId = @DataChainId OUTPUT,
                   @TxnCode =@TxnCode,
                   @I_PlugInCommand = @I_PlugInCommand,
                   @I_OrBitUserId = @I_OrBitUserId,
                   @I_ResourceId = @I_ResourceId,
                   @LotId = @LotId,
                   @MOId= @MOId,
                   @ProductId = @MOProductId,
                   @WorkcenterId = @WorkcenterId,
                   @SpecificationId = @SpecificationId,
                   @WorkflowStepId = @WorkflowStepId;

            -- 【流转批号】将LotSN传送到工作流下一节点
            EXEC @RESULT= [dbo].[TxnBase_LotMove]
            @I_ReturnMessage=@I_ReturnMessage OUTPUT,
            @I_OrBitUserId=@I_OrBitUserId,
            @I_ResourceId=@I_ResourceId,
            @LotSN=@LotSN,
            @LotInDate=@CurDate;

            IF @@ERROR<>0 OR @RESULT<>0
            BEGIN
                ROLLBACK TRANSACTION UNPACKEND;
                IF ISNULL(@I_ReturnMessage,'')=''
                    SET @I_ReturnMessage='ServerMessage:结束失败，批号流转异常，请联系管理员' + @Enter;
                SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,@LotSN AS LotSN,'' AS Command,'结束失败：批号未流转成功，请重试!' AS Tips;
                RETURN -1;
            END;

            COMMIT TRANSACTION UNPACKEND;

            SET @I_ReturnMessage='ServerMessage:拆包装结束成功，批号[' + @LotSN + ']已流转下一节点' + @Enter;
            SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,'' AS LotSN,'' AS Command,'拆包装结束成功，请扫描[批次条码]继续操作!' AS Tips;
            RETURN @RESULT;
        END;
    END;

    -- 【默认返回】非扫码事件时返回当前应操作提示
    IF @EmployeeNo=''
    BEGIN
        SELECT '' AS InputScan,'' AS EmployeeNo,'' AS LotSN,'' AS Command,'请扫描[员工工号]!' AS Tips;
        RETURN 0;
    END;

    IF @LotSN=''
    BEGIN
        SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,'' AS LotSN,'' AS Command,'请扫描[批次条码]!' AS Tips;
        RETURN 0;
    END;

    SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,@LotSN AS LotSN,'' AS Command,'请扫描命令[CMDSTARTCB/CMDENDCB]!' AS Tips;
    RETURN 0;
END
GO
