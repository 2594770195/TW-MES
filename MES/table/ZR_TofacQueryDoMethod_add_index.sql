-- =============================================
-- Description: <转厂记录查询(Zr_TofacQueryDoMethod)性能优化索引>
-- Date:    2026.09.04
-- 说明:
--   1. 查询 2000 条数据耗时 4 秒，主要原因:
--      a) ZR_ToFac_ContainerCode 表无任何索引(含主键)，多表 JOIN 时反复全表扫描;
--      b) ZR_ContainerCodeDetails.createDate 日期范围过滤无索引支撑;
--      c) VendorDeliveryItemLot.lotsn / mo.soname / Tofac.ProudctionLotSN 等
--         JOIN 与筛选字段缺少索引。
--   2. 本脚本所有索引均带存在性检查，可重复执行;
--      请 DBA 先核对数据库中实际已有的索引，避免重复/冗余创建。
--   3. ZR_ContainerCodeDetails / ZR_ContainerCode 表定义未纳入代码库，
--      若下列 INCLUDE 列与实际表结构不符，请按实际字段调整后再执行。
-- =============================================

-- 1. ZR_ContainerCodeDetails: 主表按创建时间范围过滤(覆盖常用查询列，避免回表)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ZR_ContainerCodeDetails_createDate' AND object_id = OBJECT_ID(N'dbo.ZR_ContainerCodeDetails'))
    CREATE NONCLUSTERED INDEX IX_ZR_ContainerCodeDetails_createDate
    ON dbo.ZR_ContainerCodeDetails (createDate)
    INCLUDE (ZR_ToFac_ContainerCodeID, CodeStatus, num, remark, I_OrBitUserId);
GO

-- 2. ZR_ContainerCodeDetails: 按转厂容器码关联(按容器码查询路径的反向查找)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ZR_ContainerCodeDetails_ToFacCCID' AND object_id = OBJECT_ID(N'dbo.ZR_ContainerCodeDetails'))
    CREATE NONCLUSTERED INDEX IX_ZR_ContainerCodeDetails_ToFacCCID
    ON dbo.ZR_ContainerCodeDetails (ZR_ToFac_ContainerCodeID)
    INCLUDE (CodeStatus, num, remark, I_OrBitUserId, createDate);
GO

-- 3. ZR_ToFac_ContainerCode: 被 ZR_ContainerCodeDetails 关联的主键方向
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ZR_ToFac_ContainerCode_ID' AND object_id = OBJECT_ID(N'dbo.ZR_ToFac_ContainerCode'))
    CREATE NONCLUSTERED INDEX IX_ZR_ToFac_ContainerCode_ID
    ON dbo.ZR_ToFac_ContainerCode (ZR_ToFac_ContainerCodeID)
    INCLUDE (ToFacId, ZR_ContainerCodeId, BoxLotSn);
GO

-- 4. ZR_ToFac_ContainerCode: 关联 Tofac 表
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ZR_ToFac_ContainerCode_ToFacId' AND object_id = OBJECT_ID(N'dbo.ZR_ToFac_ContainerCode'))
    CREATE NONCLUSTERED INDEX IX_ZR_ToFac_ContainerCode_ToFacId
    ON dbo.ZR_ToFac_ContainerCode (ToFacId);
GO

-- 5. ZR_ToFac_ContainerCode: 关联 ZR_ContainerCode 表
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ZR_ToFac_ContainerCode_ContainerCodeId' AND object_id = OBJECT_ID(N'dbo.ZR_ToFac_ContainerCode'))
    CREATE NONCLUSTERED INDEX IX_ZR_ToFac_ContainerCode_ContainerCodeId
    ON dbo.ZR_ToFac_ContainerCode (ZR_ContainerCodeId);
GO

-- 6. ZR_ToFac_ContainerCode: 按箱号关联 WW_RMInventory / VendorDeliveryItemLot
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ZR_ToFac_ContainerCode_BoxLotSn' AND object_id = OBJECT_ID(N'dbo.ZR_ToFac_ContainerCode'))
    CREATE NONCLUSTERED INDEX IX_ZR_ToFac_ContainerCode_BoxLotSn
    ON dbo.ZR_ToFac_ContainerCode (BoxLotSn);
GO

-- 7. ZR_ContainerCode: 容器码筛选与关联
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ZR_ContainerCode_ContainerCode' AND object_id = OBJECT_ID(N'dbo.ZR_ContainerCode'))
    CREATE NONCLUSTERED INDEX IX_ZR_ContainerCode_ContainerCode
    ON dbo.ZR_ContainerCode (ContainerCode);
GO

-- 8. VendorDeliveryItemLot: 外购 PO 查询按 lotsn 关联(当前仅有主键索引)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VendorDeliveryItemLot_LotSN' AND object_id = OBJECT_ID(N'dbo.VendorDeliveryItemLot'))
    CREATE NONCLUSTERED INDEX IX_VendorDeliveryItemLot_LotSN
    ON dbo.VendorDeliveryItemLot (LotSN)
    INCLUDE (VendorDeliveryItemId, ProductId, Qty, ProductionDate, ProductionLotNO);
GO

-- 9. mo: 按销售单号 soname 查询(当前仅有 MOName 唯一索引)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MO_SOName' AND object_id = OBJECT_ID(N'dbo.mo'))
    CREATE NONCLUSTERED INDEX IX_MO_SOName
    ON dbo.mo (soname);
GO

-- 10. Tofac: 按批次号 ProudctionLotSN 查询/关联
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ToFac_ProudctionLotSN' AND object_id = OBJECT_ID(N'dbo.Tofac'))
    CREATE NONCLUSTERED INDEX IX_ToFac_ProudctionLotSN
    ON dbo.Tofac (ProudctionLotSN);
GO
