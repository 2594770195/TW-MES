-- 未清采购订单数：同物料上尚未收货完成的采购订单行剩余数量合计，
-- 口径参考 POItemTreeView 中的在途数：按 POItem.ProductId 关联同物料，排除逻辑删除，
-- 排除已全部收货(30)/已关闭(40)的订单行，剩余数量 = 需求数量 + 备品数量 - 已收货数量
WITH req AS (
    SELECT d.ProductId,
           SUM(ISNULL(d.ItemQtyRequired,0) - ISNULL(d.ItemQtyIssued,0) + ISNULL(d.ItemQtyBack,0)) AS ReserveQty
    FROM dbo.MOItem d
        INNER JOIN dbo.MO dm ON dm.MOId = d.MOId
    WHERE ISNULL(d.LineSequence,'') <> '000'
      AND ISNULL(d.DeleteFlag,'')  <> '1'
      AND ISNULL(dm.DeleteFlag,'') <> '1'
      AND dm.SAPMOStates = N'下达'
    GROUP BY d.ProductId
),
po AS (
    SELECT p.ProductId,
           SUM(ISNULL(p.ItemQtyRequired,0) + ISNULL(p.ItemQtySpare,0) - ISNULL(p.ItemQtyReceived,0)) AS OpenPOQty
    FROM dbo.POItem p
    WHERE ISNULL(p.DeleteFlag,'') <> '1'
      AND (p.ItemStates IS NULL OR p.ItemStates NOT IN ('30','40'))
    GROUP BY p.ProductId
),
-- 【已理货】依据 zpp12 口径：半成品批次预分配表按 物料 + 批次 汇总有效占用且已确认的理货数量
-- 口径：DeleteFlag='0'（未逻辑删除）、IsOccupyAllocatedQty=1（占用中）、ConfirmStatus='1'（已确认）
-- 按 物料 + 批次 分组，保证同一批次的理货数量只统计一次，避免多工单分配记录重复计数
alloc AS (
    SELECT a.ProductId,
           a.LotSN,
           SUM(ISNULL(a.Qty,0)) AS AllocatedQty
    FROM dbo.MOSemiFinishedLotAllocation a
    WHERE a.DeleteFlag = '0'
      AND a.IsOccupyAllocatedQty = 1
      AND a.ConfirmStatus = '1'
    GROUP BY a.ProductId, a.LotSN
)
SELECT f.FactoryName, PI.LotSN, PI.ProductInventoryNum, PI.CheckNum,
       CONVERT(decimal(18,6), ISNULL(req.ReserveQty,0)) AS 预留数量,
       -- 【已理货】该物料对应批次的已理货(已确认占用)数量
       CONVERT(decimal(18,6), ISNULL(al.AllocatedQty,0)) AS 已理货,
       -- 【净用量】本批次库存数量 - 该批次已理货数量
       CONVERT(decimal(18,6), ISNULL(PI.ProductInventoryNum,0) - ISNULL(al.AllocatedQty,0)) AS 净用量,
       CONVERT(decimal(18,6), ISNULL(po.OpenPOQty,0))  AS 未清采购订单数,
       PI.LockQty, 0 AS 限制使用
FROM dbo.ProductInventory PI
    INNER JOIN dbo.Factory f ON f.FactoryId = PI.FactoryId
    LEFT JOIN req   ON req.ProductId = PI.ProductId
    LEFT JOIN po    ON po.ProductId  = PI.ProductId
    LEFT JOIN alloc al ON al.ProductId = PI.ProductId
                      AND al.LotSN     = PI.LotSN   -- 按批次匹配，批次为空时不匹配
WHERE PI.DeleteFlag = 0;

