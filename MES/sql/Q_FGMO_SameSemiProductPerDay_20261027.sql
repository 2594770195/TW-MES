/* ================================================================
   查询主题：成品工单同一天使用同一个半成品物料的情况
   输出列  ：计划开始日期 / 半成品物料 / 使用次数（附涉及工单数、工单清单便于核对）
   数据库  ：OrBitMOM（生产库）或 OrBitMOMTestBack_WMSQAS（开发库）
   ----------------------------------------------------------------
   口径说明（与现有脚本保持一致，如需调整见文末注释）：
     1) 成品工单 ：dbo.MO 且成品工单号以 2 开头（MOName LIKE '2%'），
                   与 AssignLot_GetLot_Script、MOSemiFinishedLotAllocationBatchDoMethod
                   等成品工单半成品理货脚本的判定写法一致；
                   返工工单（工单号以 7 结尾）不在此列。
     2) 使用     ：成品工单 BOM 中的半成品物料行（dbo.MOItem），
                   半成品判定 = Product.ProductClassify = '2'（与报表 zpp12 口径一致）；
                   一条物料行 = 一次使用（不区分是否已投料 / 已理货分配）。
     3) 同一天   ：MO.PlannedDateFrom（工单计划开始日期）取日期部分分组。
     4) 使用次数 ：COUNT(*) 使用记录条数（工单物料行条数）。
     5) 默认只输出同一天同一半成品被使用 2 次及以上的组合（HAVING COUNT(*) > 1），
        需要查看全部组合时删除该 HAVING 条件。
   涉及表：dbo.MO、dbo.MOItem、dbo.Product、dbo.ProductRoot
   ================================================================ */

-- 【入参】过滤条件，不需要过滤时保持 NULL / '' 即可
DECLARE @DateFrom    date         = NULL;   -- 计划开始日期起（含），NULL = 不限
DECLARE @DateTo      date         = NULL;   -- 计划开始日期止（含），NULL = 不限
DECLARE @ProductName nvarchar(50) = N'';    -- 半成品物料编号，'' = 不限

;WITH BaseData AS (
    -- 【准备】成品工单 + 半成品物料行明细基础集，一行 = 一次使用
    SELECT
        CONVERT(date, mo.PlannedDateFrom) AS PlanDate,            -- 工单计划开始日期（按天）
        mi.ProductId                      AS ProductId,           -- 半成品物料 ID（分组主键）
        pr2.ProductName                   AS ProductName,         -- 半成品物料编号
        p2.ProductDescription             AS ProductDescription,  -- 半成品物料描述
        mo.MOName                         AS MOName               -- 成品工单号（同工单多条物料行会重复出现）
    FROM dbo.MO mo
        -- 【关联】成品工单 → 工单物料行 → 物料 → 物料编号 / 描述
        INNER JOIN dbo.MOItem     mi  ON mi.MOId = mo.MOId
        INNER JOIN dbo.Product    p2  ON p2.ProductId = mi.ProductId
        INNER JOIN dbo.ProductRoot pr2 ON pr2.ProductRootId = p2.ProductRootId
    WHERE
        -- 【过滤】成品工单：工单号以 2 开头
        mo.MOName LIKE '2%'
        -- 【过滤】排除已逻辑删除的工单与物料行，排除工单占位物料行(LineSequence='000')
        AND ISNULL(mo.DeleteFlag, '') <> '1'
        AND ISNULL(mi.DeleteFlag, '') <> '1'
        AND ISNULL(mi.LineSequence, '') <> '000'
        -- 【过滤】只统计半成品物料（ProductClassify='2'）
        AND RTRIM(ISNULL(p2.ProductClassify, '')) = '2'
        -- 【过滤】计划开始日期为空的行无法按天归组，直接排除（边界处理）
        AND mo.PlannedDateFrom IS NOT NULL
        -- 【过滤】可选时间范围
        AND (@DateFrom IS NULL OR CONVERT(date, mo.PlannedDateFrom) >= @DateFrom)
        AND (@DateTo   IS NULL OR CONVERT(date, mo.PlannedDateFrom) <= @DateTo)
        -- 【过滤】可选半成品物料编号
        AND (@ProductName = N'' OR pr2.ProductName = @ProductName)
)
SELECT
    b.PlanDate                    AS 计划开始日期,
    b.ProductName                 AS 半成品物料编码,
    MAX(b.ProductDescription)     AS 半成品物料描述,
    -- 【使用次数】该日期下该半成品物料被成品工单使用的记录条数（工单物料行条数）
    COUNT(*)                      AS 使用次数,
    COUNT(DISTINCT b.MOName)      AS 涉及成品工单数,
    -- 【工单清单】同一天使用该半成品物料的成品工单号，用 FOR XML 拼接（兼容低版本 SQL Server）
    STUFF((
        SELECT N',' + x.MOName
        FROM BaseData x
        WHERE x.PlanDate = b.PlanDate
          AND x.ProductId = b.ProductId
        ORDER BY x.MOName
        FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 1, N'') AS 成品工单清单
FROM BaseData b
GROUP BY
    b.PlanDate,
    b.ProductId,
    b.ProductName
-- 【过滤】只保留同一天同一半成品物料被使用 2 次及以上的组合
HAVING COUNT(*) > 1
ORDER BY
    计划开始日期 DESC,
    使用次数 DESC,
    半成品物料编码;

/* ================================================================
   调整说明：
   1) 若成品工单另有判定口径（如按工单产出物料分类判断），可把
      `mo.MOName LIKE '2%'` 替换为：
        INNER JOIN dbo.Product p1 ON p1.ProductId = mo.ProductId
        AND RTRIM(ISNULL(p1.ProductClassify, '')) = '1'
   2) 若只想统计仍未完工的工单，可追加：AND mo.MOStates = '20'。
   3) 若“同一天”改按工单实际投料 / 理货发生日，则日期字段改用
      MOItemLot.CreateDate（投料）或 MOSemiFinishedLotAllocation.CreateDate（理货）。
   ================================================================ */
