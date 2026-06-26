
-- =============================================
-- Author:		<Gavin>
-- Create date: <03  2 2012 10:18AM>
-- Description:	删除PickingList表的数据
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListOtherDeleteData]
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
	
	--通用
	DECLARE @BillStates VARCHAR(20)=''
	DECLARE @BillStatesDesc NVARCHAR(50)=''
	
	--获取修改的单据信息
	SELECT @BillStates=PickingListStates
	FROM dbo.PickingList
	WHERE PickingListId = @I_PKId 

	SELECT @BillStatesDesc=BillStatesDescription
	FROM dbo.Bill
	INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
	WHERE BillName='PickingListOther' AND BillStatesName=@BillStates
	AND IsERP=0

	IF @BillStates<>'10'
	BEGIN
		SELECT @I_ReturnMessage='ServerMessage:此单据当前状态【'+@BillStatesDesc+'】,禁止删除!'
		RETURN -1
	END

	--如果有领料单明细,则禁止删除，先删除领料明细，才能删除领料单
	--因为领料明细可能有发料 或者 冲销的超发，所以不能随便删除
	IF EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@I_PKId)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:该领料单存在领料明细行，禁止删除！先删除领料明细后才能删除！'
		RETURN -1
	END 

	--执行Delete
	--如果您不了解Delete过程如何编写，请参考我们提供的示例_SampleProjectDeleteData
	--获取删除前的记录	
  	DECLARE @FieldsChanged NVARCHAR(MAX)
	EXEC	dbo.SysGetTableFieldsCombine 'PickingList',@I_PKId,@FieldsChanged OUTPUT

	BEGIN TRAN
		DELETE dbo.PickingList WHERE PickingListId = @I_PKId 
	COMMIT TRAN

	--将所做的删除写入修改历史中
	EXEC	dbo.SysWriteInModifyHistory
			@ObjectName = 'PickingList',
			@TablePKId = @I_PKId ,
			@ModifyType = 'Delete',
			@UserName = @I_OrBitUserName,
			@ModifyHistory =  @FieldsChanged

END
go

