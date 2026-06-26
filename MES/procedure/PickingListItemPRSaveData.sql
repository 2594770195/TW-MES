-- =============================================
-- Author:		<Gavin>
-- Create date: <03  2 2012  3:21PM>
-- Description:	为PickingListItem创建保存过程
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListItemPRSaveData]
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_IsNewRow BIT = 0 OUTPUT,				--向客户端报告是否是新行
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT, --向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKId CHAR(12) = '',				--主键
@I_SourcePKId CHAR(12)='',			--执行拷贝时传入的源主键  
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(100)='',		--插件参数
--以上变量为服务固定接口参数，必须在每一个Save过程中实现。

--以下参与必须与该元对象数据在MetadataField表中提供的字段一一对应。

--警告:	以下变量请一定要赋以默认值，否则前台程序会报错
--提示：元数据在MetadataField表中提供的所有字段必须全部包含在Save过程中
--      否则会导致因在更新时为参数不找到出前台程序报错。>
--提示：以下是用户变量定义段，如有用户变量定义段，请将上面@I_Parameter nvarchar(100)=''后面加上,号！
@MOItemIdNO CHAR(12),
@MOName NVARCHAR(50)='',
@ProductName NVARCHAR(50)='',
@ProductId  CHAR(12)='',
@QtyRequired  FLOAT=0,	 
@QtyIssued  FLOAT=0,
@ProductDescription NVARCHAR(1000)='',
@HedgeQty FLOAT=0,
@ItemSequence VARCHAR(20)='',
@ItemStates VARCHAR(20)='',
@WareHouseId CHAR(12)='',
@WareHouseName NVARCHAR(50)='',
@UOMName NVARCHAR(50)=''

