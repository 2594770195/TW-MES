
-- =============================================
-- Author:		<HH0102>
-- Create date: <05  6 2020  4:03PM>
-- Description:	为PickingList_MO创建导航树视图
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingList_MOTreeView]
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_LanguageId char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand varchar(5)='',		--插件命令
@I_FiltCondition	nvarchar(max)='',	--过滤条件表达式
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKId char(12) ='',				--主键
@I_ParentPKId char(12)='',			--父级主键
@I_Parameter nvarchar(100)=''		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个TreeView过程中实现.
AS
BEGIN
	-- This Stored Procedure is created by OrBit-MetaObject engine	
	SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	--执行TreeView,注意：以下过程必须根据业务的需求进行调整
	--如果您不了解TreeView过程如何编写，请参考我们提供的示例_SampleProjectTreeView

    Declare @IsUVUser char(1)='0'
    --判断是否是UV用户组
    IF @I_OrBitUserId IN(SELECT   SysUser_UserGroup.UserId
                FROM         SysUser_UserGroup 
                left join   SysUserGroup on SysUser_UserGroup.UserGroupId=SysUserGroup.UserGroupId
                WHERE    SysUserGroup.UserGroupName='UV' )
    BEGIN
        set @IsUVUser='1'
    END
	IF @I_ParentPKId<>''  
	BEGIN
		SELECT  
		        PickingList_MOId,
				PickingListId,
				MOName,
				ProductName,
				ProductDescription,
				CAST(MOQtyRequired AS FLOAT) AS MOQtyRequired
				--,ToSAPStates,SAPInfor,ui.MatDoc
				
		FROM  PickingList_MO
		LEFT JOIN dbo.MO ON MO.MOId = PickingList_MO.MOId
		LEFT JOIN dbo.Product ON Product.ProductId = MO.ProductId
		LEFT JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
		LEFT JOIN dbo.UploadIng AS ui ON ui.UploadDateId=PickingList_MOId AND ISNULL(ui.MatDoc,'')<>''
		WHERE PickingListId=@I_ParentPKId 
        --UV的单保密，不允许仓库的人看，如果需要指定人查看，可以用用户组的方式，需要修改该sql
        AND ( MO.ProductLine !='UV'  OR @IsUVUser='1' )
		RETURN 0
	END

	IF @I_PKId<>''  --当SaveData执行完成后刷新单行时执行
	BEGIN
		SELECT  
		        PickingList_MOId,
				PickingListId,
				MOName,
				ProductName,
				ProductDescription,
				CAST(MOQtyRequired AS FLOAT) AS MOQtyRequired,
				ToSAPStates
		FROM  PickingList_MO
		LEFT JOIN dbo.MO ON MO.MOId = PickingList_MO.MOId
		LEFT JOIN dbo.Product ON Product.ProductId = MO.ProductId
		LEFT JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
		WHERE PickingList_MOId=@I_PKId 
        --UV的单保密，不允许仓库的人看，如果需要指定人查看，可以用用户组的方式，需要修改该sql
        AND ( MO.ProductLine !='UV'  OR @IsUVUser='1' )
        
		RETURN 0
	END
END
go

