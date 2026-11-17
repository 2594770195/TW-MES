SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:        
-- Create date:   <2026/09/29>
-- Description:   <成品理货-指定批次>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[AssignLot_GetLot_Script] 
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

	--
	DECLARE @MOItemId char(12)=''
    DECLARE @ProductId CHAR(12)=''
    DECLARE @MONames nvarchar(max) = ''

    insert into mwjtestlog(src,log1,log3) VALUEs('AssignLot_GetLot_Script',@QueryParameter,@I_ParentPKId)

    DECLARE @SplitPos INT = CHARINDEX('&&', @QueryParameter)
	IF @SplitPos > 0
	BEGIN
		SET @MOItemId = LTRIM(RTRIM(SUBSTRING(@QueryParameter, 1, @SplitPos - 1)))
		SET @MONames = LTRIM(RTRIM(SUBSTRING(@QueryParameter, @SplitPos + 2, LEN(@QueryParameter) - @SplitPos - 1)))
	END
	ELSE
	BEGIN
		return -1 
	END

	SELECT @MOItemId=MOItemId,@ProductId=ProductId FROM MOItem where MOItemId=@MOItemId
    IF ISNULL(@MOItemId,'')=''
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

    -- 【查询】读取正常在库批次；LotSN 唯一性仅约束库存表，分配表按 LotSN 汇总占用数量
	-- 已分配给当前工单物料行的批次排在最前(IsRowSelect=1)，其后为其他可分配批次(IsRowSelect=0)
	SELECT
        CASE WHEN moAlloc.LotSN IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsRowSelect,
		wri.WWId,
        @MOItemId AS MOItemId,
		wri.ProductId,
        f.FactoryName,
		w.WorkcenterName,
		pr.ProductName,
		p.ProductDescription,
		wri.LotSN,
		wri.ProductionLotNO,
        0.0 AS Qty,
		CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0) - ISNULL(alloc.AllocatedQty, 0)) AS 可分配数量,
		CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0)) AS 批次数量,
		CONVERT(decimal(18, 8), ISNULL(alloc.AllocatedQty, 0)) AS 已分配数量,
		CONVERT(decimal(18, 8), ISNULL(moAlloc.MoItemAllocatedQty, 0)) AS 本行已分配数量,
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
            AND (a.ConfirmStatus = '1' OR (a.ConfirmStatus = '0' AND a.MOId IN (SELECT MOId FROM #MOList)))
			AND ISNULL(a.LotSN, '') <> ''
		GROUP BY a.LotSN
	) alloc ON alloc.LotSN = wri.LotSN
	LEFT JOIN (
		-- 【准备】按 LotSN 汇总当前工单物料行有效占用中的预分配数量，用于标记 IsRowSelect
		SELECT
			a.LotSN,
			SUM(ISNULL(a.Qty, 0)) AS MoItemAllocatedQty
		FROM dbo.MOSemiFinishedLotAllocation a
		WHERE a.MOItemId = @MOItemId
			AND a.DeleteFlag = '0'
			AND a.IsOccupyAllocatedQty = 1
            AND (a.ConfirmStatus = '1' OR (a.ConfirmStatus = '0' AND a.MOId IN (SELECT MOId FROM #MOList)))
			AND ISNULL(a.LotSN, '') <> ''
		GROUP BY a.LotSN
	) moAlloc ON moAlloc.LotSN = wri.LotSN
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
		-- 【过滤】返回可分配库存大于 0 的批次，或已分配给当前工单物料行的批次(允许可用为 0，便于回显)
		-- AND (
		-- 	ISNULL(wri.Qty, 0) - ISNULL(alloc.AllocatedQty, 0) > 0
		-- 	OR moAlloc.LotSN IS NOT NULL
		-- )
	-- 【排序】已分配给当前工单物料行的批次优先显示，其后按生产日期升序（先进先出）；
	-- ProductionDate 为 varchar，支持 20260912/2026-09-12 等可识别格式，
	-- 无法转换为日期的记录置为 99991231 排在最后，同日期内再按入库日期、批次号保持稳定排序
	ORDER BY
		CASE WHEN moAlloc.LotSN IS NOT NULL THEN 0 ELSE 1 END,
		ISNULL(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(wri.ProductionDate)), '')), '99991231'),
		wri.EntryDate,
		wri.LotSN
	RETURN 0
END

GO
