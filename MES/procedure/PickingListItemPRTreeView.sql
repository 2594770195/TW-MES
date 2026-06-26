
-- =============================================
-- Author:		<Gavin>
-- Create date: <03  2 2012  3:21PM>
-- Description:	为PickingListItem创建导航树视图
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListItemPRTreeView]
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_FiltCondition	NVARCHAR(MAX)='',	--过滤条件表达式
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKId CHAR(12) ='',				--主键
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(100)=''		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个TreeView过程中实现.
AS
BEGIN
	-- This Stored Procedure is created by OrBit-MetaObject engine	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

    Declare @IsUVUser char(1)='0'
    --判断是否是UV用户组
    IF @I_OrBitUserId IN(SELECT   SysUser_UserGroup.UserId
                FROM         SysUser_UserGroup 
                left join   SysUserGroup on SysUser_UserGroup.UserGroupId=SysUserGroup.UserGroupId
                WHERE    SysUserGroup.UserGroupName='UV' )
    BEGIN
        set @IsUVUser='1'
    END
	 
	--执行TreeView,注意：以下过程必须根据业务的需求进行调整
	--如果您不了解TreeView过程如何编写，请参考我们提供的示例_SampleProjectTreeView
	IF @I_PKId<>''
	BEGIN
		SELECT     
			PickingListItemId, 
			PickingListId,
            ItemSequence,
			CASE WHEN MO.ProductLine ='UV' AND @IsUVUser='0' THEN '' else  MO.MOName END MOName,
			--PickingListItem.ItemStates,
			PickingListItem.ProductId, 
			ProductName AS ProductName, 
			ProductDescription,
			CONVERT(FLOAT,QtyRequired) AS QtyRequired, 
			CONVERT(FLOAT,QtyIssued) AS QtyIssued,			
			CONVERT(FLOAT,HedgeQty) AS HedgeQty,
			UOMName AS UOMName, 
			PickingListItem.WorkcenterId AS WareHouseId,
			WorkcenterName+CASE ISNULL(WorkcenterDescription,'') WHEN '' THEN '' ELSE ' : '+WorkcenterDescription END  AS WarehouseName,
			PickingListItem.CreateDate,
			CASE WHEN CONVERT(FLOAT,(QtyIssued-QtyRequired))>=0
				THEN '[ItemSequence:XF]'
				ELSE '' END AS ColorControlId
		FROM dbo.PickingListItem 
		LEFT JOIN dbo.Product ON Product.ProductId = PickingListItem.ProductId 
		LEFT JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
		LEFT JOIN dbo.Workcenter ON Workcenter.WorkcenterId=PickingListItem.WorkcenterId
		LEFT JOIN dbo.UOM ON PickingListItem.UOMId = UOM.UOMId 
		LEFT JOIN dbo.MO ON PickingListItem.MOId=MO.MOId
		WHERE PickingListItemId=@I_PKId
        --UV生产领料单明细非UV组用户只能看过账失败的行
        AND ( MO.ProductLine !='UV' OR ToSAPStates='过账失败' OR @IsUVUser='1' )
		RETURN 0
	END
	
	SELECT
		PickingListItemId, 
		PickingListItem.PickingListId,
		ItemSequence,
		--PickingListItem.ItemStates,
		CASE WHEN MO.ProductLine ='UV' AND @IsUVUser='0' THEN '' else  MO.MOName END MOName,
		mi.LineSequence,
		PickingListItem.ProductId, 
		ProductName AS ProductName, 
		ProductDescription,
		CONVERT(FLOAT,QtyRequired) AS QtyRequired, 
		CONVERT(FLOAT,QtyIssued) AS QtyIssued,			
		CONVERT(FLOAT,HedgeQty) AS HedgeQty,
		mi.ItemQtyBack,
		UOMName AS UOMName, 
		PickingListItem.WorkcenterId AS WareHouseId,
		WorkcenterName+CASE ISNULL(WorkcenterDescription,'') WHEN '' THEN '' ELSE ' : '+WorkcenterDescription END  AS WarehouseName,
		PickingListItem.CreateDate,
		CASE WHEN CONVERT(FLOAT,(QtyIssued-QtyRequired))>=0
			THEN '[ItemSequence:XF]'
			ELSE '' END AS ColorControlId,
			PickingListItem.ToSAPStates,

  PickingListItem.SAPInfor  AS SAPInfor
	FROM dbo.PickingListItem 
	LEFT JOIN dbo.Product ON Product.ProductId = PickingListItem.ProductId 
	LEFT JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
	LEFT JOIN dbo.Workcenter ON Workcenter.WorkcenterId=PickingListItem.WorkcenterId
	LEFT JOIN dbo.UOM ON PickingListItem.UOMId = UOM.UOMId 
	LEFT JOIN dbo.MO ON PickingListItem.MOId=MO.MOId
	LEFT JOIN dbo.MOItem AS mi ON mi.MOItemId = PickingListItem.MOItemId
	LEFT JOIN dbo.PickingList_MO AS plm ON plm.MOId = MO.MOId AND plm.PickingListId = PickingListItem.PickingListId
	LEFT JOIN dbo.UploadIng AS ui ON ui.UploadDateId=PickingListItemId AND ISNULL(ui.MatDoc,'')<>''
	LEFT JOIN dbo.UploadIng AS ui2 ON ui2.UploadDateId=plm.PickingList_MOId AND ISNULL(ui2.MatDoc,'')<>''
	WHERE PickingListItem.PickingListId=@I_ParentPKId
    --UV生产领料单明细非UV组用户只能看过账失败的行
    AND ( MO.ProductLine !='UV' OR PickingListItem.ToSAPStates='过账失败' OR @IsUVUser='1' )
    ORDER BY PickingListItem.ToSAPStates ASC 
	 

	RETURN 0
END
go

