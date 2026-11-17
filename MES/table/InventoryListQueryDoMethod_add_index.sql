-- =============================================
-- Description: <库存清单查询(InventoryListQueryDoMethod)性能优化索引>
-- Date:    2026.10.27
-- 说明:
--   1. 新增的“容器码+货位码+数量”列按生产批次
--      ZR_ContainerCode.CurrentProudctionLotSN 过滤容器明细，
--      该字段若无索引会导致 ZR_ContainerCode 全表扫描，是查询慢的主因。
--   2. 本脚本所有索引均带存在性检查，可重复执行；
--      请 DBA 先核对实际已有索引，避免重复/冗余创建。
--   3. ZR_ContainerCode / ZR_ContainerCodeDetails 表定义未纳入代码库，
--      若 INCLUDE 列与实际表结构不符，请按实际字段调整后再执行。
-- =============================================

-- 1. ZR_ContainerCode: 按当前生产批次过滤容器（本次新增的核心索引）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ZR_ContainerCode_CurrentProudctionLotSN' AND object_id = OBJECT_ID(N'dbo.ZR_ContainerCode'))
    CREATE NONCLUSTERED INDEX IX_ZR_ContainerCode_CurrentProudctionLotSN
    ON dbo.ZR_ContainerCode (CurrentProudctionLotSN)
    INCLUDE (ZR_ContainerCodeID, ContainerCode);
GO

-- 2. ZR_ContainerCodeDetails: 按转厂容器码关联（与 Zr_TofacQueryDoMethod 索引脚本同名，已存在则跳过）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ZR_ContainerCodeDetails_ToFacCCID' AND object_id = OBJECT_ID(N'dbo.ZR_ContainerCodeDetails'))
    CREATE NONCLUSTERED INDEX IX_ZR_ContainerCodeDetails_ToFacCCID
    ON dbo.ZR_ContainerCodeDetails (ZR_ToFac_ContainerCodeID)
    INCLUDE (CodeStatus, num, createDate);
GO

-- 3. ZR_ToFac_ContainerCode: 关联 ZR_ContainerCode（与 Zr_TofacQueryDoMethod 索引脚本同名，已存在则跳过）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ZR_ToFac_ContainerCode_ContainerCodeId' AND object_id = OBJECT_ID(N'dbo.ZR_ToFac_ContainerCode'))
    CREATE NONCLUSTERED INDEX IX_ZR_ToFac_ContainerCode_ContainerCodeId
    ON dbo.ZR_ToFac_ContainerCode (ZR_ContainerCodeId)
    INCLUDE (ZR_ToFac_ContainerCodeID);
GO
