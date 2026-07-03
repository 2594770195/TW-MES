-- =============================================
-- Author:		Cursor AI
-- Create date: 2026-07-01
-- Description:	查询当前库中索引碎片率超过指定阈值的表及索引（只读，不修改数据）
-- Revision: 1.00
-- =============================================
CREATE PROCEDURE [dbo].[Batch_QueryIndexFragmentation]
    @MinFragmentationPercent DECIMAL(5, 2) = 80 -- 碎片百分比下限，默认 80
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    -- 【查询】扫描当前库索引叶级页物理统计，返回碎片率超过阈值的表与索引
    SELECT
        OBJECT_SCHEMA_NAME(ips.object_id) AS SchemaName,
        OBJECT_NAME(ips.object_id) AS TableName,
        i.name AS IndexName,
        CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5, 2)) AS FragmentationPercent
    FROM sys.dm_db_index_physical_stats(
        DB_ID(),
        NULL,
        NULL,
        NULL,
        'LIMITED' -- 比 SAMPLED 更快，只扫描叶级页
    ) ips
    INNER JOIN sys.indexes i
        ON ips.object_id = i.object_id
       AND ips.index_id = i.index_id
    WHERE ips.index_id > 0 -- 排除堆表，仅统计索引
      AND ips.avg_fragmentation_in_percent > @MinFragmentationPercent
    ORDER BY ips.avg_fragmentation_in_percent DESC;

    RETURN 0;
END
GO
