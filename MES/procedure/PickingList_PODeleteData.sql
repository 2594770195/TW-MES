
-- =============================================
-- Author:		<HH0102>
-- Create date: <04  7 2021  1:51PM>
-- Description:	删除PickingList_PO表的数据
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingList_PODeleteData]
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',			--插件命令
@I_OrBitUserId CHAR(12)='',				--用户ID
@I_OrBitUserName NVARCHAR(100)='',		--用户名
@I_ResourceId	CHAR(12)='',			--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',		--资源名
@I_FiltCondition	NVARCHAR(MAX)='',	--过滤条件表达式
@I_PKId CHAR(12)='',					--主键
@I_ParentPKId CHAR(12)='',				--用于过滤的上级主键
@I_Parameter NVARCHAR(100)=''			--插件参数
--以上变量为系统服务固定接口参数，必须在每一个TreeView过程中实现.
AS
BEGIN
	-- This Stored Procedure is created by OrBit-MetaObject engine	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @POId CHAR(12)=''
	DECLARE @POName NVARCHAR(50)=''

	SELECT @POId=PickingList_PO.POId,
		   @POName=POName
	FROM dbo.PickingList_PO
	INNER JOIN dbo.PO ON PO.POId = PickingList_PO.POId
	WHERE PickingList_POId=@I_PKId

	IF EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@I_ParentPKId AND POId=@POId)
	BEGIN
	   SET @I_ReturnMessage='ServerMessage:采购订单【'+@POName+'】已生成领料明细，禁止删除！'
	   RETURN -1
	END


	--执行Delete
	--如果您不了解Delete过程如何编写，请参考我们提供的示例_SampleProjectDeleteData
	--获取删除前的记录	
	DECLARE @FieldsChanged NVARCHAR(MAX)
	EXEC	dbo.SysGetTableFieldsCombine 'PickingList_PO',@I_PKId,@FieldsChanged OUTPUT

	DELETE dbo.PickingList_PO WHERE PickingList_POId = @I_PKId 

	--将所做的删除写入修改历史中
	EXEC	[dbo].[SysWriteInModifyHistory]
			@ObjectName = 'PickingList_PO',
			@TablePKId = @I_PKId ,
			@ModifyType = 'Delete',
			@UserName = @I_OrBitUserName,
			@ModifyHistory =  @FieldsChanged

END
go

