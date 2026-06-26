-- =============================================
-- Author:		Cursor AI
-- Create date: 2026-06-18
-- Description:	按盘点结果批量更新原材料库存，支持预览、按仓库独立事务、更新、新增（含数量不足补差额）、冻结和置出库
-- Revision: 1.04
-- Revision History:
--   1.04 2026-06-24 新增库存时按 Product.SafeStorageTime 计算 ValidityEndDate，基准日期优先沿用同 SAP 批次已有库存
--   1.03 2026-06-22 新增处理：Excel 冻结数量不为 0 时，将对应产品同一 SAP 批次的在库 LotStatus 置为 0（冻结）
--   1.02 2026-06-22 新增处理：Excel 与库存表均存在但库存数量小于盘点数量时，按差额补足新增
--   1.01 历史版本
-- =============================================
CREATE PROCEDURE [dbo].[Batch_StocktakeUpdateRMInventory]
    @I_ReturnMessage NVARCHAR(MAX) = '' OUTPUT, -- 返回 JSON 处理结果
    @CreateUserId CHAR(12) = '',                -- 操作人
    @DryRun BIT = 0                             -- 1=预览校验，0=正式更新
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BatchNo NVARCHAR(30) = N'ST' + CONVERT(CHAR(8), GETDATE(), 112) + REPLACE(CONVERT(CHAR(8), GETDATE(), 108), ':', '');
    DECLARE @Now DATETIME = GETDATE();
    DECLARE @ErrorMsg NVARCHAR(MAX) = N'';
    DECLARE @DetailsJson NVARCHAR(MAX) = N'[]';

    -- 【校验】检查盘点暂存表是否存在
    IF OBJECT_ID(N'dbo.TempStocktakeData', N'U') IS NULL
    BEGIN
        SET @ErrorMsg = N'盘点暂存表 TempStocktakeData 不存在，请先创建表结构';
        SELECT @I_ReturnMessage = (
            SELECT CAST(0 AS BIT) AS result,
                   @ErrorMsg AS message,
                   @BatchNo AS batchNo,
                   0 AS totalWarehouses,
                   0 AS successWarehouses,
                   0 AS failedWarehouses,
                   JSON_QUERY(N'[]') AS details
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );
        RETURN -1;
    END;

    -- 【校验】检查盘点数据是否为空，避免误把空数据当作清仓指令
    IF NOT EXISTS (SELECT 1 FROM dbo.TempStocktakeData)
    BEGIN
        SET @ErrorMsg = N'盘点数据不能为空';
        SELECT @I_ReturnMessage = (
            SELECT CAST(0 AS BIT) AS result,
                   @ErrorMsg AS message,
                   @BatchNo AS batchNo,
                   0 AS totalWarehouses,
                   0 AS successWarehouses,
                   0 AS failedWarehouses,
                   JSON_QUERY(N'[]') AS details
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );
        RETURN -1;
    END;

    -- 【校验】检查必填字段，文本字段统一按去空格后的值判断
    IF EXISTS (
        SELECT 1
        FROM dbo.TempStocktakeData
        WHERE ISNULL(LTRIM(RTRIM(FactoryName)), N'') = N''
           OR ISNULL(LTRIM(RTRIM(WarehouseName)), N'') = N''
           OR ISNULL(LTRIM(RTRIM(ProductNo)), N'') = N''
           OR ISNULL(LTRIM(RTRIM(UOMName)), N'') = N''
           OR ISNULL(LTRIM(RTRIM(SAPBatchNo)), N'') = N''
    )
    BEGIN
        SET @ErrorMsg = N'盘点数据存在必填字段为空：工厂、仓库、物料号、单位、SAP批号均不能为空';
        SELECT @I_ReturnMessage = (
            SELECT CAST(0 AS BIT) AS result,
                   @ErrorMsg AS message,
                   @BatchNo AS batchNo,
                   0 AS totalWarehouses,
                   0 AS successWarehouses,
                   0 AS failedWarehouses,
                   JSON_QUERY(N'[]') AS details
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );
        RETURN -1;
    END;

    -- 【校验】检查盘点数量，负数库存会导致库存保留和置出库口径不明确
    IF EXISTS (
        SELECT 1
        FROM dbo.TempStocktakeData
        WHERE StockQty IS NULL
           OR StockQty < 0
    )
    BEGIN
        SET @ErrorMsg = N'盘点数据存在库存数量为空或小于 0 的记录';
        SELECT @I_ReturnMessage = (
            SELECT CAST(0 AS BIT) AS result,
                   @ErrorMsg AS message,
                   @BatchNo AS batchNo,
                   0 AS totalWarehouses,
                   0 AS successWarehouses,
                   0 AS failedWarehouses,
                   JSON_QUERY(N'[]') AS details
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );
        RETURN -1;
    END;

    -- 【校验】检查冻结数量，负数会导致冻结口径不明确
    IF EXISTS (
        SELECT 1
        FROM dbo.TempStocktakeData
        WHERE FrozenQty IS NULL
           OR FrozenQty < 0
    )
    BEGIN
        SET @ErrorMsg = N'盘点数据存在冻结数量为空或小于 0 的记录';
        SELECT @I_ReturnMessage = (
            SELECT CAST(0 AS BIT) AS result,
                   @ErrorMsg AS message,
                   @BatchNo AS batchNo,
                   0 AS totalWarehouses,
                   0 AS successWarehouses,
                   0 AS failedWarehouses,
                   JSON_QUERY(N'[]') AS details
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );
        RETURN -1;
    END;

    -- 【校验】检查同一盘点口径是否重复，防止同一 SAP 批次被重复覆盖
    IF EXISTS (
        SELECT 1
        FROM dbo.TempStocktakeData
        GROUP BY LTRIM(RTRIM(FactoryName)),
                 LTRIM(RTRIM(WarehouseName)),
                 LTRIM(RTRIM(ProductNo)),
                 LTRIM(RTRIM(SAPBatchNo))
        HAVING COUNT(1) > 1
    )
    BEGIN
        SET @ErrorMsg = N'盘点数据存在重复的工厂、仓库、物料号、SAP批号，请先清理后再导入';
        SELECT @I_ReturnMessage = (
            SELECT CAST(0 AS BIT) AS result,
                   @ErrorMsg AS message,
                   @BatchNo AS batchNo,
                   0 AS totalWarehouses,
                   0 AS successWarehouses,
                   0 AS failedWarehouses,
                   JSON_QUERY(N'[]') AS details
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );
        RETURN -1;
    END;

    -- 【解析】将 Excel 文本字段解析成 MES 主数据 ID，并保留行级错误原因
    SELECT
        s.RowNo,
        LTRIM(RTRIM(s.FactoryName)) AS FactoryName,
        LTRIM(RTRIM(s.WarehouseName)) AS WarehouseName,
        LTRIM(RTRIM(s.ProductNo)) AS ProductNo,
        s.StockQty,
        ISNULL(s.FrozenQty, 0) AS FrozenQty,
        LTRIM(RTRIM(s.UOMName)) AS UOMName,
        LTRIM(RTRIM(s.SAPBatchNo)) AS SAPBatchNo,
        NULLIF(LTRIM(RTRIM(ISNULL(s.LotSN, N''))), N'') AS SourceLotSN,
        f.FactoryId,
        wc.WorkcenterId,
        prod.ProductId,
        uom.UOMId,
        STUFF(
            (CASE WHEN f.FactoryId IS NULL THEN N'；工厂在 MES 中不存在' ELSE N'' END) +
            (CASE WHEN f.FactoryId IS NOT NULL AND wc.WorkcenterId IS NULL THEN N'；仓库在该工厂下不存在或名称不匹配' ELSE N'' END) +
            (CASE WHEN prod.ProductId IS NULL THEN N'；物料号在 MES 中不存在' ELSE N'' END) +
            (CASE WHEN uom.UOMId IS NULL THEN N'；单位在 MES 中不存在' ELSE N'' END),
            1,
            1,
            N''
        ) AS ResolveError
    INTO #ResolvedStocktakeData
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
    OUTER APPLY (
        SELECT TOP 1 u.UOMId
        FROM dbo.UOM u WITH (NOLOCK)
        WHERE u.UOMName = LTRIM(RTRIM(s.UOMName))
           OR u.ERPUnitcode = LTRIM(RTRIM(s.UOMName))
        ORDER BY CASE WHEN u.UOMName = LTRIM(RTRIM(s.UOMName)) THEN 0 ELSE 1 END,
                 u.CreateDate DESC,
                 u.UOMId DESC
    ) uom;

    -- 【准备】生成本次盘点涉及的仓库清单，后续按仓库独立处理和返回结果
    CREATE TABLE #WarehouseList
    (
        RowId INT IDENTITY(1,1) PRIMARY KEY,
        FactoryName NVARCHAR(100) NOT NULL,
        WarehouseName NVARCHAR(100) NOT NULL,
        FactoryId CHAR(12) NULL,
        WorkcenterId CHAR(12) NULL
    );

    INSERT INTO #WarehouseList (FactoryName, WarehouseName, FactoryId, WorkcenterId)
    SELECT FactoryName, WarehouseName, FactoryId, WorkcenterId
    FROM #ResolvedStocktakeData
    GROUP BY FactoryName, WarehouseName, FactoryId, WorkcenterId;

    -- 【准备】保存仓库级处理结果，用于最终返回 JSON
    CREATE TABLE #ProcessResult
    (
        FactoryName NVARCHAR(100) NOT NULL,
        WorkcenterId CHAR(12) NULL,
        WorkcenterName NVARCHAR(100) NOT NULL,
        Status NVARCHAR(20) NOT NULL,
        ErrorMsg NVARCHAR(MAX) NOT NULL,
        TotalRows INT NOT NULL,
        UpdatedRows INT NOT NULL,
        InsertedRows INT NOT NULL,
        RemovedRows INT NOT NULL
    );

    DECLARE @RowId INT = 1;
    DECLARE @MaxRowId INT = 0;
    DECLARE @CurrentFactoryName NVARCHAR(100) = N'';
    DECLARE @CurrentWarehouseName NVARCHAR(100) = N'';
    DECLARE @CurrentFactoryId CHAR(12) = '';
    DECLARE @CurrentWorkcenterId CHAR(12) = '';
    DECLARE @TotalRows INT = 0;
    DECLARE @UpdatedRows INT = 0;
    DECLARE @InsertedRows INT = 0;
    DECLARE @RemovedRows INT = 0;
    DECLARE @RemovedExcessRows INT = 0;
    DECLARE @RemovedMissingRows INT = 0;
    DECLARE @InsertCount INT = 0;
    DECLARE @SNRuleId CHAR(12) = '';
    DECLARE @return_value INT = 0;
    DECLARE @CandidateId INT = 0;
    DECLARE @NewWWId CHAR(12) = '';
    DECLARE @NewLotSN NVARCHAR(100) = N'';

    SELECT @MaxRowId = MAX(RowId) FROM #WarehouseList;

    -- 【循环】按仓库独立处理，单个仓库失败不影响后续仓库
    WHILE @RowId <= ISNULL(@MaxRowId, 0)
    BEGIN
        SELECT
            @CurrentFactoryName = FactoryName,
            @CurrentWarehouseName = WarehouseName,
            @CurrentFactoryId = ISNULL(FactoryId, ''),
            @CurrentWorkcenterId = ISNULL(WorkcenterId, '')
        FROM #WarehouseList
        WHERE RowId = @RowId;

        SET @ErrorMsg = N'';
        SET @TotalRows = 0;
        SET @UpdatedRows = 0;
        SET @InsertedRows = 0;
        SET @RemovedRows = 0;
        SET @RemovedExcessRows = 0;
        SET @RemovedMissingRows = 0;
        SET @InsertCount = 0;

        SELECT @TotalRows = COUNT(1)
        FROM #ResolvedStocktakeData
        WHERE FactoryName = @CurrentFactoryName
          AND WarehouseName = @CurrentWarehouseName;

        -- 【校验】当前仓库存在主数据解析失败时，仅标记该仓失败并继续处理其他仓库
        IF EXISTS (
            SELECT 1
            FROM #ResolvedStocktakeData
            WHERE FactoryName = @CurrentFactoryName
              AND WarehouseName = @CurrentWarehouseName
              AND ISNULL(ResolveError, N'') <> N''
        )
        BEGIN
            SELECT @ErrorMsg = STUFF((
                SELECT N'；第' + CAST(RowNo AS NVARCHAR(20)) + N'行' + ResolveError
                FROM #ResolvedStocktakeData
                WHERE FactoryName = @CurrentFactoryName
                  AND WarehouseName = @CurrentWarehouseName
                  AND ISNULL(ResolveError, N'') <> N''
                ORDER BY RowNo
                FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)'), 1, 1, N'');

            INSERT INTO #ProcessResult
            (
                FactoryName, WorkcenterId, WorkcenterName, Status, ErrorMsg,
                TotalRows, UpdatedRows, InsertedRows, RemovedRows
            )
            VALUES
            (
                @CurrentFactoryName, NULLIF(@CurrentWorkcenterId, ''), @CurrentWarehouseName, N'failed', @ErrorMsg,
                @TotalRows, 0, 0, 0
            );

            SET @RowId += 1;
            CONTINUE;
        END;

        -- 【统计】预先计算当前仓库已有库存的保留、调整和超量置出库行数
        IF OBJECT_ID('tempdb..#MatchedInventory') IS NOT NULL
            DROP TABLE #MatchedInventory;

        SELECT
            inv.WWId,
            inv.Qty,
            s.StockQty,
            s.UOMId,
            SUM(ISNULL(inv.Qty, 0)) OVER (
                PARTITION BY inv.FactoryId, inv.WorkcenterId, inv.ProductId, inv.ProductionLotNO
                ORDER BY inv.CreateDate DESC, inv.WWId DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS RunningQty
        INTO #MatchedInventory
        FROM dbo.WW_RMInventory inv WITH (NOLOCK)
        INNER JOIN #ResolvedStocktakeData s
            ON s.FactoryId = inv.FactoryId
           AND s.WorkcenterId = inv.WorkcenterId
           AND s.ProductId = inv.ProductId
           AND s.SAPBatchNo = inv.ProductionLotNO
        WHERE s.FactoryId = @CurrentFactoryId
          AND s.WorkcenterId = @CurrentWorkcenterId
          AND inv.IsStorage = 1;

        SELECT @UpdatedRows = COUNT(1)
        FROM #MatchedInventory
        WHERE RunningQty - ISNULL(Qty, 0) < StockQty;

        SELECT @RemovedExcessRows = COUNT(1)
        FROM #MatchedInventory
        WHERE RunningQty - ISNULL(Qty, 0) >= StockQty;

        -- 【统计】计算需要新增的批次数量：包含库存表中完全不存在的批次，
        --         以及库存表存在但在库总数量小于盘点数量、需补足差额的批次
        SELECT @InsertedRows = COUNT(1)
        FROM #ResolvedStocktakeData s
        OUTER APPLY (
            SELECT SUM(ISNULL(inv.Qty, 0)) AS ExistQty
            FROM dbo.WW_RMInventory inv WITH (NOLOCK)
            WHERE inv.FactoryId = s.FactoryId
              AND inv.WorkcenterId = s.WorkcenterId
              AND inv.ProductId = s.ProductId
              AND inv.ProductionLotNO = s.SAPBatchNo
              AND inv.IsStorage = 1
        ) exist
        WHERE s.FactoryId = @CurrentFactoryId
          AND s.WorkcenterId = @CurrentWorkcenterId
          AND s.StockQty - ISNULL(exist.ExistQty, 0) > 0;

        -- 【统计】计算本仓库中 Excel 未出现的物料或 SAP 批次置出库数量
        SELECT @RemovedMissingRows = COUNT(1)
        FROM dbo.WW_RMInventory inv WITH (NOLOCK)
        WHERE inv.FactoryId = @CurrentFactoryId
          AND inv.WorkcenterId = @CurrentWorkcenterId
          AND inv.IsStorage = 1
          AND NOT EXISTS (
              SELECT 1
              FROM #ResolvedStocktakeData s
              WHERE s.FactoryId = inv.FactoryId
                AND s.WorkcenterId = inv.WorkcenterId
                AND s.ProductId = inv.ProductId
                AND s.SAPBatchNo = inv.ProductionLotNO
          );

        SET @RemovedRows = ISNULL(@RemovedExcessRows, 0) + ISNULL(@RemovedMissingRows, 0);

        -- 【预览】DryRun 只返回预计影响数量，不修改正式库存表
        IF ISNULL(@DryRun, 0) = 1
        BEGIN
            INSERT INTO #ProcessResult
            (
                FactoryName, WorkcenterId, WorkcenterName, Status, ErrorMsg,
                TotalRows, UpdatedRows, InsertedRows, RemovedRows
            )
            VALUES
            (
                @CurrentFactoryName, @CurrentWorkcenterId, @CurrentWarehouseName, N'success', N'预览成功，未修改库存',
                @TotalRows, @UpdatedRows, @InsertedRows, @RemovedRows
            );

            SET @RowId += 1;
            CONTINUE;
        END;

        BEGIN TRY
            -- 【事务】当前仓库独立事务，失败时只回滚当前仓库
            BEGIN TRANSACTION StocktakeWarehouse;

            -- 【更新】按 SAP 批次累计保留最新库存批次，超出盘点数量的旧批次置为不在库
            UPDATE inv
            SET
                inv.Qty = CASE
                    WHEN m.RunningQty <= m.StockQty THEN inv.Qty
                    WHEN m.RunningQty - ISNULL(m.Qty, 0) < m.StockQty AND m.RunningQty > m.StockQty
                        THEN m.StockQty - (m.RunningQty - ISNULL(m.Qty, 0))
                    ELSE inv.Qty
                END,
                inv.UOMId = m.UOMId,
                inv.IsStorage = CASE
                    WHEN m.RunningQty - ISNULL(m.Qty, 0) < m.StockQty THEN 1
                    ELSE 0
                END,
                inv.ModifyDate = GETDATE()
            FROM dbo.WW_RMInventory inv
            INNER JOIN #MatchedInventory m
                ON m.WWId = inv.WWId;

            -- 【准备】找出需要新增的库存记录，后续逐行生成系统主键和内部批号
            IF OBJECT_ID('tempdb..#InsertCandidates') IS NOT NULL
                DROP TABLE #InsertCandidates;

            CREATE TABLE #InsertCandidates
            (
                CandidateId INT IDENTITY(1,1) PRIMARY KEY,
                RowNo INT NOT NULL,
                FactoryId CHAR(12) NOT NULL,
                WorkcenterId CHAR(12) NOT NULL,
                ProductId CHAR(12) NOT NULL,
                UOMId CHAR(12) NOT NULL,
                InsertQty DECIMAL(18, 8) NOT NULL,
                SAPBatchNo NVARCHAR(100) NOT NULL,
                NewWWId CHAR(12) NULL,
                NewLotSN NVARCHAR(100) NULL
            );

            -- 【准备】按盘点缺口生成待新增记录：新增数量 = 盘点数量 - 库存现有在库总数量。
            --         库存不存在时缺口为全量，库存存在但不足时缺口为差额，仅缺口大于 0 才新增。
            INSERT INTO #InsertCandidates
            (
                RowNo, FactoryId, WorkcenterId, ProductId, UOMId, InsertQty, SAPBatchNo
            )
            SELECT
                s.RowNo, s.FactoryId, s.WorkcenterId, s.ProductId, s.UOMId,
                s.StockQty - ISNULL(exist.ExistQty, 0),
                s.SAPBatchNo
            FROM #ResolvedStocktakeData s
            OUTER APPLY (
                SELECT SUM(ISNULL(inv.Qty, 0)) AS ExistQty
                FROM dbo.WW_RMInventory inv WITH (NOLOCK)
                WHERE inv.FactoryId = s.FactoryId
                  AND inv.WorkcenterId = s.WorkcenterId
                  AND inv.ProductId = s.ProductId
                  AND inv.ProductionLotNO = s.SAPBatchNo
                  AND inv.IsStorage = 1
            ) exist
            WHERE s.FactoryId = @CurrentFactoryId
              AND s.WorkcenterId = @CurrentWorkcenterId
              AND s.StockQty - ISNULL(exist.ExistQty, 0) > 0;

            SELECT @InsertCount = COUNT(1) FROM #InsertCandidates;

            IF @InsertCount > 0
            BEGIN
                -- 【新增】获取 MES 内部批号生成规则，缺少规则时阻断当前仓库
                SELECT TOP 1 @SNRuleId = SNRuleId
                FROM dbo.SNRule WITH (NOLOCK)
                WHERE SNRuleName = 'WW_MP_LotSN'
                  AND IsActivity = 1;

                IF ISNULL(@SNRuleId, '') = ''
                BEGIN
                    SET @ErrorMsg = N'未找到启用的库存内部批号规则 WW_MP_LotSN，无法新增库存';
                    RAISERROR(@ErrorMsg, 16, 1);
                END;

                SELECT @CandidateId = MIN(CandidateId) FROM #InsertCandidates;

                WHILE @CandidateId IS NOT NULL
                BEGIN
                    SET @NewWWId = '';
                    SET @NewLotSN = N'';
                    SET @return_value = 0;

                    -- 【新增】为待新增库存生成 WWId 和 MES 内部批号
                    EXEC dbo.SysGetObjectPKId '', 'WW_RMInventory', @NewWWId OUTPUT;

                    EXEC @return_value = dbo.StartRuleSNDoMethod
                        @I_ReturnMessage = @I_ReturnMessage OUTPUT,
                        @SNRuleId = @SNRuleId,
                        @RCharStr = N'',
                        @JumpQty = 1,
                        @NewSN = @NewLotSN OUTPUT;

                    IF ISNULL(@NewWWId, '') = '' OR ISNULL(@NewLotSN, N'') = N'' OR ISNULL(@return_value, 0) <> 0
                    BEGIN
                        SET @ErrorMsg = N'生成新增库存主键或 MES 内部批号失败：' + ISNULL(@I_ReturnMessage, N'');
                        RAISERROR(@ErrorMsg, 16, 1);
                    END;

                    UPDATE #InsertCandidates
                    SET NewWWId = @NewWWId,
                        NewLotSN = @NewLotSN
                    WHERE CandidateId = @CandidateId;

                    SELECT @CandidateId = MIN(CandidateId)
                    FROM #InsertCandidates
                    WHERE CandidateId > @CandidateId;
                END;

                -- 【新增】写入盘点缺口：库存表中不存在的批次按全量新增，
                --         库存表存在但数量不足的批次按差额补足新增
                INSERT INTO dbo.WW_RMInventory
                (
                    WWId,
                    LotSN,
                    LotStatus,
                    Qty,
                    OrgQty,
                    ProductId,
                    UOMId,
                    ProductionDate,
                    ProductionLotNO,
                    ReceiveDate,
                    ValidityEndDate,
                    FactoryId,
                    WorkcenterId,
                    IsStorage,
                    IsInternalLot,
                    Operator,
                    ModifyDate,
                    CreateDate
                )
                SELECT
                    ic.NewWWId,
                    ic.NewLotSN,
                    '1',
                    ic.InsertQty,
                    ic.InsertQty,
                    ic.ProductId,
                    ic.UOMId,
                    CONVERT(VARCHAR(50), base.StorageDateBase, 120),
                    LEFT(ic.SAPBatchNo, 50),
                    GETDATE(),
                    -- 【计算】有效期：与 UpdateInventoryBySAP_BCP 口径一致
                    CASE
                        WHEN ISNULL(p.SafeStorageTime, 0) <= 0 THEN NULL
                        ELSE ISNULL(
                            TRY_CAST(DATEADD(DAY, p.SafeStorageTime, base.StorageDateBase) AS DATE),
                            CAST('9999-12-31' AS DATE)
                        )
                    END,
                    ic.FactoryId,
                    ic.WorkcenterId,
                    1,
                    0,
                    @CreateUserId,
                    GETDATE(),
                    GETDATE()
                FROM #InsertCandidates ic
                -- 【关联】取物料安全存储天数，用于计算有效期
                INNER JOIN dbo.Product p WITH (NOLOCK)
                    ON p.ProductId = ic.ProductId
                -- 【关联】同 SAP 批次已有库存时，取最新一条的入库/生产日期作为有效期基准
                OUTER APPLY (
                    SELECT TOP 1
                        TRY_CAST(NULLIF(LTRIM(RTRIM(inv.ProductionDate)), N'') AS DATE) AS ProdDate,
                        CAST(inv.EntryDate AS DATE) AS EntryDate
                    FROM dbo.WW_RMInventory inv WITH (NOLOCK)
                    WHERE inv.FactoryId = ic.FactoryId
                      AND inv.WorkcenterId = ic.WorkcenterId
                      AND inv.ProductId = ic.ProductId
                      AND inv.ProductionLotNO = ic.SAPBatchNo
                    ORDER BY inv.CreateDate DESC, inv.WWId DESC
                ) existInv
                -- 【计算】基准日期：优先 ProductionDate，其次 EntryDate，最后当前日期
                CROSS APPLY (
                    SELECT COALESCE(existInv.ProdDate, existInv.EntryDate, CAST(GETDATE() AS DATE)) AS StorageDateBase
                ) base;
            END;

            -- 【置出库】将本仓库中 Excel 没有出现的物料或 SAP 批次标记为不在库
            UPDATE inv
            SET
                inv.IsStorage = 0,
                inv.ModifyDate = GETDATE()
            FROM dbo.WW_RMInventory inv
            WHERE inv.FactoryId = @CurrentFactoryId
              AND inv.WorkcenterId = @CurrentWorkcenterId
              AND inv.IsStorage = 1
              AND NOT EXISTS (
                  SELECT 1
                  FROM #ResolvedStocktakeData s
                  WHERE s.FactoryId = inv.FactoryId
                    AND s.WorkcenterId = inv.WorkcenterId
                    AND s.ProductId = inv.ProductId
                    AND s.SAPBatchNo = inv.ProductionLotNO
              );

            -- 【冻结】Excel 中冻结数量不为 0 时，将对应产品同一 SAP 批次的在库记录 LotStatus 置为 0（冻结）
            UPDATE inv
            SET
                inv.LotStatus = '0',
                inv.ModifyDate = GETDATE()
            FROM dbo.WW_RMInventory inv
            WHERE inv.FactoryId = @CurrentFactoryId
              AND inv.WorkcenterId = @CurrentWorkcenterId
              AND inv.IsStorage = 1
              AND EXISTS (
                  SELECT 1
                  FROM #ResolvedStocktakeData s
                  WHERE s.FactoryId = inv.FactoryId
                    AND s.WorkcenterId = inv.WorkcenterId
                    AND s.ProductId = inv.ProductId
                    AND s.SAPBatchNo = inv.ProductionLotNO
                    AND ISNULL(s.FrozenQty, 0) <> 0
              );

            COMMIT TRANSACTION StocktakeWarehouse;

            INSERT INTO #ProcessResult
            (
                FactoryName, WorkcenterId, WorkcenterName, Status, ErrorMsg,
                TotalRows, UpdatedRows, InsertedRows, RemovedRows
            )
            VALUES
            (
                @CurrentFactoryName, @CurrentWorkcenterId, @CurrentWarehouseName, N'success', N'处理成功',
                @TotalRows, @UpdatedRows, @InsertedRows, @RemovedRows
            );
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION StocktakeWarehouse;

            SET @ErrorMsg = ERROR_MESSAGE();

            -- 【异常】记录当前仓库失败原因并继续后续仓库
            INSERT INTO #ProcessResult
            (
                FactoryName, WorkcenterId, WorkcenterName, Status, ErrorMsg,
                TotalRows, UpdatedRows, InsertedRows, RemovedRows
            )
            VALUES
            (
                @CurrentFactoryName, @CurrentWorkcenterId, @CurrentWarehouseName, N'failed', @ErrorMsg,
                @TotalRows, 0, 0, 0
            );
        END CATCH;

        SET @RowId += 1;
    END;

    -- 【返回】汇总仓库级结果，返回 JSON 供调用方保存和展示
    SELECT @DetailsJson = (
        SELECT
            FactoryName AS factoryName,
            WorkcenterId AS workcenterId,
            WorkcenterName AS workcenterName,
            Status AS status,
            ErrorMsg AS errorMsg,
            TotalRows AS totalRows,
            UpdatedRows AS updatedRows,
            InsertedRows AS insertedRows,
            RemovedRows AS removedRows
        FROM #ProcessResult
        ORDER BY FactoryName, WorkcenterName
        FOR JSON PATH, INCLUDE_NULL_VALUES
    );

    SELECT @I_ReturnMessage = (
        SELECT
            CAST(CASE WHEN SUM(CASE WHEN Status = N'failed' THEN 1 ELSE 0 END) = 0 THEN 1 ELSE 0 END AS BIT) AS result,
            CASE
                WHEN SUM(CASE WHEN Status = N'failed' THEN 1 ELSE 0 END) = 0 AND ISNULL(@DryRun, 0) = 1 THEN N'盘点预览完成'
                WHEN SUM(CASE WHEN Status = N'failed' THEN 1 ELSE 0 END) = 0 THEN N'盘点更新完成'
                ELSE N'盘点处理完成，存在失败仓库，请查看 details'
            END AS message,
            @BatchNo AS batchNo,
            COUNT(1) AS totalWarehouses,
            SUM(CASE WHEN Status = N'success' THEN 1 ELSE 0 END) AS successWarehouses,
            SUM(CASE WHEN Status = N'failed' THEN 1 ELSE 0 END) AS failedWarehouses,
            JSON_QUERY(ISNULL(@DetailsJson, N'[]')) AS details
        FROM #ProcessResult
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
    );

    IF EXISTS (SELECT 1 FROM #ProcessResult WHERE Status = N'failed')
        RETURN -1;

    RETURN 0;
END;
GO
