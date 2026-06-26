
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/04/09 17:19:14:5601>
-- Description:   <领料单审核：生产、杂发、委外、外协>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[PickingListApproveDoMethod]
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
@I_Parameter NVARCHAR(100)=''		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.


AS
BEGIN 

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--通用
	DECLARE @return_value INT =0
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


	--非“已创建”“待审核”状态，不允许审核操作
	IF @PickingListStates NOT IN ('10')
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:此单据当前状态 ['+@PickingListStatesDesc+'] 不允许审核操作！'
		RETURN -1
	END
	


	--是否存在行项目
	IF NOT EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId = @PickingListId)
	BEGIN
	    SET @I_ReturnMessage ='ServerMessage:没有找到单据相关明细行项，不能审核操作！'
		RETURN -1
	END

	--IF EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@PickingListId AND ISNULL(WorkcenterId,'')='')
	--BEGIN
	--	SET @I_ReturnMessage='ServerMessage:领料单['+@PickingListName+']有的明细行没有仓库，请检查！'  
	--	RETURN -1
	--END 


	 ---执行审核
	UPDATE dbo.PickingList SET 
		PickingListStates='20', 
		ApproveUserId = @I_OrBitUserId, 
		ApproveDate = GETDATE() 
	WHERE PickingListId=@I_PKid

   SET @I_ReturnMessage ='ServerMessage:审核完成！'

   RETURN 0
END






go

