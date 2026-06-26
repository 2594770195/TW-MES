

-- =============================================
-- Author:		<OrBit Team Owen>
-- Create date: <2021.06.19>
-- Description:	<获取MO工单清单>
-- Rev:1.00
-- =============================================
CREATE PROCEDURE [dbo].[MOPicking_ViewList] 
@QueryParameter nvarchar(100)=''
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	--IF @QueryParameter<>''
	--select MO.MOId,MO.MOName,MO.ProductId,MO.MOQtyRequired 
	--from MO MO INNER JOIN (SELECT TOP 1 FactoryId FROM dbo.Factory_User where UserId='SUR1000003OW') FA
 --   ON MO.FactoryId=FA.FactoryId WHERE MO.MOStates=20
  select '' as MOName,'' as MOQtyRequired

 --   select TOP 500 MOName,MOQtyRequired 
	--from MO INNER JOIN Product P ON MO.ProductId=P.ProductId  
	--WHERE MO.MOStates=20 and ISNULL(MO.DeleteFlag,'')!='X' AND rtrim(ltrim(P.ProductClassify))=1 ORDER BY MO.PlannedDateFrom DESC


	return 0
END
go

