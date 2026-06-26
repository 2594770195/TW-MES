SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		 
-- Create Date: <2026.05.15>
-- Description:	根据SAP导出的库存数据，更新MES库存,默认同一个仓库内一个批次只有一个码(只能用于半成品)
-- Version: 1
-- =============================================
CREATE PROCEDURE  [dbo].[UpdateInventoryBySAP_BCP]
@WarehouseName NVARCHAR(20)='',
@FactoryName NVARCHAR(20)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

    DECLARE @WarehouseId NVARCHAR(20)=''
    DECLARE @FactoryId NVARCHAR(20)=''
    select @WarehouseId=Workcenterid,@FactoryId=a.FactoryId from Workcenter a left join Factory b on a.FactoryId=b.FactoryId where b.FactoryName=@FactoryName and a.WorkcenterName=@WarehouseName
    IF ISNULL(@WarehouseId,'')=''
    BEGIN
        select '找不到仓库'
        return -1
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ========== 1. 清理 WW_RMInventory 中的重复数据 ==========
        -- 按 (WorkcenterId, ProductId, ProductionLotNO) 分组，保留 Id 最小的那条，删除其余
        WITH DuplicatesCTE AS (
            SELECT WWId,
                   ROW_NUMBER() OVER (
                       PARTITION BY WorkcenterId, ProductId, ProductionLotNO 
                       ORDER BY WWId
                   ) AS rn
            FROM dbo.WW_RMInventory where WorkcenterId=@WarehouseId and IsStorage=1
        )
        update  dbo.WW_RMInventory  set IsStorage=0 WHERE WWId IN (SELECT WWId FROM DuplicatesCTE WHERE rn > 1);

        -- ========== 1. 预处理 SAP 数据，生成唯一批次汇总 ==========
        -- 假设 SAP 表三个数量列：Quantity, InspectionQty, BlockedQty（请替换为实际列名）
        -- 汇总为每个批次的唯一数量与状态
        DROP TABLE IF EXISTS #SapSummary;
        CREATE TABLE #SapSummary (
            WorkcenterId    nVARCHAR(50) NOT NULL,
            ProductId       nVARCHAR(50) NOT NULL,
            ProductionLotNO nVARCHAR(50) NOT NULL,
            qty        decimal(18, 8) NOT NULL,
            LotStatus       char(1) NOT NULL ,
            StorageDate      nVARCHAR(50), 
            Note  nVARCHAR(50), 
            UomName  nVARCHAR(50)
        );

        INSERT INTO #SapSummary (WorkcenterId, ProductId, ProductionLotNO, qty, LotStatus,StorageDate,Note,UomName)
        SELECT
            WorkcenterId,
            ProductId,
            lotsn AS ProductionLotNO,
            qty  = CASE 
                    WHEN ISNULL(ProductInventoryNum, 0) > 0 THEN ProductInventoryNum
                    WHEN ISNULL(CheckNum, 0) > 0 THEN CheckNum
                    WHEN ISNULL(LockQty, 0) > 0 THEN LockQty
                    ELSE 0
                END,
                -- 根据哪个列有值设置状态
                LotStatus = CASE 
                    WHEN ISNULL(ProductInventoryNum, 0) > 0 THEN '1'
                    WHEN ISNULL(CheckNum, 0) > 0 THEN '1'
                    WHEN ISNULL(LockQty, 0) > 0 THEN '0'
                    ELSE '1'   -- 全 0 时默认为正常批次
                END
            , a.StorageDate StorageDate
            ,a.Note Note
            ,a.UomName UomName
        FROM dbo.SAP_PRODUCT_INVENTORY a 
            left join Factory b on b.FactoryName=a.FactoryName
            left join Workcenter c on b.FactoryId=c.FactoryId and c.WorkcenterName=@WarehouseName
            left join product d on d.tproductname=a.ProductName
            WHERE a.FactoryName=@FactoryName and a.WorkcenterName=@WarehouseName  and d.ProductId is not null
        --GROUP BY WorkcenterId, ProductId, lotsn;

        IF (select count(1) from #SapSummary)=0
        BEGIN
            RETURN 0
        END
        -- ========== 2. SAP 不存在的批次：逻辑删除有效记录 ==========
        UPDATE W
        SET IsStorage = 0,
            ModifyDate = GETDATE()
        FROM dbo.WW_RMInventory W
        LEFT JOIN #SapSummary S
            ON W.WorkcenterId = S.WorkcenterId
            AND W.ProductId = S.ProductId
            AND W.ProductionLotNO = S.ProductionLotNO
        WHERE w.WorkcenterId=@WarehouseId AND  S.WorkcenterId IS NULL AND W.IsStorage = 1;

        -- ========== 3. SAP 存在的批次：修改对应数量 ==========
        UPDATE W
        SET qty=S.qty ,IsStorage = 1,
            ModifyDate = GETDATE()
        FROM dbo.WW_RMInventory W
        LEFT JOIN #SapSummary S
            ON W.WorkcenterId = S.WorkcenterId
            AND W.ProductId = S.ProductId
            AND W.ProductionLotNO = S.ProductionLotNO
        WHERE w.WorkcenterId=@WarehouseId AND  S.WorkcenterId IS NOT NULL AND W.IsStorage = 1;

        -- ========== 3. SAP 存在但MES不存在 ==========
        DECLARE
		-- 游标遍历变量（关联查询结果+批次数据）
		@WorkcenterId CHAR(12),  
		@ProductId CHAR(12),          -- 物料ID（从关联查询获取）
		@ProductionLotNO NVARCHAR(50),          -- 批次条码
		@qty DECIMAL(18,8),           -- 批次数量
		@LotStatus NVARCHAR(50),
        @StorageDate      VARCHAR(50), 
        @Note  VARCHAR(50), 
        @UomName  VARCHAR(50),
        @UOMId  VARCHAR(50)

        DECLARE PLILSOR CURSOR FOR
        select s.WorkcenterId, s.ProductId, s.ProductionLotNO,s.qty,s.LotStatus,s.StorageDate,  s.Note,s.UomName 
        FROM #SapSummary S
        LEFT JOIN  dbo.WW_RMInventory W
            ON W.WorkcenterId = S.WorkcenterId
            AND W.ProductId = S.ProductId
            AND W.ProductionLotNO = S.ProductionLotNO
            AND W.IsStorage = 1
        WHERE W.WorkcenterId IS NULL;
        OPEN PLILSOR;
	    FETCH NEXT FROM PLILSOR INTO @WorkcenterId, @ProductId, @ProductionLotNO,@qty,@LotStatus,@StorageDate,@Note,@UomName 
        WHILE @@FETCH_STATUS = 0  -- 游标遍历未结束
	    BEGIN
            DECLARE    @WWId NVARCHAR(20)=''
            DECLARE @SafeStorageTime  INT=0
            DECLARE @ValidityEndDate DATE=NULL
            select top 1 @WWId=wwid from WW_RMInventory where WorkcenterId=@WorkcenterId and ProductId=@ProductId and lotsn=@ProductionLotNO+'001'
            IF ISNULL(@WWId,'')<>''
            BEGIN
                Update WW_RMInventory set IsStorage=0,Qty=@qty,LotStatus=@LotStatus where WWId=@WWId
            END
            select @UOMId =UOMId from uom where UOMName=@UomName
            SELECT  
                @SafeStorageTime=SafeStorageTime
            FROM dbo.Product WITH(NOLOCK)
            INNER JOIN dbo.ProductRoot WITH(NOLOCK) ON ProductRoot.ProductRootId = Product.ProductRootId
            WHERE ProductId=@ProductId
            SET @ValidityEndDate=NULL
            IF ISNULL(@SafeStorageTime,0)>0 
            BEGIN 
                --获取有效期
                BEGIN TRY
                    SET @ValidityEndDate=DATEADD(d,@SafeStorageTime,@StorageDate)
                END TRY
                BEGIN CATCH
                    --超出时间范围
                    SET @ValidityEndDate=CAST('9999-12-31 23:59:59' AS DATETIME)
                END CATCH
            END
            DECLARE @Lotsn NVARCHAR(100)=''
            SET @Lotsn=@ProductionLotNO+'001'
            IF EXISTS(select 1 from WW_RMInventory where lotsn=@Lotsn)
            BEGIN
                DECLARE @RCharStr NVARCHAR(10)='' --10位预留字符
                DECLARE @I_ReturnMessage NVARCHAR(max)=''
                SET @RCharStr=(SELECT TOP 1 ProductLineCode FROM Product_Factory WHERE ProductId=@ProductId)
                SET @RCharStr=LEFT(@RCharStr,2)
                --申请SN
                EXEC   dbo.StartRuleSNDoMethod
                    @I_ReturnMessage = @I_ReturnMessage OUTPUT,
                    @SNRuleId = 'SNRU000000T4',--SELECT SNRuleId FROM dbo.SNRule WHERE SNRuleName='TWLOTSN',同库存批号打印
                    @JumpQty = 1,
                    @RCharStr = @RCharStr,
                    @NewSN = @Lotsn OUTPUT
            END

            EXEC dbo.SysGetObjectPKId '','WW_RMInventory',@WWId OUTPUT
			INSERT INTO dbo.WW_RMInventory(
				WWId,
				LotSN,
				LotStatus,
				Qty,
				OrgQty,
				BoxSN,
				ProductId,
				POId,
				VendorId,
				UOMId,
				ProductionDate,
				ProductionLotNO,
				ReceiveDate,
				ValidityEndDate,
				IsStorage,
				FactoryId,
				WorkcenterId,
				IsInternalLot,
				LotSType,
                SAPRemark,
                EntryDate
				)
			VALUES(
				@WWId,
				@ProductionLotNO+'001',
				@LotStatus,
				@qty,
				@qty,
				'',
				@ProductId,
				'',
				'',
				@UOMId,
				@StorageDate,
				@ProductionLotNO,
				GETDATE(),
				@ValidityEndDate,
				1,
				@FactoryId,
				@WorkcenterId,
				0,
				'2',
                @Note,
                CAST(@StorageDate AS DATETIME)
				)
            FETCH NEXT FROM PLILSOR INTO @WorkcenterId, @ProductId, @ProductionLotNO,@qty,@LotStatus,@StorageDate,@Note,@UomName
        END

        update SAP_PRODUCT_INVENTORY set ischange=1 where FactoryName=@FactoryName and WorkcenterName=@WarehouseName
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 
            ROLLBACK TRANSACTION;

        -- 抛出错误信息供上层捕获
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
    END CATCH;

END
GO
