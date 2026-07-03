-- =============================================
-- Author:		Cursor AI
-- Create date: 2026-06-29
-- Description:	盘点更新后校验：对比 TempStocktakeData 盘点数量与 WW_RMInventory 实际在库数量，
--              输出主数据解析失败、数量不一致、Excel 未出现但仍在库三类差异，仅查询不修改库存
-- Revision: 1.00
-- =============================================
CREATE PROCEDURE [dbo].[Batch_StocktakeCheckRMInventory]
    @I_ReturnMessage NVARCHAR(MAX) = '' OUTPUT -- 返回 JSON 校验结果
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    DECLARE @ErrorMsg NVARCHAR(MAX) = N'';
    DECLARE @DetailsJson NVARCHAR(MAX) = N'[]';

    -- 【校验】检查盘点暂存表是否存在
    IF OBJECT_ID(N'dbo.TempStocktakeData', N'U') IS NULL
    BEGIN
        SET @ErrorMsg = N'盘点暂存表 TempStocktakeData 不存在，请先创建表结构';
        SELECT @I_ReturnMessage = (
            SELECT CAST(0 AS BIT) AS result,
                   @ErrorMsg AS message,
                   0 AS totalRows,
                   0 AS issueCount,
                   JSON_QUERY(N'[]') AS details
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );
        RETURN -1;
    END;

    -- 【校验】检查盘点数据是否为空，空数据无校验基准
    IF NOT EXISTS (SELECT 1 FROM dbo.TempStocktakeData)
    BEGIN
        SET @ErrorMsg = N'盘点数据为空，无法校验，请先导入盘点 Excel';
        SELECT @I_ReturnMessage = (
            SELECT CAST(0 AS BIT) AS result,
                   @ErrorMsg AS message,
                   0 AS totalRows,
                   0 AS issueCount,
                   JSON_QUERY(N'[]') AS details
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );
        RETURN -1;
    END;

    -- 【准备】#ResolvedStocktake：将 Excel 文本解析为 MES 主数据 ID 并按盘点口径汇总盘点数量，
    --         作为后续与 WW_RMInventory 实际在库数量比对的基准
    SELECT
        LTRIM(RTRIM(s.FactoryName)) AS FactoryName,
        LTRIM(RTRIM(s.WarehouseName)) AS WarehouseName,
        LTRIM(RTRIM(s.ProductNo)) AS ProductNo,
        LTRIM(RTRIM(s.SAPBatchNo)) AS SAPBatchNo,
        SUM(ISNULL(s.StockQty, 0)) AS StocktakeQty,
        f.FactoryId,
        wc.WorkcenterId,
        prod.ProductId
    INTO #ResolvedStocktake
    FROM dbo.TempStocktakeData s
    LEFT JOIN dbo.Factory f WITH (NOLOCK)
        ON f.FactoryName = LTRIM(RTRIM(s.FactoryName))
    LEFT JOIN dbo.Workcenter wc WITH (NOLOCK)
        ON wc.WorkcenterName = LTRIM(RTRIM(s.WarehouseName))
       AND wc.FactoryId = f.FactoryId
    OUTER APPLY (
        SELECT TOP 1 p.ProductId
        FROM dbo.ProductRoot pr WITH (NOLOCK)
        INNER JOIN dbo.Product p WITH (NOLOCK)
            ON p.ProductRootId = pr.ProductRootId
        WHERE pr.ProductName = LTRIM(RTRIM(s.ProductNo))
        ORDER BY CASE WHEN p.ProductId = pr.DefaultProductId THEN 0 ELSE 1 END,
                 ISNULL(p.IsDefaultProduct, 0) DESC,
                 p.CreateDate DESC,
                 p.ProductId DESC
    ) prod
    GROUP BY
        LTRIM(RTRIM(s.FactoryName)),
        LTRIM(RTRIM(s.WarehouseName)),
        LTRIM(RTRIM(s.ProductNo)),
        LTRIM(RTRIM(s.SAPBatchNo)),
        f.FactoryId,
        wc.WorkcenterId,
        prod.ProductId;

    -- 【准备】#CheckResult：收集所有校验差异行，最终统一汇总成 JSON 返回调用方
    CREATE TABLE #CheckResult
    (
        CheckType    NVARCHAR(50)   NOT NULL, -- 差异类型
        FactoryName  NVARCHAR(100)  NULL,
        WarehouseName NVARCHAR(100) NULL,
        ProductNo    NVARCHAR(100)  NULL,
        SAPBatchNo   NVARCHAR(100)  NULL,
        ExpectedQty  DECIMAL(18, 8) NULL,     -- 盘点应有数量
        ActualQty    DECIMAL(18, 8) NULL,     -- MES 实际在库数量
        DiffQty      DECIMAL(18, 8) NULL      -- 实际 - 应有，正数=MES偏多，负数=MES偏少
    );

    -- 【校验1】主数据解析失败：工厂、仓库或物料无法在 MES 匹配，无法参与数量比对
    INSERT INTO #CheckResult
        (CheckType, FactoryName, WarehouseName, ProductNo, SAPBatchNo, ExpectedQty, ActualQty, DiffQty)
    SELECT
        N'主数据解析失败',
        FactoryName, WarehouseName, ProductNo, SAPBatchNo,
        StocktakeQty, NULL, NULL
    FROM #ResolvedStocktake
    WHERE FactoryId IS NULL
       OR WorkcenterId IS NULL
       OR ProductId IS NULL;

    -- 【校验2】数量不一致：同一工厂、仓库、物料、SAP批次下盘点数量与实际在库数量不相等
    INSERT INTO #CheckResult
        (CheckType, FactoryName, WarehouseName, ProductNo, SAPBatchNo, ExpectedQty, ActualQty, DiffQty)
    SELECT
        N'数量不一致',
        s.FactoryName, s.WarehouseName, s.ProductNo, s.SAPBatchNo,
        s.StocktakeQty,
        ISNULL(inv.ActualQty, 0),
        ISNULL(inv.ActualQty, 0) - s.StocktakeQty
    FROM #ResolvedStocktake s
    OUTER APPLY (
        -- 【汇总】同一盘点口径在库的全部 MES 批次合计数量
        SELECT SUM(ISNULL(i.Qty, 0)) AS ActualQty
        FROM dbo.WW_RMInventory i WITH (NOLOCK)
        WHERE i.FactoryId = s.FactoryId
          AND i.WorkcenterId = s.WorkcenterId
          AND i.ProductId = s.ProductId
          AND i.ProductionLotNO = s.SAPBatchNo
          AND i.IsStorage = 1
    ) inv
    WHERE s.FactoryId IS NOT NULL
      AND s.WorkcenterId IS NOT NULL
      AND s.ProductId IS NOT NULL
      AND ABS(ISNULL(inv.ActualQty, 0) - s.StocktakeQty) > 0.00000001;

    -- 【校验3】Excel 未出现但仍在库：本次盘点涉及仓库内，库存仍在库但 Excel 未覆盖该物料或 SAP 批次
    INSERT INTO #CheckResult
        (CheckType, FactoryName, WarehouseName, ProductNo, SAPBatchNo, ExpectedQty, ActualQty, DiffQty)
    SELECT
        N'Excel未出现但仍在库',
        f.FactoryName, wc.WorkcenterName, pr.ProductName, i.ProductionLotNO,
        0,
        SUM(ISNULL(i.Qty, 0)),
        SUM(ISNULL(i.Qty, 0))
    FROM dbo.WW_RMInventory i WITH (NOLOCK)
    INNER JOIN dbo.Factory f WITH (NOLOCK)
        ON f.FactoryId = i.FactoryId
    INNER JOIN dbo.Workcenter wc WITH (NOLOCK)
        ON wc.WorkcenterId = i.WorkcenterId
    INNER JOIN dbo.Product p WITH (NOLOCK)
        ON p.ProductId = i.ProductId
    INNER JOIN dbo.ProductRoot pr WITH (NOLOCK)
        ON pr.ProductRootId = p.ProductRootId
    WHERE i.IsStorage = 1
      AND EXISTS (
          -- 仅检查本次盘点已覆盖的仓库，避免误报未盘点仓库
          SELECT 1
          FROM #ResolvedStocktake s
          WHERE s.WorkcenterId = i.WorkcenterId
      )
      AND NOT EXISTS (
          SELECT 1
          FROM #ResolvedStocktake s
          WHERE s.FactoryId = i.FactoryId
            AND s.WorkcenterId = i.WorkcenterId
            AND s.ProductId = i.ProductId
            AND s.SAPBatchNo = i.ProductionLotNO
      )
    GROUP BY f.FactoryName, wc.WorkcenterName, pr.ProductName, i.ProductionLotNO;

    -- 【返回】汇总差异明细为 JSON 数组
    SELECT @DetailsJson = (
        SELECT
            CheckType AS checkType,
            FactoryName AS factoryName,
            WarehouseName AS warehouseName,
            ProductNo AS productNo,
            SAPBatchNo AS sapBatchNo,
            ExpectedQty AS expectedQty,
            ActualQty AS actualQty,
            DiffQty AS diffQty
        FROM #CheckResult
        ORDER BY CheckType, FactoryName, WarehouseName, ProductNo, SAPBatchNo
        FOR JSON PATH, INCLUDE_NULL_VALUES
    );

    DECLARE @IssueCount INT = (SELECT COUNT(1) FROM #CheckResult);
    DECLARE @TotalRows INT = (SELECT COUNT(1) FROM #ResolvedStocktake);

    -- 【返回】无差异 result=true，否则 result=false 并附差异数量
    SELECT @I_ReturnMessage = (
        SELECT
            CAST(CASE WHEN @IssueCount = 0 THEN 1 ELSE 0 END AS BIT) AS result,
            CASE
                WHEN @IssueCount = 0 THEN N'盘点数量校验通过，库存与盘点一致'
                ELSE N'盘点数量校验发现 ' + CAST(@IssueCount AS NVARCHAR(20)) + N' 处差异，请查看明细'
            END AS message,
            @TotalRows AS totalRows,
            @IssueCount AS issueCount,
            JSON_QUERY(ISNULL(@DetailsJson, N'[]')) AS details
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
    );

    RETURN 0;
END;
GO
