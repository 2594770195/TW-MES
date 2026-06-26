-- =============================================
-- Author:        <OrBit Team>
-- Create date:   <2026/06/15>
-- Description:   <D点检验判定：对D点检验结果进行判定，更新子表数据和扩展信息>
-- Rev: 1.00
-- =============================================
CREATE PROCEDURE [dbo].[Txn_QC_DPointInspectionJudge]
    @I_Sender NVARCHAR(200) = '',              -- 客户端执行按钮
    @I_ReturnMessage NVARCHAR(MAX) = '' OUTPUT, -- 返回信息
    @I_ExceptionFieldName NVARCHAR(100) = '' OUTPUT, -- 冲突字段
    @I_LanguageId CHAR(1) = '1',               -- 语言ID
    @I_PlugInCommand VARCHAR(5) = '',          -- 插件命令
    @I_OrBitUserId CHAR(12) = '',              -- 用户ID
    @I_OrBitUserName NVARCHAR(100) = '',       -- 用户名
    @I_ResourceId CHAR(12) = '',               -- 资源ID
    @I_ResourceName NVARCHAR(100) = '',        -- 资源名
    @I_PKId CHAR(12) = '',                     -- 主键
    @I_SourcePKId CHAR(12) = '',               -- 源主键
    @I_ParentPKId CHAR(12) = '',               -- 父级主键
    @I_Parameter NVARCHAR(100) = '',           -- 插件参数
    
    @InsName NVARCHAR(50) = '',                -- 检验单名称
    @Operator NVARCHAR(50) = '',               -- 检验员工号
    @RealJudge CHAR(3) = '',                   -- 判定结果（OK/NG/LH）
    @XMLData NVARCHAR(MAX) = '',               -- 检验项明细数据（XML格式）
    @ProductTestTime NVARCHAR(MAX) = '',        -- D点时长（产品测试时间）
    @ErrorReasons NVARCHAR(MAX) = ''            -- 异常原因
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    -- =============================================
    -- 声明变量区
    -- =============================================
    DECLARE @FileName VARCHAR(30);
    DECLARE @xml XML;
    DECLARE @idoc INT;

    DECLARE @QC_ProcessInsId CHAR(12) = '';
    DECLARE @InsStates CHAR(3) = '';
    DECLARE @InsCategory CHAR(5) = '';

    DECLARE @QC_ProcessIns_ItemId CHAR(12) = '';
    DECLARE @ItemName NVARCHAR(50) = '';
    DECLARE @QCMode NVARCHAR(20) = '';
    DECLARE @ItemResult CHAR(3) = '';
    DECLARE @InspectionQty FLOAT = 0;

    DECLARE @QC_ProcessIns_ItemDetId CHAR(12) = '';
    DECLARE @DefectTotal INT = 0;

    DECLARE @RowId INT = 0;
    DECLARE @Rows INT = 0;

    DECLARE @SysJudgeRes CHAR(2) = '';
    DECLARE @MOId CHAR(12) = '';

    -- =============================================
    -- 定义临时表
    -- =============================================
    IF OBJECT_ID('tempdb..#XMLData') IS NOT NULL
        DROP TABLE #XMLData;

    CREATE TABLE #XMLData
    (
        ID INT IDENTITY(1,1),
        QC_ProcessIns_ItemId CHAR(12),
        ItemName NVARCHAR(50),
        QCMode NVARCHAR(20),
        ItemType NVARCHAR(50),
        ItemResult CHAR(3),
        InspectionQty FLOAT,
        ItemSTDValue FLOAT,
        ItemMaxValue FLOAT,
        ItemMinValue FLOAT
    );

    -- =============================================
    -- 输入校验区
    -- =============================================
    -- 检查检验单名称是否为空
    IF ISNULL(@InsName, '') = ''
    BEGIN
        SET @I_ReturnMessage = 'ServerMessage:未获取到检验单号，请先扫描批号获取!';
        SET @I_ExceptionFieldName = 'InsName';
        RETURN -1;
    END

    -- 检查检验员工号是否为空
    IF ISNULL(@Operator, '') = ''
    BEGIN
        SET @I_ReturnMessage = 'ServerMessage:请扫描工号!';
        SET @I_ExceptionFieldName = 'Operator';
        RETURN -1;
    END

    -- 检查判定结果是否选择
    IF ISNULL(@RealJudge, '') = ''
    BEGIN
        SET @I_ReturnMessage = 'ServerMessage:请选择判定结果!';
        RETURN -1;
    END

    -- 检查判定结果合法性（OK/NG/LH）
    IF @RealJudge NOT IN ('OK', 'NG', 'LH')
    BEGIN
        SET @I_ReturnMessage = 'ServerMessage:选择判定结果不合法!';
        RETURN -1;
    END

    -- 检查检验项网格是否有数据
    IF ISNULL(@XMLData, '') = ''
    BEGIN
        SET @I_ReturnMessage = 'ServerMessage:请先获取检验项数据!';
        RETURN -1;
    END

    -- =============================================
    -- 解析XML数据
    -- =============================================
    SET @FileName = '/ResultDataSet/ResultDataSet';
    SET @xml = @XMLData;
    SET @idoc = 0;

    -- 将XML转换成临时表
    EXEC sp_xml_preparedocument @idoc OUTPUT, @xml;

    INSERT INTO #XMLData
    (
        QC_ProcessIns_ItemId, ItemName, QCMode, ItemType, 
        ItemResult, InspectionQty, ItemSTDValue, ItemMaxValue, ItemMinValue
    )
    SELECT 
        QC_ProcessIns_ItemId, ItemName, QCMode, ItemType,
        ItemResult, InspectionQty, ItemSTDValue, ItemMaxValue, ItemMinValue
    FROM OPENXML(@idoc, @FileName, 2)
    WITH (
        QC_ProcessIns_ItemId CHAR(12),
        ItemName NVARCHAR(50),
        QCMode NVARCHAR(20),
        ItemType NVARCHAR(50),
        ItemResult CHAR(3),
        InspectionQty FLOAT,
        ItemSTDValue FLOAT,
        ItemMaxValue FLOAT,
        ItemMinValue FLOAT
    );

    EXEC sp_xml_removedocument @idoc;

    -- =============================================
    -- 获取检验单数据并校验状态
    -- =============================================
    SET @InsStates = '';
    SET @QC_ProcessInsId = '';
    SET @InsCategory = '';

    SELECT 
        @QC_ProcessInsId = QC_ProcessInsId,
        @InsStates = InsStates,
        @InsCategory = SubmissCategory,
        @MOId = MOId
    FROM QC_ProcessIns
    WHERE InsName = @InsName;

    -- 检查检验单是否存在
    IF ISNULL(@QC_ProcessInsId, '') = ''
    BEGIN
        SET @I_ReturnMessage = 'ServerMessage:检验单【' + @InsName + '】不存在!';
        RETURN -1;
    END

    -- 检查过程检验单号状态
    IF @InsStates <> '10'
    BEGIN
        SET @I_ReturnMessage = 'ServerMessage:过程检验单【' + @InsName + '】不是待检状态.';
        RETURN -1;
    END

    -- =============================================
    -- 核心业务逻辑区：处理检验项数据
    -- =============================================
    SET @Rows = 0;
    SELECT @Rows = COUNT(ID) FROM #XMLData;
    SET @RowId = 1;

    -- 遍历检验项数据
    WHILE @RowId <= @Rows
    BEGIN
        SET @QC_ProcessIns_ItemId = '';
        SET @ItemName = '';
        SET @QCMode = '';
        SET @ItemResult = '';
        SET @InspectionQty = 0;

        SELECT 
            @QC_ProcessIns_ItemId = QC_ProcessIns_ItemId,
            @ItemName = ItemName,
            @QCMode = QCMode,
            @ItemResult = ItemResult,
            @InspectionQty = ISNULL(InspectionQty, 0)
        FROM #XMLData
        WHERE ID = @RowId;

        -- 定性型检验项处理
        IF ISNULL(@QCMode, '') = '定性型'
        BEGIN
            -- 未判定结果自动PASS
            IF ISNULL(@ItemResult, '') = ''
            BEGIN
                -- 申请主键
                EXEC dbo.SysGetObjectPKId 
                    @ObjectId = '',
                    @ObjectName = N'QC_ProcessIns_ItemDet',
                    @PKID = @QC_ProcessIns_ItemDetId OUTPUT;

                -- 写入检验项明细表
                INSERT INTO dbo.QC_ProcessIns_ItemDet
                (
                    QC_ProcessIns_ItemDetId, QC_ProcessIns_ItemId,
                    DefectQty, DefectCodeName, DefectDescription,
                    ResourceId, CreateUser, CreateDate
                )
                VALUES
                (
                    @QC_ProcessIns_ItemDetId, @QC_ProcessIns_ItemId,
                    1, '0000', 'PASS',
                    @I_ResourceId, @Operator, GETDATE()
                );

                -- 更新检验项不良总数和结果
                UPDATE dbo.QC_ProcessIns_Item
                SET DefectTotal = 1,
                    ItemResult = 'OK',
                    InspectionQty = 1
                WHERE QC_ProcessIns_ItemId = @QC_ProcessIns_ItemId;
            END
        END

        SET @RowId = @RowId + 1;
    END

    -- =============================================
    -- 更新检验项结果
    -- =============================================
    UPDATE dbo.QC_ProcessIns_Item
    SET ItemResult = CASE 
        WHEN ISNULL(dbo.QC_ProcessIns_Item.ItemResult, '') = '' 
        THEN TA.ItemResult 
        ELSE dbo.QC_ProcessIns_Item.ItemResult 
    END
    FROM dbo.QC_ProcessIns_Item
    INNER JOIN #XMLData AS TA ON TA.QC_ProcessIns_ItemId = QC_ProcessIns_Item.QC_ProcessIns_ItemId
    WHERE QC_ProcessIns_Item.QC_ProcessInsId = @QC_ProcessInsId;

    -- =============================================
    -- 系统判定结果计算
    -- =============================================
    SET @SysJudgeRes = 'OK';

    -- 如果检验项中存在OK且没有NG的，则系统判定OK
    IF EXISTS(SELECT 1 FROM dbo.QC_ProcessIns_Item 
              WHERE QC_ProcessInsId = @QC_ProcessInsId AND ItemResult = 'OK')
       AND NOT EXISTS(SELECT 1 FROM dbo.QC_ProcessIns_Item 
                      WHERE QC_ProcessInsId = @QC_ProcessInsId AND ItemResult = 'NG')
    BEGIN
        SET @SysJudgeRes = 'OK';
    END

    -- 如果检验项中存在NG，则系统判定NG
    IF EXISTS(SELECT 1 FROM dbo.QC_ProcessIns_Item 
              WHERE QC_ProcessInsId = @QC_ProcessInsId AND ItemResult = 'NG')
    BEGIN
        SET @SysJudgeRes = 'NG';
    END

    -- =============================================
    -- 事务处理：更新主表和扩展表
    -- =============================================
    BEGIN TRANSACTION;
    BEGIN TRY
        -- 统计不良总数
        SET @DefectTotal = 0;
        SELECT @DefectTotal = ISNULL(SUM(DefectTotal), 0)
        FROM dbo.QC_ProcessIns_Item
        WHERE QC_ProcessInsId = @QC_ProcessInsId;

        -- 更新检验单主表
        UPDATE dbo.QC_ProcessIns
        SET 
            RealInQty = ISNULL(SubmissQty, 0) - ISNULL(@DefectTotal, 0),
            TotalDefectQty = @DefectTotal,
            InsResult = @SysJudgeRes,
            RealInsResult = @RealJudge,
            InsDate = GETDATE(),
            Inspector = @Operator,
            InsStates = '20'
        WHERE QC_ProcessInsId = @QC_ProcessInsId;

        -- 插入扩展表数据（异常原因和D点时长）
        IF ISNULL(@ErrorReasons, '') != '' OR ISNULL(@ProductTestTime, '') != ''
        BEGIN
            INSERT INTO dbo.ZR_QC_ProcessIns_Extend
            (QC_ProcessInsId, ErrorReasons, ProductTestTime, CreateUser, CreateDate)
            VALUES (@QC_ProcessInsId, @ErrorReasons, @ProductTestTime, @Operator, GETDATE());
        END

        COMMIT TRANSACTION;
        SET @I_ReturnMessage = 'ServerMessage:检验判定成功!';
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SET @I_ReturnMessage = 'ServerMessage:检验判定失败: ' + ERROR_MESSAGE();
        RETURN -1;
    END CATCH
END
GO