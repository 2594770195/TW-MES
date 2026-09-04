SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		<OrBit Team benson>
-- Create date: <2018.03.19>
-- Description:	调拨单明细-指定批次
-- =============================================
CREATE PROCEDURE  [dbo].[ProductAllotItemAssignProductLotNODoMethod]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT, --向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKid CHAR(12) ='',				--主键
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(100)='',		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@ProductLotNO  NVARCHAR(50)=''  

AS
BEGIN 

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

    DECLARE @ProductId NVARCHAR(20)=''
    DECLARE @InputLotCount INT = 0      -- 传入的批次数量
    DECLARE @ExistLotCount INT = 0      -- 库存中存在的批次数量

    -- 获取调拨明细对应的产品ID
    SELECT @ProductId = ProductId FROM ProductAllotItem WHERE ProductAllotItemId = @I_PKid

    -- ========== 新增：调用WMS接口验证每个批次是否存在 ==========
    -- 非空检查：ProductId为空时跳过WMS验证
    IF ISNULL(@ProductId, '') <> ''
    BEGIN
        DECLARE @BatchNo NVARCHAR(50) = ''
        DECLARE @RC_Api INT = 0
        DECLARE @AllBatchInWMS INT = 1  -- 标记：所有批次是否都在WMS中存在

        -- 临时表结构必须与APISyncD_WMSInventory中@InvItem的6列完全一致
        CREATE TABLE #WMSResult (
            RecQuantity   DECIMAL(18, 3),
            BatchNo       NVARCHAR(50),
            LicPlateNo    NVARCHAR(50),
            MaterialCode  NVARCHAR(50),
            warehouseName NVARCHAR(50),
            FactoryName   NVARCHAR(50)
        )

        -- 游标遍历每个批次号，逐个调用WMS接口
        DECLARE batch_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT LTRIM(RTRIM(col)) 
            FROM DB_Split(@ProductLotNO, ',') 
            WHERE LTRIM(RTRIM(col)) <> ''

        OPEN batch_cursor
        FETCH NEXT FROM batch_cursor INTO @BatchNo

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- 每次调用前清空临时表，确保结果干净
            DELETE FROM #WMSResult

            -- 调用WMS库存同步接口
            -- MaterialCode传入ProductId，BatchNo传入当前批次号
            INSERT INTO #WMSResult
            EXECUTE @RC_Api = [dbo].[APISyncD_WMSInventory] 
                @I_ReturnMessage = @I_ReturnMessage OUTPUT,
                @BatchNo = @BatchNo,
                @MaterialCode = @ProductId

            -- 判断接口是否返回了结果行
            -- 有结果行 = 该批次在WMS中存在，无结果行 = 不存在
            IF NOT EXISTS (SELECT 1 FROM #WMSResult)
            BEGIN
                SET @AllBatchInWMS = 0
                BREAK  -- 任一批次不存在，立即跳出循环
            END

            FETCH NEXT FROM batch_cursor INTO @BatchNo
        END

        CLOSE batch_cursor
        DEALLOCATE batch_cursor

        DROP TABLE #WMSResult

        -- 如果存在批次在WMS中未找到，直接返回失败
        IF @AllBatchInWMS = 0
        BEGIN
            SET @I_ReturnMessage = 'ServerMessage:指定的批次在WMS中不存在，请检查.'
            SET @I_ExceptionFieldName = 'ProductLotNO'
            RETURN -1
        END
    END
    -- ========== WMS验证结束 ==========

    -- 统计传入的批次数量（排除空字符串）
    SELECT @InputLotCount = COUNT(*) FROM DB_Split(@ProductLotNO, ',') WHERE LTRIM(RTRIM(col)) <> ''

    -- 统计库存中存在的批次数量
    SELECT @ExistLotCount = COUNT(DISTINCT ProductionLotNO) 
    FROM WW_RMInventory 
    WHERE ProductId = @ProductId 
      AND IsStorage = 1 
      AND ProductionLotNO IN (SELECT col FROM DB_Split(@ProductLotNO, ','))

    -- 判断所有批次是否都存在
    IF @InputLotCount = @ExistLotCount AND @InputLotCount > 0
    BEGIN
        SET @I_ReturnMessage = 'ServerMessage:修改成功.'
        RETURN 0
    END
    ELSE
    BEGIN
        SET @I_ReturnMessage = 'ServerMessage:指定的批次不存在或库存不足，请检查.'
        SET @I_ExceptionFieldName = 'ProductLotNO'
        RETURN -1
    END

END






GO
