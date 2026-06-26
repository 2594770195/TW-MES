-- =============================================
-- Author:		<OBit Team  HK0313.>
-- Create date: <2021.11.01>
-- Description:	<杂发单指定批次值列表>
-- Rev:1.00
-- =============================================
CREATE  PROCEDURE [dbo].[PickingListOtherAssignLot_ViewListPK] 
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKId char(12)='',				--主键ID
@I_ParentPKId char(12)='',			--父元对象主键ID
@QueryParameter nvarchar(100)=''
--以上6个变量为系统服务固定接口参数，必须在每一个ViewListEx过程中实现.>

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @ProductId char(12)

	SELECT @ProductId=ProductId FROM PickingListItem where PickingListItemId=@I_PKId

	SELECT A.LotSN,A.Qty ,B.TProductName AS ProductName,B.ProductDescription,w.WorkcenterName,A.ProductionLotNO FROM WW_RMInventory A
	INNER JOIN Product B ON A.ProductId=B.ProductId
	INNER JOIN dbo.Workcenter AS w ON w.WorkcenterId = A.WorkcenterId
	WHERE A.ProductId=@ProductId AND A.LotStatus='1' 
	AND A.IsStorage=1 AND A.Qty>0 
	ORDER BY  A.Qty


END

go

