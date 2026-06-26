
-- =============================================
-- Author:		<HH0102>
-- Create date: <05  6 2020  3:31PM>
-- Description:	删除PickingList_MO表的数据
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingList_MODeleteData]
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_LanguageId char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand varchar(5)='',			--插件命令
@I_OrBitUserId char(12)='',				--用户ID
@I_OrBitUserName nvarchar(100)='',		--用户名
@I_ResourceId	char(12)='',			--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',		--资源名
@I_FiltCondition	nvarchar(max)='',	--过滤条件表达式
@I_PKId char(12)='',					--主键
@I_ParentPKId char(12)='',				--用于过滤的上级主键
@I_Parameter nvarchar(100)=''			--插件参数
--以上变量为系统服务固定接口参数，必须在每一个TreeView过程中实现.
AS
BEGIN
	-- This Stored Procedure is created by OrBit-MetaObject engine	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @MOId CHAR(12)=''
	DECLARE @MOName NVARCHAR(50)=''

	SELECT @MOId=PickingList_MO.MOId,
		   @MOName=MOName
	FROM dbo.PickingList_MO
	INNER JOIN dbo.MO ON MO.MOId = PickingList_MO.MOId
	WHERE PickingList_MOId=@I_PKId

	IF EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@I_ParentPKId AND MOId=@MOId)
	BEGIN
	   SET @I_ReturnMessage='ServerMessage:工单【'+@MOName+'】已生成领料明细，禁止删除！'
	   RETURN -1
	END


	--执行Delete
	--如果您不了解Delete过程如何编写，请参考我们提供的示例_SampleProjectDeleteData
	--获取删除前的记录	
  	declare @FieldsChanged nvarchar(max)
	EXEC	SysGetTableFieldsCombine 'PickingList_MO',@I_PKId,@FieldsChanged output

	delete PickingList_MO where PickingList_MOId = @I_PKId 

	--将所做的删除写入修改历史中
	EXEC	[dbo].[SysWriteInModifyHistory]
			@ObjectName = 'PickingList_MO',
			@TablePKId = @I_PKId ,
			@ModifyType = 'Delete',
			@UserName = @I_OrBitUserName,
			@ModifyHistory =  @FieldsChanged

END
go

