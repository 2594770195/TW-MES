

-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/04/09 17:24:04:3141>
-- Description:   <领料单审核：生产、杂发、委外、外协>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[PickingListApproveCancelDoMethod]
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

	--ty
	DECLARE @BillName NVARCHAR(50)=''

	--bill
	DECLARE @PickingListId CHAR(12)
	DECLARE @PickingListClass VARCHAR(2)=''
	DECLARE @PickingListStates VARCHAR(10)=''
	DECLARE @PickingListStatesDesc NVARCHAR(50)=''
	DECLARE @PickingListName NVARCHAR(50)


	IF ISNULL(@I_PKid,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请选择有效行项.'
		RETURN -1
	END

	---查询状态
	SELECT 
		@PickingListId=PickingListId,
		@PickingListStates=PickingListStates,
		@PickingListName=PickingListName,
		@PickingListClass=PickingListClass
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


	--非“已审核”状态，不允许审核操作
	IF ISNULL(@PickingListStates,'') NOT IN ('20')
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:此单据当前状态 ['+@PickingListStatesDesc+'] 不允许弃审操作!'
		RETURN -1
	END

	IF @PickingListClass='02'
	BEGIN 
	  DECLARE @LotSN NVARCHAR(20)=''


	  	DECLARE cursor_2 CURSOR LOCAL FAST_FORWARD FOR  
		SELECT  plil.LotSN
		FROM dbo.PickingListItemLot AS plil
		INNER JOIN dbo.PickingListItem AS pli ON pli.PickingListItemId = plil.PickingListItemId
		INNER JOIN dbo.PickingList AS pl ON pl.PickingListId = pli.PickingListId
		INNER JOIN dbo.WW_RMInventory AS wri ON wri.LotSN = plil.LotSN AND wri.LotStatus='9'
		WHERE pl.PickingListId=@PickingListId
		OPEN cursor_2
		FETCH NEXT FROM cursor_2 
		INTO @LotSN
		WHILE @@FETCH_STATUS = 0 
		BEGIN	
			EXEC dbo.PDA_MaterialIssueRepeal @I_Sender = @I_Sender,                                      -- nvarchar(200)
			                                 @I_ReturnMessage = @I_ReturnMessage OUTPUT,           -- nvarchar(max)
			                                 @I_ExceptionFieldName = @I_ExceptionFieldName OUTPUT, -- nvarchar(100)
			                                 @I_LanguageId = @I_LanguageId,                                   -- char(1)
			                                 @I_PlugInCommand = @I_PlugInCommand,                                -- varchar(5)
			                                 @I_OrBitUserId = @I_OrBitUserId,                                  -- char(12)
			                                 @I_OrBitUserName = @I_OrBitUserName,                               -- nvarchar(100)
			                                 @I_ResourceId = @I_ResourceId,                                   -- char(12)
			                                 @I_ResourceName = @I_ResourceName,                                -- nvarchar(100)
			                                 @I_PKid =@I_PKid,                                         -- char(12)
			                                 @I_ParentPKId = @I_ParentPKId,                                   -- char(12)
			                                 @I_Parameter = @I_Parameter,                                   -- nvarchar(max)
			                                 @BoxOrLotSN = @LotSN                                     -- nvarchar(100)
			

			FETCH NEXT FROM cursor_2 
			INTO @LotSN
		END
		CLOSE cursor_2
		DEALLOCATE cursor_2 



	END 

	IF EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@I_PKid AND QtyIssued>0)
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:此单据存在实际发料数，禁止取消审核！'
		RETURN -1    
	END

	---执行审核
	UPDATE dbo.PickingList SET 
		PickingListStates='10', 
		ApproveUserId = '', 
		ApproveDate =NULL
	WHERE PickingListId=@I_PKid

	SET @I_ReturnMessage ='ServerMessage:弃审完成！'

	RETURN 0
END






go

