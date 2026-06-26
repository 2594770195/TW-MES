
-- =============================================
-- Author:		<HH0102 orbchay>
-- Create date: <04 07 2021 10:18AM>
-- Description:	为外协领料单创建主视图
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListPOMainView]
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
		FactoryName+CASE ISNULL(FactoryDescription,'') WHEN '' THEN '' ELSE ' '+FactoryDescription END  AS FactoryName,
		PickingList.VendorId,
		VendorShortName AS VendorName,
		DateRequired, 
		SysUser.UserName AS CreateUserName,
		PickingList.CreateDate, 
		SysUser_1.UserName AS ApproveUserName, 
		ApproveDate,
		SysUser_2.UserName AS ConfirmUserName,
		ConfirmDate
	FROM  dbo.PickingList 
	LEFT JOIN dbo.SysUser ON SysUser.UserId = PickingList.CreateUserId 
	LEFT JOIN dbo.Factory ON PickingList.FactoryId=Factory.FactoryId
	LEFT JOIN dbo.Workcenter ON ToWorkcenterId = Workcenter.WorkcenterId 
	LEFT JOIN dbo.SysUser AS SysUser_1 ON ApproveUserId = SysUser_1.UserId 
	LEFT JOIN dbo.SysUser AS SysUser_2 ON ConfirmUserId = SysUser_2.UserId 
	LEFT JOIN dbo.Vendor ON Vendor.VendorId = PickingList.VendorId
	LEFT JOIN dbo.BillStates_Table('PickingListPO')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
	LEFT JOIN dbo.BillType_Table('PickingListPO') BillType ON PickingListType = BillType.BillTypeName
	WHERE  (PickingListId = @I_PKId)
			
	RETURN 0

END
go

