-- =============================================
-- Author:		<administrator>
-- Create date: <07 23 2009  1:01PM>
-- Description:	为POItem创建导航树视图
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[POItemTreeView]
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_FiltCondition	NVARCHAR(MAX)='',	--过滤条件表达式
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKId CHAR(12) ='',				--主键
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(100)=''		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个TreeView过程中实现.
AS
BEGIN
	-- This Stored Procedure is created by OrBit-MetaObject engine	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--执行TreeView,注意：以下过程必须根据业务的需求进行调整
	--如果您不了解TreeView过程如何编写，请参考我们提供的示例_SampleProjectTreeView


	IF @I_PKId<>''
	BEGIN
		SELECT  
			POItem.POItemId ,
			POItem.POId ,
			POItem.ItemSequence ,
			CASE POItem.ItemStates
				WHEN '10' THEN '已创建'
				WHEN '20' THEN '部分收货'
				WHEN '30' THEN '全部收货'
				WHEN '40' THEN '关闭' END ItemStates, 
			POItem.ProductId ,
			ProductRoot.ProductName+' '+ISNULL(ProductRevision,'') AS ProductName,
			Product.ProductDescription ,
			UOM.UOMName AS PurchaseUOM ,
			CONVERT(FLOAT,POItem.ItemQtyRequired) AS ItemQtyRequired ,
			CONVERT(FLOAT,POItem.ItemQtyStarted) AS ItemQtyStarted,
			CONVERT(FLOAT,POItem.ItemQtySpare) AS ItemQtySpare,
			CAST(A.ItemQtyIntransit AS FLOAT)  AS  ItemQtyIntransit, 
			CONVERT(FLOAT,POItem.ItemQtyReceived) AS ItemQtyReceived,		
			CONVERT(FLOAT,POItem.ItemQtyRejected) AS ItemQtyRejected,
			CONVERT(FLOAT,POItem.ItemQtyEntry) AS ItemQtyEntry,	
			CONVERT(FLOAT,POItem.ItemQtyBack) AS ItemQtyBack,
			POItem.DateRequired,
			POItem.PlanDeliveryDate,
			POItem.ModifyDate
		FROM POItem 
		INNER JOIN Product ON Product.ProductId = POItem.ProductId
		INNER JOIN ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
		LEFT JOIN UOM ON Product.PurchaseUOMId = UOM.UOMId
		LEFT JOIN (SELECT POItem.POItemId,SUM(VendorDeliveryItem.ItemQtyDelivery+VendorDeliveryItem.ItemQtySpare-VendorDeliveryItem.ItemQtyReceived) AS ItemQtyIntransit
				   FROM dbo.POItem
				   INNER JOIN dbo.VendorDeliveryItem ON VendorDeliveryItem.POItemId = POItem.POItemId
				   INNER JOIN dbo.VendorDelivery ON VendorDelivery.VendorDeliveryId = VendorDeliveryItem.VendorDeliveryId
				   WHERE POItem.POId=@I_ParentPKId AND VendorDeliveryStates NOT IN('10','20','31')
				   GROUP BY POItem.POItemId
				   )A ON A.POItemId = POItem.POItemId --计算在途数(等于已送货且未接收，总启动数-总已接收数)
		WHERE   POItem.POItemId = @I_PKId and POItem.deleteflag !='1'
		ORDER BY ItemSequence;

		RETURN 0
	END



	SELECT  
		POItem.POItemId ,
		POItem.POId ,
		POItem.ItemSequence ,
		CASE POItem.ItemStates
			WHEN '10' THEN '已创建'
			WHEN '20' THEN '部分收货'
			WHEN '30' THEN '全部收货'
			WHEN '40' THEN '关闭' END ItemStates, 
		POItem.ProductId ,
		ProductRoot.ProductName+' '+ISNULL(ProductRevision,'') AS ProductName,
		Product.ProductDescription ,
		UOM.UOMName AS PurchaseUOM ,
		CONVERT(FLOAT,POItem.ItemQtyRequired) AS ItemQtyRequired ,
		CONVERT(FLOAT,POItem.ItemQtyStarted) AS ItemQtyStarted,
		CONVERT(FLOAT,POItem.ItemQtySpare) AS ItemQtySpare,
		CAST(A.ItemQtyIntransit AS FLOAT)  AS  ItemQtyIntransit,
		CONVERT(FLOAT,POItem.ItemQtyReceived) AS ItemQtyReceived,		
		CONVERT(FLOAT,POItem.ItemQtyRejected) AS ItemQtyRejected,
		CONVERT(FLOAT,POItem.ItemQtyEntry) AS ItemQtyEntry,			
		CONVERT(FLOAT,POItem.ItemQtyBack) AS ItemQtyBack,	
		POItem.DateRequired,
		POItem.PlanDeliveryDate,
		POItem.ModifyDate
	FROM POItem 
	INNER JOIN Product ON Product.ProductId = POItem.ProductId
	INNER JOIN ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
	LEFT JOIN UOM ON Product.PurchaseUOMId = UOM.UOMId
	LEFT JOIN (SELECT POItem.POItemId,SUM(VendorDeliveryItem.ItemQtyDelivery+VendorDeliveryItem.ItemQtySpare-VendorDeliveryItem.ItemQtyReceived) AS ItemQtyIntransit
			   FROM dbo.POItem
			   INNER JOIN dbo.VendorDeliveryItem ON VendorDeliveryItem.POItemId = POItem.POItemId
			   INNER JOIN dbo.VendorDelivery ON VendorDelivery.VendorDeliveryId = VendorDeliveryItem.VendorDeliveryId
			   WHERE POItem.POId=@I_ParentPKId AND VendorDeliveryStates NOT IN('10','20','31')
			   GROUP BY POItem.POItemId
			   )A ON A.POItemId = POItem.POItemId --计算在途数(等于已送货且未接收，总启动数-总已接收数)
	WHERE   POItem.POId = @I_ParentPKId  and POItem.deleteflag !='1'
	ORDER BY ItemSequence;

	RETURN 0
END
