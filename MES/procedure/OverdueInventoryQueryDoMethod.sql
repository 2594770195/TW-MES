SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:
-- Create date: <2026.9.24>
-- Description:	超期库存查询-在物料过期前@OverdueDays天进行临期预警(含已过期)
-- =============================================
ALTER PROCEDURE  [dbo].[OverdueInventoryQueryDoMethod]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT, --向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKid CHAR(12) ='',				--主键
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(100)='',		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@WarehouseId CHAR(12)='',
@ProductId CHAR(12)='',
@OverdueDays INT = 0

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--统一取当前日期(去掉时间部分,避免时间参与DATEDIFF导致天数偏差)
	DECLARE @CurDate DATE = CAST(GETDATE() AS DATE)

	--临期预警天数边界检查:非正数或NULL时默认提前7天预警
	IF ISNULL(@OverdueDays,0) <= 0
	BEGIN
        SET @OverdueDays = 7
	END

	--查询条件说明:
	-- 1. IsStorage=1 and Qty>0 and LotStatus='1' : 只查在库、有数量、批号状态正常的库存
	-- 2. ValidityEndDate IS NOT NULL              : NULL代表无有效期管理,不需要预警
	-- 3. ValidityEndDate <= DATEADD(DAY,@OverdueDays,@CurDate)
	--    : 有效期在@OverdueDays天内到期(含已过期),即临期预警区间
	SELECT 
		   Factory.FactoryName,
	       Workcenter.WorkcenterName AS WarehouseName,
	       WW_RMInventory.LotSN AS LotSN,				--批次号(仓库人员定位物料)
	       ProductRoot.ProductName,
	       Product.ProductDescription,
	       UOM.UOMName AS UOMName,						--库存单位,方便仓库人员核对数量
	       WW_RMInventory.Qty AS Qty,
	       WW_RMInventory.EntryDate,					--入库日期
	       WW_RMInventory.ValidityEndDate,				--有效期至
	       CASE WHEN RTRIM(Product.ProductClassify) = '3' THEN Product.OverdueTime ELSE Product.SafeStorageTime END AS 有效天数,
	       --剩余天数:正数=还剩几天到期,负数=已过期几天(取绝对值)
	       DATEDIFF(DAY, @CurDate, WW_RMInventory.ValidityEndDate) AS RemainDays,
	       --预警状态:已过期 / 临期预警
	       CASE WHEN DATEDIFF(DAY, @CurDate, WW_RMInventory.ValidityEndDate) < 0
	            THEN N'已过期' ELSE N'临期预警' END AS WarningStatus
    FROM WW_RMInventory
	INNER JOIN Product on WW_RMInventory.ProductId = Product.ProductId
	INNER JOIN ProductRoot on Product.ProductRootId = ProductRoot.ProductRootId
	LEFT JOIN Factory on Factory.FactoryId = WW_RMInventory.FactoryId
	LEFT JOIN Workcenter on WW_RMInventory.WorkcenterId = Workcenter.WorkcenterId
	LEFT JOIN UOM on UOM.UOMId = Product.InventoryUOMId		--库存单位
    WHERE WW_RMInventory.IsStorage = 1
	  AND WW_RMInventory.Qty > 0
	  AND WW_RMInventory.LotStatus = '1'
	  AND WW_RMInventory.ValidityEndDate IS NOT NULL
	  AND WW_RMInventory.ValidityEndDate <= DATEADD(DAY, @OverdueDays, @CurDate)
	  AND ( ISNULL(@ProductId,'') = '' OR WW_RMInventory.ProductId = @ProductId )
	  AND ( ISNULL(@WarehouseId,'') = '' OR WW_RMInventory.WorkcenterId = @WarehouseId )
		--按有效期升序:最紧急(最快到期/已过期最久)的排最前面
	ORDER BY WW_RMInventory.ValidityEndDate ASC, WW_RMInventory.LotSN ASC

	RETURN 0

END

GO
