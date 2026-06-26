
-- =============================================
-- Author:		<Gavin>
-- Create date: <03  2 2012 10:18AM>
-- Description:	为零星领料单创建主视图
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListPRMainView]
@I_PKId CHAR(12) =''				--主键
--以上变量为系统服务固定接口参数，必须在每一个MainView过程中实现.
AS
BEGIN
	-- This Stored Procedure is created by OrBit-MetaObject engine
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--执行MainView,注意：以下过程必须根据业务的需求进行调整
	--如果您不了解MainView过程如何编写，请参考我们提供的示例_SampleProjectMainView

	SELECT     
		PickingListName, 
		PickingListStates+' '+ISNULL(BillState.BillStatesDescription,'') AS PickingListStates,
		PickingListType AS PickingListTypeCode, 
		PickingListType+' '+BillType.BillTypeDescription  AS PickingListType,
		PickingListDescription, 
		PickingList.FactoryId,
		FactoryName+CASE ISNULL(FactoryDescription,'') WHEN '' THEN '' ELSE ' '+FactoryDescription END AS FactoryName,
		PickingList.DivisionId,
		DivisionCode+' '+DivisionName AS DivisionName,
		Workcenter.WorkcenterId AS ToWorkcenterId,
		WorkcenterName+' '+ISNULL(WorkcenterDescription,'') AS ToWorkcenterName,
		CASE WHEN ISNULL(DateRequired,'')='' THEN PickingList.CreateDate ELSE DateRequired END  AS DateRequired, 
		SysUser.UserName+SysUser.UserDescription AS CreateUserName,
		PickingList.CreateDate, 
		SysUser_1.UserName +SysUser_1.UserDescription AS ApproveUserName, 
		ApproveDate,
		SysUser_2.UserName+SysUser_2.UserDescription AS ConfirmUserName,
		ConfirmDate
	FROM  dbo.PickingList 
	LEFT JOIN dbo.Division ON Division.DivisionId=PickingList.DivisionId
	LEFT JOIN dbo.SysUser ON SysUser.UserId = PickingList.CreateUserId 
	LEFT JOIN dbo.Workcenter ON PickingList.ToWorkcenterId = Workcenter.WorkcenterId 
	LEFT JOIN dbo.Factory ON Factory.FactoryId = PickingList.FactoryId 
	LEFT JOIN dbo.SysUser AS SysUser_1 ON ApproveUserId = SysUser_1.UserId 
	LEFT JOIN dbo.SysUser AS SysUser_2 ON ConfirmUserId = SysUser_2.UserId 
	LEFT JOIN dbo.BillStates_Table('PickingListPR')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
	LEFT JOIN dbo.BillType_Table('PickingListPR') BillType ON PickingListType = BillType.BillTypeName
	WHERE  (PickingListId = @I_PKId)
			
	RETURN 0

END
go

