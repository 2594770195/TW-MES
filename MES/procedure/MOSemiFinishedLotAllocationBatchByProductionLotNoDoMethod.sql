SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OrBit Team>
-- Create date: <2026-10-21>
-- Description:	成品工单半成品批次批量分配 DoMethod（按 ProductionLotNO 分配版本）
-- Revision: 2.11（新增版本，不覆盖 MOSemiFinishedLotAllocationBatchDoMethod；已同步批版本最新改造）
--
-- Revision 2.14（2026-11-16，SAP 同步标记）：
--   新增 MOSemiFinishedLotAllocation.SAPSyncFlag（0=未同步，1=已同步）：
--   1) ConfirmLot 确认(ConfirmStatus 0→1)时置 SAPSyncFlag='0'（未同步）
--   2) DeleteLot 取消已确认记录时置 SAPSyncFlag='0'（未同步）
--   3) AutoAssign 新增未确认记录默认 '0'（ConfirmStatus='0' 不参与上报，确认后自然为待同步状态）
--   4) SAP 同步暂未实现，后续补充：操作完成后由统一同步逻辑
--      循环调用存在未同步记录(ConfirmStatus='1' AND SAPSyncFlag='0')的 MO 上报 SAP，
--      同步成功置 '1'，失败保持 '0' 等待下次循环补偿，阻断业务操作
--      接口过程：dbo.APISyncU_SemiFinishedTallyToSAP
--
-- Revision 2.12（2026-11-12，去旧数据兼容 + 未分配提示）：
--   1) 旧理货数据已清理，取消 FactoryId/WorkcenterId 为空的历史兼容逻辑：
--      GetAllocatedLots 的库存代表行反查改为按 ProductId+FactoryId+WorkcenterId+ProductionLotNO 严格等值匹配
--   2) AutoAssign 结束时新增提示：存在库存不足导致未分配完成的工单
--
-- Revision 2.11（2026-11-12，SAP 对接准备）：
--   1) 修正 DeleteLot 取消分配的记录形态：
--      已理货记录取消后为 ConfirmStatus='1'、IsOccupyAllocatedQty=1、DeleteFlag='1'；
--      未确认记录取消后为 ConfirmStatus='0'、IsOccupyAllocatedQty=0、DeleteFlag='1'；
--      已扣数记录(ConfirmStatus='1' 且 IsOccupyAllocatedQty=0)禁止取消分配。
--   2) ConfirmLot / DeleteLot 预留 SAP 同步位置（已理货 / 取消分配）
--
-- 与 LotSN 版本（MOSemiFinishedLotAllocationBatchDoMethod）的差异：
--   1) 分配粒度：由 MES 批次号 LotSN 改为 SAP/生产批次号 ProductionLotNO（1 个 ProductionLotNO 对应 N 个 LotSN）
--   2) 库存口径：按 ProductId + FactoryId + WorkcenterId + ProductionLotNO 四维度汇总库存数量
--   3) 已分配口径：按上述四维度汇总 MOSemiFinishedLotAllocation 中的占用数量
--   4) 分配记录：ProductionLotNO / FactoryId / WorkcenterId 必填；LotSN / WWId / CellId 不指向单一条码，
--      统一写 NULL，展示时由库存表按四维度反查（代表子批次、汇总库存数、位置、状态）
--   5) 下游若按 MOSemiFinishedLotAllocation.LotSN 关联库存/扫描校验，需同步改为四维度
--   6) 工厂口径：只能分配与工单工厂对应的库存工厂（9502/9304 工单 -> 9502 库存；9302 工单 -> 9302 库存）
--
-- 与批版本同步的改造（Revision 2.10）：
--   a) 移除 AssignLot 分支：不再按单个批次扫码分配，统一由 AutoAssign 自动分配
--   b) GetMOProduct 不再单独返回需求清单，与 AutoAssign 合并处理（仅返回提示信息）
--   c) 新增 ConfirmLot 确认、AllowBatch 允许/取消分批分支；AllowBatch 按当前工单整体取反
--   d) 删除分配记录时按状态处理占用：未确认记录释放占用，已理货记录保留占用并仅置删除标记
--   e) 净需求统一按 ItemQtyRequired - ItemQtyIssued + ItemQtyBack 计算
--   f) 未确认记录仅占用当前工单清单库存，已确认记录无条件占用
--
-- @MONames 支持多个工单号组合，用回车(CHAR(13)/CHAR(10))或逗号(英文, / 中文，)分隔
-- @I_Sender 分支说明：
--   GetInventory    【已废弃】原按工单物料行查询可分配清单，现改由 AssignLot_GetLotByProductionLotNo_Script 返回
--   AutoAssign      按工单号输入顺序逐单循环自动分配：单内按行序取待分配行，生产批次按生产日期(ProductionDate)先进先出
--   GetAllocatedLots 查询当前工单已分配的有效生产批次记录
--   DeleteLot       按分配记录 ID 逻辑删除，释放占用
--   ConfirmLot      批量确认未确认记录（0=未确认，1=已确认永久占用）
--   AllowBatch      将当前工单全部分配记录的允许分批标记整体取反（允许 <-> 取消）
-- 错误返回：失败时设置 @I_ReturnMessage='ServerMessage:...' 并 RETURN -1
-- =============================================
ALTER PROCEDURE [dbo].[MOSemiFinishedLotAllocationBatchByProductionLotNoDoMethod]
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
@BoxOrLotSN nvarchar(100) = '',					-- 生产批次号（保留接口参数，AssignLot 分支已移除）
@Grid_MoItem char(12) = '',						-- 工单半成品物料行ID（GetInventory 已废弃，参数仅保留兼容）
@MOSemiFinishedLotAllocationId char(12) = ''	-- 半成品批次分配记录ID
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- 【初始化】清空输出参数，避免复用调用上下文中的旧错误信息
	SET @I_ReturnMessage = ''
	SET @I_ExceptionFieldName = ''

	DECLARE @NameSeq int = 0						-- 工单号输入顺序号
	DECLARE @InvalidMOList nvarchar(max) = ''		-- 未解析到有效工单的工单号清单

	DECLARE @LotProductId char(12) = ''				-- 当前生产批次的半成品物料 ID
	DECLARE @AssignProductionLotNO varchar(50) = ''	-- 当前分配的生产批次号
	DECLARE @CurProductionLotNO varchar(50) = ''	-- AutoAssign 当前生产批次号
	DECLARE @StockQty decimal(18, 8) = 0			-- 生产批次汇总库存数量
	DECLARE @LotAllocatedQty decimal(18, 8) = 0		-- 生产批次已被占用分配数量
	DECLARE @AvailableQty decimal(18, 8) = 0		-- 生产批次可用数量
	DECLARE @AssignQty decimal(18, 8) = 0			-- 单次分配数量
	DECLARE @RemainQty decimal(18, 8) = 0			-- 工单物料行剩余需求
	DECLARE @NewId char(12) = ''					-- 新分配记录 ID
	DECLARE @RowId int = 0							-- 循环当前行号
	DECLARE @RowCount int = 0						-- 循环总行数
	DECLARE @ItemRowId int = 0						-- AutoAssign 当前物料行行号
	DECLARE @ItemCount int = 0						-- AutoAssign 当前工单待分配物料行数
	DECLARE @ItemLotCount int = 0					-- AutoAssign 当前物料行写入生产批次数
	DECLARE @ItemAssignQty decimal(18, 8) = 0		-- AutoAssign 当前物料行分配数量
	DECLARE @LotRowId int = 0						-- AutoAssign 当前生产批次行号
	DECLARE @LotCount int = 0						-- AutoAssign 当前物料可分配生产批次数
	DECLARE @AssignLotCount int = 0					-- 本次写入生产批次数
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
	DECLARE @CurFactoryId char(12) = ''				-- AutoAssign 当前工厂
	DECLARE @CurWorkcenterId char(12) = ''			-- AutoAssign 当前仓库

	-- 【工厂口径】理货只能分配与工单工厂对应的库存工厂
	DECLARE @CurMOFactoryName nvarchar(50) = ''		-- AutoAssign 当前工单工厂名称
	DECLARE @CurStockFactoryId char(12) = ''		-- AutoAssign 当前工单允许分配的库存工厂 ID

	DECLARE @NoRequirementMOList nvarchar(max) = ''	-- 因半成品需求数量为0被跳过不分配的工单号清单
	DECLARE @NoFactoryMOList nvarchar(max) = ''		-- 因工单未维护工厂/库存工厂不存在被跳过不分配的工单号清单
	DECLARE @UnassignedMOList nvarchar(max) = ''	-- 因库存不足导致半成品未分配完成的工单号清单

	DECLARE @SapRet int = 0							-- SAP 接口返回值：0=成功，非0=失败(失败需回滚)
	DECLARE @SapMsg nvarchar(max) = ''				-- SAP 接口返回信息
	DECLARE @TallySyncCount int = 0					-- 本次待同步 SAP 的理货记录数

	-- 【校验】仅允许已定义的批量分支，其余统一返回未知操作
	IF @I_Sender NOT IN ('GetMOProduct', 'AutoAssign', 'GetAllocatedLots', 'DeleteLot', 'ConfirmLot', 'AllowBatch')
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

	-- 【准备】#MONameList：把 @MONames 按回车/逗号等分隔符解析为按输入顺序排列的工单号清单
	-- 存放解析结果(去空格、去空段、去重)，供后续解析工单 ID 使用
	CREATE TABLE #MONameList (
		Seq int NOT NULL,				-- 输入顺序号
		MOName nvarchar(50) NOT NULL	-- 工单号
	)

	IF @MONames IS NOT NULL AND @MONames <> ''
	BEGIN
		-- 去除所有空格、逗号、制表符、换行符、回车符
		SET @MONames = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@MONames, ' ', ''), ',', ''), CHAR(9), ''), CHAR(10), ''), CHAR(13), '')
		DECLARE @pos INT = 1, @len INT = LEN(@MONames), @segment NVARCHAR(50)
		WHILE @pos <= @len
		BEGIN
			SET @segment = SUBSTRING(@MONames, @pos, 10)
			IF LEN(@segment) = 10
			BEGIN
				SET @NameSeq = @NameSeq + 1
				-- 【校验】同一工单号只保留首次出现的顺序，避免重复处理
				IF NOT EXISTS (SELECT 1 FROM #MONameList WHERE MOName = @segment)
					INSERT INTO #MONameList (Seq, MOName) VALUES (@NameSeq, @segment)
			END
			SET @pos = @pos + 10
		END
	END

	-- 【校验】解析后无有效工单号时直接返回
	IF NOT EXISTS (SELECT 1 FROM #MONameList)
	BEGIN
		SET @I_ReturnMessage = N'ServerMessage:请输入有效工单号!'
		RETURN -1
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

	-- =============================================
	-- 【已废弃】GetInventory 分支已删除（2026-11-12）
	-- 可分配批次改由对话框脚本 AssignLot_GetLotByProductionLotNo_Script 统一返回：
	--   该脚本已按 物料+工厂+仓库+SAP批次 四维度拆行，并按工单工厂口径过滤库存。
	-- 调用方若仍传入 @I_Sender='GetInventory'，将被上方白名单校验拒绝（未知操作）。
	-- =============================================
	-- =============================================
	-- 【查询】查询当前工单已分配的有效生产批次记录
	-- =============================================
	IF @I_Sender = 'GetAllocatedLots'
	BEGIN
		-- 【准备】工厂/仓库直接取分配记录自身的 FactoryId/WorkcenterId（分配时已必填）
		SELECT
			a.MOSemiFinishedLotAllocationId,
            CAST(CASE WHEN a.ConfirmStatus = '1' THEN 1 ELSE 0 END AS BIT) AS '已确认',
			a.Allow_batch 允许分批,
			a.MOName,
			a.MOItemId,
			a.FactoryId AS AllocFactoryId,
			a.WorkcenterId AS AllocWorkcenterId,
			f.FactoryName,
			w.WorkcenterName,
			pr.ProductName,
			p.ProductDescription,
			--inv.LotSN,								-- 代表子批次号(仅展示)
			a.ProductionLotNO,						-- 分配批次号
			inv.ProductionDate,
			u.UOMName,
			CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) + ISNULL(mi.ItemQtyBack, 0)) AS ItemQtyRequired,
			CONVERT(decimal(18, 8), ISNULL(a.Qty, 0)) AS '分配数量',
			a.CreateDate,
			CONVERT(decimal(18, 8), ISNULL(inv.StockQty, 0)) AS '库存数量',
			LotStatusTable.UserCodeDescription AS LotStatus,
			QCStatusTable.UserCodeDescription AS QCStatus,
			inv.EntryDate,
			inv.ValidityEndDate,
			inv.SAPRemark,
			pi.Note AS 'SAP备注',
			inv.HoldResult AS '锁定原因',
			MO.NoteMessage AS '生产备注信息'
		FROM dbo.MOSemiFinishedLotAllocation a
			LEFT JOIN dbo.MOItem mi ON mi.MOItemId = a.MOItemId
			INNER JOIN dbo.Product p ON p.ProductId = a.ProductId
			LEFT JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId
			LEFT JOIN dbo.UOM u ON u.UOMId = a.UOMId
			-- 【准备】按 ProductId + FactoryId + WorkcenterId + ProductionLotNO 取代表库存行(最早入库)及该生产批次该维度汇总库存数量
			OUTER APPLY (
				SELECT TOP 1
					x.LotSN,
					x.ProductionDate,
					x.EntryDate,
					x.ValidityEndDate,
					x.SAPRemark,
					x.HoldResult,
					x.LotStatus,
					x.QCStatus,
					x.FactoryId,
					x.WorkcenterId,
					x.MOId,
					(SELECT SUM(ISNULL(y.Qty, 0))
					 FROM dbo.WW_RMInventory y
					 WHERE y.ProductId = a.ProductId
						AND y.FactoryId = a.FactoryId
						AND y.WorkcenterId = a.WorkcenterId
						AND y.ProductionLotNO = a.ProductionLotNO) AS StockQty
				FROM dbo.WW_RMInventory x
				WHERE x.ProductId = a.ProductId
					AND x.FactoryId = a.FactoryId
					AND x.WorkcenterId = a.WorkcenterId
					AND x.ProductionLotNO = a.ProductionLotNO
					AND ISNULL(x.Qty, 0) > 0
				-- 【排序】同维度内按入库日期、批次号取最早一行作为代表子批次
				ORDER BY x.EntryDate, x.LotSN
			) inv
			-- 【工厂/仓库列】按分配记录自身的 a.FactoryId/a.WorkcenterId 反查名称
			LEFT JOIN dbo.Factory f ON f.FactoryId = a.FactoryId
			LEFT JOIN dbo.Workcenter w ON w.WorkcenterId = a.WorkcenterId
			LEFT JOIN UserCode_Table('URC100000AA9') LotStatusTable ON inv.LotStatus = LotStatusTable.UserCodeName
			LEFT JOIN UserCode_Table('URC100000AMP') QCStatusTable ON inv.QCStatus = QCStatusTable.UserCodeName
			LEFT JOIN ProductInventory pi ON pi.ProductId = a.ProductId
				AND pi.LotSN = a.ProductionLotNO
				AND pi.WorkcenterId = a.WorkcenterId
				AND pi.DeleteFlag = '0'
			LEFT JOIN dbo.MO ON MO.MOId = inv.MOId
			INNER JOIN #MOList m ON m.MOId = a.MOId
		WHERE
			-- 【过滤】返回所有有效分配记录（含未确认与已确认，由确认状态列区分）
			a.DeleteFlag = '0'
			AND a.IsOccupyAllocatedQty = 1
		-- 【排序】按工单、物料行、工厂、仓库、创建日期稳定排序
		ORDER BY a.MOName, a.MOItemId, a.FactoryId, a.WorkcenterId, w.WorkcenterName, a.CreateDate DESC, a.ProductionLotNO

		RETURN 0
	END

	-- =============================================
	-- 【写入】按工单号输入顺序逐单循环自动分配：单内按行序取待分配行，生产批次按生产日期先进先出
	-- =============================================
	IF @I_Sender = 'AutoAssign' OR @I_Sender = 'GetMOProduct'
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

		-- 【准备】#AutoLots：当前物料按生产日期(ProductionDate)先进先出排列的可分配生产批次，非法日期排最后
		CREATE TABLE #AutoLots (
			RowId int NOT NULL,							-- 行号
			FactoryId char(12) NOT NULL,				-- 工厂
			WorkcenterId char(12) NOT NULL,				-- 仓库
			ProductionLotNO varchar(50) NOT NULL,		-- 生产批次号
			LotSNCount int NOT NULL,					-- 该生产批次该仓库下的子批次数
			AvailableQty decimal(18, 8) NOT NULL		-- 生产批次该仓库可用数量
		)

		-- 【准备】#AutoResult：按工单物料行记录本次自动分配结果，供最终汇总返回
		CREATE TABLE #AutoResult (
			MOSeq int NOT NULL,					-- 工单输入顺序号
			MOName nvarchar(50) NOT NULL,		-- 工单号
			LineSequence varchar(20) NOT NULL,	-- 行序
			ProductName nvarchar(50) NOT NULL,	-- 物料名称
			AssignedLotCount int NOT NULL,		-- 分配生产批次数
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

			-- 【工厂口径】解析当前工单允许分配的库存工厂：
			--   工单工厂为 9502 / 9304 时，只能分配 9502 的库存；
			--   工单工厂为 9302 时，只能分配 9302 的库存；
			--   其他工厂按同名工厂分配
			SET @CurMOFactoryName = ''
			SET @CurStockFactoryId = ''
			SELECT
				@CurMOFactoryName = mf.FactoryName,
				@CurStockFactoryId = sf.FactoryId
			FROM dbo.MO mo
				INNER JOIN dbo.Factory mf ON mf.FactoryId = mo.FactoryId
				INNER JOIN dbo.Factory sf ON sf.FactoryName = CASE
					WHEN mf.FactoryName IN (N'9502', N'9304') THEN N'9502'
					WHEN mf.FactoryName = N'9302' THEN N'9302'
					ELSE mf.FactoryName
				END
			WHERE mo.MOId = @CurMOId

			-- 【校验】工单未维护工厂或库存工厂不存在时跳过该工单，记入清单供最终提示
			IF ISNULL(@CurStockFactoryId, '') = ''
			BEGIN
				SET @NoFactoryMOList = ISNULL(@NoFactoryMOList + ',', '') + @CurMOName
				CONTINUE
			END

			-- 【校验】分配前筛选：当前工单半成品无可分配需求(净需求为0)时整单跳过，并记入无需求工单号清单
			IF NOT EXISTS (
				SELECT 1
				FROM dbo.MOItem mi
					INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
				WHERE mi.MOId = @CurMOId
					AND ISNULL(mi.DeleteFlag, '') = '0'
					AND mi.LineSequence <> '000'
					AND p.ProductClassify = '2'
					AND ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) + ISNULL(mi.ItemQtyBack, 0) > 0
			)
			BEGIN
				SET @NoRequirementMOList = ISNULL(@NoRequirementMOList + ',', '') + @CurMOName
				CONTINUE
			END

			-- 【分配】库存数量不足时仍继续分配，直至可分配库存为 0（不整单跳过，按可用量部分分配）

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
				CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) + ISNULL(mi.ItemQtyBack, 0) - ISNULL(alloc.AllocatedQty, 0)) AS RemainQty
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
				AND ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) + ISNULL(mi.ItemQtyBack, 0) - ISNULL(alloc.AllocatedQty, 0) > 0

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

				-- 【准备】装载当前物料按 ProductId + FactoryId + WorkcenterId + ProductionLotNO 汇总的可分配生产批次(先进先出)
				-- 口径与可分配批次查询一致：正常在库、ProductionLotNO 非空、可用数量 > 0；本次运行中已写入的分配也会被扣减
				DELETE FROM #AutoLots
				INSERT INTO #AutoLots (RowId, FactoryId, WorkcenterId, ProductionLotNO, LotSNCount, AvailableQty)
				SELECT
					-- 【排序】按生产日期先进先出，空字符串经 TRY_CONVERT 会得到 1900-01-01，
					-- 故先用 NULLIF 置 NULL，再由 ISNULL 统一排到最后，同日期内再按入库日期、工厂、仓库、生产批次号保持稳定排序
					ROW_NUMBER() OVER (ORDER BY x.FirstProductionDate, x.FirstEntryDate, x.FactoryId, x.WorkcenterId, x.ProductionLotNO) AS RowId,
					x.FactoryId,
					x.WorkcenterId,
					x.ProductionLotNO,
					x.LotSNCount,
					x.AvailableQty
				FROM (
					SELECT
						wri.FactoryId,
						wri.WorkcenterId,
						wri.ProductionLotNO,
						COUNT(1) AS LotSNCount,
						MIN(ISNULL(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(wri.ProductionDate)), '')), '99991231')) AS FirstProductionDate,
						MIN(wri.EntryDate) AS FirstEntryDate,
						CONVERT(decimal(18, 8), SUM(ISNULL(wri.Qty, 0)) - ISNULL(alloc.AllocatedQty, 0)) AS AvailableQty
					FROM dbo.WW_RMInventory wri
						LEFT JOIN (
							-- 【准备】按 ProductId + FactoryId + WorkcenterId + ProductionLotNO 汇总有效占用中的分配数量
							SELECT
								a.ProductId,
								a.FactoryId,
								a.WorkcenterId,
								a.ProductionLotNO,
								SUM(ISNULL(a.Qty, 0)) AS AllocatedQty
							FROM dbo.MOSemiFinishedLotAllocation a
							WHERE a.DeleteFlag = '0'
								AND a.IsOccupyAllocatedQty = 1
								AND (a.ConfirmStatus = '1' OR (a.ConfirmStatus = '0' AND a.MOId IN (SELECT MOId FROM #MOList)))
								AND ISNULL(a.ProductionLotNO, '') <> ''
							GROUP BY a.ProductId, a.FactoryId, a.WorkcenterId, a.ProductionLotNO
						) alloc ON alloc.ProductId = wri.ProductId
							AND alloc.FactoryId = wri.FactoryId
							AND alloc.WorkcenterId = wri.WorkcenterId
							AND alloc.ProductionLotNO = wri.ProductionLotNO
					WHERE wri.ProductId = @CurProductId
						AND wri.FactoryId = @CurStockFactoryId	-- 【工厂口径】只取当前工单允许分配的库存工厂
						AND wri.LotStatus = '1'
						AND wri.IsStorage = 1
						AND ISNULL(wri.Qty, 0) > 0
						AND ISNULL(wri.ProductionLotNO, '') <> ''
					GROUP BY wri.ProductId, wri.FactoryId, wri.WorkcenterId, wri.ProductionLotNO, alloc.AllocatedQty
					HAVING SUM(ISNULL(wri.Qty, 0)) - ISNULL(alloc.AllocatedQty, 0) > 0
				) x

				SELECT @LotCount = COUNT(1) FROM #AutoLots

				-- 【循环】按生产日期先进先出逐生产批次分配，直到剩余需求为 0 或批次用尽
				SET @LotRowId = 1
				WHILE @LotRowId <= @LotCount AND ISNULL(@RemainQty, 0) > 0
				BEGIN
					-- 【初始化】先清空当前批次变量，避免读取不到行时沿用上一轮值
					SET @CurProductionLotNO = ''
					SET @CurFactoryId = ''
					SET @CurWorkcenterId = ''
					SET @AvailableQty = 0

					SELECT
						@CurFactoryId = FactoryId,
						@CurWorkcenterId = WorkcenterId,
						@CurProductionLotNO = ProductionLotNO,
						@AvailableQty = AvailableQty
					FROM #AutoLots
					WHERE RowId = @LotRowId

					SET @LotRowId = @LotRowId + 1

					IF ISNULL(@AvailableQty, 0) <= 0 OR ISNULL(@CurProductionLotNO, '') = ''
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

					-- 【写入】按 ProductId + FactoryId + WorkcenterId + ProductionLotNO 粒度写一条记录；LotSN/WWId/CellId 留空，由库存表按四字段反查代表子批次
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
						@NewId,
						@CurMOId,
						@CurMOName,
						@CurMOItemId,
						@CurProductId,
						NULL,
						NULL,
						@CurProductionLotNO,
						@CurFactoryId,
						@CurWorkcenterId,
						NULL,
						@CurUOMId,
						@AssignQty,
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

			-- 【记录】当前工单存在剩余未分配数量(库存不足)时，记入清单供最终提示
			-- 说明：本判断在提交/回滚前执行，可看到本工单在临时表中的分配结果
			IF EXISTS (SELECT 1 FROM #AutoResult WHERE MOSeq = @MOSeq AND RemainQty > 0)
				SET @UnassignedMOList = ISNULL(@UnassignedMOList + ',', '') + @CurMOName

			-- 【提交】当前工单有写入则提交；无写入回滚空事务，继续处理下一工单
			IF ISNULL(@CurMOAssignQty, 0) > 0
				COMMIT TRANSACTION AutoAssignBatch
			ELSE
				ROLLBACK TRANSACTION AutoAssignBatch

			SET @GrandTotalQty = @GrandTotalQty + ISNULL(@CurMOAssignQty, 0)
		END

		IF OBJECT_ID('tempdb..#AutoResult') IS NOT NULL
			DROP TABLE #AutoResult
		IF OBJECT_ID('tempdb..#AutoLots') IS NOT NULL
			DROP TABLE #AutoLots
		IF OBJECT_ID('tempdb..#AutoItems') IS NOT NULL
			DROP TABLE #AutoItems

		SET @I_ReturnMessage = N'ServerMessage:'
		IF ISNULL(@NoRequirementMOList, '') <> ''
		BEGIN
			SET @I_ReturnMessage += N'[工单][' + @NoRequirementMOList + N']半成品需求数量为0，未进行自动分配!'
		END

		-- 【提示】工单未维护工厂或对应库存工厂不存在时，无法按工厂口径分配
		IF ISNULL(@NoFactoryMOList, '') <> ''
		BEGIN
			SET @I_ReturnMessage += N'[工单][' + @NoFactoryMOList + N']未维护工厂或对应库存工厂不存在，未进行自动分配!'
		END

		-- 【提示】可分配库存不足，工单存在未分配完成的半成品行
		IF ISNULL(@UnassignedMOList, '') <> ''
		BEGIN
			SET @I_ReturnMessage += N'[工单][' + @UnassignedMOList + N']半成品库存不足，未分配完成，请检查库存或手工指定批次!'
		END

		RETURN 0
	END

	-- =============================================
	-- 【确认】按工单批量确认未确认的预分配记录：0=未确认(仅当前单号占用)，1=已确认(永久占用)
	-- =============================================
	IF @I_Sender = 'ConfirmLot'
	BEGIN
		-- 【事务】开启确认事务，保证库存校验与写入的原子性
		BEGIN TRANSACTION ConfirmLot

		-- 【校验】逐个工单校验：任一工单完全没有分配记录时整体拒绝确认
		-- 口径：工单在 MOSemiFinishedLotAllocation 中不存在有效占用记录(DeleteFlag='0' 且 IsOccupyAllocatedQty=1)
		IF EXISTS (
			SELECT 1
			FROM #MOList m
			WHERE NOT EXISTS (
				SELECT 1
				FROM dbo.MOSemiFinishedLotAllocation a
				WHERE a.MOId = m.MOId
					AND a.DeleteFlag = '0'
					AND a.IsOccupyAllocatedQty = 1
			)
		)
		BEGIN
			-- 【收集】完全没有分配记录的工单号清单(按工单输入顺序)
			DECLARE @NoAllocMOList nvarchar(max) = ''
			SELECT @NoAllocMOList = ISNULL(@NoAllocMOList + ',', '') + m.MOName
			FROM #MOList m
			WHERE NOT EXISTS (
				SELECT 1
				FROM dbo.MOSemiFinishedLotAllocation a
				WHERE a.MOId = m.MOId
					AND a.DeleteFlag = '0'
					AND a.IsOccupyAllocatedQty = 1
			)
			ORDER BY m.Seq

			ROLLBACK TRANSACTION ConfirmLot
			SET @I_ReturnMessage = N'ServerMessage:[工单号][' + @NoAllocMOList + N']完全没有分配记录，无法确认，请先进行分配!'
			RETURN -1
		END

		-- 【校验】当前工单不存在未确认记录时，无需确认
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.MOSemiFinishedLotAllocation a
			INNER JOIN #MOList m ON m.MOId = a.MOId
			WHERE a.DeleteFlag = '0'
				AND a.IsOccupyAllocatedQty = 1
				AND a.ConfirmStatus = '0'
		)
		BEGIN
			ROLLBACK TRANSACTION ConfirmLot
			SET @I_ReturnMessage = N'ServerMessage:当前工单无待确认分配记录!'
			RETURN -1
		END

		-- 【校验】确认前校验：当前工单待确认记录按 ProductionLotNO 汇总后，
		-- 不得导致该生产批次已确认占用数量超过库存数量；存在不足批次时整体拒绝确认

		-- 【准备】不足批次：库存不足以同时覆盖“已确认 + 本次待确认”占用数量的生产批次
		SELECT
			pending.ProductId,
			pending.FactoryId,
			pending.WorkcenterId,
			pending.ProductionLotNO
		INTO #InsufficientLots
		FROM (
			-- 【准备】本次待确认记录按 ProductId + FactoryId + WorkcenterId + ProductionLotNO 汇总
			SELECT
				a.ProductId,
				a.FactoryId,
				a.WorkcenterId,
				a.ProductionLotNO,
				SUM(ISNULL(a.Qty, 0)) AS ConfirmQty
			FROM dbo.MOSemiFinishedLotAllocation a
			INNER JOIN #MOList m ON m.MOId = a.MOId
			WHERE a.DeleteFlag = '0'
				AND a.IsOccupyAllocatedQty = 1
				AND a.ConfirmStatus = '0'
				AND ISNULL(a.ProductionLotNO, '') <> ''
			GROUP BY a.ProductId, a.FactoryId, a.WorkcenterId, a.ProductionLotNO
		) pending
		LEFT JOIN (
			-- 【准备】该维度已确认占用数量
			SELECT
				ProductId,
				FactoryId,
				WorkcenterId,
				ProductionLotNO,
				SUM(ISNULL(Qty, 0)) AS ConfirmedQty
			FROM dbo.MOSemiFinishedLotAllocation
			WHERE DeleteFlag = '0'
				AND IsOccupyAllocatedQty = 1
				AND ConfirmStatus = '1'
				AND ISNULL(ProductionLotNO, '') <> ''
			GROUP BY ProductId, FactoryId, WorkcenterId, ProductionLotNO
		) confirmed ON confirmed.ProductId = pending.ProductId
			AND confirmed.FactoryId = pending.FactoryId
			AND confirmed.WorkcenterId = pending.WorkcenterId
			AND confirmed.ProductionLotNO = pending.ProductionLotNO
		LEFT JOIN (
			-- 【准备】该维度汇总库存数量(仅统计正常在库、非锁定库存；锁定/非在库不计入)
			SELECT
				ProductId,
				FactoryId,
				WorkcenterId,
				ProductionLotNO,
				SUM(ISNULL(Qty, 0)) AS StockQty
			FROM dbo.WW_RMInventory
			WHERE LotStatus = '1'
				AND IsStorage = 1
				AND ISNULL(ProductionLotNO, '') <> ''
			GROUP BY ProductId, FactoryId, WorkcenterId, ProductionLotNO
		) inv ON inv.ProductId = pending.ProductId
			AND inv.FactoryId = pending.FactoryId
			AND inv.WorkcenterId = pending.WorkcenterId
			AND inv.ProductionLotNO = pending.ProductionLotNO
		WHERE ISNULL(inv.StockQty, 0) - ISNULL(confirmed.ConfirmedQty, 0) < pending.ConfirmQty

		-- 【校验】存在不足批次时整体拒绝确认
		IF EXISTS (SELECT 1 FROM #InsufficientLots)
		BEGIN
			-- 【收集】不足批次关联的工单号清单(按工单输入顺序)
			DECLARE @InsufficientMOList nvarchar(max) = ''
			SELECT @InsufficientMOList = ISNULL(@InsufficientMOList + ',', '') + m.MOName
			FROM #MOList m
			WHERE EXISTS (
				SELECT 1
				FROM dbo.MOSemiFinishedLotAllocation a
				INNER JOIN #InsufficientLots ins ON ins.ProductId = a.ProductId
					AND ins.FactoryId = a.FactoryId
					AND ins.WorkcenterId = a.WorkcenterId
					AND ins.ProductionLotNO = a.ProductionLotNO
				WHERE a.MOId = m.MOId
					AND a.DeleteFlag = '0'
					AND a.IsOccupyAllocatedQty = 1
					AND a.ConfirmStatus = '0'
			)

			ROLLBACK TRANSACTION ConfirmLot
			IF OBJECT_ID('tempdb..#InsufficientLots') IS NOT NULL
				DROP TABLE #InsufficientLots
			SET @I_ReturnMessage = N'ServerMessage:[工单号][' + @InsufficientMOList + N']存在批次[工厂][仓库]剩余库存不足，无法确认，请检查分配数量!'
			RETURN -1
		END

		-- 【清理】无不足批次时释放临时表
		IF OBJECT_ID('tempdb..#InsufficientLots') IS NOT NULL
			DROP TABLE #InsufficientLots

		-- 【准备】不分批且分配不足的物料行清单：allow_batch=0(不分批)且最终分配总量不足净需求的行
		-- 参考 MOLotSpecify_AssignReserveLot_DoMethod 事务尾兜底校验口径
		SELECT
			mi.MOItemId,
			mi.MOId
		INTO #InsufficientAlloc
		FROM dbo.MOItem mi
		WHERE mi.MOId IN (SELECT MOId FROM #MOList)
			AND ISNULL(mi.DeleteFlag, '') = '0'
			AND mi.LineSequence <> '000'
			-- 【过滤】仅关注存在"不分批"有效预分配记录的物料行
			AND EXISTS (
				SELECT 1
				FROM dbo.MOSemiFinishedLotAllocation a
				WHERE a.MOItemId = mi.MOItemId
					AND a.DeleteFlag = '0'
					AND a.IsOccupyAllocatedQty = 1
					AND a.allow_batch = 0
			)
			-- 【过滤】最终分配总量 < 净需求(ItemQtyRequired-ItemQtyIssued+ItemQtyBack)
			AND CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) + ISNULL(mi.ItemQtyBack, 0))
				> ISNULL((
					SELECT SUM(ISNULL(a.Qty, 0))
					FROM dbo.MOSemiFinishedLotAllocation a
					WHERE a.MOItemId = mi.MOItemId
						AND a.DeleteFlag = '0'
						AND a.IsOccupyAllocatedQty = 1
						AND (a.ConfirmStatus = '1' OR (a.ConfirmStatus = '0' AND a.MOId IN (SELECT MOId FROM #MOList)))
				), 0)

		-- 【校验】存在不分批且分配不足的物料行时整体拒绝确认
		IF EXISTS (SELECT 1 FROM #InsufficientAlloc)
		BEGIN
			-- 【收集】不足物料行关联的工单号清单(按工单输入顺序)
			DECLARE @InsufficientAllocMOList nvarchar(max) = ''
			SELECT @InsufficientAllocMOList = ISNULL(@InsufficientAllocMOList + ',', '') + m.MOName
			FROM #MOList m
			WHERE EXISTS (
				SELECT 1
				FROM #InsufficientAlloc ins
				WHERE ins.MOId = m.MOId
			)

			ROLLBACK TRANSACTION ConfirmLot
			IF OBJECT_ID('tempdb..#InsufficientAlloc') IS NOT NULL
				DROP TABLE #InsufficientAlloc
			SET @I_ReturnMessage = N'ServerMessage:[工单号][' + @InsufficientAllocMOList + N']分配数量不足，无法确认！'
			RETURN -1
		END

		-- 【清理】无不足时释放临时表
		IF OBJECT_ID('tempdb..#InsufficientAlloc') IS NOT NULL
			DROP TABLE #InsufficientAlloc

		-- 【写入】批量确认：将当前工单全部未确认记录置为已确认，转为永久占用库存
		-- 【SAP 同步标记】ConfirmStatus 0→1 属于需上报 SAP 的变更，同步置为未同步
		UPDATE a
		SET a.ConfirmStatus = '1',
			a.SAPSyncFlag = '0',
			a.ModifyDate = GETDATE()
		FROM dbo.MOSemiFinishedLotAllocation a
		INNER JOIN #MOList m ON m.MOId = a.MOId
		WHERE a.DeleteFlag = '0'
			AND a.IsOccupyAllocatedQty = 1
			AND a.ConfirmStatus = '0'

		-- =============================================
		-- 【SAP 同步 - 已理货】暂未实现，后续补充；
		-- 实现方式：确认操作完成后（COMMIT 之后），由统一同步逻辑循环调用存在未同步记录
		--          （ConfirmStatus='1' AND SAPSyncFlag='0'）的 MO，按记录状态推导动作上报 SAP；
		--          同步成功置 SAPSyncFlag='1'，失败保持 '0' 等待下次循环补偿，阻断本次确认
		-- 接口过程：dbo.APISyncU_SemiFinishedTallyToSAP
		--   入参示意：按 MO 维度取待同步记录（物料+工厂+仓库+SAP批次+数量+状态），动作=N'已理货'
		--   返回约定：0=同步成功；非 0=同步失败，@SapMsg 为失败原因
		-- =============================================

		-- 【提交】确认成功
		COMMIT TRANSACTION ConfirmLot

		SET @I_ReturnMessage = N'ServerMessage:确认成功!'
		RETURN 0
	END

	-- =============================================
	-- 【删除】按分配记录 ID 逻辑删除预分配记录
	-- =============================================
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

		-- 【取数】读取当前记录状态，用于区分"未确认 / 已理货 / 已扣数"三种形态
		DECLARE @DelConfirmStatus char(1) = '0'			-- 确认状态：0=未确认，1=已确认
		DECLARE @DelIsOccupy bit = 0					-- 是否占用：1=占用，0=不占用(已扣数)
		DECLARE @DelQty decimal(18, 8) = 0				-- 分配数量
		DECLARE @DelMOName nvarchar(50) = ''			-- 工单号(供同步使用)
		DECLARE @DelProductId char(12) = ''				-- 半成品物料(供同步使用)
		DECLARE @DelProductionLotNO varchar(50) = ''	-- SAP/生产批次(供同步使用)
		DECLARE @DelFactoryId char(12) = ''				-- 工厂(供同步/报错使用)
		DECLARE @DelWorkcenterId char(12) = ''			-- 仓库(供同步/报错使用)

		SELECT
			@DelConfirmStatus = a.ConfirmStatus,
			@DelIsOccupy = a.IsOccupyAllocatedQty,
			@DelQty = ISNULL(a.Qty, 0),
			@DelMOName = ISNULL(a.MOName, ''),
			@DelProductId = ISNULL(a.ProductId, ''),
			@DelProductionLotNO = ISNULL(a.ProductionLotNO, ''),
			@DelFactoryId = ISNULL(a.FactoryId, ''),
			@DelWorkcenterId = ISNULL(a.WorkcenterId, '')
		FROM dbo.MOSemiFinishedLotAllocation a
		WHERE a.MOSemiFinishedLotAllocationId = @MOSemiFinishedLotAllocationId
			AND a.DeleteFlag = '0'

		-- 【校验】已扣数记录(已确认 + 已释放占用)不允许取消分配
		-- 说明：已扣数表示 SAP 已完成扣数，取消分配需要回冲 SAP，当前不支持
		IF @DelConfirmStatus = '1' AND @DelIsOccupy = 0
		BEGIN
			ROLLBACK TRANSACTION DeleteLot
			SET @I_ReturnMessage = N'ServerMessage:[批次][' + ISNULL(@DelProductionLotNO, '') + N'][工厂][' + ISNULL(@DelFactoryId, '') + N'][仓库][' + ISNULL(@DelWorkcenterId, '') + N']已扣数，不允许取消分配!'
			RETURN -1
		END

		-- 【写入】取消分配，按记录状态区分处理：
		--   1) 未确认记录(ConfirmStatus='0')：仅逻辑删除并释放占用，不参与全局占用、不触发 SAP 同步；
		--   2) 已理货记录(ConfirmStatus='1' 且 IsOccupyAllocatedQty=1)：逻辑删除但保留占用标记，
		--      最终形态为 ConfirmStatus='1'、IsOccupyAllocatedQty=1、DeleteFlag='1'，需同步 SAP 取消分配。
		-- 【SAP 同步标记】已确认记录被取消属于需上报 SAP 的变更，同步置为未同步（未确认记录本就是'0'，统一置'0'无副作用）
		UPDATE dbo.MOSemiFinishedLotAllocation
		SET DeleteFlag = '1',
			-- 【状态】已理货记录保留占用标记(1)，未确认记录释放占用(0)
			IsOccupyAllocatedQty = CASE WHEN ConfirmStatus = '1' THEN IsOccupyAllocatedQty ELSE 0 END,
			SAPSyncFlag = '0',
			ModifyDate = GETDATE()
		WHERE MOSemiFinishedLotAllocationId = @MOSemiFinishedLotAllocationId
			AND DeleteFlag = '0'

		IF @@ROWCOUNT = 0
		BEGIN
			ROLLBACK TRANSACTION DeleteLot
			SET @I_ReturnMessage = N'ServerMessage:分配记录不存在或已删除!'
			RETURN -1
		END

		-- =============================================
		-- 【SAP 同步 - 取消分配】暂未实现，后续补充；
		-- 触发条件：仅当原记录为已理货(ConfirmStatus='1')时才需上报 SAP 取消分配；
		--           未确认记录取消不触发 SAP 同步（其 SAPSyncFlag 本就是'0'，上报时按状态过滤）。
		-- 实现方式：取消操作完成后（COMMIT 之后），由统一同步逻辑循环调用存在未同步记录
		--          （ConfirmStatus='1' AND SAPSyncFlag='0'）的 MO，按记录状态推导动作上报 SAP；
		--          同步成功置 SAPSyncFlag='1'，失败保持 '0' 等待下次循环补偿，阻断本次取消
		-- 接口过程：dbo.APISyncU_SemiFinishedTallyToSAP
		--   入参示意：MOName、ProductId、FactoryId、WorkcenterId、ProductionLotNO、Qty、动作=N'取消'
		--   返回约定：0=同步成功；非 0=同步失败，@SapMsg 为失败原因
		-- =============================================
	
		-- 【提交】逻辑删除成功
		COMMIT TRANSACTION DeleteLot

		RETURN 0
	END

	-- =============================================
	-- 【写入】将当前工单全部分配记录的允许分批标记整体取反（允许 <-> 取消）
	-- =============================================
	IF @I_Sender = 'AllowBatch'
	BEGIN
		-- 【校验】分配记录 ID 不能为空
		IF ISNULL(@MOSemiFinishedLotAllocationId, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:分配记录不存在或已删除!'
			RETURN -1
		END

		-- 【校验】分配记录必须存在且有效
		IF NOT EXISTS (
			SELECT 1
			FROM dbo.MOSemiFinishedLotAllocation
			WHERE MOSemiFinishedLotAllocationId = @MOSemiFinishedLotAllocationId
				AND DeleteFlag = '0'
		)
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:分配记录不存在或已删除!'
			RETURN -1
		END

		-- 【准备】取当前工单有效分配记录中最高的分批标记作为切换基准
		DECLARE @Allow_batch bit = 0
		SELECT TOP 1 @Allow_batch = Allow_batch
		FROM dbo.MOSemiFinishedLotAllocation
		WHERE MOId IN (
			SELECT MOId
			FROM dbo.MOSemiFinishedLotAllocation
			WHERE MOSemiFinishedLotAllocationId = @MOSemiFinishedLotAllocationId
		)
			AND DeleteFlag = '0'
			AND IsOccupyAllocatedQty = 1
		ORDER BY Allow_batch DESC

		-- 【写入】当前工单有效记录整体取反：允许分批 -> 取消分批，取消分批 -> 允许分批
		UPDATE dbo.MOSemiFinishedLotAllocation
		SET Allow_batch = 1 - ISNULL(@Allow_batch, 0),
			ModifyDate = GETDATE()
		WHERE MOId IN (
			SELECT MOId
			FROM dbo.MOSemiFinishedLotAllocation
			WHERE MOSemiFinishedLotAllocationId = @MOSemiFinishedLotAllocationId
		)
			AND DeleteFlag = '0'
			AND IsOccupyAllocatedQty = 1

		SET @I_ReturnMessage = N'ServerMessage:已允许/取消分批!'
		RETURN 0
	END

	-- 【异常处理】未识别的功能分支统一返回 OrBit 风格错误
	SET @I_ReturnMessage = N'ServerMessage:未知操作!'
	RETURN -1
END
GO
