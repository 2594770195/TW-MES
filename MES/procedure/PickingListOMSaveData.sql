
-- =============================================
-- Author:		<Orbchay>
-- Create date: <07 09 2019 10:18AM>
-- Description:	为PickingList创建保存过程
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListOMSaveData]
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
@PickingListName  NVARCHAR(50)='',
@PickingListDescription  NVARCHAR(100)='',
@PickingListTypeCode VARCHAR(10)='',
@PickingListType  NVARCHAR(50)='',
@PickingListStates  CHAR(20)='',
@FactoryId CHAR(12)='',
@FactoryName NVARCHAR(50)='',
@DateRequired  DATETIME=NULL,
@CreateDate DATETIME=NULL,
@CreateUserName NVARCHAR(100)='',
@ApproveDate DATETIME=NULL,
@ApproveUserName NVARCHAR(100)='',
@ConfirmUserName NVARCHAR(50)='',
@ConfirmDate DATETIME=NULL,
@VendorId CHAR(12)='',
@VendorName NVARCHAR(50)=''

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
	DECLARE	@return_value INT
	DECLARE @S_ReturnMessage NVARCHAR(100)

	DECLARE @FieldsValueOld NVARCHAR(MAX)
	DECLARE @FieldsValueNew NVARCHAR(MAX)
	DECLARE @FieldsChanged NVARCHAR(MAX)

	SET @I_ReturnMessage=''
	SET @I_IsNewRow = 0
	SET @I_ExceptionFieldName=''
	SET @ModifyObject='PickingList'   --这里必须要是当前操作的表名
	SET @ModifyType =''

	--自定义变量
	DECLARE @BillStates VARCHAR(20)=''
	DECLARE @BillStatesDesc NVARCHAR(50)=''
	
	--没有申请到主键就退出(平台会有申请动作)
	IF LTRIM(@I_PKId)=''
	BEGIN
		SET @I_ReturnMessage='No PKId applied'
		RETURN -1
	END
	

	
	--判断是否是新增的记录
    IF NOT EXISTS(SELECT PickingListId FROM dbo.PickingList WHERE PickingListId=@I_PKId)
	BEGIN
		DECLARE @NewSN NVARCHAR(50)
		SET @NewSN = ''

		EXEC dbo.Txn_BillNewSN
			@BillName = N'PickingListOM',
			@NewSN = @NewSN OUTPUT,
			@BillStates=@BillStates OUTPUT

		IF EXISTS(SELECT PickingListId FROM dbo.PickingList 
		WHERE PickingListName = @PickingListName AND  PickingListId <> @I_PKId)		
		BEGIN
			SET @I_ReturnMessage='ServerMessage:系统已存在此领料单！请检查！'+@PickingListName
			RETURN -1
		END	

		INSERT INTO dbo.PickingList(
				 PickingListId,
				 PickingListName,
				 PickingListDescription,
				 PickingListClass,
				 PickingListStates,
				 PickingListType,
				 DateRequired,
				 FactoryId,
				 VendorId,
				 CreateUserId
			)VALUES(
				 @I_PKId,
				 @NewSN,
				 @PickingListDescription,
				 '03',
				 @BillStates,
				 @PickingListTypeCode,
				 @DateRequired,
				 @FactoryId,
				 @VendorId,
				 @I_OrBitUserId)

		SET @I_IsNewRow=1
		SET @ModifyType='Insert'
		--获取刚刚插入的记录
		EXEC	dbo.SysGetTableFieldsCombine @ModifyObject,@I_PKId,@FieldsChanged OUTPUT

	END
    ELSE
	BEGIN
		--获取修改的单据信息
		SELECT @BillStates=PickingListStates
		FROM dbo.PickingList
		WHERE PickingListId = @I_PKId 

		SELECT @BillStatesDesc=BillStatesDescription
		FROM dbo.Bill
		INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
		WHERE BillName='PickingListOM' AND BillStatesName=@BillStates
		AND IsERP=0

		IF @BillStates<>'10'
		BEGIN
			SELECT @I_ReturnMessage='ServerMessage:此单据当前状态【'+@BillStatesDesc+'】,不允许修改!'
			RETURN -1
		END
		
		--获更新前的记录
		EXEC	dbo.SysGetTableFieldsCombine @ModifyObject,@I_PKId,@FieldsValueOld OUTPUT

		UPDATE dbo.PickingList SET 
			PickingListDescription=@PickingListDescription,
			DateRequired=@DateRequired,
			FactoryId=@FactoryId,
			VendorId=@VendorId,
			ModifyDate=GETDATE()
		WHERE PickingListId=@I_PKId

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

