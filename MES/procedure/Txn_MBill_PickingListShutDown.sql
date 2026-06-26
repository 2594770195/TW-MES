-- =============================================
-- Author:        <OrBit Team Orbchay HK0325 >
-- Create date:   <2021/08/02 09:57:42:1539>
-- Description:   <领来单强制关闭操作>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE  PROCEDURE  [dbo].[Txn_MBill_PickingListShutDown]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_Parameter NVARCHAR(MAX)='',		--插件参数
@I_PKId CHAR(12) ='',
---------------------------------------------
@PickingListName NVARCHAR(50)='',
@CreateDate DATETIME=NULL 

AS
BEGIN

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	

	--通用信息
	DECLARE @return_value INT =-1
	DECLARE @Enter VARCHAR(2)=CHAR(13)+CHAR(10)
	DECLARE @BillName  NVARCHAR(50)=''

	--领料单信息
	--bill
	DECLARE @PickingListId CHAR(12)=''
	DECLARE @PickingListClass VARCHAR(2)=''
	DECLARE @PickingListStates VARCHAR(10)=''
	DECLARE @StatesName VARCHAR(10)=''
	DECLARE @StateDesc NVARCHAR(50)=''
	DECLARE @VendorId CHAR(12)=''
	DECLARE @FactoryId CHAR(12)=''
	DECLARE @FactoryName NVARCHAR(50)=''
	DECLARE @DivisionId CHAR(12)=''
	DECLARE @ToWorkcenterId CHAR(12)='' --发料的目标工作中心
	--billitem
	DECLARE @PickingListItemId CHAR(12)=''
	DECLARE @QtyRequired DECIMAL(18,8)=0
	DECLARE @QtyIssued DECIMAL(18,8)=0
	DECLARE @ProductId CHAR(12)=''
	DECLARE @ExceedQty DECIMAL(18,8)=0
	DECLARE @MOId CHAR(12)=''
	DECLARE @MOName NVARCHAR(50)=''
	DECLARE @MOItemId CHAR(12)=''  --工单明细Id
	DECLARE @POId CHAR(12)=''
	DECLARE @POName NVARCHAR(50)=''
	DECLARE @POItemMId CHAR(12)='' --采购订单明细物料Id
	DECLARE @WarehouseId CHAR(12)='' --发料仓库
	DECLARE @UOMId CHAR(12)=''
	--billitemlot
	DECLARE @LotSN NVARCHAR(50)=''

	--原始单据物料删除比较
	DECLARE @DeleteItemSequence VARCHAR(20)=''
	DECLARE @DeleteProductId CHAR(12)=''
	DECLARE @DeleteProductName NVARCHAR(50)=''
	DECLARE @DeleteMOItemId CHAR(12)=''
	DECLARE @DeletePOItemMId CHAR(12)=''

	--超发管理信息
	DECLARE @ExceedPickingId CHAR(12)=''
	DECLARE @ExceedPickingItemId CHAR(12)=''

	--调拨单
	DECLARE @ProductAllotId CHAR(12)=''
	DECLARE @ProductAllotName NVARCHAR(50)=''
	DECLARE @ToWarehouseId CHAR(12)='' --调拨的目标仓库,取工厂对应的寄存仓库
	--billitem
	DECLARE @ProductAllotItemId CHAR(12)=''
	DECLARE @ItemLotPKId char(12)=''
	DECLARE @BoxSN VARCHAR(100)
	DECLARE @ItemSequence VARCHAR(20)=''
	DECLARE @UploadIngId CHAR(12)
	DECLARE @InterfaceItemId CHAR(12)

	DECLARE @PProductId CHAR(12)
	DECLARE @PQty DECIMAL(18,8)
	DECLARE @PickingListItemLotId CHAR(12)

	DECLARE @CellId CHAR(12)
	DECLARE @PLotSN VARCHAR(100)
	DECLARE @ProductName NVARCHAR(64)
	DECLARE @WQty DECIMAL(18,8)

	DECLARE @AdviceCellId CHAR(12)

	DECLARE @PickingQty DECIMAL(18,8)
	DECLARE @OrgLotSN VARCHAR(50)

	DECLARE @API_ReturnMessage NVARCHAR(MAX)=''
	DECLARE @Api_ReturnValue INT=-1

	DECLARE @RFC_ReturnMessage NVARCHAR(MAX)=''
	DECLARE @PickingList_MOId CHAR(12)=''
	DECLARE @MOName1 NVARCHAR(50)=''

	DECLARE @SPickingListItemId CHAR(12)=''
	DECLARE @SItemSequence NVARCHAR(30)=''

	

