-- =============================================
-- 报表 zpp12：成品工单半成品理货 / 缺料分析
-- 数据库：OrBitMOMTestBack
-- 行粒度：成品工单 + 工单物料行(半成品) + 销售单行
-- 说明：
--   1) 已理货：取自 dbo.MOSemiFinishedLotAllocation（成品理货-指定批次 生成的预分配记录），
--      按工单 + 工单物料行 + 物料 汇总理货数量。
--      口径：DeleteFlag='0'（未逻辑删除）、IsOccupyAllocatedQty=1（占用中，删除时置 0 释放）、
--            ConfirmStatus='1'（已确认）。
--   2) 半制品MO1~MO5：生产当前物料行物料(mi.ProductId)的生产订单，关联关系 sf.ProductId = mi.ProductId，
--      按计划开始日期升序最多展示 5 条；排除当前成品工单自身与已逻辑删除工单。
--      MOn数量 = 工单需求数量 MOQtyRequired；MOn基本开始日期 = 计划开始日期 PlannedDateFrom。
--   3) 预留数量 = 当前物料在"全部未完工工单"物料行上的需求总量
--            = Σ(MOItem.ItemQtyRequired - MOItem.ItemQtyIssued + MOItem.ItemQtyBack)，不限本工单；
--      欠料数量 = 全部未完工工单预留总量 - 当前正常状态库存数量；
--      超期数量 = 当前正常状态库存中已超过有效期的数量；
--      可用量   = 当前正常状态库存数量 - 超期数量；
--      领用数量 = 本工单物料行已领用数量 - 已退料数量。
--      正常状态库存取自 dbo.ProductInventory：DeleteFlag<>'1'，数量取 ProductInventoryNum（不扣减冻结/待检数），
--      按物料 mi.ProductId 汇总；有效期 = StorageDate(入库日期) + Product.SafeStorageTime(安全存储天数)，
--      存储天数为 0/NULL 或 StorageDate 无法解析时视为无有效期，不计超期。
--      全部工单只统计未完工工单：MOStates='20'（已审核/在制）。
--   4) 在途数 = 对应物料的半制品生产订单（生产该物料的工单）的工单需求数量合计，
--      口径与半制品MO1~MO5一致：生产该物料的工单、排除已逻辑删除工单、SAPMOStates='下达'，
--      不限展示条数，全部符合条件的工单需求数量求和；无记录时按 0 处理。
--      净用量 = 正常状态库存数量 - 已理货数量（同物料在本工单物料行口径）；
--      预计到料期暂以 '' 占位，待后续补数规则确认后再填充。
--   5) TOP 10 为试跑行数限制，正式报表可去掉 TOP 10 或改为按条件分页。
--   6) 过滤：已理货数量 >= 工单物料行需求数量(MOItem.ItemQtyRequired)时，视为已满足需求，不输出该行。
-- =============================================
DECLARE @FactoryName NVARCHAR(100)='',
@ProductName NVARCHAR(100)='',
@WorkcenterName NVARCHAR(100)='',
@MoName NVARCHAR(20)='',
@SoName NVARCHAR(20)='5260224937'

 SELECT TOP 1000
        f.FactoryName                        AS 工厂,          -- 工厂名称
        pr1.ProductName                      AS 产品编号,      -- 成品产品编号
        p1.ProductDescription                 AS 产品描述,      -- 成品产品描述
        mo.MOName                            AS 生产订单,      -- 成品生产订单号
        -- 【已理货】当前工单物料行在半成品批次分配表中的有效占用理货数量
        CONVERT(decimal(18, 6), ISNULL(alloc.AllocatedQty, 0)) AS 已理货,
        -- 【净用量】正常状态库存数量(inv.StockQty) - 已理货数量(alloc.AllocatedQty)，无记录时按 0 参与计算
        CONVERT(decimal(18, 6), ISNULL(inv.StockQty, 0) - ISNULL(alloc.AllocatedQty, 0)) AS 净用量,
        pr2.ProductName                      AS 物料编码,      -- 半成品/物料编号
        p2.ProductDescription                 AS 物料名称,      -- 半成品/物料描述
        -- 【在途数】对应物料的半制品生产订单（生产该物料的工单）的工单需求数量合计，不限展示条数
        CONVERT(decimal(18, 6), ISNULL(sfmo.MOQtyTotal, 0)) AS 在途数,
        -- 【预留数量】当前物料在"全部未完工工单"物料行上的需求总量 = Σ(需求数量 - 已领用数量 + 已退料数量)
        CONVERT(decimal(18, 6), ISNULL(req.ReserveQty, 0)) AS 预留数量,
        -- 【领用数量】本工单物料行已领用数量 - 已退料数量
        CONVERT(decimal(18, 6), ISNULL(mi.ItemQtyIssued, 0) - ISNULL(mi.ItemQtyBack, 0)) AS 领用数量,
        -- 【欠料数量】全部未完工工单预留总量 - 当前正常状态库存数量；不欠料(差值<=0，库存充足)时显示 0
        CONVERT(decimal(18, 6), CASE WHEN ISNULL(req.ReserveQty, 0) - ISNULL(inv.StockQty, 0) > 0
                                    THEN ISNULL(req.ReserveQty, 0) - ISNULL(inv.StockQty, 0)
                                    ELSE 0 END) AS 欠料数量,
        -- 【超期数量】正常状态库存中已超过有效期的数量（有效期 = StorageDate + SafeStorageTime 天）
        CONVERT(decimal(18, 6), ISNULL(inv.ExpiredQty, 0)) AS 超期数量,
        -- 【可用量】正常状态库存数量 - 超期数量
        CONVERT(decimal(18, 6), ISNULL(inv.StockQty, 0) - ISNULL(inv.ExpiredQty, 0)) AS 可用量,
        '' AS 预计到料期,
        mo.SOName                            AS 销售单号,      -- 销售订单号
        so.SODescription                     AS 客户采购单号,  -- 客户采购单号
        si.RequiredDate                      AS 交货单出货日期,-- 销售单行的需求(出货)日期
        -- 【半制品工单】生产当前物料行物料的生产订单，按计划开始日期升序最多展示 5 条
        ISNULL(sfmo.MO1Name, '') AS 半制品MO1,
        CONVERT(decimal(18, 6), ISNULL(sfmo.MO1Qty, 0)) AS MO1数量,
        sfmo.MO1Date             AS MO1基本开始日期,
        ISNULL(sfmo.MO2Name, '') AS 半制品MO2,
        CONVERT(decimal(18, 6), ISNULL(sfmo.MO2Qty, 0)) AS MO2数量,
        sfmo.MO2Date             AS MO2基本开始日期,
        ISNULL(sfmo.MO3Name, '') AS 半制品MO3,
        CONVERT(decimal(18, 6), ISNULL(sfmo.MO3Qty, 0)) AS MO3数量,
        sfmo.MO3Date             AS MO3基本开始日期,
        ISNULL(sfmo.MO4Name, '') AS 半制品MO4,
        CONVERT(decimal(18, 6), ISNULL(sfmo.MO4Qty, 0)) AS MO4数量,
        sfmo.MO4Date             AS MO4基本开始日期,
        ISNULL(sfmo.MO5Name, '') AS 半制品MO5,
        CONVERT(decimal(18, 6), ISNULL(sfmo.MO5Qty, 0)) AS MO5数量,
        sfmo.MO5Date             AS MO5基本开始日期
    FROM dbo.MO mo
        -- 【关联】成品工单 → 成品物料 → 产品编号 → 工厂
        INNER JOIN dbo.Product p1      ON p1.ProductId = mo.ProductId
        INNER JOIN dbo.ProductRoot pr1 ON pr1.ProductRootId = p1.ProductRootId
        INNER JOIN dbo.Factory f       ON f.FactoryId = mo.FactoryId
        -- 【关联】成品工单 → 工单物料行(半成品/物料) → 物料编号与物料描述
        -- 物料行用 INNER JOIN：物料行或对应物料缺失时该行无意义，且会放大为笛卡尔行
        INNER JOIN dbo.MOItem mi       ON mi.MOId = mo.MOId 
        INNER JOIN dbo.Product p2      ON p2.ProductId = mi.ProductId
        INNER JOIN dbo.ProductRoot pr2 ON pr2.ProductRootId = p2.ProductRootId
        -- 【关联】工单 → 销售单 → 销售单行
        -- 工单 SoItemSequence 与销售单行 ItemSequence 均可能为空或非数字，用 TRY_CONVERT 避免转换报错
        INNER JOIN dbo.SO so           ON so.SOName = mo.SOName
        INNER JOIN dbo.SOItem si       ON si.SOId = so.SOId
                                    AND TRY_CONVERT(int, si.ItemSequence) = TRY_CONVERT(int, mo.SoItemSequence)
        -- 【汇总】当前工单物料行的已理货数量（无记录时 SUM 返回 NULL，外层 ISNULL 兜底为 0）
        OUTER APPLY (
            SELECT SUM(ISNULL(a.Qty, 0)) AS AllocatedQty
            FROM dbo.MOSemiFinishedLotAllocation a
            WHERE a.DeleteFlag = '0'                -- 仅统计未逻辑删除的记录
            AND a.IsOccupyAllocatedQty = 1        -- 仅统计占用中的记录（删除时置 0 释放）
            AND a.ConfirmStatus = '1'             -- 仅统计已确认的理货记录
            AND a.MOId = mo.MOId                  -- 限定当前成品工单
            AND a.MOItemId = mi.MOItemId          -- 限定当前工单物料行
            AND a.ProductId = mi.ProductId        -- 限定当前物料
        ) alloc
        -- 【汇总】当前物料行物料的库存数量（ProductInventory，半成品/成品库存）
        -- 正常状态库存：DeleteFlag<>'1' 的记录，取 ProductInventoryNum（冻结数量、待检数不扣减）
        -- 有效期 = 入库日期 StorageDate(格式 yyyy-MM-dd) + 物料安全存储天数 SafeStorageTime
        -- 存储期为 0/NULL、或 StorageDate 无法解析时视为无有效期，不计超期
        -- 注意：SafeStorageTime 在 APPLY 内部通过 pp 自关联取值，不能直接在聚合表达式里引用外层 p2，
        --       否则 SQL Server 报 8124（聚合表达式含多个列的外部引用）
        OUTER APPLY (
            SELECT
                SUM(ISNULL(w.ProductInventoryNum, 0)) AS StockQty,               -- 正常状态库存数量
                SUM(CASE WHEN ISNULL(pp.SafeStorageTime, 0) > 0
                        AND DATEADD(day, pp.SafeStorageTime, TRY_CONVERT(date, w.StorageDate)) < CAST(GETDATE() AS date)
                        THEN ISNULL(w.ProductInventoryNum, 0) ELSE 0 END) AS ExpiredQty  -- 其中已超期数量
            FROM dbo.ProductInventory w
                INNER JOIN dbo.Product pp ON pp.ProductId = w.ProductId   -- 取该物料的安全存储天数
            WHERE w.ProductId = mi.ProductId        -- 只统计当前物料行对应的物料
            AND ISNULL(w.DeleteFlag, '') <> '1'   -- 排除已逻辑删除的库存记录
            AND w.FactoryId = mo.FactoryId
        ) inv
        -- 【汇总】当前物料在"全部工单"物料行上的预留(需求)总量，不限于本工单
        -- 口径：Σ(ItemQtyRequired - ItemQtyIssued + ItemQtyBack)，只统计未完工工单(SAPMOStates = '下达' )
        OUTER APPLY (
            SELECT SUM(ISNULL(d.ItemQtyRequired, 0) - ISNULL(d.ItemQtyIssued, 0) + ISNULL(d.ItemQtyBack, 0)) AS ReserveQty
            FROM dbo.MOItem d
                INNER JOIN dbo.MO dm ON dm.MOId = d.MOId
            WHERE d.ProductId = mi.ProductId           -- 同一物料
            AND ISNULL(d.LineSequence, '') <> '000'  -- 排除工单占位物料行
            AND ISNULL(d.DeleteFlag, '') <> '1'      -- 排除已逻辑删除的物料行
            AND ISNULL(dm.DeleteFlag, '') <> '1'     -- 排除已逻辑删除的工单
            AND dm.SAPMOStates = '下达'               
        ) req
        -- 【汇总】当前物料行对应物料的半制品生产订单（半制品MO1~MO5 与 在途数）
        -- 关联关系：半制品工单.ProductId = mi.ProductId
        -- MOQtyTotal：全部符合条件的半制品工单需求数量合计（用于在途数），不受展示条数限制；
        -- MO1~MO5：按计划开始日期升序编号，只取前 5 条；无记录时聚合仍返回一行，字段为 NULL 由外层兜底
        OUTER APPLY (
            SELECT
                SUM(t.MOQty)                              AS MOQtyTotal,
                MAX(CASE WHEN t.rn = 1 THEN t.MOName END) AS MO1Name,
                MAX(CASE WHEN t.rn = 1 THEN t.MOQty END)  AS MO1Qty,
                MAX(CASE WHEN t.rn = 1 THEN t.MOPlanDate END) AS MO1Date,
                MAX(CASE WHEN t.rn = 2 THEN t.MOName END) AS MO2Name,
                MAX(CASE WHEN t.rn = 2 THEN t.MOQty END)  AS MO2Qty,
                MAX(CASE WHEN t.rn = 2 THEN t.MOPlanDate END) AS MO2Date,
                MAX(CASE WHEN t.rn = 3 THEN t.MOName END) AS MO3Name,
                MAX(CASE WHEN t.rn = 3 THEN t.MOQty END)  AS MO3Qty,
                MAX(CASE WHEN t.rn = 3 THEN t.MOPlanDate END) AS MO3Date,
                MAX(CASE WHEN t.rn = 4 THEN t.MOName END) AS MO4Name,
                MAX(CASE WHEN t.rn = 4 THEN t.MOQty END)  AS MO4Qty,
                MAX(CASE WHEN t.rn = 4 THEN t.MOPlanDate END) AS MO4Date,
                MAX(CASE WHEN t.rn = 5 THEN t.MOName END) AS MO5Name,
                MAX(CASE WHEN t.rn = 5 THEN t.MOQty END)  AS MO5Qty,
                MAX(CASE WHEN t.rn = 5 THEN t.MOPlanDate END) AS MO5Date
            FROM (
                SELECT
                    sf.MOName,
                    ISNULL(sf.MOQtyRequired, 0) AS MOQty,                      -- MO 数量取工单需求数量
                    sf.PlannedDateFrom          AS MOPlanDate,                 -- 基本开始日期取计划开始日期
                    ROW_NUMBER() OVER (
                        ORDER BY ISNULL(sf.PlannedDateFrom, '9999-12-31'), sf.MOName
                    ) AS rn
                FROM dbo.MO sf
                WHERE sf.ProductId = mi.ProductId          -- 只取生产当前物料行物料的生产订单
                AND ISNULL(sf.DeleteFlag, '') <> '1'     -- 排除已逻辑删除的工单
                AND sf.SAPMOStates = '下达'                    
            ) t
        ) sfmo
    -- 【过滤】排除已逻辑删除的工单与工单物料行
    WHERE ISNULL(mi.DeleteFlag, '') <> '1'
    AND ISNULL(mo.DeleteFlag, '') <> '1'
    AND mi.LineSequence<>'000'
    AND p2.ProductClassify = '2'
    AND mo.SAPMOStates = '下达'
    AND (ISNULL(@FactoryName, '') = '' OR f.FactoryName  = LTRIM(RTRIM(@FactoryName)))
    AND (ISNULL(@ProductName, '') = '' OR pr2.ProductName = LTRIM(RTRIM(@ProductName)))
    AND (ISNULL(@MoName, '')      = '' OR mo.MOName      = LTRIM(RTRIM(@MoName)))    
    AND (ISNULL(@SoName, '')      = '' OR mo.SOName      = LTRIM(RTRIM(@SoName)))         
    -- 【过滤】理货数量已满足MO需求数(已理货 >= 工单物料行需求数量)时，该行无需再分析缺料，不展示
    AND ISNULL(alloc.AllocatedQty, 0) < ISNULL(mi.ItemQtyRequired, 0)
    order by mo.CreateDate desc 