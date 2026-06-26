
-- =============================================
-- Author:		<HH0102>
-- Create date: <04  7 2021  1:51PM>
-- Description:	为PickingList_PO创建主视图
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingList_POMainView]
@I_PKId char(12) =''				--主键
--以上变量为系统服务固定接口参数，必须在每一个MainView过程中实现.
AS
BEGIN
	-- This Stored Procedure is created by OrBit-MetaObject engine
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	--执行MainView,注意：以下过程必须根据业务的需求进行调整
	--如果您不了解MainView过程如何编写，请参考我们提供的示例_SampleProjectMainView

	SELECT	PO.POId,
			POName
	FROM dbo.PickingList_PO
	LEFT JOIN dbo.PO ON PO.POId = PickingList_PO.POId
	LEFT JOIN dbo.SysUser ON PickingList_PO.CreateUserId=dbo.SysUser.UserId
	WHERE PickingList_POId=@I_PKId 

END
go

