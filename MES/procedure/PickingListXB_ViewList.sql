	

-- =============================================
-- Author:		<OBit Team  HK0313>
-- Create date: <2021.11.10>
-- Description:	<为工单获取Product清单>
-- Rev:1.00
-- =============================================
CREATE PROCEDURE [dbo].[PickingListXB_ViewList] 
@QueryParameter NVARCHAR(100)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	
	DECLARE @FSWorkCenterId CHAR(12)
	DECLARE @UVWorkCenterId CHAR(12)	

	SELECT TOP 1 @FSWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='FSXB'
	SELECT TOP 1 @UVWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='UVXB'


	SELECT PickingListName FROM PickingList 
	WHERE PickingListId IN(SELECT DISTINCT PickingListId FROM PickingListItem WHERE WorkcenterId IN(@FSWorkCenterId,@UVWorkCenterId) AND ISNULL(DeleteFlag,'')<>'X')
	AND PickingListStates='20'
 
END
go

