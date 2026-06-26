-- =============================================
-- Author:        <OrBit Team HF0029>
-- Create date:   <2024/12/13 >
-- Description:   <领料单关闭：生产、杂发、委外、外协>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[PickingListCloseDoMethod]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT, --向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKid CHAR(12) ='',				--主键
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(100)='',		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@CloseReason NVARCHAR(MAX)=''
AS
BEGIN 

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--通用

	DECLARE @BillName NVARCHAR(50)=''

	--单据
	DECLARE @PickingListId CHAR(12)=''
	DECLARE @PickingListClass VARCHAR(2)=''
	DECLARE @PickingListStates VARCHAR(10)=''
	DECLARE @PickingListStatesDesc NVARCHAR(50)=''
	DECLARE @PickingListName NVARCHAR(50)=''

	IF ISNULL(@I_PKid,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请选择有效行项.'
		RETURN -1
	END

-- 	IF ISNULL(@CloseReason,'')=''
-- 	BEGIN
-- 		SET @I_ReturnMessage='ServerMessage:备注不能为空值.'
-- 		RETURN -1
-- 	END

	---查询状态
	SELECT 
		@PickingListId=PickingListId,
		@PickingListStates=PickingListStates,
		@PickingListClass=PickingListClass,
		@PickingListName=PickingListName
	FROM dbo.PickingList 
	WHERE PickingListId=@I_PKid

	--对应的单据名称
	SET @BillName=CASE @PickingListClass
					   WHEN '01' THEN 'PickingListPR'
					   WHEN '02' THEN 'PickingListOther'
					   WHEN '03' THEN 'PickingListOM'
					   WHEN '04' THEN 'PickingListPO'
					   ELSE '' END

	SELECT
		@PickingListStates=BillStatesName,
		@PickingListStatesDesc=BillStatesDescription
	FROM	dbo.Bill 
	INNER JOIN dbo.BillStates ON Bill.BillId =BillStates.BillId
	WHERE BillName = @BillName AND BillStatesName=@PickingListStates
	AND IsERP=0

	--非过账失败，不允许关闭
	IF @PickingListStates<>'41'
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:此单据当前状态 ['+@PickingListStatesDesc+'] 不允许关闭操作！'
		RETURN -1
	END
	
	--是否存在行项目
	IF NOT EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId = @PickingListId)
	BEGIN
	    SET @I_ReturnMessage ='ServerMessage:没有找到单据相关明细行项，不能审核操作！'
		RETURN -1
	END

	--检查退料
	IF EXISTS(
	    SELECT 1 FROM dbo.PickingListItem join MOItem on MOItem.MOItemId = PickingListItem.MOItemId
         WHERE PickingListId=@I_PKid
               AND ToSAPStates='过账失败'
                and PickingListItem.QtyIssued > isnull(MOItem.ItemQtyBack,0)
    )
	    Begin
            SET @I_ReturnMessage ='ServerMessage:存在退料数小于发放数，不能关闭领料单，请检查！'
            RETURN -1
        END

	--检查是否存在退料数大于或等于需求数
	IF EXISTS(
         SELECT 1 FROM dbo.MOItem
            WHERE MOItemId IN (SELECT MOItemId FROM dbo.PickingListItem WHERE PickingListId=@I_PKid  AND ToSAPStates='过账失败')
            AND (MOItem.ItemQtyIssued - isnull(MOItem.ItemQtyBack,0)) != ItemQtyRequired
	)
	BEGIN
	    SET @I_ReturnMessage ='ServerMessage:工单明细 需求量 = 领料数量 - 物料退回数，才能关闭领料单，请检查！'
		RETURN -1
	END

	
		
	 ---执行审核
	UPDATE dbo.PickingList SET 
		PickingListStates='42'		
	WHERE PickingListId=@I_PKid

-- 	DECLARE @PickingListCloseId CHAR(12)=''
-- 	EXEC dbo.SysGetObjectPKId '','PickingListClose',@PickingListCloseId OUTPUT
-- 	INSERT INTO [dbo].[PickingListClose]
--            ([PickingListCloseId]
--            ,[PickingListId]
--            ,[CloseReason]
--            ,[CreateUserId]
--            ,[CreateDate])
--      VALUES
--            (@PickingListCloseId
--            ,@PickingListId
--            ,@CloseReason
--            ,@I_OrBitUserId
--            ,GETDATE())
   SET @I_ReturnMessage ='ServerMessage:单据关闭完成完成！'
   RETURN 0
END
go

