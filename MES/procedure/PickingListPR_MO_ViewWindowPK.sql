-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2020/07/25 14:50:52:9509>
-- Description:   <生产领料单：获取工单清单>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListPR_MO_ViewWindowPK] 
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKId char(12)='',				--主键ID
@I_ParentPKId char(12)='',			--父元对象主键ID
@QueryParameter nvarchar(100)=''
--以上8个变量为系统服务固定接口参数，必须在每一个ViewWindow过程中实现.>

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @FactoryId CHAR(12)='' --通过工厂过滤
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




	SELECT @FactoryId=FactoryId
	FROM dbo.PickingList
	WHERE PickingListId=@I_ParentPKId

	SELECT     
		MO.MOId, 
		MO.MOName,
		MO.ProductId,
		ProductRoot.ProductName,
		ProductDescription,
		CAST(MO.MOQtyRequired AS FLOAT) AS MOQtyRequired,
		BillType.BillTypeDescription AS MOType
	FROM  dbo.MO
	INNER JOIN Product ON Product.ProductId=MO.ProductId
	INNER JOIN ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
	INNER JOIN @BillTypeTable BillType ON MO.MOType=BillType.BillTypeName AND BillType.IsOM=0
	INNER JOIN @BillStatesTable BillState ON mo.MOStates=BillState.BillStatesName
	WHERE FactoryId IN (SELECT FactoryId FROM Factory WHERE FactoryName IN ('9102','9302', '9304'))

END
go

