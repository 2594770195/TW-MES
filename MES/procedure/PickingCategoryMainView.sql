-- =============================================
-- Author:		<HH0082>
-- Create date: <02 24 2022 10:04AM>
-- Description:	为PickingCategory创建主视图
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROC [dbo].[PickingCategoryMainView]
@I_PKId char(12) =''				--主键
--以上变量为系统服务固定接口参数，必须在每一个MainView过程中实现.
AS
BEGIN
	-- This Stored Procedure is created by OrBit-MetaObject engine
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	--执行MainView,注意：以下过程必须根据业务的需求进行调整
	--如果您不了解MainView过程如何编写，请参考我们提供的示例_SampleProjectMainView

			SELECT     
                PickingCategory.ProductFamilyId,
				ProductFamily.ProductFamilyName,
				PickingCategory.WorkshopTypeId,
                UserCode.UserCodeDescription AS ProductType
			FROM   PickingCategory
			LEFT JOIN dbo.ProductFamily ON ProductFamily.ProductFamilyId = PickingCategory.ProductFamilyId 
			LEFT JOIN dbo.UserCode ON PickingCategory.WorkshopTypeId=UserCode.UserCodeId
			where PickingCategoryId=@I_PKId
			return 0

END
go