IF ISNULL(@PickingListName,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:没有获取到领料单，请检查！'
		RETURN -1
	END

	---查询状态
	SELECT 
		@PickingListId=PickingListId,
		@PickingListClass=PickingListClass,
		@PickingListStates=PickingListStates,
		@PickingListName=PickingListName,
		@FactoryId=FactoryId,
		@VendorId=ISNULL(VendorId,''),
		@ToWorkcenterId=ISNULL(ToWorkcenterId,''),
		@DivisionId=ISNULL(DivisionId,'')
	FROM dbo.PickingList 
	WHERE PickingListName=@PickingListName

	SELECT @FactoryName=FactoryName
	FROM dbo.Factory
	WHERE FactoryId=@FactoryId

	IF ISNULL(@PickingListId,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:领料单['+@PickingListName+']不存在，请检查！'
		RETURN -1
	END

	--对应的单据名称
	SET @BillName=CASE @PickingListClass
					   WHEN '01' THEN 'PickingListPR'
					   WHEN '02' THEN 'PickingListOther'
					   WHEN '03' THEN 'PickingListOM'
					   WHEN '04' THEN 'PickingListPO'
					   ELSE '' END

	SELECT
		@StatesName=BillStatesName,
		@StateDesc=BillStatesDescription
	FROM	dbo.Bill 
	INNER JOIN dbo.BillStates ON Bill.BillId =BillStates.BillId
	WHERE BillName = @BillName AND BillStatesName=@PickingListStates
	AND IsERP=0

	--非“审核”，“确认”，“过站失败”，禁止操作！
	IF @StatesName NOT IN ('41') 
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:此单据当前状态【'+@StateDesc+'】不允许【强制关闭】操作！'
		RETURN -1
	END

	--领料单是否存在行项目
	IF NOT EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId = @PickingListId)
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:没有找到领料单['+@PickingListName+']的相关明细行项，不允许【确认/过账】操作！'
		RETURN -1
	END

	IF EXISTS(SELECT 1 FROM dbo.PickingListItem AS pli 
	INNER JOIN dbo.MOItem AS mi ON mi.MOItemId = pli.MOItemId
	WHERE ISNULL(pli.QtyIssued,0)!=ISNULL(mi.ItemQtyBack,0) AND pli.ToSAPStates='过账失败' AND pli.PickingListId=@PickingListId)
	BEGIN 

	DECLARE @ItemLine NVARCHAR(20)=''
	SELECT @ItemLine=pli.ItemSequence FROM dbo.PickingListItem AS pli 
	INNER JOIN dbo.MOItem AS mi ON mi.MOItemId = pli.MOItemId
	WHERE ISNULL(pli.QtyIssued,0)!=ISNULL(mi.ItemQtyBack,0) AND pli.ToSAPStates='过账失败' AND pli.PickingListId=@PickingListId

	   SET @I_ReturnMessage ='ServerMessage:领料单['+@PickingListName+']的明细行项['+@ItemLine+']，存在未退料数，不允许【强制关闭】操作！'
		RETURN -1
	END 

	
	UPDATE dbo.PickingList SET 
			PickingListStates = '42', 
			ShutdownUserId = @I_OrBitUserId, 
			ShutdownDate = GETDATE() ,
			ShutdownResult='包材过账失败，SAP物料更改，无法过账'
		WHERE PickingListId = @PickingListId


	RETURN 0
END
go

