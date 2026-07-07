-- =============================================
-- Author:		<OrBit Team>
-- Create date: <2026-07-07>
-- Description:	成品工单半成品批次分配 DoMethod
-- Revision: 1.01
-- @I_Sender 分支说明：
--   GetMOProduct     查询工单半成品需求、已分配数量、剩余数量
--   GetInventory     查询半成品可分配批次库存
--   GetAllocatedLots 查询当前工单已分配批次
--   AssignLot        输入 LotSN 自动分配批次
--   DeleteLot        按分配记录 ID 逻辑删除
-- 错误返回：失败时设置 @I_ReturnMessage='ServerMessage:...' 并 RETURN -1
-- =============================================
CREATE PROCEDURE [dbo].[MOSemiFinishedLotAllocationDoMethod]
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
@MOId char(12) = '',							-- 成品工单ID
@MOName nvarchar(50) = '',						-- 成品工单号
@MOItemId char(12) = '',						-- 工单半成品物料行ID
@ProductId char(12) = '',						-- 半成品物料ID
@LotSN nvarchar(100) = '',						-- MES批次号
@MOSemiFinishedLotAllocationId char(12) = ''	-- 半成品批次分配记录ID
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	-- 【初始化】清空输出参数，避免复用调用上下文中的旧错误信息
	SET @I_ReturnMessage = ''
	SET @I_ExceptionFieldName = ''

	DECLARE @ResolvedMOId char(12) = ''              -- GetMOProduct / GetAllocatedLots 解析后的工单 ID
	DECLARE @ResolvedMOName nvarchar(50) = ''          -- GetMOProduct / GetAllocatedLots 解析后的工单号
	DECLARE @AssignMOId char(12) = ''                  -- AssignLot 工单 ID
	DECLARE @AssignMOName nvarchar(50) = ''            -- AssignLot 工单号快照
	DECLARE @AssignProductId char(12) = ''             -- AssignLot 半成品物料 ID
	DECLARE @AssignUOMId char(12) = ''                 -- AssignLot 单位 ID
	DECLARE @AssignWWId char(12) = ''                  -- AssignLot 库存记录 ID
	DECLARE @AssignProductionLotNO varchar(50) = ''      -- AssignLot SAP/生产批次
	DECLARE @AssignFactoryId char(12) = ''             -- AssignLot 工厂 ID
	DECLARE @AssignWorkcenterId char(12) = ''          -- AssignLot 仓库 ID
	DECLARE @AssignCellId char(12) = ''                -- AssignLot 储位 ID
	DECLARE @RequiredQty decimal(18, 8) = 0            -- AssignLot 工单物料需求数量
	DECLARE @RemainQty decimal(18, 8) = 0              -- AssignLot 剩余需求数量
	DECLARE @StockQty decimal(18, 8) = 0               -- AssignLot 批次库存数量
	DECLARE @LotAllocatedQty decimal(18, 8) = 0        -- AssignLot 批次已占用分配数量
	DECLARE @AvailableQty decimal(18, 8) = 0             -- AssignLot 批次可用库存
	DECLARE @AssignQty decimal(18, 8) = 0              -- AssignLot 本次实际分配数量
	DECLARE @InventoryRowCount int = 0                 -- AssignLot 库存表 LotSN 行数校验
	DECLARE @NewMOSemiFinishedLotAllocationId char(12) = '' -- AssignLot 新分配记录 ID

	-- 【查询】查询工单半成品需求，返回需求、已分配和剩余数量
	IF @I_Sender = 'GetMOProduct'
	BEGIN
		SET @ResolvedMOId = ''
		SET @ResolvedMOName = ''

		-- 【校验】工单 ID 与工单号不能同时为空
		IF ISNULL(@MOId, '') = '' AND ISNULL(@MOName, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:请选择有效工单!'
			RETURN -1
		END

		-- 【准备】按工单 ID 优先解析工单，未传 ID 时按工单号解析
		SELECT TOP 1
			@ResolvedMOId = mo.MOId,
			@ResolvedMOName = mo.MOName
		FROM dbo.MO mo
		WHERE (ISNULL(@MOId, '') <> '' AND mo.MOId = @MOId)
			OR (ISNULL(@MOId, '') = '' AND ISNULL(@MOName, '') <> '' AND mo.MOName = @MOName)

		-- 【校验】解析不到有效工单时返回业务提示
		IF ISNULL(@ResolvedMOId, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:请选择有效工单!'
			RETURN -1
		END

		-- 【查询】汇总当前工单半成品物料需求和占用中的预分配数量
		SELECT
			mo.MOId,
			mo.MOName,
			mi.MOItemId,
			mi.ProductId,
			pr.ProductName,
			p.ProductDescription,
			mi.UOMId,
			CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0)) AS RequiredQty,
			CONVERT(decimal(18, 8), ISNULL(alloc.AllocatedQty, 0)) AS AllocatedQty,
			CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(alloc.AllocatedQty, 0)) AS RemainQty,
			mi.LineSequence
		FROM dbo.MOItem mi
		INNER JOIN dbo.MO mo ON mo.MOId = mi.MOId
		INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
		LEFT JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId
		LEFT JOIN (
			-- 【准备】按工单物料行汇总有效占用中的预分配数量
			SELECT
				MOId,
				MOItemId,
				ProductId,
				SUM(ISNULL(Qty, 0)) AS AllocatedQty
			FROM dbo.MOSemiFinishedLotAllocation
			WHERE DeleteFlag = '0'
				AND IsOccupyAllocatedQty = 1
			GROUP BY MOId, MOItemId, ProductId
		) alloc ON alloc.MOId = mi.MOId
			AND alloc.MOItemId = mi.MOItemId
			AND alloc.ProductId = mi.ProductId
		WHERE mi.MOId = @ResolvedMOId
			AND ISNULL(mi.DeleteFlag, '') = ''
			AND mi.LineSequence <> '000'
			AND p.ProductClassify = '2'
		ORDER BY mi.LineSequence, pr.ProductName

		RETURN 0
	END

	-- 【查询】按半成品 ProductId 查询可分配批次库存
	IF @I_Sender = 'GetInventory'
	BEGIN
		-- 【校验】物料 ID 不能为空
		IF ISNULL(@ProductId, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:请选择有效半成品物料!'
			RETURN -1
		END

		-- 【查询】读取正常在库批次；LotSN 唯一性仅约束库存表，分配表按 LotSN 汇总占用数量
		SELECT
			wri.WWId,
			wri.ProductId,
			pr.ProductName,
			p.ProductDescription,
			wri.LotSN,
			wri.ProductionLotNO,
			wri.FactoryId,
			f.FactoryName,
			wri.WorkcenterId,
			w.WorkcenterName,
			wri.CellId,
			c.CellName,
			wri.UOMId,
			CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0)) AS StockQty,
			CONVERT(decimal(18, 8), ISNULL(alloc.AllocatedQty, 0)) AS AllocatedQty,
			CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0) - ISNULL(alloc.AllocatedQty, 0)) AS AvailableQty,
			wri.ProductionDate,
			wri.ValidityEndDate,
			wri.EntryDate
		FROM dbo.WW_RMInventory wri
		INNER JOIN dbo.Product p ON p.ProductId = wri.ProductId
		LEFT JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId
		LEFT JOIN dbo.Factory f ON f.FactoryId = wri.FactoryId
		LEFT JOIN dbo.Workcenter w ON w.WorkcenterId = wri.WorkcenterId
		LEFT JOIN dbo.Cell c ON c.CellId = wri.CellId
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
		ORDER BY wri.EntryDate, wri.LotSN

		RETURN 0
	END

	-- 【查询】查询当前工单已分配的有效批次记录
	IF @I_Sender = 'GetAllocatedLots'
	BEGIN
		SET @ResolvedMOId = ''
		SET @ResolvedMOName = ''

		-- 【校验】工单 ID 与工单号不能同时为空
		IF ISNULL(@MOId, '') = '' AND ISNULL(@MOName, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:请选择有效工单!'
			RETURN -1
		END

		-- 【准备】按工单 ID 优先解析工单，未传 ID 时按工单号解析
		SELECT TOP 1
			@ResolvedMOId = mo.MOId,
			@ResolvedMOName = mo.MOName
		FROM dbo.MO mo
		WHERE (ISNULL(@MOId, '') <> '' AND mo.MOId = @MOId)
			OR (ISNULL(@MOId, '') = '' AND ISNULL(@MOName, '') <> '' AND mo.MOName = @MOName)

		-- 【校验】解析不到有效工单时返回业务提示
		IF ISNULL(@ResolvedMOId, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:请选择有效工单!'
			RETURN -1
		END

		-- 【查询】返回当前工单有效分配记录及物料、库存位置信息
		SELECT
			a.MOSemiFinishedLotAllocationId,
			a.MOId,
			a.MOName,
			a.MOItemId,
			a.ProductId,
			pr.ProductName,
			p.ProductDescription,
			a.WWId,
			a.LotSN,
			a.ProductionLotNO,
			a.FactoryId,
			f.FactoryName,
			a.WorkcenterId,
			w.WorkcenterName,
			a.CellId,
			c.CellName,
			a.UOMId,
			u.UOMName,
			CONVERT(decimal(18, 8), ISNULL(a.Qty, 0)) AS Qty,
			a.IsOccupyAllocatedQty,
			a.CreateUserId,
			a.CreateUserName,
			a.CreateDate,
			a.ModifyDate,
			CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0)) AS StockQty,
			wri.LotStatus,
			wri.IsStorage
		FROM dbo.MOSemiFinishedLotAllocation a
		INNER JOIN dbo.Product p ON p.ProductId = a.ProductId
		LEFT JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId
		LEFT JOIN dbo.Factory f ON f.FactoryId = a.FactoryId
		LEFT JOIN dbo.Workcenter w ON w.WorkcenterId = a.WorkcenterId
		LEFT JOIN dbo.Cell c ON c.CellId = a.CellId
		LEFT JOIN dbo.UOM u ON u.UOMId = a.UOMId
		LEFT JOIN dbo.WW_RMInventory wri ON wri.WWId = a.WWId
		WHERE a.MOId = @ResolvedMOId
			-- 【过滤】只返回有效分配记录
			AND a.DeleteFlag = '0'
		ORDER BY a.CreateDate DESC, a.LotSN

		RETURN 0
	END

	-- 【写入】输入 LotSN 自动分配批次给工单物料行
	IF @I_Sender = 'AssignLot'
	BEGIN
		-- 【初始化】清空 AssignLot 工作变量，避免复用旧值
		SET @AssignMOId = ''
		SET @AssignMOName = ''
		SET @AssignProductId = ''
		SET @AssignUOMId = ''
		SET @AssignWWId = ''
		SET @AssignProductionLotNO = ''
		SET @AssignFactoryId = ''
		SET @AssignWorkcenterId = ''
		SET @AssignCellId = ''
		SET @RequiredQty = 0
		SET @RemainQty = 0
		SET @StockQty = 0
		SET @LotAllocatedQty = 0
		SET @AvailableQty = 0
		SET @AssignQty = 0
		SET @InventoryRowCount = 0
		SET @NewMOSemiFinishedLotAllocationId = ''

		-- 【校验】工单物料行与批次号不能为空
		IF ISNULL(@MOItemId, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:请选择有效半成品物料行!'
			RETURN -1
		END

		IF ISNULL(@LotSN, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:批次不存在或不可分配!'
			RETURN -1
		END

		-- 【校验】工单物料行必须存在、未删除且为半成品
		SELECT
			@AssignMOId = mi.MOId,
			@AssignMOName = mo.MOName,
			@AssignProductId = mi.ProductId,
			@AssignUOMId = mi.UOMId,
			@RequiredQty = CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0))
		FROM dbo.MOItem mi
		INNER JOIN dbo.MO mo ON mo.MOId = mi.MOId
		INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
		WHERE mi.MOItemId = @MOItemId
			AND ISNULL(mi.DeleteFlag, '') = ''
			AND mi.LineSequence <> '000'
			AND p.ProductClassify = '2'

		IF ISNULL(@AssignMOId, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:请选择有效半成品物料行!'
			RETURN -1
		END

		-- 【校验】库存表 LotSN 必须唯一，且批次需正常在库
		SELECT @InventoryRowCount = COUNT(1)
		FROM dbo.WW_RMInventory
		WHERE LotSN = @LotSN

		IF @InventoryRowCount <> 1
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:批次不存在或不可分配!'
			RETURN -1
		END

		SELECT
			@AssignWWId = wri.WWId,
			@StockQty = CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0)),
			@AssignProductionLotNO = wri.ProductionLotNO,
			@AssignFactoryId = wri.FactoryId,
			@AssignWorkcenterId = wri.WorkcenterId,
			@AssignCellId = wri.CellId
		FROM dbo.WW_RMInventory wri
		WHERE wri.LotSN = @LotSN
			AND wri.LotStatus = '1'
			AND wri.IsStorage = 1
			AND ISNULL(wri.Qty, 0) > 0

		IF ISNULL(@AssignWWId, '') = ''
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:批次不存在或不可分配!'
			RETURN -1
		END

		-- 【校验】批次物料必须与工单物料一致
		IF EXISTS (
			SELECT 1
			FROM dbo.WW_RMInventory wri
			WHERE wri.WWId = @AssignWWId
				AND wri.ProductId <> @AssignProductId
		)
		BEGIN
			SET @I_ReturnMessage = N'ServerMessage:批次物料与工单物料不一致!'
			RETURN -1
		END

		-- 【事务】开启分配事务，避免并发重复分配
		BEGIN TRANSACTION AssignLot

		-- 【计算】事务内重新计算工单物料剩余需求
		SELECT @RemainQty = CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(alloc.AllocatedQty, 0))
		FROM dbo.MOItem mi WITH (UPDLOCK, HOLDLOCK)
		LEFT JOIN (
			SELECT
				MOItemId,
				SUM(ISNULL(Qty, 0)) AS AllocatedQty
			FROM dbo.MOSemiFinishedLotAllocation WITH (UPDLOCK, HOLDLOCK)
			WHERE MOId = @AssignMOId
				AND MOItemId = @MOItemId
				AND ProductId = @AssignProductId
				AND DeleteFlag = '0'
				AND IsOccupyAllocatedQty = 1
			GROUP BY MOItemId
		) alloc ON alloc.MOItemId = mi.MOItemId
		WHERE mi.MOItemId = @MOItemId
			AND ISNULL(mi.DeleteFlag, '') = ''
			AND mi.LineSequence <> '000'

		IF ISNULL(@RemainQty, 0) <= 0
		BEGIN
			ROLLBACK TRANSACTION AssignLot
			SET @I_ReturnMessage = N'ServerMessage:当前物料已无剩余需求数量!'
			RETURN -1
		END

		-- 【计算】事务内重新计算批次可用库存
		SELECT @StockQty = CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0))
		FROM dbo.WW_RMInventory wri WITH (UPDLOCK, HOLDLOCK)
		WHERE wri.WWId = @AssignWWId
			AND wri.LotStatus = '1'
			AND wri.IsStorage = 1
			AND ISNULL(wri.Qty, 0) > 0

		IF ISNULL(@StockQty, 0) <= 0
		BEGIN
			ROLLBACK TRANSACTION AssignLot
			SET @I_ReturnMessage = N'ServerMessage:批次不存在或不可分配!'
			RETURN -1
		END

		SELECT @LotAllocatedQty = CONVERT(decimal(18, 8), ISNULL(SUM(ISNULL(Qty, 0)), 0))
		FROM dbo.MOSemiFinishedLotAllocation WITH (UPDLOCK, HOLDLOCK)
		WHERE LotSN = @LotSN
			AND DeleteFlag = '0'
			AND IsOccupyAllocatedQty = 1

		SET @AvailableQty = @StockQty - ISNULL(@LotAllocatedQty, 0)

		IF ISNULL(@AvailableQty, 0) <= 0
		BEGIN
			ROLLBACK TRANSACTION AssignLot
			SET @I_ReturnMessage = N'ServerMessage:当前批次已无可用库存!'
			RETURN -1
		END

		SET @AssignQty = CASE
			WHEN @RemainQty < @AvailableQty THEN @RemainQty
			ELSE @AvailableQty
		END

		-- 【校验】分配数量必须大于 0
		IF ISNULL(@AssignQty, 0) <= 0
		BEGIN
			ROLLBACK TRANSACTION AssignLot
			SET @I_ReturnMessage = N'ServerMessage:当前批次已无可用库存!'
			RETURN -1
		END

		-- 【写入】生成主键并插入预分配记录
		EXEC dbo.SysGetObjectPKId '', 'MOSemiFinishedLotAllocation', @NewMOSemiFinishedLotAllocationId OUTPUT

		IF ISNULL(@NewMOSemiFinishedLotAllocationId, '') = ''
		BEGIN
			ROLLBACK TRANSACTION AssignLot
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
			@NewMOSemiFinishedLotAllocationId,
			@AssignMOId,
			@AssignMOName,
			@MOItemId,
			@AssignProductId,
			@AssignWWId,
			@LotSN,
			@AssignProductionLotNO,
			@AssignFactoryId,
			@AssignWorkcenterId,
			@AssignCellId,
			@AssignUOMId,
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
			ROLLBACK TRANSACTION AssignLot
			SET @I_ReturnMessage = N'ServerMessage:生成分配记录失败!'
			RETURN -1
		END

		-- 【提交】分配写入成功
		COMMIT TRANSACTION AssignLot

		-- 【返回】返回新插入的分配记录
		SELECT
			a.MOSemiFinishedLotAllocationId,
			a.MOId,
			a.MOName,
			a.MOItemId,
			a.ProductId,
			pr.ProductName,
			p.ProductDescription,
			a.WWId,
			a.LotSN,
			a.ProductionLotNO,
			a.FactoryId,
			f.FactoryName,
			a.WorkcenterId,
			w.WorkcenterName,
			a.CellId,
			c.CellName,
			a.UOMId,
			u.UOMName,
			CONVERT(decimal(18, 8), ISNULL(a.Qty, 0)) AS Qty,
			a.IsOccupyAllocatedQty,
			a.CreateUserId,
			a.CreateUserName,
			a.CreateDate,
			a.ModifyDate
		FROM dbo.MOSemiFinishedLotAllocation a
		INNER JOIN dbo.Product p ON p.ProductId = a.ProductId
		LEFT JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId
		LEFT JOIN dbo.Factory f ON f.FactoryId = a.FactoryId
		LEFT JOIN dbo.Workcenter w ON w.WorkcenterId = a.WorkcenterId
		LEFT JOIN dbo.Cell c ON c.CellId = a.CellId
		LEFT JOIN dbo.UOM u ON u.UOMId = a.UOMId
		WHERE a.MOSemiFinishedLotAllocationId = @NewMOSemiFinishedLotAllocationId

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
