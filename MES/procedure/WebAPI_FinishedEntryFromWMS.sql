SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		<OrBit Team Administrato>
-- Create date: <2026/1/19 HO0565>
-- Description:	WebAPI 接口-FinishedEntryFromWMS 完工入库接口 TODO待修改
-- =============================================
CREATE PROCEDURE  [dbo].[WebAPI_FinishedEntryFromWMS]
@OrBitUserName NVARCHAR(100)='',		--调用WebAPI的用户名
@ResourceName NVARCHAR(100)='',			--调用WebAPI的远程电脑名
@UserParameter NVARCHAR(MAX)='',		--WebAPI接口定义的参数串
@UserData NVARCHAR(MAX)='',				--WebAPI接口定义的JSON/XML数据
@MOName NVARCHAR(50) = '',				--工单名称
@Qty INT  = 0,						    -- 数量
@Body NVARCHAR(MAX) = ''
AS
BEGIN
		
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	
	---处理逻辑
	--1.解析json，验证数据保存数据
	--2.更改单据状态；
	--3.返回结果

	DECLARE @JsonString NVARCHAR(MAX)=''
	DECLARE @JsonResult NVARCHAR(MAX); -- 存储JSON结果的变量
	DECLARE @I_ReturnMessage NVARCHAR(MAX)=''; -- 返回结果
		
	DECLARE @return_Value INT=-1
	DECLARE @returnResult INT=-1
	DECLARE @UserName NVARCHAR(50)=''
	DECLARE @PluginCommand VARCHAR(10)=''

	DECLARE @FinishingEntryItemLotId CHAR(12)=''
	DECLARE @UploadIngId CHAR(12)=''
    DECLARE @FactoryId CHAR(12)=''
    DECLARE @FinishingEntryName VARCHAR(20)=''
    DECLARE @FinishingEntryStates VARCHAR(20)=''

	SET @JsonString = @Body

	EXEC SysGetObjectPKId '', 'UploadIngId', @UploadIngId OUTPUT;
	INSERT INTO zr_edlog_wms (Type, InputParams, OutputParams,UploadIngId)
        VALUES (
            'FinishingEntry',
            @Body,
            @I_ReturnMessage,
			@UploadIngId
        );


	IF ISNULL(@JsonString,'') =''
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:[MES]:输入Json字符串不允许为空！'
		SET @returnResult = -1

		-- 返回数据集
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END

	-- 定义表变量，适配新字段（调整字段列表+合理数据类型）
	DECLARE @FinishingEntry TABLE(
		DOC_CODE NVARCHAR(50),           -- 单据类型
        FinishingEntryName  NVARCHAR(50),
		WhCategory NVARCHAR(50),         -- 仓库类别
		ToWorkcenter NVARCHAR(50),       -- 仓库编码（移至主表）
		CellName NVARCHAR(50),           -- 单元格/工位名称
		LotSN NVARCHAR(50),              -- 批次序列号
		EntryQty DECIMAL(18,4)           -- 录入数量（数值型更适配业务）
	)

	-- 步骤3：解析JSON数据到表变量（适配新字段）
	INSERT INTO @FinishingEntry (
		DOC_CODE, 
        FinishingEntryName,
		WhCategory, 
		ToWorkcenter, 
		CellName, 
		LotSN, 
		EntryQty
	)
	SELECT
		-- 解析JSON中FinishingEntry节点下的对应字段（需确保JSON路径与字段名一致）
		JSON_VALUE(@JsonString, '$.DOC_CODE') AS DOC_CODE,
        JSON_VALUE(@JsonString, '$.FinishingEntryName') AS FinishingEntryName,
		JSON_VALUE(@JsonString, '$.WhCategory') AS WhCategory,
		JSON_VALUE(@JsonString, '$.ToWorkcenter') AS ToWorkcenter,
		JSON_VALUE(@JsonString, '$.CellName') AS CellName,
		JSON_VALUE(@JsonString, '$.LotSN') AS LotSN,
		TRY_CAST(JSON_VALUE(@JsonString, '$.EntryQty') AS DECIMAL(18,4)) AS EntryQty
	
	-- 👇 新增：校验每个必需参数都不能为空
	DECLARE @MissingFields NVARCHAR(MAX) = '';

	IF NULLIF(RTRIM((SELECT DOC_CODE FROM @FinishingEntry)), '') IS NULL 
		SET @MissingFields = @MissingFields + 'DOC_CODE, ';
    IF NULLIF(RTRIM((SELECT FinishingEntryName FROM @FinishingEntry)), '') IS NULL 
		SET @MissingFields = @MissingFields + 'FinishingEntryName, ';
	IF NULLIF(RTRIM((SELECT WhCategory FROM @FinishingEntry)), '') IS NULL 
		SET @MissingFields = @MissingFields + 'WhCategory, ';
	IF NULLIF(RTRIM((SELECT ToWorkcenter FROM @FinishingEntry)), '') IS NULL 
		SET @MissingFields = @MissingFields + 'ToWorkcenter, ';
	--IF NULLIF(RTRIM((SELECT CellName FROM @FinishingEntry)), '') IS NULL 
	--	SET @MissingFields = @MissingFields + 'CellName, ';
	IF NULLIF(RTRIM((SELECT LotSN FROM @FinishingEntry)), '') IS NULL 
		SET @MissingFields = @MissingFields + 'LotSN, ';
	IF (SELECT EntryQty FROM @FinishingEntry) IS NULL -- EntryQty是数值，直接判断NULL
		SET @MissingFields = @MissingFields + 'EntryQty, ';

	-- 如果发现有缺失的字段，则拼接错误信息并返回
	IF LEN(@MissingFields) > 0
	BEGIN
		-- 去掉末尾多余的逗号和空格
		SET @MissingFields = LEFT(@MissingFields, LEN(@MissingFields) - 1);
		SET @I_ReturnMessage = '入库失败：以下必需参数不能为空：' + @MissingFields;
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult;
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1;
	END


	-- 校验主表数据是否正确
	IF NOT EXISTS(SELECT 1 FROM @FinishingEntry WHERE DOC_CODE = 'FinishedEntry')
	BEGIN
		SET @I_ReturnMessage = '入库失败：单据类型不是FinishedEntry；';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END
	--入库类型
	IF NOT EXISTS(SELECT 1 FROM @FinishingEntry WHERE WhCategory = '01' OR WhCategory='02')
	BEGIN
		SET @I_ReturnMessage = '入库失败：入库类型不是01（半成品入库）或02（成品入库）；';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END
    -- 校验当前状态是否可以更新
	IF EXISTS(
		SELECT 1 FROM @FinishingEntry pl JOIN FinishingEntry pm ON pl.FinishingEntryName = pm.FinishingEntryName WHERE pm.FinishingEntryName  in ('40','50') 
	)
	BEGIN
		SET @I_ReturnMessage = '校验失败：该单据在MES中已完成，不可操作；';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END

	-- 直接判断：若记录数≠1则报错
	IF (SELECT COUNT(*) FROM @FinishingEntry) <> 1
	BEGIN
		SET @I_ReturnMessage = '入库失败：完工入库单据主表必须且仅能有1条数据！';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;

		RETURN -1
	END
	DECLARE @WhCategoryCode NVARCHAR(50)='',@WhCategory CHAR(12)='',@WareHouseId CHAR(12)='',@WareHouseName NVARCHAR(50)='',@CellName NVARCHAR(50)='',@ScanSN NVARCHAR(50),@EntryQty DECIMAL(18,4)=0
	SELECT TOP 1 @WhCategoryCode = WhCategory,
	@WareHouseName = ToWorkcenter,@CellName = CellName,
    @ScanSN = LotSN,@EntryQty = EntryQty,@FinishingEntryName=FinishingEntryName FROM @FinishingEntry

    --判断入库单号和批号是否正确
    IF @ScanSN not in ( select SUBSTRING(LotSN,0,11) from FinishingEntry a 
            left join FinishingEntryItem b on a.FinishingEntryId=b.FinishingEntryId
            left join FinishingEntryItemlot c on c.FinishingEntryItemId=b.FinishingEntryItemId
            where a.FinishingEntryName=@FinishingEntryName )
    BEGIN
        SET @I_ReturnMessage = '入库失败：批号【'+@ScanSN+'】与入库单号信息不一致！';
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
    END
    Select @FactoryId= Case when FactoryId ='FAC1000000TC' --测试    --正式 FactoryId ='FAC1000000T9'
    THEN 'FAC1000000SW' ELSE FactoryId END,
    @FinishingEntryStates = FinishingEntryStates
    from FinishingEntry where FinishingEntryName=@FinishingEntryName

    IF ISNULL(@FinishingEntryStates,'')='60'
    BEGIN
        SET @I_ReturnMessage = '入库失败：当前入库单已废弃！';
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,'60' AS FinishingEntryStates,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
    END

    IF ISNULL(@FinishingEntryStates,'')='70'
    BEGIN
        SET @I_ReturnMessage = '入库成功：当前入库单已入库！';
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,'60' AS FinishingEntryStates,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN 0
    END

    --判断工单是否关闭
    IF NOT EXISTS(SELECT 1 FROM dbo.MO WHERE MOName=@ScanSN AND ISNULL(DeleteFlag,'')<>'X' AND MOStates='20')
    BEGIN
        SET @I_ReturnMessage = '入库失败：当前生产订单状态异常！';
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,'60' AS FinishingEntryStates,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
    END

	-- 赋值
	IF @WhCategoryCode='01' SET @WhCategory='半成品入库'
	IF @WhCategoryCode='02' SET @WhCategory='成品入库'
	-- 判断仓库和储位是否存在
	SELECT @WareHouseId=WorkcenterId FROM dbo.Workcenter WHERE WorkcenterName=@WareHouseName and FactoryId=@FactoryId
	IF @WareHouseId=''
	BEGIN
		SET @I_ReturnMessage = '入库失败：仓库编码【'+@WareHouseName+'】在MES系统中不存在！';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END;
	-- 暂时取消仓库校验
	--IF NOT EXISTS(SELECT 1 FROM dbo.Cell WHERE CellName=@CellName AND WorkcenterId IN(SELECT WorkcenterId FROM dbo.Workcenter WHERE WorkcenterName=@WareHouseName))
	--BEGIN
	--	SET @I_ReturnMessage = '入库失败：仓库编码【'+@WareHouseName+'】下不存在库位【'+@CellName+'】！';
	--	--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
	--	SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
	--	SELECT @JsonResult AS JsonResult
	--	UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
	--	RETURN -1
	--END;
	IF @EntryQty <=0
	BEGIN
		SET @I_ReturnMessage = '入库失败：入库数量不能小于0！';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END;
    DECLARE @LotSpecificationName NVARCHAR(50)=''
    DECLARE @SpecificationCode NVARCHAR(50)=''
    SELECT  @SpecificationCode=SpecificationRoot.SpecificationCode,
            @LotSpecificationName = SpecificationName
		FROM dbo.Lot 
        left join Specification on lot.SpecificationId=Specification.SpecificationId
        left join dbo.SpecificationRoot ON SpecificationRoot.SpecificationRootId = Specification.SpecificationRootId
		WHERE LotSN=@ScanSN+'001'
    --SPGW半制品入库，SFGW半成品入库，FSPD成品入库
	IF ISNULL(@SpecificationCode,'') NOT IN('SPGW','FSPD','SFGW','OQC','OTGW')
	BEGIN
		SET @I_ReturnMessage='ServerMessage:批号【'+@ScanSN+'】当前节点【'+@LotSpecificationName+'】非完工入库节点，请检查!'
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END

	-- TODO 调用校验存储过程，创建入库单据
	DECLARE @I_ExceptionFieldName NVARCHAR(100),@FinishingName NVARCHAR(50)=''
	EXEC @return_Value=dbo.PDA_FinishedEntryReceive_Scan @I_Sender = N'WMS回调',                                      -- nvarchar(200)
	                                @I_ReturnMessage = @I_ReturnMessage OUTPUT,           -- nvarchar(max)
	                                @I_ExceptionFieldName = @I_ExceptionFieldName OUTPUT, -- nvarchar(100)
	                                @I_LanguageId = '',                                   -- char(1)
	                                @I_PlugInCommand = '',                                -- varchar(5)
	                                @I_OrBitUserId = 'WMS',                                  -- char(12)
	                                @I_OrBitUserName = N'WMS',                               -- nvarchar(100)
	                                @I_ResourceId = '',                                   -- char(12)
	                                @I_ResourceName = N'',                                -- nvarchar(100)
	                                @I_PKid = '',                                         -- char(12)
	                                @I_ParentPKId = '',                                   -- char(12)
	                                @I_Parameter = N'',                                   -- nvarchar(max)
	                                @WareHouseId = @WareHouseId,                                    -- char(12)
	                                @WareHouseName = @WareHouseName,                                 -- nvarchar(50)
	                                --@CellName = @CellName,                                      -- nvarchar(50)
	                                @ScanSN = @ScanSN
	
	IF @return_Value<>0
	BEGIN
        set @I_ReturnMessage='入库失败，批次：'+@ScanSN+'!失败信息:【'+@I_ReturnMessage+'】'
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END

	-- 继续进行过账
	-- EXEC @return_Value=dbo.TxnBase_MBill_FinishingEntryConfirm @I_Sender = N'',                            -- nvarchar(200)
	--                                              @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
	--                                              @I_PlugInCommand = '',                      -- varchar(5)
	--                                              @I_OrBitUserId = 'WMS',                        -- char(12)
	--                                              @I_OrBitUserName = N'WMS',                     -- nvarchar(100)
	--                                              @I_ResourceId = '',                         -- char(12)
	--                                              @I_ResourceName = N'',                      -- nvarchar(100)
	--                                              @I_Parameter = N'',                         -- nvarchar(max)
	--                                              @I_PKid = '',                               -- char(12)
	--                                              @FinishingEntryName = @FinishingName                   -- nvarchar(50)

	-- IF @return_Value<>0
	-- BEGIN
	-- 	set @I_ReturnMessage='入库失败，批次：'+@ScanSN+'!失败信息:【'+@I_ReturnMessage+'】'
	-- 	SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
	-- 	SELECT @JsonResult AS JsonResult
	-- 	UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
	-- 	RETURN -1
	-- END


	-- 返回数据集
	set @I_ReturnMessage='入库成功，批次：'+@ScanSN+'!'
	--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
	SELECT @JsonResult = (SELECT CAST(1 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
	SELECT @JsonResult AS JsonResult
	UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
	return 0
END
GO
