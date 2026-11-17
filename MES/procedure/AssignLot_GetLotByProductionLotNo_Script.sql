SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		
-- Create date:   <2026/10/27>
-- Description:   <成品理货-指定批次（按 物料+工厂+仓库+SAP批次 四维度返回可分配批次网格）>
-- Rev: 2.00
-- Update comment:
--   由 v1.00 从 ProductId + ProductionLotNO 两维度，
--   升级为 ProductId + FactoryId + WorkcenterId + ProductionLotNO 四维度（与理货主流程 / 手工指定 / PDA 扣数口径对齐）。
--   同一 SAP 批次分布在多个工厂 / 仓库时，网格拆成多行、各自独立数量与占用。
-- Update date:   <2026/11/12>
-- =============================================
create PROCEDURE [dbo].[AssignLot_GetLotByProductionLotNo_Script] 
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKId char(12)='',				--主键ID
@I_ParentPKId char(12)='',			--父元对象主键ID
@QueryParameter nvarchar(100)=''
--以上变量为系统服务固定接口参数，在脚本对话框网格必须提供

AS
BEGIN

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	-- 【初始化】入参快照
	DECLARE @MOItemId char(12)=''
    DECLARE @ProductId CHAR(12)=''
    DECLARE @MONames nvarchar(max) = ''
    -- 【工厂口径】理货只能分配与工单工厂对应的库存工厂
    DECLARE @MOFactoryName nvarchar(50) = ''		-- 当前工单所属工厂名称
    DECLARE @StockFactoryName nvarchar(50) = ''		-- 允许分配的库存工厂名称
    DECLARE @StockFactoryId char(12) = ''			-- 允许分配的库存工厂 ID

    DECLARE @SplitPos INT = CHARINDEX('&&', @QueryParameter)
	-- 【校验】参数格式必须为 MOItemId&&MONames
	IF ISNULL(@QueryParameter, '') = '' OR @SplitPos <= 0
	BEGIN
		RETURN -1
	END

	SET @MOItemId = LTRIM(RTRIM(SUBSTRING(@QueryParameter, 1, @SplitPos - 1)))
	SET @MONames = LTRIM(RTRIM(SUBSTRING(@QueryParameter, @SplitPos + 2, LEN(@QueryParameter) - @SplitPos - 1)))

	-- 【校验】工单物料行 ID 不能为空
	IF ISNULL(@MOItemId, '') = ''
	BEGIN
		RETURN -1
	END

	-- 【取值】取物料行对应的半成品物料ID及所属工单工厂
	SELECT
		@MOItemId = mi.MOItemId,
		@ProductId = mi.ProductId,
		@MOFactoryName = f.FactoryName
	FROM dbo.MOItem mi
		LEFT JOIN dbo.MO mo ON mo.MOId = mi.MOId
		LEFT JOIN dbo.Factory f ON f.FactoryId = mo.FactoryId
	WHERE mi.MOItemId = @MOItemId

    IF ISNULL(@MOItemId, '') = ''
    BEGIN
		RETURN -1
    END

	-- 【校验】物料ID必须有效，否则无法查询批次
	IF ISNULL(@ProductId, '') = ''
	BEGIN
		RETURN -1
	END

	-- 【校验】工单必须维护工厂，否则无法判断可分配的库存工厂
	IF ISNULL(@MOFactoryName, '') = ''
	BEGIN
		RETURN -1
	END

	-- 【工厂口径】工单工厂 -> 允许分配的库存工厂：
	--   工单工厂为 9502 / 9304 时，只能分配 9502 的库存；
	--   工单工厂为 9302 时，只能分配 9302 的库存；
	--   其他工厂按同名工厂分配
	SET @StockFactoryName = CASE
		WHEN @MOFactoryName IN (N'9502', N'9304') THEN N'9502'
		WHEN @MOFactoryName = N'9302' THEN N'9302'
		ELSE @MOFactoryName
	END

	SET @StockFactoryId = ''
	SELECT @StockFactoryId = FactoryId
	FROM dbo.Factory
	WHERE FactoryName = @StockFactoryName

	-- 【校验】对应库存工厂必须存在
	IF ISNULL(@StockFactoryId, '') = ''
	BEGIN
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
                -- 【校验】仅解析长度为 10 的工单号片段
                IF LEN(@segment) = 10
                BEGIN
                    SET @NameSeq = @NameSeq + 1
                    -- 【校验】同一工单号只保留首次出现的顺序
                    IF NOT EXISTS (SELECT 1 FROM #MONameList WHERE MOName = @segment)
                        INSERT INTO #MONameList(Seq,MOName) VALUES (@NameSeq,@segment);
                END
                SET @pos = @pos + 10;
            END
    END
    -- 【准备】#MOList：把工单号解析为有效工单 ID 清单，供占用统计引用
	SELECT
		l.Seq,
		l.MOName,
		MIN(mo.MOId) AS MOId
	INTO #MOList
	FROM #MONameList l
	INNER JOIN dbo.MO mo ON mo.MOName = l.MOName
		AND mo.MOName LIKE '2%'
	GROUP BY l.Seq, l.MOName

    -- 【查询】按 物料 + 工厂 + 仓库 + SAP批次 四维度汇总正常在库库存；
    -- 同一 SAP 批次跨工厂 / 跨仓库拆成多行，各自独立可分配数量与占用
	;WITH
	-- 【汇总】按四字段汇总库存数量与最早生产日期 / 入库日期
	InvAgg AS (
		SELECT
			wri.ProductId,
			wri.FactoryId,
			wri.WorkcenterId,
			wri.ProductionLotNO,
			SUM(ISNULL(wri.Qty, 0)) AS StockQty,
			COUNT(1) AS LotSNCount,
			MIN(ISNULL(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(wri.ProductionDate)), '')), '99991231')) AS FirstProductionDate,
			MIN(wri.EntryDate) AS FirstEntryDate
		FROM dbo.WW_RMInventory wri
		WHERE wri.ProductId = @ProductId
			AND wri.FactoryId = @StockFactoryId		-- 【工厂口径】只取工单允许分配的库存工厂
			AND wri.LotStatus = '1'
			AND wri.IsStorage = 1
			AND ISNULL(wri.Qty, 0) > 0
			AND ISNULL(wri.ProductionLotNO, '') <> ''
		GROUP BY
			wri.ProductId,
			wri.FactoryId,
			wri.WorkcenterId,
			wri.ProductionLotNO
	),
	-- 【代表行】按四字段分区，取该维度最早入库行作为网格行标识
	InvRep AS (
		SELECT
			wri.WWId,
			wri.ProductId,
			wri.FactoryId,
			wri.WorkcenterId,
			wri.ProductionLotNO,
			wri.LotSN,
			wri.QCStatus,
			wri.SAPRemark,
			wri.HoldResult,
			wri.ValidityEndDate,
			wri.MOId,
			ROW_NUMBER() OVER (
				PARTITION BY wri.ProductId, wri.FactoryId, wri.WorkcenterId, wri.ProductionLotNO
				ORDER BY wri.EntryDate, wri.ProductionDate, wri.WWId
			) AS rn
		FROM dbo.WW_RMInventory wri
		WHERE wri.ProductId = @ProductId
			AND wri.FactoryId = @StockFactoryId		-- 【工厂口径】代表行同样限定工单允许分配的库存工厂
			AND wri.LotStatus = '1'
			AND wri.IsStorage = 1
			AND ISNULL(wri.Qty, 0) > 0
			AND ISNULL(wri.ProductionLotNO, '') <> ''
	),
	-- 【全局占用】按四字段汇总已确认 + 本单未确认的预分配数量，用于扣减可用库存
	Alloc AS (
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
		GROUP BY
			a.ProductId,
			a.FactoryId,
			a.WorkcenterId,
			a.ProductionLotNO
	),
	-- 【本行已分配】按四字段汇总当前工单物料行的有效占用，用于标记 IsRowSelect
	MoAlloc AS (
		SELECT
			a.ProductId,
			a.FactoryId,
			a.WorkcenterId,
			a.ProductionLotNO,
			SUM(ISNULL(a.Qty, 0)) AS MoItemAllocatedQty
		FROM dbo.MOSemiFinishedLotAllocation a
		WHERE a.MOItemId = @MOItemId
			AND a.DeleteFlag = '0'
			AND a.IsOccupyAllocatedQty = 1
			AND (a.ConfirmStatus = '1' OR (a.ConfirmStatus = '0' AND a.MOId IN (SELECT MOId FROM #MOList)))
			AND ISNULL(a.ProductionLotNO, '') <> ''
		GROUP BY
			a.ProductId,
			a.FactoryId,
			a.WorkcenterId,
			a.ProductionLotNO
	)
	SELECT
		CASE WHEN ISNULL(MoAlloc.MoItemAllocatedQty, 0) > 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsRowSelect,
		InvRep.WWId												AS WWId,
		@MOItemId												AS MOItemId,
		InvAgg.ProductId										AS ProductId,
		InvAgg.FactoryId										AS FactoryId,
		InvAgg.WorkcenterId										AS WorkcenterId,
		f.FactoryName											AS FactoryName,
		w.WorkcenterName										AS WorkcenterName,
		pr.ProductName											AS ProductName,
		p.ProductDescription									AS ProductDescription,
		InvAgg.ProductionLotNO									AS ProductionLotNO,
		0.0														AS Qty,
		CONVERT(decimal(18, 8), ISNULL(InvAgg.StockQty, 0) - ISNULL(Alloc.AllocatedQty, 0))	AS 可分配数量,
		CONVERT(decimal(18, 8), ISNULL(InvAgg.StockQty, 0))									AS 批次数量,
		CONVERT(decimal(18, 8), ISNULL(Alloc.AllocatedQty, 0))								AS 已分配数量,
		CONVERT(decimal(18, 8), ISNULL(MoAlloc.MoItemAllocatedQty, 0))						AS 本行已分配数量,
		MIN(ISNULL(pi.lockqty, 0))								AS lockqty,
		MIN(ISNULL(pi.limitQty, 0))								AS limitQty,
		InvAgg.FirstProductionDate								AS ProductionDate,
		InvAgg.FirstEntryDate									AS EntryDate,
		InvRep.ValidityEndDate									AS ValidityEndDate,
		InvRep.SAPRemark										AS SAPRemark,
		MIN(pi.Note)											AS 'SAP备注',
		InvRep.HoldResult										AS '锁定原因',
		MIN(MO.NoteMessage)										AS '生产备注信息'
	FROM InvAgg
	INNER JOIN InvRep
		ON InvAgg.ProductId = InvRep.ProductId
		AND InvAgg.FactoryId = InvRep.FactoryId
		AND InvAgg.WorkcenterId = InvRep.WorkcenterId
		AND InvAgg.ProductionLotNO = InvRep.ProductionLotNO
		AND InvRep.rn = 1
	INNER JOIN dbo.Product p
		ON p.ProductId = InvAgg.ProductId
	LEFT JOIN dbo.ProductRoot pr
		ON pr.ProductRootId = p.ProductRootId
	LEFT JOIN dbo.Factory f
		ON f.FactoryId = InvAgg.FactoryId
	LEFT JOIN dbo.Workcenter w
		ON w.WorkcenterId = InvAgg.WorkcenterId
	-- 【准备】SAP 备注 / 锁定量 / 限额：按 ProductId + LotSN + WorkcenterId 去重后关联
	-- 同一工厂 + 仓库 下 SAP 批次 = ProductionLotNO，匹配 pi.LotSN = ProductionLotNO
	LEFT JOIN (
		SELECT
			pi.ProductId,
			pi.LotSN,
			pi.WorkcenterId,
			MIN(pi.Note) AS Note,
			ISNULL(SUM(pi.LockQty), 0)            AS lockqty,
			ISNULL(SUM(pi.limitQty), 0)           AS limitQty,
			ISNULL(SUM(pi.ProductInventoryNum), 0) AS ProductInventoryNum
		FROM dbo.ProductInventory pi
		WHERE pi.DeleteFlag = '0'
		GROUP BY pi.ProductId, pi.LotSN, pi.WorkcenterId
	) pi
		ON pi.ProductId = InvAgg.ProductId
		AND pi.WorkcenterId = InvAgg.WorkcenterId
		AND pi.LotSN = InvAgg.ProductionLotNO
	LEFT JOIN dbo.MO
		ON MO.MOId = InvRep.MOId
	LEFT JOIN Alloc
		ON Alloc.ProductId = InvAgg.ProductId
		AND Alloc.FactoryId = InvAgg.FactoryId
		AND Alloc.WorkcenterId = InvAgg.WorkcenterId
		AND Alloc.ProductionLotNO = InvAgg.ProductionLotNO
	LEFT JOIN MoAlloc
		ON MoAlloc.ProductId = InvAgg.ProductId
		AND MoAlloc.FactoryId = InvAgg.FactoryId
		AND MoAlloc.WorkcenterId = InvAgg.WorkcenterId
		AND MoAlloc.ProductionLotNO = InvAgg.ProductionLotNO
	GROUP BY
		InvAgg.ProductId,
		InvAgg.FactoryId,
		InvAgg.WorkcenterId,
		InvAgg.ProductionLotNO,
		f.FactoryName,
		w.WorkcenterName,
		pr.ProductName,
		p.ProductDescription,
		InvAgg.FirstProductionDate,
		InvAgg.FirstEntryDate,
		InvRep.WWId,
		InvRep.SAPRemark,
		InvRep.HoldResult,
		InvRep.ValidityEndDate,
		InvAgg.StockQty,
		Alloc.AllocatedQty,
		MoAlloc.MoItemAllocatedQty
	-- 【排序】已分配给当前工单物料行的生产批次优先显示，其后按生产日期升序（先进先出）；
	-- FirstProductionDate 已在 InvAgg 中转换为 date 类型，保证同日期内入库日期再升序；
	-- FactoryId、WorkcenterId 作为同批次多行的稳定排序尾键，确保每次刷新行序一致
	ORDER BY
		CASE WHEN ISNULL(MoAlloc.MoItemAllocatedQty, 0) > 0 THEN 0 ELSE 1 END,
		InvAgg.FirstProductionDate,
		InvAgg.FirstEntryDate,
		InvAgg.FactoryId,
		InvAgg.WorkcenterId,
		InvAgg.ProductionLotNO
	RETURN 0
END

GO
