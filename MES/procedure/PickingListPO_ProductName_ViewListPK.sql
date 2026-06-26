 
 
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/04/08 10:48:13:0226>
-- Description:   <获取外协领料单明细>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListPO_ProductName_ViewListPK] 
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId CHAR(12)='',			--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKId CHAR(12)='',				--主键ID
@I_ParentPKId CHAR(12)='',			--父元对象主键ID
@QueryParameter NVARCHAR(100)='' 
--以上个变量为系统服务固定接口参数，必须在每一个ViewListEx过程中实现.>
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED


	SELECT    TOP (100) PERCENT
	          Product.ProductId, 
			  ProductRoot.ProductName+' '+ISNULL(Product.ProductRevision,'')  AS ProductName,
			  Product.ProductDescription,
			  CAST(POItemM.ItemQtyRequired AS FLOAT) AS ItemQtyRequired,	--需求数
			  CAST(POItemM.ItemQtyIssued-POItemM.ItemQtyBack AS FLOAT) AS ItemQtyIssued, --已发数
			  CAST(POItemM.ItemQtyRequired+ POItemM.ItemQtyBack -POItemM.ItemQtyIssued AS FLOAT) AS ItemQtyOweIssued, --欠发数
			  UOMName,
			  POName,
			  POItemMId AS POItemMIdNO,
			  POItem.POItemId,
			  POItem_ProductRoot.ProductName AS OMMakeProductName,--委外制造产品
			  Product_Factory.WorkcenterId AS WarehouseId,
			  WorkcenterName AS WarehouseName
	FROM dbo.PickingList_PO
	INNER JOIN dbo.POItem ON POItem.POId = PickingList_PO.POId
	INNER JOIN dbo.POItemM ON POItemM.POItemId = POItem.POItemId
	INNER JOIN dbo.PO ON PO.POId = PickingList_PO.POId
	INNER JOIN dbo.Product ON Product.ProductId = POItemM.ProductId
	INNER JOIN dbo.ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId 
	LEFT OUTER JOIN dbo.UOM ON POItemM.UOMId = UOM.UOMId
	LEFT JOIN dbo.Product_Factory ON POItemM.ProductId=Product_Factory.ProductId AND PO.FactoryId=Product_Factory.FactoryId
	LEFT JOIN dbo.Workcenter ON Workcenter.WorkcenterId = Product_Factory.WorkcenterId
	LEFT JOIN dbo.Product POItem_Product ON POItem_Product.ProductId=POItem.ProductId
	LEFT JOIN dbo.ProductRoot POItem_ProductRoot ON POItem_ProductRoot.ProductRootId = POItem_Product.ProductRootId
	WHERE PickingListId=@I_ParentPKId
	ORDER BY POName,POItemId,POItemMId

    RETURN 0
END




go

