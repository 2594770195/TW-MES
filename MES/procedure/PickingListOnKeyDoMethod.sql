
-- =============================================
-- Author:        <OrBit Team Orbchay HK0313 >
-- Create date:   <2022/01/05 17:19:14:5601>
-- Description:   <领料单一键领料>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[PickingListOnKeyDoMethod]
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
		SET @I_ReturnMessage ='ServerMessage:此单据当前状态 ['+@PickingListStatesDesc+'] 不允许领料操作！'
		RETURN -1
	END
	


	--是否存在行项目
	IF NOT EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId = @PickingListId)
	BEGIN
	    SET @I_ReturnMessage ='ServerMessage:没有找到单据相关明细行项，不能领料操作！'
		RETURN -1
	END

	--IF EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@PickingListId AND ISNULL(WorkcenterId,'')='')
	--BEGIN
	--	SET @I_ReturnMessage='ServerMessage:领料单['+@PickingListName+']有的明细行没有仓库，请检查！'  
	--	RETURN -1
	--END 
	DECLARE @RESULT INT =0

	DECLARE @PickingListItemId CHAR(12)
	DECLARE @WareHouseId CHAR(12)
	DECLARE @ProductId CHAR(12)
	DECLARE @ProductName NVARCHAR(50)
	DECLARE @LotSN VARCHAR(50)

	DECLARE @NowDate DATETIME=GETDATE()

	BEGIN transaction Request

	DECLARE PickingDetailLot CURSOR  for

	SELECT PickingListItemId FROM PickingListItem WHERE PickingListId=@PickingListId AND QtyIssued<QtyRequired AND DeleteFlag IN(NULL,'','0')

	OPEN PickingDetailLot
	FETCH NEXT FROM PickingDetailLot INTO @PickingListItemId
	WHILE @@FETCH_STATUS =0
	BEGIN
		IF NOT EXISTS(SELECT 1 FROM PickingListItem WHERE PickingListItemId=@PickingListItemId AND QtyIssued<QtyRequired)
		BEGIN
			FETCH NEXT FROM PickingDetailLot INTO @PickingListItemId
			CONTINUE;
		END
						
		SELECT TOP 1 @WareHouseId=WorkcenterId,@ProductId=ProductId FROM PickingListItem WHERE PickingListItemId=@PickingListItemId AND QtyIssued<QtyRequired

		IF EXISTS(SELECT D.ProductFamilyName FROM PickingListItem A
		INNER JOIN Product B ON A.ProductId=B.ProductId
		INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
		INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
		WHERE A.PickingListItemId=@PickingListItemId AND D.ProductFamilyName IN('102850','102855','102857','102858','102859'))
		BEGIN
			SELECT @ProductName=TProductName FROM Product WHERE ProductId=@ProductId
			SET @LotSN='MES'+@ProductName;
		END
		ELSE
		BEGIN
			SELECT @LotSN=LotSN FROM WW_RMInventory WITH(NOLOCK)
			WHERE LotStatus='1' AND IsStorage=1 AND WorkcenterId=@WareHouseId AND ProductId=@ProductId AND ValidityEndDate>@NowDate
			ORDER BY IsSM DESC,EntryDate
		END
						
		IF EXISTS(SELECT 1 FROM WW_RMInventory WHERE LotSN=@LotSN AND LotStatus='1')
		BEGIN
			EXEC @RESULT=[dbo].[PDA_MaterialToPickingListPR]
			@I_Sender=@I_Sender,
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@PickingListName=@PickingListName,
			@BoxOrLotSN=@LotSN

			IF @RESULT<>0
			BEGIN
				ROLLBACK transaction Request
				return @RESULT
			END
		END
						
		FETCH NEXT FROM PickingDetailLot INTO @PickingListItemId
	END
	CLOSE PickingDetailLot --关闭游标
	DEALLOCATE PickingDetailLot --释放游标

	IF @@ERROR<>0
	BEGIN
		ROLLBACK transaction Request

		set @I_ReturnMessage='ServerMessage:领料失败!'
		return -1
	END
	ELSE
	BEGIN
		COMMIT transaction Request
	END

   SET @I_ReturnMessage ='ServerMessage:领料完成！'

   RETURN 0
END






go

