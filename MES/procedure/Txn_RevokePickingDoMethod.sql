-- =============================================
-- Author:		<OrBit Team HK0313>
-- Create date: <2022.01.14>
-- Description:	<撤销领料申请>
-- Rev: 1.00
--=============================================
CREATE PROC [dbo].[Txn_RevokePickingDoMethod]
@I_Sender nvarchar(200)='', --客户端执行按钮
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_ExceptionFieldName nvarchar(100)='' output, --向客户端报告引起冲突的字段
@I_LanguageId char(1)='1',				--客户端传入的语言ID	
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKId char(12) = '',				--主键
@I_SourcePKId char(12)='',			--执行拷贝时传入的源主键  
@I_ParentPKId char(12)='',			--父级主键
@I_Parameter nvarchar(100)='',		--插件参数	
-- ======================= 以上是系统参数 ============================
@MOName VARCHAR(32)=''

AS
BEGIN
	-- set NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	set NOCOUNT ON; 
	set TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--SET @I_ReturnMessage='ServerMessage:'+@ToWareHouseId
	--	RETURN -1

	DECLARE @RESULT INT=0
	DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10)

	DECLARE @MOId CHAR(12)
	DECLARE @PickingListId CHAR(12)
	DECLARE @PickingListName VARCHAR(50)
	DECLARE @MOAllotRequestId CHAR(12)

	IF ISNULL(@MOName,'')=''
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:请扫描工单号！'
		RETURN -1
	END

	IF NOT EXISTS(SELECT 1 FROM MO WHERE MOName=@MOName)
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:工单号【'+@MOName+'】不存在！'
		RETURN -1
	END

	SELECT @MOId=MOId FROM MO WHERE MOName=@MOName

	
	--获取已申请但未过账的领料单
	IF NOT EXISTS(SELECT 1 FROM PickingList_MO A
	INNER JOIN PickingList B ON A.PickingListId=B.PickingListId
	WHERE A.MOId=@MOId)
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:工单号【'+@MOName+'】还未创建领料单，无需撤销！'
		RETURN -1
	END

	
	IF EXISTS(SELECT 1 FROM PickingList_MO A
	INNER JOIN PickingListItem B ON A.PickingListId=B.PickingListId AND A.MOId=B.MOId
	INNER JOIN PickingListItemLot C ON B.PickingListItemId=C.PickingListItemId
	WHERE A.MOId=@MOId)
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:工单号【'+@MOName+'】已领料或已扫描物料，无法撤销！'
		RETURN -1
	END

	DECLARE PICK CURSOR
	FOR
	SELECT A.PickingListId,B.MOAllotRequestId FROM PickingList_MO A
	INNER JOIN PickingList B ON A.PickingListId=B.PickingListId
	WHERE A.MOId=@MOId

	OPEN PICK

	FETCH NEXT FROM PICK INTO @PickingListId,@MOAllotRequestId

	WHILE @@FETCH_STATUS=0
	BEGIN
		DELETE FROM PickingListItem WHERE PickingListId=@PickingListId AND MOId=@MOId
		DELETE FROM PickingList_MO WHERE PickingListId=@PickingListId AND MOId=@MOId
		
		IF NOT EXISTS(SELECT 1 FROM PickingList_MO WHERE PickingListId=@PickingListId)
		BEGIN
			DELETE FROM PickingList WHERE PickingListId=@PickingListId
		END

		DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@MOAllotRequestId AND MOId=@MOId
		IF NOT EXISTS(SELECT 1 FROM MOAllotMODetail WHERE MOAllotRequestId=@MOAllotRequestId)
		BEGIN
			DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@MOAllotRequestId
			DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@MOAllotRequestId
		END

		FETCH NEXT FROM PICK INTO @PickingListId,@MOAllotRequestId
	END

	CLOSE PICK --关闭游标
	DEALLOCATE PICK --释放游标

	SET @I_ReturnMessage ='ServerMessage:工单号【'+@MOName+'】已成功撤销领料，请重新领料！'

	RETURN 0
END

 



go