--用户变量结束
AS
BEGIN
	-- This Stored Procedure is created by OrBit-MetaObject engine
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--执行SaveData,注意：以下过程必须根据业务的需求进行调整
	--如果您不了解SaveData过程如何编写，请参考我们提供的示例_SampleProjectSaveData


	DECLARE @ModifyObject NVARCHAR(50)
	DECLARE @ModifyType NVARCHAR(20)

	DECLARE @FieldsValueOld NVARCHAR(MAX)
	DECLARE @FieldsValueNew NVARCHAR(MAX)
	DECLARE @FieldsChanged NVARCHAR(MAX)
	DECLARE @UOMId CHAR(12)=''

	SET @I_ReturnMessage=''
	SET @I_IsNewRow = 0
	SET @I_ExceptionFieldName=''
	SET @ModifyObject='PickingListItem'   --这里必须要是当前操作的表名
	SET @ModifyType =''

	--bill
	DECLARE @BillStates VARCHAR(20)=''
	DECLARE @BillStatesDesc NVARCHAR(50)=''
    --billItem
	DECLARE @MOId CHAR(12)=''

	--没有申请到主键就退出
	IF LTRIM(@I_PKId)=''
	BEGIN
		SET @I_ReturnMessage='No PKId applied'
		RETURN -1
	END


	--单据信息
	SELECT @BillStates=PickingListStates
	FROM dbo.PickingList
	WHERE PickingListId = @I_ParentPKId 

	SELECT @BillStatesDesc=BillStatesDescription
	FROM dbo.Bill
	INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
	WHERE BillName='PickingListPR' AND BillStatesName=@BillStates
	AND IsERP=0

	--IF @BillStates<>'10'
	--BEGIN
	--	SELECT @I_ReturnMessage='ServerMessage:此单据当前状态【'+@BillStatesDesc+'】,无法操作此功能!'
	--	RETURN -1
	--END


	--判断是否有命名冲突
	IF EXISTS(SELECT PickingListId FROM dbo.PickingListItem 
			WHERE PickingListId = @I_ParentPKId AND MOId=@MOId AND ProductId=@ProductId AND PickingListItemId <> @I_PKId)		
	BEGIN
		SET @I_ReturnMessage='NamingConflicts'
			SET @I_ExceptionFieldName='ProductName'
		RETURN -1
	END

	IF ISNULL(@QtyRequired,0)<=0
	BEGIN
		SET @I_ReturnMessage='ServerMessage:需求数必须大于0'
		RETURN -1
	END

	SELECT @MOId=MOId
	FROM dbo.MO WHERE MOName=@MOName

	--获取物料的单位ID
	SELECT 
		@UOMId=UOMId
	FROM dbo.UOM 
	WHERE UOMName=@UOMName
    
    IF NOT EXISTS(SELECT PickingListItemId FROM dbo.PickingListItem WHERE PickingListItemId=@I_PKId)
	BEGIN
		-- 获取采购单行号
		IF EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@I_ParentPKId)
			SELECT
				@ItemSequence = RIGHT('000'+CAST(MAX(CAST(ItemSequence AS INT))+1 AS VARCHAR),4)
			FROM dbo.PickingListItem
			WHERE PickingListId = @I_ParentPKId
		ELSE
			SET @ItemSequence = RIGHT('000'+CAST(1 AS VARCHAR),4)

		INSERT INTO dbo.PickingListItem(
				PickingListItemId,
				PickingListId,
				ItemSequence ,
				MOId,
				MOItemId,
				ProductId,
				QtyRequired,
				QtyIssued,
				WorkcenterId,
				UOMId
				)
			VALUES(
				@I_PKId,
				@I_ParentPKId,
				@ItemSequence ,
				@MOId,
				@MOItemIdNO,
				@ProductId,
				@QtyRequired,
				@QtyIssued,
				@WareHouseId,
				@UOMId
			)

		SET @I_IsNewRow=1		
		SET @ModifyType='Insert'
		--获取刚刚插入的记录
		EXEC	dbo.SysGetTableFieldsCombine @ModifyObject,@I_PKId,@FieldsChanged OUTPUT

	END
    ELSE
	BEGIN

        
		-- 此领料单是否创建人，才可以修改
		--IF NOT EXISTS(SELECT PickingListId FROM dbo.PickingList WHERE PickingListId= @I_ParentPKId AND CreateUserId = @I_OrBitUserId)
		--BEGIN
		--	SET @I_ReturnMessage ='ServerMessage:此领料单不是用户【'+@I_OrBitUserName+'】创建的，无权操作!'
		--	RETURN -1
		--END
        
		-- 检查是否已发数
		IF ISNULL(@QtyIssued,0) > 0
		BEGIN
			SET @I_ReturnMessage ='ServerMessage:不允许修改,有发料数!'
            RETURN -1
		END
        

		--获更新前的记录
		EXEC	dbo.SysGetTableFieldsCombine @ModifyObject,@I_PKId,@FieldsValueOld OUTPUT

		UPDATE dbo.PickingListItem SET 
			ProductId=@ProductId,
			QtyRequired=@QtyRequired ,
			WorkcenterId=@WareHouseId,
			MOId=@MOId,
			MOItemId=@MOItemIdNO,
			UOMId=@UOMId
		WHERE PickingListItemId=@I_PKId

		SET @ModifyType='Update'
		--获更新后的记录,并进行比较
		EXEC	dbo.SysGetTableFieldsCombine @ModifyObject,@I_PKId,@FieldsValueNew OUTPUT
		EXEC	dbo.SysGetTableFieldsCompare @FieldsValueOld,@FieldsValueNew,@FieldsChanged OUTPUT

	END

    --最后将所做的修改入修改历史中
	IF @FieldsChanged<>''
	EXEC	dbo.SysWriteInModifyHistory
			@ObjectName = @ModifyObject,
			@TablePKId = @I_PKId ,
			@ModifyType = @ModifyType,
			@UserName = @I_OrBitUserName,
			@ModifyHistory =  @FieldsChanged

		RETURN 0

END
go

