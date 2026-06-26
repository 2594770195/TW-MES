-- =============================================
-- Author:		<OBit Team  Orbchay>
-- Create date: <2020.5.6>
-- Description:	<为工单获取领料单的工单清单>
-- Rev:1.00
-- =============================================
CREATE PROCEDURE [dbo].[PickingListOM_MO_ViewList] 
@QueryParameter NVARCHAR(100)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @MOTyesOM NVARCHAR(50)='' --MO委外单
	DECLARE @MOStatesNotUsable NVARCHAR(50)='' --MO不可用状态


	--获取单据类型
	DECLARE @BillTypeTable TABLE(
		BillTypeName  NVARCHAR(50),
		BillTypeDescription NVARCHAR(50),
		IsOM BIT
	)

	--哪些状态要显示
	DECLARE @BillStatesTable TABLE(
		BillStatesName  NVARCHAR(50),
		BillStatesDescription NVARCHAR(50)
	)

	--获取系统参数
	--获取委外单据
	SELECT @MOTyesOM=ParameterValueEx 
	FROM dbo.SysParameter WHERE ParameterName='[WES SysControl]' AND ParameterValue='Bill_MO_Type_OM'

	--获取不可用单
	SELECT @MOStatesNotUsable=ParameterValueEx 
	FROM dbo.SysParameter WHERE ParameterName='[WES SysControl]' AND ParameterValue='Bill_MO_States_NotUsable'

	--获取单据类型
	INSERT INTO @BillTypeTable
			(
				BillTypeName,
				BillTypeDescription,
				IsOM
			)
	SELECT BillTypeName,
		   BillTypeDescription,
		   CASE ISNULL(OMType.parameter_Value,'') WHEN '' THEN 0 ELSE 1 END
	FROM dbo.Bill
	INNER JOIN dbo.BillType ON BillType.BillId = Bill.BillId
	LEFT JOIN (SELECT parameter_Value FROM dbo.ConvertParameterToTable(@MOTyesOM,';')) OMType ON BillType.BillTypeName=OMType.parameter_Value
	WHERE BillName='MO'

	--获取可用单据
	INSERT INTO @BillStatesTable
		 (
			 BillStatesName,
			 BillStatesDescription
		 )
	SELECT BillStatesName,
		   BillStatesDescription
	FROM dbo.Bill
	INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
	WHERE BillName='MO'
	AND BillStatesName NOT IN (SELECT parameter_Value FROM dbo.ConvertParameterToTable(@MOStatesNotUsable,';'))




	
	SELECT     
		MO.MOId, 
		MO.MOName,
		MO.ProductId,
		ProductRoot.ProductName,
		ProductDescription,
		MO.MOQtyRequired
	FROM  dbo.MO
	INNER JOIN Product ON Product.ProductId=MO.ProductId
	INNER JOIN ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
	INNER JOIN @BillTypeTable BillType ON MO.MOType=BillType.BillTypeName AND BillType.IsOM=1
	INNER JOIN @BillStatesTable BillState ON mo.MOStates=BillState.BillStatesName

 
END

go

