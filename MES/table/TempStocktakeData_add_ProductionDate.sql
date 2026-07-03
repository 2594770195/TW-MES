-- =============================================
-- 升级脚本：为 TempStocktakeData 新增生产日期字段
-- 适用场景：数据库中已存在旧版 TempStocktakeData 表但尚无 ProductionDate 列
-- 执行前请经 DBA 审批
-- =============================================

IF COL_LENGTH(N'dbo.TempStocktakeData', N'ProductionDate') IS NULL
BEGIN
    -- 【新增字段】生产日期，选填，新增库存时存在则作为 ProductionDate
    ALTER TABLE dbo.TempStocktakeData
        ADD ProductionDate DATE NULL;
END
GO
