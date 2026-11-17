SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		
-- Create date: <2026-10-27>
-- Modify date: <2026-11-12>
-- Description:	<成品工单半成品批次批量分配（按 物料+工厂+仓库+生产批次 四维度分配版本）>
-- 批次预留批量修改：对账本次提交的选中批次 与 已存在的预分配记录
-- 约束：本次 XML 只能包含唯一一个 MOItemId(单物料行)，多个物料行直接判定异常
-- 处理方式（Rev 2.00：由"覆盖式全量取消后重插"改为 Upsert）：
--   1) 同维度(物料+工厂+仓库+SAP批次)已存在记录：更新数量，保留原确认状态（未确认/已理货）；
--   2) 本次新增维度：插入新记录；
--   3) 本次不再选中的有效占用记录：按状态取消
--      未确认(ConfirmStatus='0', IsOccupyAllocatedQty=1) → 0/0/1，释放占用；
--      已理货(ConfirmStatus='1', IsOccupyAllocatedQty=1) → 1/1/1，保留占用仅置删除标记；
--   4) 已扣数记录(ConfirmStatus='1', IsOccupyAllocatedQty=0)：不参与本次修改，原样保留。
-- 数量校验：事务前先做预检(净需求 vs 选中维度可分配总量)，不足则整体失败，
--           不开启事务、不改动任何现有分配记录；事务尾再做兜底校验
-- 工厂口径：选中维度的工厂必须等于工单允许分配的库存工厂
--           工单工厂 9502/9304 → 9502 库存；9302 → 9302 库存；其他工厂按同名
-- 参考实现：MOSemiFinishedLotAllocationBatchByProductionLotNoDoMethod 的 AutoAssign 与 DeleteLot
--
-- 与 LotSN 版本（MOLotSpecify_AssignReserveLot_DoMethod）的差异：
--   1) 分配粒度：由 MES 批次号 LotSN 改为 SAP/生产批次号 ProductionLotNO + 工厂 + 仓库
--   2) 入参 XML 必须传 ProductionLotNO + FactoryId + WorkcenterId；
--      缺任一维度直接报错，不做缺省反查（仅批次号可由 WWId 反查）
--   3) 库存口径：按 物料+工厂+仓库+生产批次 汇总有效 LotSN 行的库存数量
--   4) 已分配口径：按上述四维度汇总 MOSemiFinishedLotAllocation 中的占用数量
--      （未确认记录只占用当前工单清单库存，已确认记录无条件占用）
--   5) 指定数量(Qty)：按四维度汇总，作为该维度的人工指定分配数量
--   6) 分配记录：ProductionLotNO / FactoryId / WorkcenterId 必填；LotSN / WWId / CellId 写 NULL，
--      展示时由库存表按四维度反查（代表子批次、汇总库存数、位置、状态）
--   7) 下游若按 MOSemiFinishedLotAllocation.LotSN 关联库存/扫描校验，需同步改为四维度
-- Rev: 2.01
-- Rev 2.01（2026-11-16，SAP 同步标记）：
--   新增 MOSemiFinishedLotAllocation.SAPSyncFlag（0=未同步，1=已同步）：
--   1) 步骤③取消已确认记录 / 步骤④修改已确认记录数量时，同一句 UPDATE 同步置 SAPSyncFlag='0'（未同步）；
--      步骤⑤插入新记录显式写 '0'（ConfirmStatus='0' 不参与上报，确认后自然为待同步状态）
--   2) SAP 同步暂未实现，后续补充：操作完成后由统一同步逻辑
--      循环调用存在未同步记录(ConfirmStatus='1' AND SAPSyncFlag='0')的 MO 上报 SAP，
--      同步成功置 '1'，失败保持 '0' 等待下次循环补偿，不阻断业务操作
--      接口过程：dbo.APISyncU_SemiFinishedTallyToSAP
-- =============================================
CREATE PROCEDURE  [dbo].[MOLotSpecify_AssignReserveLotByProductionLotNo_DoMethod]
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
@I_Parameter NVARCHAR(MAX)='', 		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@MONames nvarchar(max) = ''
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	-- 【初始化】清空输出参数，避免复用调用上下文中的旧错误信息
	SET @I_ReturnMessage = ''
	SET @I_ExceptionFieldName = ''
    DECLARE @Enter CHAR(10) = CHAR(10)+CHAR(13)

	DECLARE @xml NVARCHAR(MAX)=@I_Parameter --xml文本
	DECLARE @idoc INT --xml句柄
	DECLARE @xmlFileName NVARCHAR(100)='/NewDataSet/SQLDataSet' --解析路径

    DECLARE @log NVARCHAR(max)='' --错误日志（记录工单号等上下文）

	-- 【校验】插件参数不能为空
	IF ISNULL(@xml, '') = ''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:没有选择生产批次！'
		RETURN -1
	END

	--本次要保存的明细（工厂/仓库必须传入；生产批次未传时可由 WWId 反查）
	DECLARE @Temp TABLE(
		IsRowSelect bit,
		MOItemId CHAR(12),
		WWId    CHAR(12),
		FactoryId CHAR(12),
		WorkcenterId CHAR(12),
        ProductionLotNO VARCHAR(50),
        Qty     float
	)

	BEGIN TRY
		--获取XML句柄
		EXEC sys.sp_xml_preparedocument @idoc OUTPUT, @xml

		--解析数据：openxml(idoc,rowpattern,flags)
		INSERT INTO @Temp
		(
			IsRowSelect,
		    MOItemId,
		    WWId,
			FactoryId,
			WorkcenterId,
	        ProductionLotNO,
            Qty
		)
		SELECT
			IsRowSelect,
			MOItemId,
			WWId,
			FactoryId,
			WorkcenterId,
			ProductionLotNO,
			Qty
		FROM  OPENXML(@idoc,@xmlFileName,2)
		--与XML的列名一致
		WITH (
			IsRowSelect bit,
		    MOItemId CHAR(12),
		    WWId    CHAR(12),
			FactoryId CHAR(12),
			WorkcenterId CHAR(12),
	        ProductionLotNO VARCHAR(50),
            Qty     float
		)

		--释放句柄	
		EXEC sys.sp_xml_removedocument @idoc
	END TRY
	BEGIN CATCH
		SET @I_ReturnMessage='ServerMessage:数据解析失败，请联系IT人员！'+ERROR_MESSAGE()
		RETURN -1
	END CATCH

	IF NOT EXISTS(SELECT 1 FROM @Temp WHERE IsRowSelect=1)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:没有选择生产批次！'
		RETURN -1
	END


	CREATE TABLE #MONameList (
		Seq int NOT NULL,				-- 输入顺序号
		MOName nvarchar(50) NOT NULL	-- 工单号
	)
    DECLARE @NameSeq int = 0

    IF @MONames IS NOT NULL AND @MONames <> ''
    BEGIN
        -- 去除所有空格、逗号、制表符、换行符、回车符
        SET @MONames = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@MONames, ' ', ''), ',', ''), CHAR(9), ''), CHAR(10), ''), CHAR(13), '');
        DECLARE @pos INT = 1, @len INT = LEN(@MONames), @segment NVARCHAR(50);
        WHILE @pos <= @len
            BEGIN
                SET @segment = SUBSTRING(@MONames, @pos, 10);
                -- 【校验】仅解析长度为 10 的工单号片段，避免尾部残段误入
                IF LEN(@segment) = 10
                BEGIN
                    SET @NameSeq = @NameSeq + 1
                    -- 【校验】同一工单号只保留首次出现的顺序，避免重复处理
                    IF NOT EXISTS (SELECT 1 FROM #MONameList WHERE MOName = @segment)
                        INSERT INTO #MONameList(Seq,MOName) VALUES (@NameSeq,@segment);
                END
                SET @pos = @pos + 10;
            END
    END
    -- 【准备】#MOList：把工单号解析为有效工单 ID 清单，供各分支按输入顺序引用
	SELECT
		l.Seq,
		l.MOName,
		MIN(mo.MOId) AS MOId
	INTO #MOList
	FROM #MONameList l
	INNER JOIN dbo.MO mo ON mo.MOName = l.MOName
		AND mo.MOName LIKE '2%'
	GROUP BY l.Seq, l.MOName

SET @log+=@MONames +@Enter
	-- =========================================================
	-- 批次预留批量修改(单物料行)：按四维度（物料+工厂+仓库+生产批次）Upsert：
	--   事务前预检验证数量足够(不足则整体失败、不改动数据)，
	--   事务内：取消不再选中的行 → 更新已存在维度 → 新增不存在维度
	-- =========================================================
	DECLARE @SelMOItemId CHAR(12)               -- 当前处理的选中物料行ID
	DECLARE @SelMOId CHAR(12)                   -- 当前物料行所属工单ID
	DECLARE @SelMOName NVARCHAR(50)             -- 当前工单号快照
	DECLARE @SelProductId CHAR(12)              -- 当前物料ID
	DECLARE @SelUOMId CHAR(12)                  -- 当前物料单位ID
	DECLARE @SelRequiredQty DECIMAL(18,8)       -- 当前物料净需求
	DECLARE @SelAllocatedQty DECIMAL(18,8)      -- 当前物料已分配(保留)数量
	DECLARE @SelRemainQty DECIMAL(18,8)         -- 当前物料剩余待分配需求
	DECLARE @SelAssignQty DECIMAL(18,8)         -- 单维度分配数量
	DECLARE @SelFactoryId CHAR(12)              -- 当前维度：工厂
	DECLARE @SelWorkcenterId CHAR(12)           -- 当前维度：仓库
	DECLARE @SelProductionLotNO VARCHAR(50)     -- 当前维度：SAP/生产批次
	DECLARE @SelAvailableQty DECIMAL(18,8)      -- 当前维度可用量
	DECLARE @SelNewId CHAR(12)                  -- 新增分配记录ID
	DECLARE @SelLotRowId INT                    -- 生产批次循环当前行号
	DECLARE @SelLotCount INT                    -- 生产批次循环行数
	DECLARE @SelSumQty DECIMAL(18,8)            -- 本次选中的人工指定数量合计
	DECLARE @TgtRowId INT                       -- 目标数量循环当前行号
	DECLARE @TgtCount INT                       -- 目标数量行数

	-- 【工厂口径】理货只能分配与工单工厂对应的库存工厂
	DECLARE @SelMOFactoryName NVARCHAR(50)      -- 工单工厂名称
	DECLARE @SelStockFactoryId CHAR(12)         -- 工单允许分配的库存工厂ID
	DECLARE @BadDimList NVARCHAR(MAX) = ''      -- 校验失败的生产批次清单

	-- 【准备】本次选中的明细（工厂/仓库直接取前端传值，生产批次可由 WWId 反查）
	CREATE TABLE #TempResolved (
		MOItemId CHAR(12),
		FactoryId CHAR(12),
		WorkcenterId CHAR(12),
		ProductionLotNO VARCHAR(50),
		Qty float,
		IsRowSelect bit
	)

	INSERT INTO #TempResolved (MOItemId, FactoryId, WorkcenterId, ProductionLotNO, Qty, IsRowSelect)
	SELECT
		t.MOItemId,
		-- 【准备】工厂/仓库必须由前端传入，不做缺省反查（对应列序第2、3位）
		LTRIM(RTRIM(ISNULL(t.FactoryId, ''))),
		LTRIM(RTRIM(ISNULL(t.WorkcenterId, ''))),
		-- 【准备】生产批次可由 WWId 反查（对应列序第4位）
		LTRIM(RTRIM(CASE WHEN ISNULL(t.ProductionLotNO, '') <> '' THEN t.ProductionLotNO
						ELSE ISNULL(inv.ProductionLotNO, '') END)),
		ISNULL(t.Qty, 0),
		ISNULL(t.IsRowSelect, 0)
	FROM @Temp t
	LEFT JOIN dbo.WW_RMInventory inv ON inv.WWId = t.WWId
	WHERE ISNULL(t.MOItemId, '') <> ''

	-- 【校验】无有效明细时直接失败
	IF NOT EXISTS (SELECT 1 FROM #TempResolved)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:选择的生产批次无效，请检查！'
		RETURN -1
	END

	-- 【校验】生产批次 / 工厂 / 仓库 任一为空即报错（不再兼容缺省维度）
	IF EXISTS (
		SELECT 1
		FROM #TempResolved
		WHERE ISNULL(ProductionLotNO, '') = ''
			OR ISNULL(FactoryId, '') = ''
			OR ISNULL(WorkcenterId, '') = ''
	)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:提交的生产批次缺少工厂或仓库信息，请重新打开对话框选择后再提交！'
		RETURN -1
	END

	-- 【准备】本次选中的期望维度集合：按四维度汇总（同一维度含多个 WWId 时只计一次）
	CREATE TABLE #TempSelected (
		FactoryId CHAR(12),
		WorkcenterId CHAR(12),
		ProductionLotNO VARCHAR(50),
        MOItemId CHAR(12),
        Qty     float
	)

	-- 【校验】人工指定数量优先；未指定时按勾选行取数
	IF (SELECT ISNULL(SUM(Qty), 0) FROM @Temp) > 0
    BEGIN
        INSERT INTO #TempSelected (FactoryId, WorkcenterId, ProductionLotNO, MOItemId, Qty)
        SELECT FactoryId, WorkcenterId, ProductionLotNO, MOItemId, SUM(Qty)
        FROM #TempResolved
        WHERE Qty > 0
        GROUP BY FactoryId, WorkcenterId, ProductionLotNO, MOItemId
    END
    ELSE
    BEGIN
        INSERT INTO #TempSelected (FactoryId, WorkcenterId, ProductionLotNO, MOItemId, Qty)
        SELECT FactoryId, WorkcenterId, ProductionLotNO, MOItemId, SUM(Qty)
        FROM #TempResolved
        WHERE IsRowSelect = 1
        GROUP BY FactoryId, WorkcenterId, ProductionLotNO, MOItemId
    END


	IF NOT EXISTS (SELECT 1 FROM #TempSelected)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:没有选择生产批次！'
		RETURN -1
	END

	-- 【校验】选中批次必须唯一归属一个物料行(仅允许单个物料行操作)
	IF (SELECT COUNT(DISTINCT MOItemId) FROM #TempSelected) <> 1
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:选择工单明细异常！'
		RETURN -1
	END

	-- 【取值】取唯一物料行主键与人工指定数量合计
	SELECT TOP 1 @SelMOItemId = MOItemId FROM #TempSelected
	SELECT @SelSumQty = CONVERT(decimal(18, 8), ISNULL(SUM(Qty), 0)) FROM #TempSelected

	-- 【取值+校验】取该物料行的工单/物料/净需求/工单工厂信息，并校验有效性
	SET @SelMOId = ''
	SELECT
		@SelMOId = mo.MOId,
		@SelMOName = mo.MOName,
		@SelProductId = mi.ProductId,
		@SelUOMId = mi.UOMId,
		@SelRequiredQty = CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) + ISNULL(mi.ItemQtyBack, 0)),
		@SelMOFactoryName = mf.FactoryName
	FROM dbo.MOItem mi
	INNER JOIN dbo.MO mo ON mo.MOId = mi.MOId
	INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
	LEFT JOIN dbo.Factory mf ON mf.FactoryId = mo.FactoryId
	WHERE mi.MOItemId = @SelMOItemId
		AND ISNULL(mi.DeleteFlag, '') = '0'
		AND mi.LineSequence <> '000'
		AND p.ProductClassify = '2'

	-- 【校验】物料行必须有效解析，否则直接失败
	IF ISNULL(@SelMOId, '') = ''
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:工单半成品物料行不存在或已失效，请检查！'
		RETURN -1
	END

	-- 【工厂口径】解析工单允许分配的库存工厂：
	--   工单工厂为 9502 / 9304 时，只能分配 9502 的库存；
	--   工单工厂为 9302 时，只能分配 9302 的库存；
	--   其他工厂按同名工厂分配
	SET @SelStockFactoryId = ''
	SELECT @SelStockFactoryId = sf.FactoryId
	FROM dbo.Factory sf
	WHERE sf.FactoryName = CASE
		WHEN @SelMOFactoryName IN (N'9502', N'9304') THEN N'9502'
		WHEN @SelMOFactoryName = N'9302' THEN N'9302'
		ELSE @SelMOFactoryName
	END

	-- 【校验】工单未维护工厂或对应库存工厂不存在时不允许分配
	IF ISNULL(@SelStockFactoryId, '') = ''
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:[工单][' + ISNULL(@SelMOName, '') + ']未维护工厂或对应库存工厂不存在，无法分配理货批次！'
		RETURN -1
	END

	-- 【校验】所选维度的工厂必须等于工单允许分配的库存工厂，避免绕过对话框写入跨厂理货
	IF EXISTS (
		SELECT 1
		FROM #TempSelected ts
		WHERE ISNULL(ts.FactoryId, '') <> @SelStockFactoryId
	)
	BEGIN
		SELECT @BadDimList = ISNULL(@BadDimList + ',', '') + ts.ProductionLotNO
		FROM #TempSelected ts
		WHERE ISNULL(ts.FactoryId, '') <> @SelStockFactoryId

		SET @I_ReturnMessage = 'ServerMessage:生产批次[' + ISNULL(@BadDimList, '') + ']的工厂不在工单允许的库存工厂范围内，无法分配！'
		RETURN -1
	END

	-- =========================================================
	-- 0️⃣ 数量预检（在事务前执行，不足则整体失败，不改动任何现有分配记录）
	--    可分配总量 = Σ 选中维度 [ 该维度汇总库存 - 该维度除本物料行外的有效占用 ]
	--    （本物料行的旧占用已含在可分配量内，等价于前端"本行已分配 + 可分配"）
	--    过滤口径与下方分配完全一致，确保预检结果与最终分配一致
	-- =========================================================
    --人工指定数量的不需要检验，允许部分指定
    IF ISNULL(@SelSumQty, 0) = 0 AND ISNULL((
		SELECT SUM(CASE WHEN PreQty > 0 THEN PreQty ELSE 0 END)
		FROM (
			SELECT
				CONVERT(decimal(18, 8), ISNULL(inv.StockQty, 0) - ISNULL(other.AllocOtherQty, 0)) AS PreQty
			FROM (
				-- 【准备】按 物料+工厂+仓库+生产批次 汇总库存数量
				SELECT
					wri.FactoryId,
					wri.WorkcenterId,
					wri.ProductionLotNO,
					SUM(ISNULL(wri.Qty, 0)) AS StockQty
				FROM dbo.WW_RMInventory wri
				WHERE wri.ProductId = @SelProductId
					AND wri.LotStatus = '1'
					AND wri.IsStorage = 1
					AND ISNULL(wri.Qty, 0) > 0
					AND ISNULL(wri.ProductionLotNO, '') <> ''
				GROUP BY wri.FactoryId, wri.WorkcenterId, wri.ProductionLotNO
			) inv
			INNER JOIN #TempSelected ts
				ON ts.FactoryId = inv.FactoryId
			   AND ts.WorkcenterId = inv.WorkcenterId
			   AND ts.ProductionLotNO = inv.ProductionLotNO
			CROSS APPLY (
				-- 该维度上除本物料行以外的有效占用数量
				SELECT SUM(ISNULL(a.Qty, 0)) AS AllocOtherQty
				FROM dbo.MOSemiFinishedLotAllocation a
				WHERE a.ProductId = @SelProductId
					AND a.FactoryId = inv.FactoryId
					AND a.WorkcenterId = inv.WorkcenterId
					AND a.ProductionLotNO = inv.ProductionLotNO
					AND a.DeleteFlag = '0'
					AND a.IsOccupyAllocatedQty = 1
                    AND (a.ConfirmStatus = '1' OR (a.ConfirmStatus = '0' AND a.MOId IN (SELECT MOId FROM #MOList)))
					AND a.MOItemId <> @SelMOItemId
			) other
		) t
	), 0) < @SelRequiredQty
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:预留批次数量不足，无法完成分配！'
		RETURN -1
	END

	-- 【事务】开启对账事务，保证取消/更新/新增整体原子性
	BEGIN TRANSACTION ResvLotReconcile

	-- =========================================================
	-- ① 选中维度的可分配量清单（按 生产日期 → 入库日期 → 维度 先进先出）
	--    可用量 = 该维度汇总库存 - 该维度其他物料行的有效占用
	--    （本物料行自身的旧占用不计入，本次会覆盖或取消）
	-- =========================================================
	CREATE TABLE #CurLots (
		RowId int NOT NULL,
		FactoryId char(12) NOT NULL,
		WorkcenterId char(12) NOT NULL,
		ProductionLotNO varchar(50) NOT NULL,
		AvailableQty decimal(18, 8) NOT NULL
	)

	INSERT INTO #CurLots (RowId, FactoryId, WorkcenterId, ProductionLotNO, AvailableQty)
	SELECT
		ROW_NUMBER() OVER (
			ORDER BY x.FirstProductionDate, x.FirstEntryDate, x.FactoryId, x.WorkcenterId, x.ProductionLotNO
		) AS RowId,
		x.FactoryId,
		x.WorkcenterId,
		x.ProductionLotNO,
		x.AvailableQty
	FROM (
		SELECT
			inv.FactoryId,
			inv.WorkcenterId,
			inv.ProductionLotNO,
			MIN(ISNULL(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(inv.ProductionDate)), '')), '99991231')) AS FirstProductionDate,
			MIN(inv.EntryDate) AS FirstEntryDate,
			CONVERT(decimal(18, 8), SUM(ISNULL(inv.Qty, 0)) - ISNULL(other.AllocatedQty, 0)) AS AvailableQty
		FROM dbo.WW_RMInventory inv
		INNER JOIN #TempSelected ts
			ON ts.FactoryId = inv.FactoryId
		   AND ts.WorkcenterId = inv.WorkcenterId
		   AND ts.ProductionLotNO = inv.ProductionLotNO
		LEFT JOIN (
			-- 该维度被其他工单物料占用的有效数量(本物料行不计入)
			SELECT
				a.FactoryId,
				a.WorkcenterId,
				a.ProductionLotNO,
				SUM(ISNULL(a.Qty, 0)) AS AllocatedQty
			FROM dbo.MOSemiFinishedLotAllocation a
			WHERE a.DeleteFlag = '0'
				AND a.IsOccupyAllocatedQty = 1
                AND (a.ConfirmStatus = '1' OR (a.ConfirmStatus = '0' AND a.MOId IN (SELECT MOId FROM #MOList)))
				AND ISNULL(a.ProductionLotNO, '') <> ''
				AND a.MOItemId <> @SelMOItemId
			GROUP BY a.FactoryId, a.WorkcenterId, a.ProductionLotNO
		) other
			ON other.FactoryId = inv.FactoryId
		   AND other.WorkcenterId = inv.WorkcenterId
		   AND other.ProductionLotNO = inv.ProductionLotNO
		WHERE inv.ProductId = @SelProductId
			-- 只取正常在库、数量>0、生产批次非空的库存
			AND inv.LotStatus = '1'
			AND inv.IsStorage = 1
			AND ISNULL(inv.Qty, 0) > 0
			AND ISNULL(inv.ProductionLotNO, '') <> ''
		GROUP BY inv.FactoryId, inv.WorkcenterId, inv.ProductionLotNO, other.AllocatedQty
	) x

	-- =========================================================
	-- ② 计算目标数量 #TargetLots：本次每个维度最终应保留的理货数量
	-- =========================================================
	CREATE TABLE #TargetLots (
		RowId int IDENTITY(1, 1) NOT NULL,
		FactoryId char(12) NOT NULL,
		WorkcenterId char(12) NOT NULL,
		ProductionLotNO varchar(50) NOT NULL,
		Qty decimal(18, 8) NOT NULL
	)

	IF ISNULL(@SelSumQty, 0) > 0
	BEGIN
		-- 【人工指定】指定数量即目标数量，允许部分指定
		INSERT INTO #TargetLots (FactoryId, WorkcenterId, ProductionLotNO, Qty)
		SELECT
			ts.FactoryId,
			ts.WorkcenterId,
			ts.ProductionLotNO,
			CONVERT(decimal(18, 8), SUM(ISNULL(ts.Qty, 0)))
		FROM #TempSelected ts
		WHERE ISNULL(ts.Qty, 0) > 0
		GROUP BY ts.FactoryId, ts.WorkcenterId, ts.ProductionLotNO

		-- 【校验】人工指定数量不能超过该维度可分配量（含维度在库存中不存在的情况）
		IF EXISTS (
			SELECT 1
			FROM #TargetLots t
			LEFT JOIN #CurLots c
				ON c.FactoryId = t.FactoryId
			   AND c.WorkcenterId = t.WorkcenterId
			   AND c.ProductionLotNO = t.ProductionLotNO
			WHERE c.ProductionLotNO IS NULL
				OR t.Qty > c.AvailableQty
		)
		BEGIN
			ROLLBACK TRANSACTION ResvLotReconcile
			SET @I_ReturnMessage = 'ServerMessage:指定数量大于可用数量，或所选批次已无可用库存，分配失败!'
			RETURN -1
		END
	END
	ELSE
	BEGIN
		-- 【自动分配】按生产日期先进先出逐维度分配，直到满足净需求
		SET @SelRemainQty = ISNULL(@SelRequiredQty, 0)
		SELECT @SelLotCount = COUNT(1) FROM #CurLots
		SET @SelLotRowId = 1

		WHILE @SelLotRowId <= @SelLotCount AND ISNULL(@SelRemainQty, 0) > 0
		BEGIN
			-- 【初始化】先清空当前维度变量，避免读取不到行时沿用上一轮值
			SET @SelFactoryId = ''
			SET @SelWorkcenterId = ''
			SET @SelProductionLotNO = ''
			SET @SelAvailableQty = 0
			SET @SelAssignQty = 0

			SELECT
				@SelFactoryId = FactoryId,
				@SelWorkcenterId = WorkcenterId,
				@SelProductionLotNO = ProductionLotNO,
				@SelAvailableQty = AvailableQty
			FROM #CurLots
			WHERE RowId = @SelLotRowId

			SET @SelLotRowId = @SelLotRowId + 1

			-- 【校验】批次号为空或可用量<=0 的维度不分配
			IF ISNULL(@SelProductionLotNO, '') = '' OR ISNULL(@SelAvailableQty, 0) <= 0
				CONTINUE

			SET @SelAssignQty = CASE
				WHEN @SelRemainQty < @SelAvailableQty THEN @SelRemainQty
				ELSE @SelAvailableQty
			END

			IF ISNULL(@SelAssignQty, 0) <= 0
				CONTINUE

			INSERT INTO #TargetLots (FactoryId, WorkcenterId, ProductionLotNO, Qty)
			VALUES (@SelFactoryId, @SelWorkcenterId, @SelProductionLotNO, @SelAssignQty)

			SET @SelRemainQty = @SelRemainQty - @SelAssignQty
		END
	END

	-- =========================================================
	-- ③ 取消本次不再选中的有效占用记录（三态判定，与主流程 DeleteLot 一致）
	--    未确认(0/1/0) → 0/0/1 释放占用
	--    已理货(1/1/0) → 1/1/1 保留占用，仅置删除标记
	--    已扣数(1/0/0) → IsOccupyAllocatedQty=0，不满足下方条件，原样保留
	-- =========================================================
	UPDATE a
	SET a.DeleteFlag = '1',
		-- 【状态】已确认(已理货)记录保留占用标记，未确认记录释放占用
		a.IsOccupyAllocatedQty = CASE WHEN a.ConfirmStatus = '1' THEN a.IsOccupyAllocatedQty ELSE 0 END,
		-- 【SAP 同步标记】已确认记录被取消属于需上报 SAP 的变更，同步置为未同步（未确认记录本就是'0'，统一置'0'无副作用）
		a.SAPSyncFlag = '0',
		a.ModifyDate = GETDATE()
	FROM dbo.MOSemiFinishedLotAllocation a
	WHERE a.MOItemId = @SelMOItemId
		AND a.DeleteFlag = '0'
		AND a.IsOccupyAllocatedQty = 1
		AND NOT EXISTS (
			SELECT 1
			FROM #TargetLots t
			WHERE t.FactoryId = a.FactoryId
				AND t.WorkcenterId = a.WorkcenterId
				AND t.ProductionLotNO = a.ProductionLotNO
		)

	-- 【SAP 同步 - 取消分配】暂未实现，后续补充；本过程仅将本操作涉及的已确认记录置 SAPSyncFlag='0'（未同步）；
	-- 实现方式：本操作完成后由统一同步逻辑循环调用存在未同步记录
	--          （ConfirmStatus='1' AND SAPSyncFlag='0'）的 MO，按记录状态推导动作上报 SAP；
	-- 接口过程：dbo.APISyncU_SemiFinishedTallyToSAP（已理货→创建/修改预留，取消→关闭预留）

	-- =========================================================
	-- ④ 更新同维度已存在记录：只改数量，保留原确认状态
	--    已扣数记录(IsOccupyAllocatedQty=0)不参与更新，原样保留
	--    【SAP 同步标记】数量变化属于需上报 SAP 的变更，同步置为未同步
	-- =========================================================
	UPDATE a
	SET a.Qty = t.Qty,
		a.SAPSyncFlag = '0',
		a.ModifyDate = GETDATE()
	FROM dbo.MOSemiFinishedLotAllocation a
	INNER JOIN #TargetLots t
		ON t.FactoryId = a.FactoryId
	   AND t.WorkcenterId = a.WorkcenterId
	   AND t.ProductionLotNO = a.ProductionLotNO
	WHERE a.MOItemId = @SelMOItemId
		AND a.DeleteFlag = '0'
		AND a.IsOccupyAllocatedQty = 1

	-- =========================================================
	-- ⑤ 插入新维度记录：本次选中但库内不存在的维度
	-- =========================================================
	SET @TgtRowId = 1
	SELECT @TgtCount = COUNT(1) FROM #TargetLots

	WHILE @TgtRowId <= @TgtCount
	BEGIN
		-- 【初始化】先清空当前维度变量，避免读取不到行时沿用上一轮值
		SET @SelFactoryId = ''
		SET @SelWorkcenterId = ''
		SET @SelProductionLotNO = ''
		SET @SelAssignQty = 0

		SELECT
			@SelFactoryId = FactoryId,
			@SelWorkcenterId = WorkcenterId,
			@SelProductionLotNO = ProductionLotNO,
			@SelAssignQty = Qty
		FROM #TargetLots
		WHERE RowId = @TgtRowId

		SET @TgtRowId = @TgtRowId + 1

		-- 【校验】该维度已存在"未扣数有效占用"记录(DeleteFlag='0' AND IsOccupyAllocatedQty=1)时不重复插入；
		--         已扣数(IsOccupyAllocatedQty=0)或已取消(DeleteFlag='1')的记录不命中，会作为新维度正常插入
		IF ISNULL(@SelProductionLotNO, '') = ''
			OR EXISTS (
				SELECT 1
				FROM dbo.MOSemiFinishedLotAllocation a
				WHERE a.MOItemId = @SelMOItemId
					AND a.DeleteFlag = '0'
					AND a.FactoryId = @SelFactoryId
					AND a.WorkcenterId = @SelWorkcenterId
					AND a.ProductionLotNO = @SelProductionLotNO
					AND a.IsOccupyAllocatedQty=1
			)
			CONTINUE

		SET @SelNewId = ''
		EXEC dbo.SysGetObjectPKId '', 'MOSemiFinishedLotAllocation', @SelNewId OUTPUT

		IF ISNULL(@SelNewId, '') = ''
		BEGIN
			ROLLBACK TRANSACTION ResvLotReconcile
			SET @I_ReturnMessage = 'ServerMessage:生成分配记录失败!'
			RETURN -1
		END

		-- 【写入】按四维度写一条记录；LotSN/WWId/CellId 留空，由库存表按四维度反查代表子批次
		INSERT INTO dbo.MOSemiFinishedLotAllocation (
			MOSemiFinishedLotAllocationId,
			MOId,
			MOName,
			MOItemId,
			ProductId,
			WWId,
			LotSN,
			ProductionLotNO,
			FactoryId,
			WorkcenterId,
			CellId,
			UOMId,
			Qty,
			IsOccupyAllocatedQty,
			ConfirmStatus,
			DeleteFlag,
			SAPSyncFlag,
			CreateUserId,
			CreateUserName,
			CreateDate,
			ModifyDate
		)
		VALUES (
			@SelNewId,
			@SelMOId,
			@SelMOName,
			@SelMOItemId,
			@SelProductId,
			NULL,
			NULL,
			@SelProductionLotNO,
			@SelFactoryId,
			@SelWorkcenterId,
			NULL,
			@SelUOMId,
			@SelAssignQty,
			1,
			'0',
			'0',
			'0',	-- SAPSyncFlag：新增未确认记录默认未同步（ConfirmStatus='0' 不参与SAP上报，确认后自然为待同步状态）
			@I_OrBitUserId,
			@I_OrBitUserName,
			GETDATE(),
			GETDATE()
		)

		IF @@ROWCOUNT = 0
		BEGIN
			ROLLBACK TRANSACTION ResvLotReconcile
			SET @I_ReturnMessage = 'ServerMessage:生成分配记录失败!'
			RETURN -1
		END
	END

	-- =========================================================
	-- 【兜底】分配后再次校验该物料最终分配总量是否足够净需求
	--    正常情况下事务前预检已保证数量充足；此兜底用于应对
	--    并发改动/口径差异等异常场景，避免提交不完整分配
	-- =========================================================
	SELECT @SelAllocatedQty = CONVERT(decimal(18, 8), ISNULL(SUM(ISNULL(Qty, 0)), 0))
	FROM dbo.MOSemiFinishedLotAllocation
	WHERE MOItemId = @SelMOItemId
		AND DeleteFlag = '0'
		AND IsOccupyAllocatedQty = 1
        AND (ConfirmStatus = '1' OR (ConfirmStatus = '0' AND MOId IN (SELECT MOId FROM #MOList)))

	IF ISNULL(@SelAllocatedQty, 0) < ISNULL(@SelRequiredQty, 0) AND ISNULL(@SelSumQty, 0) = 0
	BEGIN
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION ResvLotReconcile
		SET @I_ReturnMessage = 'ServerMessage:分配数量异常，无法完成分配！分配数量：'+@log
		RETURN -1
	END
    ELSE IF ISNULL(@SelAllocatedQty, 0) > ISNULL(@SelRequiredQty, 0)
    BEGIN
        IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION ResvLotReconcile
		SET @I_ReturnMessage = 'ServerMessage:分配数量超出需求数量，无法完成分配！'
		RETURN -1
    END

    IF OBJECT_ID('tempdb..#TargetLots') IS NOT NULL
		DROP TABLE #TargetLots
    IF OBJECT_ID('tempdb..#CurLots') IS NOT NULL
		DROP TABLE #CurLots
    IF OBJECT_ID('tempdb..#TempSelected') IS NOT NULL
		DROP TABLE #TempSelected
    IF OBJECT_ID('tempdb..#TempResolved') IS NOT NULL
		DROP TABLE #TempResolved

	-- 【提交】数量校验通过(预检+兜底)，取消/更新/新增整体生效
	COMMIT TRANSACTION ResvLotReconcile

	SET @I_ReturnMessage='ServerMessage:工单物料预留批次成功!'

	RETURN 0

END
GO
