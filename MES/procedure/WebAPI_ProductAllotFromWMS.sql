SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OrBit Team Administrato>
-- Create date: <2026/1/19 HO0565>
-- Description:	WebAPI 接口-ProductAllotWMS 调拨从WMS回传接口 
-- =============================================
CREATE PROCEDURE  [dbo].[WebAPI_ProductAllotFromWMS]
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
	
	-- Json 格式
	-- {"SQLDataSet":[{"UserName":"admin","PluginCommand":"AAAA"}]}



	DECLARE @JsonString NVARCHAR(MAX)=''
	DECLARE @JsonResult NVARCHAR(MAX); -- 存储JSON结果的变量
	DECLARE @I_ReturnMessage NVARCHAR(MAX)=''; -- 返回结果
		
	DECLARE @return_Value INT=-1
	DECLARE @returnResult INT=-1
	DECLARE @UserName NVARCHAR(50)=''
	DECLARE @PluginCommand VARCHAR(10)=''

	DECLARE @ProductAllotItemLotId CHAR(12)=''
    DECLARE @ProductAllotName NVARCHAR(20)=''
	DECLARE @UploadIngId CHAR(12)=''

    DECLARE @WWId CHAR(12);


	SET @JsonString = @Body

	EXEC SysGetObjectPKId '', 'UploadIngId', @UploadIngId OUTPUT;
	INSERT INTO zr_edlog_wms (Type, InputParams, OutputParams,UploadIngId)
        VALUES (
            'PRODUCTALLOTBACK',
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

		-- 调拨出库主表 - 表变量（新增ToWorkcenter字段）
	DECLARE @ProductAllot TABLE(
		DOC_CODE NVARCHAR(50),       -- 单据类型
		ProductAllotName NVARCHAR(50) -- 单据名称
	)

	-- 调拨出库明细表 - 表变量（移除ToWorkcenter字段）
	DECLARE @ProductAllotItem TABLE(
		ProductAllotName NVARCHAR(50), -- 单据名称
		ProductName NVARCHAR(50),     -- 物料编码
		LotSN NVARCHAR(50),           -- 批次条码
		BoxSN NVARCHAR(50),           -- 箱号条码
		Qty DECIMAL(18,4),            -- 数量（匹配decimal(18,4)类型）
		CellName NVARCHAR(50),         -- 原储位编码
		ToCellName NVARCHAR(50)       -- 目标储位编码
	)
	-- 步骤3：解析JSON数据到新表变量（适配字段调整）
	-- =============================================
	-- 解析主表数据（新增ToWorkcenter字段解析）
	INSERT INTO @ProductAllot (DOC_CODE, ProductAllotName)
	SELECT
		JSON_VALUE(@JsonString, '$.DOC_CODE') AS DOC_CODE,
		JSON_VALUE(@JsonString, '$.ProductAllotName') AS ProductAllotName


	-- 解析明细表数据（移除ToWorkcenter字段解析）
	INSERT INTO @ProductAllotItem (ProductAllotName,ProductName, LotSN,BoxSN, Qty, CellName,ToCellName)
	SELECT
		ProductAllotName,
		ProductName,
		LotSN,
		BoxSN,
		TRY_CAST(Qty AS DECIMAL(18,4)) AS Qty,  -- 强制转换为decimal类型，避免格式错误
		CellName,
		ToCellName
	FROM OPENJSON(@JsonString, '$.ProductAllotItem')  -- 指定JSON明细数组路径
	WITH (
		ProductAllotName NVARCHAR(50) '$.ProductAllotName',
		ProductName NVARCHAR(50) '$.ProductName',
		LotSN NVARCHAR(50) '$.LotSN',
		BoxSN NVARCHAR(50) '$.BoxSN',
		Qty NVARCHAR(20) '$.Qty',  -- 先以字符串接收，再转换为decimal
		CellName NVARCHAR(50) '$.CellName',  -- 明细表仅解析这4个字段
		ToCellName NVARCHAR(50) '$.ToCellName'  -- 明细表仅解析这4个字段
	)
    SET @ProductAllotName=(select top 1 ProductAllotName from  @ProductAllotItem)
	-- 校验主表数据是否正确
	IF NOT EXISTS(SELECT 1 FROM @ProductAllot WHERE DOC_CODE = 'PRODUCTALLOT')
	BEGIN
		SET @I_ReturnMessage = '校验失败：单据类型不是PRODUCTALLOT；';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END
	-- 直接判断：若记录数≠1则报错
	IF (SELECT COUNT(*) FROM @ProductAllot) <> 1
	BEGIN
		SET @I_ReturnMessage = '校验失败：调拨出库单据主表必须且仅能有1条数据！';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;

		RETURN -1
	END
    IF (SELECT COUNT(*) FROM @ProductAllotItem) =0
	BEGIN
		SET @I_ReturnMessage = '校验失败：调拨出库单据明细数据为空！';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;

		RETURN -1
	END

	-- 校验3：校验单据是否已发料（假设ProductAllotMain存储单据发料状态，关联字段ProductAllotName）
	IF EXISTS(
		SELECT 1 FROM @ProductAllot pl JOIN ProductAllot pm ON pl.ProductAllotName = pm.ProductAllotName WHERE pm.ProductAllotStates ='40'
	)
	BEGIN
		SET @I_ReturnMessage = '校验失败：该单据已回传成功，不可重复操作；';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END
	-- 单据不存在
	IF NOT EXISTS(
		SELECT 1 FROM @ProductAllot pl JOIN ProductAllot pm ON pl.ProductAllotName = pm.ProductAllotName
	)
	BEGIN
		SET @I_ReturnMessage = '校验失败：该单据在MES系统不存在，请检查！';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END
	-- 校验当前状态是否可以更新
	IF EXISTS(
		SELECT 1 FROM @ProductAllot pl JOIN ProductAllot pm ON pl.ProductAllotName = pm.ProductAllotName WHERE pm.ProductAllotStates NOT IN('50','20')
	)
	BEGIN
		SET @I_ReturnMessage = '校验失败：该单据在MES中不是【已审核】状态，不可操作；';
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END
    -- 校验SAP批次是否为空
	IF EXISTS(
		SELECT 1 FROM @ProductAllotItem  WHERE isnull(LotSN,'')=''
	)
	BEGIN
		SET @I_ReturnMessage = '校验失败：SAP批次不可为空';
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END
    --校验是否全部是单中的物料
    IF  EXISTS (
        SELECT 1 FROM @ProductAllotItem t WHERE NOT EXISTS (
            SELECT 1 FROM (
                SELECT c.TProductName 
                FROM ProductAllot a
                LEFT JOIN ProductAllotItem b ON a.ProductAllotId = b.ProductAllotId 
                LEFT JOIN product c ON c.ProductId = b.ProductId
                WHERE a.ProductAllotName = @ProductAllotName
            ) r
            WHERE r.TProductName = t.ProductName
        )
    )
    BEGIN
		SET @I_ReturnMessage = '校验失败：存在调拨单以外的物料';
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
    END
    --校验是否全部不为0
    IF EXISTS(select 1 from @ProductAllotItem where Qty<=0)
    BEGIN
        SET @I_ReturnMessage =  '发货单回调异常！'
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
        return -1
    END

	--TODO 校验储位库位，暂时不做校验
	---- 储位对比CellName -- 库位对比ToWorkcenter
	DECLARE @ErrorWarehouse NVARCHAR(200) = '';  -- 错误仓库编码
	--DECLARE @ErrorCell NVARCHAR(200) = '';       -- 错误储位（含仓库信息）
	-- 第一步：校验仓库是否存在
	-- --------------------------
-- 	SELECT @ErrorWarehouse = STUFF(
-- 		(
-- 			-- 筛选表变量中「不存在于仓库主表」的仓库编码
-- 			SELECT DISTINCT ',' + pl.ToWorkcenter
-- 			FROM @ProductAllotItem pl
-- 			WHERE pl.ToWorkcenter NOT IN (
-- 				SELECT WorkcenterName FROM dbo.Workcenter w
-- 			)
-- 			FOR XML PATH(''), TYPE
-- 		).value('.', 'NVARCHAR(200)'),
-- 		1, 1, ''  -- 去掉开头逗号
-- 	);

	---- --------------------------
	---- 第二步：校验储位是否存在（且属于该仓库）
	---- --------------------------
	--SELECT @ErrorCell = STUFF(
	--	(
	--		-- 筛选：储位不存在，或储位不属于填写的仓库
	--		SELECT DISTINCT ',' + pl.ToWorkcenter + '-' + pl.CellName
	--		FROM @ProductAllotItem pl
	--		-- 先过滤掉已确认错误的仓库（避免无效校验）
	--		WHERE pl.ToWorkcenter IN (SELECT WorkcenterName FROM dbo.Workcenter)
	--		  AND NOT EXISTS (
	--			  SELECT 1
	--			  FROM dbo.Cell c
	--			  INNER JOIN dbo.Workcenter w ON c.WorkcenterId = w.WorkcenterId
	--			  WHERE c.CellName = pl.CellName  -- 储位存在
	--				AND w.WorkcenterName = pl.ToWorkcenter  -- 储位属于该仓库
	--		  )
	--		FOR XML PATH(''), TYPE
	--	).value('.', 'NVARCHAR(200)'),
	--	1, 1, ''  -- 去掉开头逗号
	--);

	---- --------------------------
	---- 第三步：拼接错误信息+返回结果
	---- --------------------------
	---- 仓库错误提示
	--IF @ErrorWarehouse <> ''
	--BEGIN
	--	SET @I_ReturnMessage = '仓库编码不存在，错误仓库【' + @ErrorWarehouse + '】；';
	--END

	---- 储位错误提示（追加到仓库错误后）
	--IF @ErrorCell <> ''
	--BEGIN
	--	SET @I_ReturnMessage = ISNULL(@I_ReturnMessage,'') +'储位编码不存在/储位不属于该仓库，错误组合【' + @ErrorCell + '】；';
	--END

	--IF @ErrorWarehouse<>'' OR @ErrorCell<>''
	--BEGIN
	--	SET @I_ReturnMessage = '校验失败：库位编码或储位编码不正确，错误信息【'+ISNULL(@I_ReturnMessage,'')+'】；';
	--	--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
	--	SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
	--	SELECT @JsonResult AS JsonResult
	--	UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
	--	RETURN -1
	--END;

    --20260413,根据WMS实际操作的方式可能会存在分多次回调，不检验物料是否完整
	-- 获取的数据和ProductAllotItem表数据做对比
	-- DECLARE @ProductNameStr NVARCHAR(500)=''
	-- SELECT @ProductNameStr = STUFF(
	-- 	(
	-- 		-- 子查询：拼接所有缺失的物料名称，用逗号分隔
	-- 		SELECT ',' + ProductRoot.ProductName
	-- 		FROM ProductAllotItem  -- 物理明细表
	-- 		INNER JOIN dbo.Product ON Product.ProductId = ProductAllotItem.ProductId
	-- 		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
	-- 		INNER JOIN dbo.ProductAllot ON ProductAllot.ProductAllotId = ProductAllotItem.ProductAllotId
	-- 		INNER JOIN @ProductAllot pk ON pk.ProductAllotName = ProductAllot.ProductAllotName
	-- 		LEFT JOIN @ProductAllotItem pl
	-- 			ON pl.ProductAllotName = ProductAllot.ProductAllotName  -- 单据名称关联
	-- 			AND pl.ProductName = ProductRoot.ProductName        -- 物料名称关联
	-- 		WHERE pl.Qty IS NULL  -- 筛选：表变量中无此物料的记录
	-- 		FOR XML PATH(''), TYPE  -- 关键：将多行结果拼接成字符串
	-- 	).value('.', 'NVARCHAR(500)'),  -- 转换XML为字符串
	-- 	1, 1, ''  -- STUFF参数：从第1位开始，删除1个字符（去掉开头的逗号）
	-- );
	-- IF @ProductNameStr<>''
	-- BEGIN
	-- 	SET @I_ReturnMessage = '校验失败：回传物料不完整，缺失物料【'+@ProductNameStr+'】；';
	-- 			--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
	-- 	SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
	-- 	SELECT @JsonResult AS JsonResult
	-- 	UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
	-- 	RETURN -1
	-- END;

	-- 数量校验
	DECLARE @ErrorMsg NVARCHAR(MAX) = ''
	SELECT
		pl.ProductAllotName,
		p.TProductName ProductName,
		pli.AllotQty,
		pl_item.Qty,
		pli.AllotQty - pl_item.Qty AS DiffQty
	INTO #QtyDiff  -- 临时表存储差异明细
	FROM dbo.ProductAllot pl  -- 物理主表
	INNER JOIN dbo.ProductAllotItem pli ON pl.ProductAllotId = pli.ProductAllotId  -- 物理明细表（发料需求）
	INNER JOIN dbo.Product p ON pli.ProductId = p.ProductId
	INNER JOIN dbo.ProductRoot pr ON p.ProductRootId = pr.ProductRootId
	INNER JOIN (SELECT ProductAllotName,ProductName,ISNULL(SUM(qty),0)AS qty FROM @ProductAllotItem GROUP BY ProductAllotName,ProductName) pl_item  -- 回传数据
		ON pl.ProductAllotName = pl_item.ProductAllotName
		AND pr.ProductName = pl_item.ProductName
	WHERE pli.AllotQty - pl_item.qty > 0.0001;  -- 数量差异>0（兼容decimal精度）调拨数量不能少

	-- 第二步：拼接错误信息（用于接口返回）
	SELECT @ErrorMsg = STUFF(
		(
			SELECT ','+ '(料号：' + ProductName + ')：需求' + CAST(AllotQty AS NVARCHAR) + '，回传' + CAST(Qty AS NVARCHAR)
			FROM #QtyDiff
			FOR XML PATH(''), TYPE
		).value('.', 'NVARCHAR(MAX)'),
		1, 1, ''
	);

	-- 第三步：判断是否数量一致
	IF EXISTS(SELECT 1 FROM #QtyDiff)
	BEGIN
		SET @ErrorMsg = '调拨数量小于需求数量：' + @ErrorMsg;
        SET @I_ReturnMessage =  @ErrorMsg
		SELECT @JsonResult = (SELECT CAST(0 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
		SELECT @JsonResult AS JsonResult
		UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
		RETURN -1
	END

	-- 开始插入数据
		DECLARE
		-- 游标遍历变量（关联查询结果+批次数据）
		@ProductAllotItemId CHAR(12),  -- 物理明细表ID（从关联查询获取）
		@ProductId CHAR(12),          -- 物料ID（从关联查询获取）
		@LotSN NVARCHAR(50),          -- 批次条码
		@WWLOTSN NVARCHAR(50),          -- 批次条码
		@LotQty DECIMAL(18,8),           -- 批次数量
		@CellName NVARCHAR(50),       -- 库位ID
		@ToCellName NVARCHAR(50),       -- 库位ID
		@CellId CHAR(12),
		@ToCellId CHAR(12)=''

	-- =============================================
	-- 步骤1：定义游标（数据源为你指定的关联查询+批次表）
	-- 核心：关联ProductAllotItem/Product/ProductRoot/ProductAllot/@ProductAllotItem，获取插入所需的核心ID
	-- =============================================
	DECLARE PLILSOR CURSOR FOR
		SELECT
			pli.ProductAllotItemId,  -- 物理明细表ID（你的查询字段）
			pli.ProductId,          -- 物料ID（你的查询字段）
			pl_item.LotSN,           -- SAP批次条码
			pl_item.BoxSN AS WWLOTSN, -- 批次条码
			pl_item.Qty,             -- 批次数量
			pl_item.CellName,           -- 库位ID
			pl_item.ToCellName          -- 库位ID
		FROM dbo.ProductAllotItem pli  -- 物理明细表（你的查询主表）
		INNER JOIN dbo.Product p ON p.ProductId = pli.ProductId  -- 你的关联逻辑
		INNER JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId  -- 你的关联逻辑
		INNER JOIN dbo.ProductAllot pl ON pl.ProductAllotId = pli.ProductAllotId  -- 你的关联逻辑
		INNER JOIN @ProductAllotItem pl_item  -- 关联表变量（你的关联条件）
			ON pl_item.ProductAllotName = pl.ProductAllotName  -- 单据名称关联（你的规则）
			AND pl_item.ProductName = pr.ProductName        -- 物料名称关联（你的规则）
		WHERE pl_item.ProductAllotName IS NOT NULL;  -- 仅处理表变量中存在的单据+物料


	-- =============================================
	-- 步骤2：打开游标并循环插入ProductAllotItemLot
	-- =============================================
	OPEN PLILSOR;
	FETCH NEXT FROM PLILSOR INTO @ProductAllotItemId, @ProductId, @LotSN,@WWLOTSN, @LotQty, @CellName,@ToCellName

	WHILE @@FETCH_STATUS = 0  -- 游标遍历未结束
	BEGIN
		-- 1. 生成调拨明细批次表唯一主键（调用系统存储过程）
		SELECT @CellId=CellId FROM dbo.Cell WHERE CellName=@CellName
		SELECT @ToCellId=CellId FROM dbo.Cell WHERE CellName=@ToCellName

        DECLARE @FactoryId CHAR(12)
        DECLARE @ToFactoryId CHAR(12)
        DECLARE @workcenterId CHAR(12)
        DECLARE @ToworkcenterId CHAR(12)
        DECLARE @RCharStr NVARCHAR(10)='' --10位预留字符
insert into mwjtestlog(src,log1) VALUES('调拨',@WWLOTSN)
        Select @FactoryId=FactoryId,@ToFactoryId=ToFactoryId,@workcenterId=workcenterId,@ToworkcenterId=ToworkcenterId
        from ProductAllot a  join @ProductAllot b  on a.ProductAllotName=b.ProductAllotName

        --由WMS传存货组编号作为MES批号，WMS存货组编号为MES送货单明细批号中的批号或手动在WMS收货的存货组编号
        -- Select top 1 @WWLOTSN=lotsn from WW_RMInventory
        -- where ProductionLotNO=@LotSN AND IsStorage=1 and  ProductId=@ProductId AND Workcenterid=@workcenterId
        -- order by CreateDate desc
        -- --如果原仓库查到批号则用原仓库的批号，查不到则用目标仓库的批号
        -- IF ISNULL(@WWLOTSN,'')=''
        -- BEGIN
        --     Select top 1 @WWLOTSN=lotsn from WW_RMInventory
        --     where ProductionLotNO=@LotSN AND IsStorage=1 and  ProductId=@ProductId AND Workcenterid=@ToworkcenterId
        --     order by CreateDate desc
        -- END
        --WMS传回来的lotsn是SAP的批号，需要MES自己创建MES的批号
        IF ISNULL(@WWLOTSN,'')=''
        BEGIN
            SET @RCharStr=(SELECT TOP 1 ProductLineCode FROM Product_Factory WHERE ProductId=@ProductId)
            SET @RCharStr=LEFT(@RCharStr,2)
            --申请SN
            EXEC @return_value = dbo.StartRuleSNDoMethod
                @I_ReturnMessage = @I_ReturnMessage OUTPUT,
                @SNRuleId = 'SNRU000000T4',--SELECT SNRuleId FROM dbo.SNRule WHERE SNRuleName='TWLOTSN',同库存批号打印
                @JumpQty = 1,
                @RCharStr = @RCharStr,
                @NewSN = @WWLOTSN OUTPUT
            IF @return_value=-1
            BEGIN
                Set @WWLOTSN=@ProductId+@LotSN + '-001'
            END
        END

        EXEC SysGetObjectPKId '', 'ProductAllotItemLot', @ProductAllotItemLotId OUTPUT;
		-- 2. 插入调拨明细批次表（核心逻辑，参数均来自关联查询/批次表）
		INSERT INTO dbo.ProductAllotItemLot
		(
		    ProductAllotItemLotId,
		    ProductAllotItemId,
		    LotSN,
		    BoxSN,
		    Qty,
		    CellId,
		    ToCellId,
		    IsAEScan,
		    AllotType,
		    CreateUserId,
		    CreateDate,
		    IsAOScan
		)
		VALUES
		(   @ProductAllotItemLotId, -- ProductAllotItemLotId - char(12)
		    @ProductAllotItemId,    -- ProductAllotItemId - char(12)
		    @WWLOTSN,    -- LotSN - nvarchar(50)
		    '',    -- BoxSN - nvarchar(50)
		    @LotQty, -- Qty - decimal(18, 6)
		    @CellId,    -- CellId - char(12)
		    @ToCellId,    -- ToCellId - char(12)
		    1, -- IsAEScan - bit
		    'R',    -- AllotType - char(1)
		    NULL,    -- CreateUserId - char(12)
		    GETDATE(), -- CreateDate - datetime
		    1
		)


		UPDATE ProductAllotItem SET RealAllotQty+=@LotQty WHERE ProductAllotItemId=@ProductAllotItemId AND ProductId=@ProductId

        ------------------------------------------更新线边库存START------------------------------------------------------------------------------
        --更新库存表
        --调拨单原仓库不为空，且为线边仓，根据仓库和批号扣除库存
        --入库仓库为线边仓，增加仓库库存

        IF ISNULL(@workcenterId,'')<>'' AND 
         EXISTS(Select 1 from Workcenter a  
         left join ProductlineWH b  on a.WorkcenterId=b.warehouseid and b.WMSWarehouseCode='C101'--WMS线边仓
         where Workcenterid=@workcenterId ) 
        BEGIN
            --如果有多个批次，依次扣数
            -- DECLARE @tempqty decimal(18,4)=@LotQty
            -- DECLARE @CurrentQty DECIMAL(18,4);
            -- DECLARE @DeductQty DECIMAL(18,4);
            -- DECLARE cur CURSOR FOR
            --     SELECT WWId,qty
            --     FROM WW_RMInventory
            --     WHERE qty > 0  -- 只处理有库存的批次
            --     AND ProductionLotNO=@LotSN AND ProductId=@ProductId AND Workcenterid=@workcenterId
            --     ORDER BY CreateDate ASC;
                
            -- OPEN cur;
            -- FETCH NEXT FROM cur INTO @WWId ,@CurrentQty;

            -- WHILE @@FETCH_STATUS = 0 AND @tempqty > 0
            -- BEGIN
            --     IF @CurrentQty > 0
            --     BEGIN
            --         SET @DeductQty = CASE WHEN @tempqty >= @CurrentQty THEN @CurrentQty ELSE @tempqty END;
            --         UPDATE WW_RMInventory  SET QTY = QTY - @DeductQty WHERE WWId = @WWId
            --         SET @tempqty = @tempqty - @DeductQty;
            --         EXEC dbo.TxnBase_MLotTrack
            --         @I_OrBitUserId ='SUR1000004EQ', -- char(12)
            --         @I_PlugInCommand='',
            --         @I_ResourceId ='', -- char(12)
            --         @LotSN = @WWLOTSN, -- nvarchar(50) --物料批号
            --         @LotQty = @DeductQty, -- decimal(18, 6)--数量
            --         @TxnCode = 'M-WMS调拨扣数', -- nvarchar(50) --事务码
            --         @OrderName =@MOName , -- nvarchar(50) --单据号
            --         @Remark = '' -- nvarchar(200) --备注
            --     END
            --     FETCH NEXT FROM cur INTO @WWId ,@CurrentQty;
            -- END

            -- CLOSE cur;
            -- DEALLOCATE cur;
            SELECT  @WWId=wwid FROM WW_RMInventory 
            WHERE qty > 0    AND LotSN=@WWLOTSN AND ProductId=@ProductId AND Workcenterid=@workcenterId and IsStorage=1
               
            UPDATE WW_RMInventory  SET QTY = QTY - @LotQty WHERE WWId = @WWId
            EXEC dbo.TxnBase_MLotTrack
            @I_OrBitUserId ='SUR1000004EQ', -- char(12)
            @I_PlugInCommand='',
            @I_ResourceId ='', -- char(12)
            @LotSN = @WWLOTSN, -- nvarchar(50) --物料批号
            @LotQty = @LotQty, -- decimal(18, 6)--数量
            @TxnCode = 'M-WMS调拨扣数', -- nvarchar(50) --事务码
            @OrderName =@MOName , -- nvarchar(50) --单据号
            @Remark = '' -- nvarchar(200) --备注
        END
        --目标仓库是线边仓则加库存
        IF EXISTS(Select 1 from Workcenter a  
         join ProductlineWH b  on a.WorkcenterId=b.warehouseid and b.WMSWarehouseCode='C101'--WMS线边仓
         where Workcenterid=@ToworkcenterId ) 
        BEGIN
            -- IF EXISTS( Select 1 from WW_RMInventory where ProductionLotNO=@LotSN AND IsStorage=1 AND Workcenterid=@ToworkcenterId)
            -- BEGIN
            --     Select top 1 @WWId=wwid from WW_RMInventory where ProductionLotNO=@LotSN AND IsStorage=1 AND Workcenterid=@ToworkcenterId order by CreateDate desc
            --     Select top 1 @WWId=wwid from WW_RMInventory where lotsn=@WWLOTSN AND IsStorage=1 
            --     UPDATE WW_RMInventory Set Qty = Qty+@LotQty where wwid=@WWId
            --     EXEC dbo.TxnBase_MLotTrack
            --         @I_OrBitUserId ='SUR1000004EQ', -- char(12)
            --         @I_PlugInCommand='',
            --         @I_ResourceId ='', -- char(12)
            --         @LotSN = @WWLOTSN, -- nvarchar(50) --物料批号
            --         @LotQty = @LotQty, -- decimal(18, 6)--数量
            --         @TxnCode = 'M-WMS调拨增加库存', -- nvarchar(50) --事务码
            --         @OrderName =@MOName , -- nvarchar(50) --单据号
            --         @Remark = '' -- nvarchar(200) --备注
            -- END
            IF EXISTS( Select 1 from WW_RMInventory where lotsn=@WWLOTSN and IsStorage=1 AND WorkcenterId=@ToworkcenterId )
            BEGIN
                Select top 1 @WWId=wwid from WW_RMInventory where lotsn=@WWLOTSN and IsStorage=1 AND WorkcenterId=@ToworkcenterId
                UPDATE WW_RMInventory Set Qty = Qty+@LotQty where wwid=@WWId 
                EXEC dbo.TxnBase_MLotTrack
                    @I_OrBitUserId ='SUR1000004EQ', -- char(12)
                    @I_PlugInCommand='',
                    @I_ResourceId ='', -- char(12)
                    @LotSN = @WWLOTSN, -- nvarchar(50) --物料批号
                    @LotQty = @LotQty, -- decimal(18, 6)--数量
                    @TxnCode = 'M-WMS调拨增加库存', -- nvarchar(50) --事务码
                    @OrderName =@MOName , -- nvarchar(50) --单据号
                    @Remark = '' -- nvarchar(200) --备注
            END
            ELSE
            BEGIN
                DECLARE @SoName NVARCHAR(100)=''
                DECLARE @Moid   nvarchar(100)=''
                DECLARE @LotId   nvarchar(100)=''
                DECLARE @UOMId NVARCHAR(20)=''
                --半成品入库会有库存到大仓，调拨的时候会出现批次重复的情况，需要进行处理
                IF EXISTS(select 1 from WW_RMInventory where lotsn=@WWLOTSN)
                BEGIN
                    select top 1 @WWId=wwid from WW_RMInventory where lotsn=@WWLOTSN
                    update WW_RMInventory  set qty=@LotQty,WorkcenterId=@ToworkcenterId ,IsStorage=1 where wwid=@WWId
                END
                ELSE
                BEGIN
                    SELECT
                        @UOMId=UsageUOMId
                    FROM dbo.Product WITH(NOLOCK)
                    INNER JOIN dbo.ProductRoot WITH(NOLOCK) ON ProductRoot.ProductRootId = Product.ProductRootId
                    WHERE ProductId=@ProductId

                    EXEC dbo.SysGetObjectPKId '','WW_RMInventory',@WWId OUTPUT
                    INSERT INTO dbo.WW_RMInventory(
                        WWId,
                        LotSN,
                        LotStatus,
                        Qty,
                        OrgQty,
                        BoxSN,
                        ProductId,
                        POId,
                        VendorId,
                        UOMId,
                        ProductionDate,
                        ProductionLotNO,
                        ReceiveDate,
                        ValidityEndDate,
                        IsStorage,
                        FactoryId,
                        WorkcenterId,
                        CellId,
                        IsInternalLot,
                        LotSType,
                        sSOName,
                        moid,
                        LotId
                        )
                    VALUES(
                        @WWId,
                        @WWLOTSN,
                        '1',
                        @LotQty,
                        @LotQty,
                        '',
                        @ProductId,
                        '',
                        '',
                        @UOMId,
                        '',
                        @LotSN,
                        GETDATE(),
                        CAST('9999-12-31 23:59:59' AS DATETIME),
                        1,
                        @ToFactoryId,
                        @ToworkcenterId,
                        @CellId,
                        0,
                        '2',
                        @SoName,
                        @Moid,
                        @LotId
                        )
                        EXEC dbo.TxnBase_MLotTrack
                        @I_OrBitUserId ='SUR1000004EQ', -- char(12)
                        @I_PlugInCommand='',
                        @I_ResourceId ='', -- char(12)
                        @LotSN = @WWLOTSN, -- nvarchar(50) --物料批号
                        @LotQty = @LotQty, -- decimal(18, 6)--数量
                        @TxnCode = 'M-WMS调拨增加库存', -- nvarchar(50) --事务码
                        @OrderName =@MOName , -- nvarchar(50) --单据号
                        @Remark = '' -- nvarchar(200) --备注
                END
                
            END
        END
        ------------------------------------------更新线边库存END------------------------------------------------------------------------------



		-- 3. 读取游标下一条数据
		FETCH NEXT FROM PLILSOR INTO @ProductAllotItemId, @ProductId, @LotSN,@WWLOTSN, @LotQty, @CellName,@ToCellName
	END

	-- =============================================
	-- 步骤3：关闭并释放游标（必须执行，避免资源泄漏）
	-- =============================================
	CLOSE PLILSOR;
	DEALLOCATE PLILSOR;

	-- 更新主表数据
    --判断是否全部已完成
    IF EXISTS(select 1 from ProductAllot a 
            left join ProductAllotItem b on b.ProductAllotId=a.ProductAllotId 
            INNER JOIN @ProductAllot pl_var ON a.ProductAllotName = pl_var.ProductAllotName
            where b.RealAllotQty<b.AllotQty  )
    BEGIN
        UPDATE pl_phy 
        SET
            pl_phy.ProductAllotStates = '20'
        FROM dbo.ProductAllot pl_phy
        INNER JOIN @ProductAllot pl_var ON pl_phy.ProductAllotName = pl_var.ProductAllotName
    END
    ELSE
    BEGIN
        UPDATE pl_phy 
        SET
            pl_phy.ProductAllotStates = '50'
        FROM dbo.ProductAllot pl_phy
        INNER JOIN @ProductAllot pl_var ON pl_phy.ProductAllotName = pl_var.ProductAllotName
    END
	

	set @I_ReturnMessage='ServerMessage:调拨单回传成功!'
	set @returnResult=0

	-- 返回数据集
		--SELECT @returnResult as ReturnResult, @I_ReturnMessage AS ReturnMessage
	SELECT @JsonResult = (SELECT CAST(1 AS BIT) AS result,@I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
	SELECT @JsonResult AS JsonResult
	UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId;
	return 0
END
GO
