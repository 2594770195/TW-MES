-- =============================================
-- 升级脚本：为 TempStocktakeData 新增冻结数量字段
-- 适用场景：数据库中已存在旧版 TempStocktakeData 表但尚无 FrozenQty 列
-- 执行前请经 DBA 审批
-- =============================================

IF COL_LENGTH(N'dbo.TempStocktakeData', N'FrozenQty') IS NULL
BEGIN
    -- 【新增字段】冻结数量，不为 0 时存储过程将同一 SAP 批次的在库 LotStatus 置为 0
    ALTER TABLE dbo.TempStocktakeData
        ADD FrozenQty DECIMAL(18, 8) NOT NULL
            CONSTRAINT DF_TempStocktakeData_FrozenQty DEFAULT 0;
END
GO
