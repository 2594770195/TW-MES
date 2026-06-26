-- =============================================
-- Author:		<OBit Team  H.R.>
-- Create date: <2008.8.8>
-- Description:	<获取PickingProductType 车间清单>
-- Rev:1.00
-- =============================================
CREATE PROC dbo.PickingProductType_ViewList 
@QueryParameter nvarchar(100)=''
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	SELECT UserCodeId AS WorkshopTypeId, UserCodeDescription AS ProductType FROM dbo.UserCode 
	WHERE ParentUserCodeId='URC100000BH7' --UserCodeName='PickingProductType/成品车间分类'

END


go

