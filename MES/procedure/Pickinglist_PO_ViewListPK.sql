

-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/04/07 14:40:37:3025>
-- Description:   <外协领料单 之采购订单>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[Pickinglist_PO_ViewListPK] 
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKId char(12)='',				--主键ID
@I_ParentPKId char(12)='',			--父元对象主键ID
@QueryParameter nvarchar(100)=''
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @POStatesNotUsable NVARCHAR(50)='' --PO不可用状态
	DECLARE @VendorId CHAR(12)=''
	DECLARE @FactoryId CHAR(12)=''

	--哪些状态要显示
	DECLARE @BillStatesTable TABLE(
		BillStatesName  NVARCHAR(50),
		BillStatesDescription NVARCHAR(50)
	)

	--获取系统参数
	--获取不可用单
	SELECT @POStatesNotUsable=ParameterValueEx 
	FROM dbo.SysParameter WHERE ParameterName='[WES SysControl]' AND ParameterValue='Bill_PO_States_NotUsable'

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
	WHERE BillName='PO'
	AND BillStatesName NOT IN (SELECT parameter_Value FROM dbo.ConvertParameterToTable(@POStatesNotUsable,';'))
 
	SELECT @VendorId=VendorId,
		    @FactoryId=FactoryId
	FROM dbo.PickingList
	WHERE PickingListId=@I_ParentPKId


	--返回采购订单
	SELECT DISTINCT PO.POId,POName,PODescription
	FROM dbo.PO
	INNER JOIN @BillStatesTable A ON PO.POStates=A.BillStatesName
	INNER JOIN dbo.POItem ON POItem.POId = PO.POId
	INNER JOIN dbo.POItemM ON POItemM.POItemId = POItem.POItemId
	WHERE VendorId=@VendorId AND FactoryId=@FactoryId
	AND (POItemM.ItemQtyRequired+ POItemM.ItemQtyBack)> POItemM.ItemQtyIssued

END



go

