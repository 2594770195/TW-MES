SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OrBit Team>
-- Create date: <2026-09-11>
-- Description:	成品工单半成品批次批量分配 DoMethod
-- Revision: 1.00
-- @MOName 支持多个工单号组合，用回车(CHAR(13)/CHAR(10))或逗号(英文, / 中文，)分隔
-- @I_Sender 分支说明：
--   GetMOProduct 批量查询工单半成品净需求(ItemQtyRequired-ItemQtyIssued)、已分配数量、未分配数量
--   AssignLot   输入 BoxOrLotSN，按 GetMOProduct 查询顺序把该批次可用库存依次分配给各工单半成品行，
--               直至各行需求分配完成或批次可用数量为 0(仅分配物料与批次一致的半成品行)
--   AutoAssign  按工单号输入顺序逐单循环自动分配：单内按行序取待分配行，批次按 EntryDate 先进先出
-- 错误返回：失败时设置 @I_ReturnMessage='ServerMessage:...' 并 RETURN -1
-- =============================================
ALTER PROCEDURE [dbo].[MOSemiFinishedLotAllocationBatchDoMethod]
@I_Sender nvarchar(200) = '',					-- 功能分支
@I_ReturnMessage nvarchar(max) = '' OUTPUT,		-- 返回的信息,支持多语言
@I_ExceptionFieldName nvarchar(100) = '' OUTPUT,-- 向客户端报告引起冲突的字段
@I_LanguageId char(1) = '1',					-- 客户端传入的语言ID
@I_PlugInCommand varchar(5) = '',				-- 插件命令
@I_OrBitUserId char(12) = '',					-- 用户ID
@I_OrBitUserName nvarchar(100) = '',			-- 用户名
@I_ResourceId char(12) = '',					-- 资源ID
@I_ResourceName nvarchar(100) = '',				-- 资源名
@I_PKId char(12) = '',							-- 主键
@I_ParentPKId char(12) = '',					-- 父级主键
@I_Parameter nvarchar(100) = '',				-- 插件参数
-- 以上变量为系统服务固定接口参数，必须在每一个 DoMethod 过程中实现.
@MONames nvarchar(max) = '',						-- 成品工单号，多个用回车或逗号分隔
@BoxOrLotSN nvarchar(100) = '',					-- MES批次号，AssignLot 使用
@Grid_MoItem char(12) = '',						-- 工单半成品物料行ID
@MOSemiFinishedLotAllocationId char(12) = ''	-- 半成品批次分配记录ID

AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- 【初始化】清空输出参数，避免复用调用上下文中的旧错误信息
	SET @I_ReturnMessage = ''
	SET @I_ExceptionFieldName = ''

	DECLARE @MONameNormalized nvarchar(max) = ''	-- 分隔符统一为英文逗号后的工单号串
	DECLARE @ParsePos int = 0						-- 当前分隔符位置
	DECLARE @OneMOName nvarchar(50) = ''			-- 当前解析出的单个工单号
	DECLARE @NameSeq int = 0						-- 工单号输入顺序号
	DECLARE @InvalidMOList nvarchar(max) = ''		-- 未解析到有效工单的工单号清单

	DECLARE @LotProductId char(12) = ''				-- 批次物料 ID
	DECLARE @AssignWWId char(12) = ''				-- 批次库存记录 ID
	DECLARE @AssignProductionLotNO varchar(50) = ''	-- 批次 SAP/生产批次
	DECLARE @AssignFactoryId char(12) = ''			-- 批次所在工厂 ID
	DECLARE @AssignWorkcenterId char(12) = ''		-- 批次所在仓库 ID
	DECLARE @AssignCellId char(12) = ''				-- 批次储位 ID
	DECLARE @StockQty decimal(18, 8) = 0			-- 批次库存数量
	DECLARE @LotAllocatedQty decimal(18, 8) = 0		-- 批次已被占用分配数量
	DECLARE @AvailableQty decimal(18, 8) = 0		-- 批次可用数量
	DECLARE @AssignQty decimal(18, 8) = 0			-- 单次分配数量
	DECLARE @RemainQty decimal(18, 8) = 0			-- 工单物料行剩余需求
	DECLARE @NewId char(12) = ''					-- 新分配记录 ID
	DECLARE @InventoryRowCount int = 0				-- 库存表 LotSN 行数校验
	DECLARE @RowId int = 0							-- 循环当前行号
	DECLARE @RowCount int = 0						-- 循环总行数
	DECLARE @ItemRowId int = 0						-- AutoAssign 当前物料行行号
	DECLARE @ItemCount int = 0						-- AutoAssign 当前工单待分配物料行数
	DECLARE @ItemLotCount int = 0					-- AutoAssign 当前物料行写入批次数
	DECLARE @ItemAssignQty decimal(18, 8) = 0		-- AutoAssign 当前物料行分配数量
	DECLARE @LotRowId int = 0						-- AutoAssign 当前批次行号
	DECLARE @LotCount int = 0						-- AutoAssign 当前物料可分配批次数
	DECLARE @AutoAssignLotSN nvarchar(100) = ''		-- AutoAssign 当前批次号
	DECLARE @AssignLotCount int = 0					-- 本次写入批次数
	DECLARE @AssignTotalQty decimal(18, 8) = 0		-- 本次分配总数量
	DECLARE @CurMOAssignQty decimal(18, 8) = 0		-- AutoAssign 当前工单本次分配数量
	DECLARE @GrandTotalQty decimal(18, 8) = 0		-- AutoAssign 全部工单累计分配数量
	DECLARE @MOSeq int = 0							-- AutoAssign 当前工单输入顺序号
	DECLARE @CurMOId char(12) = ''					-- 当前工单 ID
	DECLARE @CurMOName nvarchar(50) = ''			-- 当前工单号
	DECLARE @CurMOItemId char(12) = ''				-- 当前工单物料行 ID
	DECLARE @CurProductId char(12) = ''				-- 当前半成品物料 ID
	DECLARE @CurUOMId char(12) = ''					-- 当前物料单位 ID
	DECLARE @CurLineSequence varchar(20) = ''		-- 当前物料行行序
	DECLARE @CurProductName nvarchar(50) = ''		-- 当前物料名称

    DECLARE @ProductId NVARCHAR(20)='' --选中的moitem的物料

    insert into mwjtestlog(src,log1,log2) VALUES(@I_Sender,@Grid_MoItem,@BoxOrLotSN)


	-- 【校验】仅允许已定义的批量分支，其余统一返回未知操作
	IF @I_Sender NOT IN ('GetMOProduct', 'AssignLot', 'AutoAssign','GetInventory','GetAllocatedLots','DeleteLot')
	BEGIN
		SET @I_ReturnMessage = N'ServerMessage:未知操作!'
		RETURN -1
	END

	-- 【校验】工单号参数不能为空
	IF ISNULL(@MONames, '') = ''
	BEGIN
		SET @I_ReturnMessage = N'ServerMessage:请输入有效工单号!'
		RETURN -1
	END

	-- 【准备】#MONameList：把 @MOName 按回车/逗号等分隔符解析为按输入顺序排列的工单号清单
	-- 存放解析结果(去空格、去空段、去重)，供后续解析工单 ID 使用
	CREATE TABLE #MONameList (
		Seq int NOT NULL,				-- 输入顺序号
		MOName nvarchar(50) NOT NULL	-- 工单号
	)

	IF @MONames IS NOT NULL AND @MONames <> ''
    BEGIN
        -- 去除所有空格、逗号、制表符、换行符、回车符
        SET @MONames = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@MONames, ' ', ''), ',', ''), CHAR(9), ''), CHAR(10), ''), CHAR(13), '');
        DECLARE @pos INT = 1, @len INT = LEN(@MONames), @segment NVARCHAR(50);
        WHILE @pos <= @len
            BEGIN
                SET @segment = SUBSTRING(@MONames, @pos, 10);
                IF LEN(@segment) = 10
                    SET @NameSeq = @NameSeq + 1
                    INSERT INTO #MONameList(Seq,MOName) VALUES (@NameSeq,@segment);
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

	-- 【校验】任一工单号解析不到有效工单时整体失败，避免部分工单漏分配
	IF EXISTS (
		SELECT 1
		FROM #MONameList l
		WHERE NOT EXISTS (SELECT 1 FROM #MOList m WHERE m.MOName = l.MOName)
	)
	BEGIN
		SELECT @InvalidMOList = ISNULL(@InvalidMOList + ',', '') + l.MOName
		FROM #MONameList l
		WHERE NOT EXISTS (SELECT 1 FROM #MOList m WHERE m.MOName = l.MOName)
		SET @I_ReturnMessage = N'ServerMessage:[工单号][' + @InvalidMOList + ']不存在，请检查!'
		RETURN -1
	END

	-- 【查询】批量查询工单半成品需求，返回需求、已分配和未分配数量(口径与单工单版一致)
	IF @I_Sender = 'GetMOProduct'
	BEGIN
		SELECT
			mi.MOItemId,
            CASE WHEN CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) - ISNULL(alloc.AllocatedQty, 0))<=0 THEN '√'
				 ELSE '' END AS RowLogo,
			mo.MOId,
			mo.MOName,
			mi.LineSequence,
			mi.ProductId,
			pr.ProductName,
			p.ProductDescription,
			mi.UOMId,
			CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0)) AS ItemQtyRequired,
			CONVERT(decimal(18, 8), ISNULL(alloc.AllocatedQty, 0)) AS 已分配数量,
			CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) - ISNULL(alloc.AllocatedQty, 0)) AS 未分配数量
		FROM #MOList l
			INNER JOIN dbo.MOItem mi ON mi.MOId = l.MOId
			INNER JOIN dbo.MO mo ON mo.MOId = mi.MOId
			INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
			LEFT JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId
			LEFT JOIN (
				-- 【准备】按工单物料行汇总有效占用中的预分配数量
				SELECT
					MOItemId,
					SUM(ISNULL(Qty, 0)) AS AllocatedQty
				FROM dbo.MOSemiFinishedLotAllocation
				WHERE DeleteFlag = '0'
					AND IsOccupyAllocatedQty = 1
				GROUP BY MOItemId
			) alloc ON alloc.MOItemId = mi.MOItemId
		WHERE ISNULL(mi.DeleteFlag, '') = '0'
			AND mi.LineSequence <> '000'
			AND p.ProductClassify = '2'
		ORDER BY RowLogo
		RETURN 0
	END
    -- 【查询】按半成品 ProductId 查询可分配批次库存
	IF @I_Sender = 'GetInventory'
	BEGIN
		-- 【校验】物料 ID 不能为空
		IF ISNULL(@Grid_MoItem, '') = ''
		BEGIN
			return 0
		END
        select @ProductId=productid from MOItem where MOItemId=@Grid_MoItem

		-- 【查询】读取正常在库批次；LotSN 唯一性仅约束库存表，分配表按 LotSN 汇总占用数量
		SELECT
			wri.WWId,
			wri.ProductId,
            f.FactoryName,
			w.WorkcenterName,
			pr.ProductName,
			p.ProductDescription,
			wri.LotSN,
			wri.ProductionLotNO,
            CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0) - ISNULL(alloc.AllocatedQty, 0)) AS 可分配数量,
			CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0)) AS 批次数量,
			CONVERT(decimal(18, 8), ISNULL(alloc.AllocatedQty, 0)) AS 已分配数量,
            LotStatusTable.UserCodeDescription AS LotStatus,
            QCStatusTable.UserCodeDescription AS QCStatus,
			wri.ProductionDate,
            wri.EntryDate,
            wri.ValidityEndDate,
            wri.SAPRemark,pi.Note AS 'SAP备注',HoldResult as '锁定原因',
		    MO.NoteMessage AS '生产备注信息'
		FROM dbo.WW_RMInventory wri
		INNER JOIN dbo.Product p ON p.ProductId = wri.ProductId
		LEFT JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId
		LEFT JOIN dbo.Factory f ON f.FactoryId = wri.FactoryId
		LEFT JOIN dbo.Workcenter w ON w.WorkcenterId = wri.WorkcenterId
		LEFT JOIN dbo.Cell c ON c.CellId = wri.CellId
        LEFT JOIN UserCode_Table('URC100000AA9') LotStatusTable ON wri.LotStatus=LotStatusTable.UserCodeName
        LEFT JOIN UserCode_Table('URC100000AMP') QCStatusTable ON wri.QCStatus=QCStatusTable.UserCodeName
        LEFT JOIN ProductInventory pi ON pi.ProductId = wri.ProductId AND pi.LotSN=wri.ProductionLotNO AND
            pi.WorkcenterId=wri.WorkcenterId AND pi.DeleteFlag='0'
        LEFT JOIN dbo.MO ON MO.MOId = wri.MOId
		LEFT JOIN (
			-- 【准备】按 LotSN 汇总有效占用中的预分配数量，用于扣减可用库存
			SELECT
				a.LotSN,
				SUM(ISNULL(a.Qty, 0)) AS AllocatedQty
			FROM dbo.MOSemiFinishedLotAllocation a
			WHERE a.DeleteFlag = '0'
				AND a.IsOccupyAllocatedQty = 1
				AND ISNULL(a.LotSN, '') <> ''
			GROUP BY a.LotSN
		) alloc ON alloc.LotSN = wri.LotSN
		WHERE wri.ProductId = @ProductId
			-- 【过滤】只查询正常在库且数量大于 0 的批次
			AND wri.LotStatus = '1'
			AND wri.IsStorage = 1
			AND ISNULL(wri.Qty, 0) > 0
			AND ISNULL(wri.LotSN, '') <> ''
			-- 【过滤】库存表同一 LotSN 出现多行记录时视为异常，不参与查询
			AND (
				SELECT COUNT(1)
				FROM dbo.WW_RMInventory wriCnt
				WHERE wriCnt.LotSN = wri.LotSN
			) = 1
			-- 【过滤】只返回可用库存大于 0 的批次
			AND ISNULL(wri.Qty, 0) - ISNULL(alloc.AllocatedQty, 0) > 0
		-- 【排序】按生产日期升序（先进先出）；ProductionDate 为 varchar，支持 20260912/2026-09-12 等可识别格式，
		-- 无法转换为日期的记录置为 99991231 排在最后，同日期内再按入库日期、批次号保持稳定排序
		ORDER BY
			ISNULL(TRY_CONVERT(date, LTRIM(RTRIM(wri.ProductionDate))), '99991231'),
			wri.EntryDate,
			wri.LotSN

		RETURN 0
	END

    -- 【查询】查询当前工单已分配的有效批次记录
	IF @I_Sender = 'GetAllocatedLots'
	BEGIN
		IF ISNULL(@Grid_MoItem, '') = ''
		BEGIN
			RETURN 0
		END

		-- 【查询】返回当前工单有效分配记录及物料、库存位置信息
		SELECT
			a.MOSemiFinishedLotAllocationId,
			-- pr.ProductName,
			-- p.ProductDescription,
			f.FactoryName,
			w.WorkcenterName,
            a.LotSN,
			a.ProductionLotNO,
			-- c.CellName,
			u.UOMName,
			CONVERT(decimal(18, 8), ISNULL(a.Qty, 0)) AS '分配数量',
			a.CreateDate,
			CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0)) AS '库存数量',
			LotStatusTable.UserCodeDescription AS LotStatus,
            wri.ProductionDate,
			wri.ValidityEndDate,
			wri.EntryDate
		FROM dbo.MOSemiFinishedLotAllocation a
		INNER JOIN dbo.Product p ON p.ProductId = a.ProductId
		LEFT JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId
		LEFT JOIN dbo.Factory f ON f.FactoryId = a.FactoryId
		LEFT JOIN dbo.Workcenter w ON w.WorkcenterId = a.WorkcenterId
		LEFT JOIN dbo.Cell c ON c.CellId = a.CellId
		LEFT JOIN dbo.UOM u ON u.UOMId = a.UOMId
		LEFT JOIN dbo.WW_RMInventory wri ON wri.WWId = a.WWId
        LEFT JOIN UserCode_Table('URC100000AA9') LotStatusTable ON wri.LotStatus=LotStatusTable.UserCodeName
		WHERE a.MOitemId = @Grid_MoItem
			-- 【过滤】只返回有效分配记录
			AND a.DeleteFlag = '0' and a.IsOccupyAllocatedQty=1
		ORDER BY a.CreateDate DESC, a.LotSN

		RETURN 0
	END

	-- 【写入】输入单个 LotSN，按 GetMOProduct 顺序把批次可用库存依次分配给各工单半成品行
	-- 仅分配物料与批次一致的半成品行；循环直至批次可用量为 0 或各行需求满足
	IF @I_Sender = 'AssignLot'
	BEGIN
		-- 【校验】批次号不能为空
		IF ISNULL(@BoxOrLotSN, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:批次不存在或不可分配!'
			RETURN -1
		END

		-- 【校验】库存表 LotSN 必须唯一
		SELECT @InventoryRowCount = COUNT(1)
		FROM dbo.WW_RMInventory
		WHERE LotSN = @BoxOrLotSN

		IF @InventoryRowCount <> 1
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:[批次条码][' + @BoxOrLotSN + ']不存在或不可分配!'
			RETURN -1
		END

		-- 【校验】批次需正常在库且数量大于 0
		SELECT
			@AssignWWId = wri.WWId,
			@LotProductId = wri.ProductId,
			@StockQty = CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0)),
			@AssignProductionLotNO = wri.ProductionLotNO,
			@AssignFactoryId = wri.FactoryId,
			@AssignWorkcenterId = wri.WorkcenterId,
			@AssignCellId = wri.CellId
		FROM dbo.WW_RMInventory wri
		WHERE wri.LotSN = @BoxOrLotSN
			AND wri.LotStatus = '1'
			AND wri.IsStorage = 1
			AND ISNULL(wri.Qty, 0) > 0

		IF ISNULL(@AssignWWId, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:[批次条码][' + @BoxOrLotSN + ']不存在或不可分配!'
			RETURN -1
		END

		-- 【事务】开启批量分配事务，避免并发重复分配
		BEGIN TRANSACTION AssignLotBatch

		-- 【计算】事务内计算批次可用数量 = 库存数量 - 全部工单已占用分配数量
		SELECT @LotAllocatedQty = CONVERT(decimal(18, 8), ISNULL(SUM(ISNULL(Qty, 0)), 0))
		FROM dbo.MOSemiFinishedLotAllocation
		WHERE LotSN = @BoxOrLotSN
			AND DeleteFlag = '0'
			AND IsOccupyAllocatedQty = 1

		SET @AvailableQty = @StockQty - ISNULL(@LotAllocatedQty, 0)

		IF ISNULL(@AvailableQty, 0) <= 0
		BEGIN
			ROLLBACK TRANSACTION AssignLotBatch
			SET @I_ReturnMessage = N'ServerMessage:[批次条码][' + @BoxOrLotSN + ']已无可用库存!'
			RETURN -1
		END

		-- 【准备】#AssignItems：所选工单中物料与批次一致且未分配数量 > 0 的半成品行
		-- 按工单输入顺序 + 行序 + 物料名排列，供循环依次分配
		SELECT
			ROW_NUMBER() OVER (ORDER BY l.Seq, mi.LineSequence, pr.ProductName) AS RowId,
			mi.MOId,
			mo.MOName,
			mi.MOItemId,
			mi.UOMId,
			CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) - ISNULL(alloc.AllocatedQty, 0)) AS RemainQty
		INTO #AssignItems
		FROM #MOList l
			INNER JOIN dbo.MOItem mi ON mi.MOId = l.MOId
			INNER JOIN dbo.MO mo ON mo.MOId = mi.MOId
			INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
			LEFT JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId
			LEFT JOIN (
				SELECT
					MOItemId,
					SUM(ISNULL(Qty, 0)) AS AllocatedQty
				FROM dbo.MOSemiFinishedLotAllocation
				WHERE DeleteFlag = '0'
					AND IsOccupyAllocatedQty = 1
				GROUP BY MOItemId
			) alloc ON alloc.MOItemId = mi.MOItemId
		WHERE ISNULL(mi.DeleteFlag, '') = '0'
			AND mi.LineSequence <> '000'
			AND p.ProductClassify = '2'
			AND mi.ProductId = @LotProductId
			AND ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) - ISNULL(alloc.AllocatedQty, 0) > 0

		SELECT @RowCount = COUNT(1) FROM #AssignItems

		-- 【校验】批次物料在所选工单中无待分配需求时失败
		IF ISNULL(@RowCount, 0) <= 0
		BEGIN
			ROLLBACK TRANSACTION AssignLotBatch
			IF OBJECT_ID('tempdb..#AssignItems') IS NOT NULL
				DROP TABLE #AssignItems
			SET @I_ReturnMessage = N'ServerMessage:[批次条码][' + @BoxOrLotSN + ']物料与所选工单半成品不一致或已无剩余需求!'
			RETURN -1
		END

		-- 【循环】按顺序逐行分配，每次取剩余需求与批次可用量的较小值，直至批次可用量为 0 或行用尽
		SET @RowId = 1
		SET @AssignLotCount = 0
		SET @AssignTotalQty = 0

		WHILE @RowId <= @RowCount AND ISNULL(@AvailableQty, 0) > 0
		BEGIN
			SELECT
				@CurMOId = MOId,
				@CurMOName = MOName,
				@CurMOItemId = MOItemId,
				@CurUOMId = UOMId,
				@RemainQty = RemainQty
			FROM #AssignItems
			WHERE RowId = @RowId

			SET @RowId = @RowId + 1

			IF ISNULL(@RemainQty, 0) <= 0
				CONTINUE

			SET @AssignQty = CASE
				WHEN @RemainQty < @AvailableQty THEN @RemainQty
				ELSE @AvailableQty
			END

			IF ISNULL(@AssignQty, 0) <= 0
				CONTINUE

			-- 【写入】生成主键并插入预分配记录
			EXEC dbo.SysGetObjectPKId '', 'MOSemiFinishedLotAllocation', @NewId OUTPUT

			IF ISNULL(@NewId, '') = ''
			BEGIN
				ROLLBACK TRANSACTION AssignLotBatch
				IF OBJECT_ID('tempdb..#AssignItems') IS NOT NULL
					DROP TABLE #AssignItems
				SET @I_ReturnMessage = N'ServerMessage:生成分配记录失败!'
				RETURN -1
			END

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
				DeleteFlag,
				CreateUserId,
				CreateUserName,
				CreateDate,
				ModifyDate
			)
			VALUES (
				@NewId,
				@CurMOId,
				@CurMOName,
				@CurMOItemId,
				@LotProductId,
				@AssignWWId,
				@BoxOrLotSN,
				@AssignProductionLotNO,
				@AssignFactoryId,
				@AssignWorkcenterId,
				@AssignCellId,
				@CurUOMId,
				@AssignQty,
				1,
				'0',
				@I_OrBitUserId,
				@I_OrBitUserName,
				GETDATE(),
				GETDATE()
			)

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION AssignLotBatch
				IF OBJECT_ID('tempdb..#AssignItems') IS NOT NULL
					DROP TABLE #AssignItems
				SET @I_ReturnMessage = N'ServerMessage:生成分配记录失败!'
				RETURN -1
			END

			SET @AvailableQty = @AvailableQty - @AssignQty
			SET @AssignTotalQty = @AssignTotalQty + @AssignQty
			SET @AssignLotCount = @AssignLotCount + 1
		END

		-- 【校验】未产生任何分配记录时整体回滚
		IF ISNULL(@AssignLotCount, 0) <= 0 OR ISNULL(@AssignTotalQty, 0) <= 0
		BEGIN
			ROLLBACK TRANSACTION AssignLotBatch
			IF OBJECT_ID('tempdb..#AssignItems') IS NOT NULL
				DROP TABLE #AssignItems
			SET @I_ReturnMessage = N'ServerMessage:[批次条码][' + @BoxOrLotSN + ']已无可用库存!'
			RETURN -1
		END

		-- 【提交】批量分配写入成功；批次不足时按可用量部分分配
		COMMIT TRANSACTION AssignLotBatch

		IF OBJECT_ID('tempdb..#AssignItems') IS NOT NULL
			DROP TABLE #AssignItems

		-- 【返回】本次批量分配汇总，便于前端提示
		SELECT
			@AssignLotCount AS AssignedRowCount,
			CONVERT(decimal(18, 8), @AssignTotalQty) AS AssignedQty,
			CONVERT(decimal(18, 8), ISNULL(@AvailableQty, 0)) AS RemainLotAvailableQty

		RETURN 0
	END

	-- 【写入】按工单号输入顺序逐单循环自动分配：单内按行序取待分配行，批次按 EntryDate 先进先出
	IF @I_Sender = 'AutoAssign'
	BEGIN
		-- 【准备】#AutoItems：当前工单未分配数量 > 0 的半成品行，按行序+物料名排列，供逐行分配
		CREATE TABLE #AutoItems (
			RowId int NOT NULL,					-- 行号
			MOId char(12) NOT NULL,				-- 工单 ID
			MOName nvarchar(50) NOT NULL,		-- 工单号
			MOItemId char(12) NOT NULL,			-- 工单物料行 ID
			ProductId char(12) NOT NULL,		-- 半成品物料 ID
			UOMId char(12) NOT NULL,			-- 单位 ID
			LineSequence varchar(20) NOT NULL,	-- 行序
			ProductName nvarchar(50) NOT NULL,	-- 物料名称
			RemainQty decimal(18, 8) NOT NULL	-- 剩余需求数量
		)

		-- 【准备】#AutoLots：当前物料按生产日期(ProductionDate)先进先出排列的可分配批次，非法日期排最后，供循环写入分配记录
		CREATE TABLE #AutoLots (
			RowId int NOT NULL,					-- 行号
			WWId char(12) NOT NULL,				-- 库存记录 ID
			LotSN nvarchar(100) NOT NULL,		-- MES 批次号
			ProductionLotNO varchar(50) NULL,	-- SAP/生产批次
			FactoryId char(12) NULL,			-- 工厂 ID
			WorkcenterId char(12) NULL,			-- 仓库 ID
			CellId char(12) NULL,				-- 储位 ID
			AvailableQty decimal(18, 8) NOT NULL-- 批次可用数量
		)

		-- 【准备】#AutoResult：按工单物料行记录本次自动分配结果，供最终汇总返回
		CREATE TABLE #AutoResult (
			MOSeq int NOT NULL,					-- 工单输入顺序号
			MOName nvarchar(50) NOT NULL,		-- 工单号
			LineSequence varchar(20) NOT NULL,	-- 行序
			ProductName nvarchar(50) NOT NULL,	-- 物料名称
			AssignedLotCount int NOT NULL,		-- 分配批次数
			AssignedQty decimal(18, 8) NOT NULL,-- 分配数量
			RemainQty decimal(18, 8) NOT NULL	-- 剩余未分配数量
		)

		-- 【循环】按输入顺序逐个工单处理，每个工单独立事务，单据间互不影响
		SET @MOSeq = 0
		WHILE 1 = 1
		BEGIN
			SELECT @MOSeq = MIN(Seq)
			FROM #MOList
			WHERE Seq > @MOSeq

			IF @MOSeq IS NULL
				BREAK

			SELECT
				@CurMOId = MOId,
				@CurMOName = MOName
			FROM #MOList
			WHERE Seq = @MOSeq

			-- 【事务】当前工单的分配写入独立成单事务
			BEGIN TRANSACTION AutoAssignBatch

			-- 【准备】装载当前工单待分配半成品行(净需求 - 已分配 > 0)
			DELETE FROM #AutoItems
			INSERT INTO #AutoItems (RowId, MOId, MOName, MOItemId, ProductId, UOMId, LineSequence, ProductName, RemainQty)
			SELECT
				ROW_NUMBER() OVER (ORDER BY mi.LineSequence, pr.ProductName) AS RowId,
				mi.MOId,
				mo.MOName,
				mi.MOItemId,
				mi.ProductId,
				mi.UOMId,
				mi.LineSequence,
				pr.ProductName,
				CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) - ISNULL(alloc.AllocatedQty, 0)) AS RemainQty
			FROM dbo.MOItem mi
				INNER JOIN dbo.MO mo ON mo.MOId = mi.MOId
				INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
				LEFT JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId
				LEFT JOIN (
					SELECT
						MOItemId,
						SUM(ISNULL(Qty, 0)) AS AllocatedQty
					FROM dbo.MOSemiFinishedLotAllocation
					WHERE DeleteFlag = '0'
						AND IsOccupyAllocatedQty = 1
					GROUP BY MOItemId
				) alloc ON alloc.MOItemId = mi.MOItemId
			WHERE mi.MOId = @CurMOId
				AND ISNULL(mi.DeleteFlag, '') = '0'
				AND mi.LineSequence <> '000'
				AND p.ProductClassify = '2'
				AND ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) - ISNULL(alloc.AllocatedQty, 0) > 0

			SELECT @ItemCount = COUNT(1) FROM #AutoItems
			SET @ItemRowId = 1
			SET @CurMOAssignQty = 0

			-- 【循环】逐个物料行自动分配
			WHILE @ItemRowId <= @ItemCount
			BEGIN
				SELECT
					@CurMOItemId = MOItemId,
					@CurProductId = ProductId,
					@CurUOMId = UOMId,
					@CurLineSequence = LineSequence,
					@CurProductName = ProductName,
					@RemainQty = RemainQty
				FROM #AutoItems
				WHERE RowId = @ItemRowId

				SET @ItemRowId = @ItemRowId + 1
				SET @ItemLotCount = 0
				SET @ItemAssignQty = 0

				-- 【准备】装载当前物料 FIFO 可分配批次
				-- 口径与 GetInventory 一致：正常在库、LotSN 唯一、可用数量 > 0；本次运行中已写入的分配也会被扣减
				DELETE FROM #AutoLots
				INSERT INTO #AutoLots (RowId, WWId, LotSN, ProductionLotNO, FactoryId, WorkcenterId, CellId, AvailableQty)
				SELECT
					-- 【排序】与 GetInventory 一致：按生产日期先进先出，无法转换为日期的记录置为 99991231 排在最后，同日期内再按入库日期、批次号保持稳定排序
					ROW_NUMBER() OVER (
						ORDER BY
							ISNULL(TRY_CONVERT(date, LTRIM(RTRIM(wri.ProductionDate))), '99991231'),
							wri.EntryDate,
							wri.LotSN
					) AS RowId,
					wri.WWId,
					wri.LotSN,
					wri.ProductionLotNO,
					wri.FactoryId,
					wri.WorkcenterId,
					wri.CellId,
					CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0) - ISNULL(alloc.AllocatedQty, 0)) AS AvailableQty
				FROM dbo.WW_RMInventory wri
					LEFT JOIN (
						SELECT
							a.LotSN,
							SUM(ISNULL(a.Qty, 0)) AS AllocatedQty
						FROM dbo.MOSemiFinishedLotAllocation a
						WHERE a.DeleteFlag = '0'
							AND a.IsOccupyAllocatedQty = 1
							AND ISNULL(a.LotSN, '') <> ''
						GROUP BY a.LotSN
					) alloc ON alloc.LotSN = wri.LotSN
				WHERE wri.ProductId = @CurProductId
					AND wri.LotStatus = '1'
					AND wri.IsStorage = 1
					AND ISNULL(wri.Qty, 0) > 0
					AND ISNULL(wri.LotSN, '') <> ''
					AND (
						SELECT COUNT(1)
						FROM dbo.WW_RMInventory wriCnt
						WHERE wriCnt.LotSN = wri.LotSN
					) = 1
					AND ISNULL(wri.Qty, 0) - ISNULL(alloc.AllocatedQty, 0) > 0

				SELECT @LotCount = COUNT(1) FROM #AutoLots

				-- 【循环】按生产日期先进先出逐批分配，直到剩余需求为 0 或批次用尽
				SET @LotRowId = 1
				WHILE @LotRowId <= @LotCount AND ISNULL(@RemainQty, 0) > 0
				BEGIN
					SELECT
						@AssignWWId = WWId,
						@AutoAssignLotSN = LotSN,
						@AssignProductionLotNO = ProductionLotNO,
						@AssignFactoryId = FactoryId,
						@AssignWorkcenterId = WorkcenterId,
						@AssignCellId = CellId,
						@AvailableQty = AvailableQty
					FROM #AutoLots
					WHERE RowId = @LotRowId

					SET @LotRowId = @LotRowId + 1

					IF ISNULL(@AvailableQty, 0) <= 0
						CONTINUE

					SET @AssignQty = CASE
						WHEN @RemainQty < @AvailableQty THEN @RemainQty
						ELSE @AvailableQty
					END

					IF ISNULL(@AssignQty, 0) <= 0
						CONTINUE

					-- 【写入】生成主键并插入预分配记录
					EXEC dbo.SysGetObjectPKId '', 'MOSemiFinishedLotAllocation', @NewId OUTPUT

					IF ISNULL(@NewId, '') = ''
					BEGIN
						ROLLBACK TRANSACTION AutoAssignBatch
						IF OBJECT_ID('tempdb..#AutoResult') IS NOT NULL
							DROP TABLE #AutoResult
						IF OBJECT_ID('tempdb..#AutoLots') IS NOT NULL
							DROP TABLE #AutoLots
						IF OBJECT_ID('tempdb..#AutoItems') IS NOT NULL
							DROP TABLE #AutoItems
						SET @I_ReturnMessage = N'ServerMessage:生成分配记录失败!'
						RETURN -1
					END

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
						DeleteFlag,
						CreateUserId,
						CreateUserName,
						CreateDate,
						ModifyDate
					)
					VALUES (
						@NewId,
						@CurMOId,
						@CurMOName,
						@CurMOItemId,
						@CurProductId,
						@AssignWWId,
						@AutoAssignLotSN,
						@AssignProductionLotNO,
						@AssignFactoryId,
						@AssignWorkcenterId,
						@AssignCellId,
						@CurUOMId,
						@AssignQty,
						1,
						'0',
						@I_OrBitUserId,
						@I_OrBitUserName,
						GETDATE(),
						GETDATE()
					)

					IF @@ROWCOUNT = 0
					BEGIN
						ROLLBACK TRANSACTION AutoAssignBatch
						IF OBJECT_ID('tempdb..#AutoResult') IS NOT NULL
							DROP TABLE #AutoResult
						IF OBJECT_ID('tempdb..#AutoLots') IS NOT NULL
							DROP TABLE #AutoLots
						IF OBJECT_ID('tempdb..#AutoItems') IS NOT NULL
							DROP TABLE #AutoItems
						SET @I_ReturnMessage = N'ServerMessage:生成分配记录失败!'
						RETURN -1
					END

					SET @RemainQty = @RemainQty - @AssignQty
					SET @ItemAssignQty = @ItemAssignQty + @AssignQty
					SET @ItemLotCount = @ItemLotCount + 1
				END

				-- 【记录】写入当前物料行的分配结果(含分配数量为 0 的行，便于前端展示缺口)
				INSERT INTO #AutoResult (MOSeq, MOName, LineSequence, ProductName, AssignedLotCount, AssignedQty, RemainQty)
				VALUES (@MOSeq, @CurMOName, @CurLineSequence, @CurProductName, @ItemLotCount, @ItemAssignQty, @RemainQty)

				SET @CurMOAssignQty = @CurMOAssignQty + @ItemAssignQty
			END

			-- 【提交】当前工单有写入则提交；无写入回滚空事务，继续处理下一工单
			IF ISNULL(@CurMOAssignQty, 0) > 0
				COMMIT TRANSACTION AutoAssignBatch
			ELSE
				ROLLBACK TRANSACTION AutoAssignBatch

			SET @GrandTotalQty = @GrandTotalQty + ISNULL(@CurMOAssignQty, 0)
		END

		-- 【校验】所有工单均未产生分配时返回业务提示
		IF ISNULL(@GrandTotalQty, 0) <= 0
		BEGIN
			IF OBJECT_ID('tempdb..#AutoResult') IS NOT NULL
				DROP TABLE #AutoResult
			IF OBJECT_ID('tempdb..#AutoLots') IS NOT NULL
				DROP TABLE #AutoLots
			IF OBJECT_ID('tempdb..#AutoItems') IS NOT NULL
				DROP TABLE #AutoItems
			SET @I_ReturnMessage = N'ServerMessage:所选工单无可分配库存，无法自动分配!'
			RETURN -1
		END

		-- 【返回】按工单输入顺序返回各物料行分配汇总
		SELECT
			MOName,
			LineSequence,
			ProductName,
			AssignedLotCount,
			CONVERT(decimal(18, 8), AssignedQty) AS AssignedQty,
			CONVERT(decimal(18, 8), RemainQty) AS RemainQty
		FROM #AutoResult
		ORDER BY MOSeq, LineSequence

		IF OBJECT_ID('tempdb..#AutoResult') IS NOT NULL
			DROP TABLE #AutoResult
		IF OBJECT_ID('tempdb..#AutoLots') IS NOT NULL
			DROP TABLE #AutoLots
		IF OBJECT_ID('tempdb..#AutoItems') IS NOT NULL
			DROP TABLE #AutoItems

		RETURN 0
	END

    -- 【删除】按分配记录 ID 逻辑删除预分配记录
	IF @I_Sender = 'DeleteLot'
	BEGIN
		-- 【校验】分配记录 ID 不能为空
		IF ISNULL(@MOSemiFinishedLotAllocationId, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:分配记录不存在或已删除!'
			RETURN -1
		END

		-- 【事务】开启删除事务，保证逻辑删除一致性
		BEGIN TRANSACTION DeleteLot

		-- 【校验】仅允许删除有效记录
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.MOSemiFinishedLotAllocation
			WHERE MOSemiFinishedLotAllocationId = @MOSemiFinishedLotAllocationId
				AND DeleteFlag = '0'
		)
		BEGIN
			ROLLBACK TRANSACTION DeleteLot
			SET @I_ReturnMessage = N'ServerMessage:分配记录不存在或已删除!'
			RETURN -1
		END

		-- 【写入】逻辑删除分配记录
		UPDATE dbo.MOSemiFinishedLotAllocation
		SET DeleteFlag = '1',
			ModifyDate = GETDATE()
		WHERE MOSemiFinishedLotAllocationId = @MOSemiFinishedLotAllocationId
			AND DeleteFlag = '0'

		IF @@ROWCOUNT = 0
		BEGIN
			ROLLBACK TRANSACTION DeleteLot
			SET @I_ReturnMessage = N'ServerMessage:分配记录不存在或已删除!'
			RETURN -1
		END

		-- 【提交】逻辑删除成功
		COMMIT TRANSACTION DeleteLot
            
		RETURN 0
	END

	-- 【异常处理】未识别的功能分支统一返回 OrBit 风格错误
	SET @I_ReturnMessage = N'ServerMessage:未知操作!'
	RETURN -1
END
GO