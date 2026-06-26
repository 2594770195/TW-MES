-- =============================================
-- Author:        <OrBit Team Orbchay HK0325 >
-- Create date:   <2021/08/02 09:57:42:1539>
-- Description:   <领来单确认：统一存储过程。完成单据确认，数据处理、接口调用等>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[TxnBase_MBill_PickingListConfirm]
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

	;IF @CreateDate=NULL 
	BEGIN 
	   SET @CreateDate=GETDATE()
	END 

	  UPDATE InputParameter
		 SET ParameterValue =  REPLACE(@CreateDate,'-','')
            WHERE InterfaceItemId = 'IFIT000000T5'
                  AND ParameterName = 'POSTDAT';


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
	DECLARE @PWorkCenterId VARCHAR(100)
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

	--领料单明细临时表  --2023.9.27 新增 by HL0445
	DECLARE @TempPickingListItem TABLE(
							PickingListItemId CHAR(12),
							ProductId CHAR(12),
							QtyRequired DECIMAL(18,3),
							QtyIssued DECIMAL(18,3),
							ToSAPStates NVARCHAR(50)
					)

	
BEGIN TRY

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

	--非“审核”，“确认”，“过站失败”，禁止操作！ --增加 21 领料中状态 by HL0445 2023.9.27
	IF @StatesName NOT IN ('20','30','41','21') 
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:此单据当前状态【'+@StateDesc+'】不允许【确认/过账】操作！'
		RETURN -1
	END

	--领料单是否存在行项目
	IF NOT EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId = @PickingListId)
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:没有找到领料单['+@PickingListName+']的相关明细行项，不允许【确认/过账】操作！'
		RETURN -1
	END

	--IF NOT EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@PickingListId AND QtyIssued>0)
	--BEGIN
	--	SET @I_ReturnMessage='ServerMessage:领料单['+@PickingListName+']没有实际发料数，请检查！'  
	--	RETURN -1
	--END



	--检查工单明细物料是否存在
	IF @PickingListClass IN('01','03')
	BEGIN
		--SET @DeleteItemSequence=''
		--SET @DeleteProductId=''
		--SET @DeleteProductName=''
		--SET @DeleteMOItemId=''
		--SET @MOId=''

		--SELECT TOP 1 
		--	   @DeleteProductId=PickingListItem.ProductId,
		--	   @DeleteItemSequence=PickingListItem.ItemSequence,
		--	   @DeleteMOItemId=MOItem.MOItemId,
		--	   @MOId=MOItem.MOId
		--FROM dbo.PickingListItem
		--LEFT JOIN dbo.MOItem ON MOItem.MOItemId = PickingListItem.MOItemId
		--INNER JOIN PickingList_MO ON PickingListItem.PickingListId=PickingList_MO.PickingListId AND PickingListItem.MOId=PickingList_MO.MOId
		--WHERE PickingListItem.PickingListId=@PickingListId AND( MOItem.MOItemId IS NULL OR ISNULL(MOItem.DeleteFlag,'') IN('X','1'))
		--AND ISNULL(PickingListItem.ToSAPStates,'') =''

		--IF ISNULL(@DeleteProductId,'')<>''
		--BEGIN
		--	SELECT @MOName=MOName 
		--	FROM dbo.MO 
		--	WHERE MOId=@MOId

		--	SELECT @DeleteProductName=ProductName
		--	FROM dbo.Product
		--	INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
		--	WHERE ProductId=@DeleteProductId

		--	SET @I_ReturnMessage='ServerMessage:领料单【'+ISNULL(@PickingListName,'')+'】行【'+ISNULL(@DeleteItemSequence,'')+'】工单【'+ISNULL(@MOName,'')+'】物料【'+ISNULL(@DeleteProductName,'')+'】已被删除，请检查！请撤销这一行物料！'
		--		+@Enter+'工单明细表Id【'+ISNULL(@DeleteMOItemId,'')+'】'
		--	RETURN -1
		--END

		--SET @DeleteItemSequence=''
		--SET @DeleteProductId=''
		--SET @DeleteProductName=''
		--SET @DeleteMOItemId=''
		--SET @MOId=''
		----检查产品是否一致
		--SELECT TOP 1 
		--	   @DeleteProductId=PickingListItem.ProductId,
		--	   @DeleteItemSequence=PickingListItem.ItemSequence,
		--	   @DeleteMOItemId=MOItem.MOItemId,
		--	   @MOId=MOItem.MOId
		--FROM dbo.PickingListItem
		--LEFT JOIN dbo.MOItem ON MOItem.MOItemId = PickingListItem.MOItemId 
		--INNER JOIN PickingList_MO ON PickingListItem.PickingListId=PickingList_MO.PickingListId AND PickingListItem.MOId=PickingList_MO.MOId
		--WHERE PickingListItem.PickingListId=@PickingListId AND( MOItem.MOItemId IS NULL OR ISNULL(MOItem.DeleteFlag,'') IN('0',''))
		--AND ISNULL(PickingListItem.ToSAPStates,'') ='' AND MOItem.ProductId <> PickingListItem.ProductId

		--IF ISNULL(@DeleteProductId,'')<>''
		--BEGIN
		--	SELECT @MOName=MOName 
		--	FROM dbo.MO 
		--	WHERE MOId=@MOId

		--	SELECT @DeleteProductName=ProductName
		--	FROM dbo.Product
		--	INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
		--	WHERE ProductId=@DeleteProductId

		--	SET @I_ReturnMessage='ServerMessage:领料单【'+ISNULL(@PickingListName,'')+'】行【'+ISNULL(@DeleteItemSequence,'')+'】工单【'+ISNULL(@MOName,'')+'】物料【'+ISNULL(@DeleteProductName,'')+'】与实际工单物料不符，请检查！请撤销这一行物料！'
		--		+@Enter+'工单明细表Id【'+ISNULL(@DeleteMOItemId,'')+'】'
		--	RETURN -1
		--END


		SET @DeleteItemSequence=''
		SET @DeleteProductId=''
		SET @DeleteProductName=''
		SET @DeleteMOItemId=''
		SET @MOId=''
	--	--检查发料数是否大于工单需求数量
	--	SELECT TOP 1 
	--		   @DeleteProductId=PickingListItem.ProductId,
	--		   @DeleteItemSequence=PickingListItem.ItemSequence,
	--		   @DeleteMOItemId=MOItem.MOItemId,
	--		   @MOId=MOItem.MOId
	--	FROM dbo.PickingListItem
	--	LEFT JOIN dbo.MOItem ON MOItem.MOItemId = PickingListItem.MOItemId 
	--	INNER JOIN PickingList_MO ON PickingListItem.PickingListId=PickingList_MO.PickingListId AND PickingListItem.MOId=PickingList_MO.MOId
	--	INNER JOIN PickingListItemLot ON PickingListItem.PickingListItemId=PickingListItemLot.PickingListItemId
	--	INNER JOIN WW_RMInventory ON PickingListItemLot.LotSN=WW_RMInventory.LotSN AND WW_RMInventory.IsStorage=1
	--	WHERE PickingListItem.PickingListId=@PickingListId AND( MOItem.MOItemId IS NULL OR ISNULL(MOItem.DeleteFlag,'') IN('0',''))
	--	AND ISNULL(PickingListItem.ToSAPStates,'') ='' AND PickingListItem.QtyIssued>=PickingListItem.QtyRequired AND (PickingListItem.QtyIssued+ISNULL(MOItem.ItemQtyIssued,0)-ISNULL(MOItem.ItemQtyBack,0))>MOItem.ItemQtyRequired
		
	--	IF ISNULL(@DeleteProductId,'')<>''
	--	BEGIN
	--		SELECT @MOName=MOName 
	--		FROM dbo.MO 
	--		WHERE MOId=@MOId

	--		SELECT @DeleteProductName=ProductName
	--		FROM dbo.Product
	--		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
	--		WHERE ProductId=@DeleteProductId

	--		SET @I_ReturnMessage='ServerMessage:领料单【'+ISNULL(@PickingListName,'')+'】行【'+ISNULL(@DeleteItemSequence,'')+'】工单【'+ISNULL(@MOName,'')+'】物料【'+ISNULL(@DeleteProductName,'')+'】发料数超出当前工单需求数量，请检查！请调整领料数量重新领料！'
	--			+@Enter+'工单明细表Id【'+ISNULL(@DeleteMOItemId,'')+'】'
	--		RETURN -1
	--	END
	END

	--检查采购订单明细物料是否存在
	IF @PickingListClass IN('04')
	BEGIN
		SET @DeleteItemSequence=''
		SET @DeleteProductId=''
		SET @DeleteProductName=''
		SET @DeletePOItemMId=''
		SET @POId=''

		SELECT TOP 1 
			   @DeleteProductId=PickingListItem.ProductId,
			   @DeleteItemSequence=PickingListItem.ItemSequence,
			   @DeletePOItemMId=PickingListItem.POItemMId,
			   @POId=POId
		FROM dbo.PickingListItem
		LEFT JOIN dbo.POItemM ON POItemM.POItemMId = PickingListItem.POItemMId
		WHERE PickingListId=@PickingListId AND POItemM.POItemMId IS NULL

		IF ISNULL(@DeleteProductId,'')<>''
		BEGIN
			SELECT @POName=POName 
			FROM dbo.PO 
			WHERE POId=@POId

			SELECT @DeleteProductName=ProductName
			FROM dbo.Product
			INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
			WHERE ProductId=@DeleteProductId

			SET @I_ReturnMessage='ServerMessage:领料单【'+@PickingListName+'】行【'+@DeleteItemSequence+'】采购单【'+@POName+'】物料【'+@DeleteProductName+'】已被删除，请检查！请撤销这一行物料！'
				+@Enter+'采购订单明细物料表Id【'+@DeletePOItemMId+'】'
			RETURN -1
		END
	END

	SELECT @ToWareHouseId=ToWorkcenterId FROM PickingList WHERE PickingListId=@PickingListId

	IF ISNULL(@ToWarehouseId,'')='' and @PickingListClass='01'
	BEGIN
		 SET @I_ReturnMessage='ServerMessage:领料单['+@PickingListName+']目标工作中心不能为空！'
		 RETURN -1
	END

	--获取寄存仓库
	--IF @PickingListClass IN('03')
	--BEGIN
	--	SELECT @ToWarehouseId= WorkcenterId
	--	FROM dbo.Workcenter
	----	INNER JOIN dbo.Site ON Site.SiteId = Workcenter.SiteId
	--	INNER JOIN UserCode ON UserCode.UserCodeId=Workcenter.WorkcenterTypeId
	--	WHERE FactoryId=@FactoryId AND IsOMDepositW=1  AND UserCode.UserCodeName='02'
	--END

	DECLARE @RowCount INT =0
	DECLARE @RowId INT=1

	--1.如果审核状态，则先执行确认:单据确认、库存批号更新、产生超发寄存
	IF @StatesName='20'
	BEGIN 
		/************************************************** 自动发料 BEGIN ******************************************************/
		BEGIN TRANSACTION PickLot
		--包材如果未进行发料扫描，则自动扣减物料发料
		SELECT ROW_NUMBER() OVER(ORDER BY A.CreateDate) AS RowId,A.ProductId,(ISNULL(A.QtyRequired,0)-ISNULL(A.QtyIssued,0)) AS Qty,A.PickingListItemId,C.ProductName INTO #TEMP FROM PickingListItem A
		INNER JOIN Product B ON A.ProductId=B.ProductId
		INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
		INNER JOIN ProductFamily D ON C.ProductFamilyId =D.ProductFamilyId
		WHERE A.PickingListId=@PickingListId AND D.ProductFamilyName IN('102850','102855','102857','102858','102859') AND ISNULL(A.QtyRequired,0)>ISNULL(A.QtyIssued,0)
		AND A.DeleteFlag IN(NULL,'','0')

		SELECT @RowCount=COUNT(1) FROM #TEMP
		IF @RowCount>0
		BEGIN
			WHILE @RowId<=@RowCount
			BEGIN
				SELECT 
					@PProductId=ProductId,
					@PQty=Qty,
					@PickingListItemId=PickingListItemId,
					@ProductName=ProductName 
				FROM #TEMP WHERE RowId=@RowId
				
				SET @PWorkCenterId= ( SELECT WorkcenterID FROM PickingListItem WHERE PickingListItemID=@PickingListItemId)

				SET @PLotSN=(select top 1 lotsn from WW_RMInventory inner join product on WW_RMInventory.ProductId=product.ProductId where product.TProductName=@ProductName AND IsStorage=1 AND QTY!=0 AND WorkcenterId=@PWorkCenterId and qty>@QtyRequired)

				IF EXISTS(SELECT 1 FROM WW_RMInventory WHERE LotSN=@PLotSN)
				BEGIN
					SELECT @WQty=Qty,@CellId=CellId FROM WW_RMInventory WHERE LotSN=@PLotSN
					IF @WQty<@PQty SET @PQty=@WQty

					IF @PQty>0
					BEGIN
						EXEC dbo.SysGetObjectPKId '','PickingListItemLot',@PickingListItemLotId OUTPUT
						-- 写入发料表
						INSERT INTO dbo.PickingListItemLot
									(
									PickingListItemLotId,
									PickingListItemId,
									ProductId,
									LotSN,
									Qty,
									ActualPickQty,
									PickType,
									CellId,
									CreateUserId,
									CreateDate,
									IsPicking
									)
						VALUES
									(
									@PickingListItemLotId, -- PickingListItemLotId - char(12)
									@PickingListItemId, -- PickingListItemId - char(12)
									@PProductId, -- ProductId - char(12)
									@PLotSN, -- LotSN - nvarchar(50)
									@PQty, -- Qty - decimal(18, 8)
									@PQty, -- Qty - decimal(18, 8)
									'R', -- PickType - char(1)
									@CellId, -- CellId - char(12)
									@I_OrBitUserId, -- CreateUserId - char(12)
									GETDATE(), -- CreateDate - datetime
									1
									)

						--插入物料批号追踪表
						EXEC dbo.TxnBase_MLotTrack
							@I_OrBitUserId =@I_OrBitUserId, -- char(12)
							@I_PlugInCommand=@I_PlugInCommand,
							@I_ResourceId =@I_ResourceId, -- char(12)
							@LotSN = @PLotSN, -- nvarchar(50) --物料批号
							@LotQty = @PQty, -- decimal(18, 6)--数量
							@TxnCode ='M-领料下架' , -- nvarchar(50) --事务码
							@OrderName =@PickingListName , -- nvarchar(50) --单据号
							@Remark = N'' -- nvarchar(200) --备注

						--更新明细发料数
						UPDATE dbo.PickingListItem SET 
							QtyIssued =ISNULL( QtyIssued,0) + @PQty
						WHERE PickingListItemId = @PickingListItemId

						--更新库存数量666
						UPDATE dbo.WW_RMInventory SET 
							Qty=Qty-@PQty,
							ModifyDate=GETDATE()
						WHERE LotSN=@PLotSN
					END
					ELSE IF @PickingListClass<>'01'
					BEGIN
						ROLLBACK TRANSACTION PickLot
						SET @I_ReturnMessage ='ServerMessage:产品['+@ProductName+']库存不足'
						RETURN -1
					END

				END

				SET @RowId+=1;
			END

		END
		
		--DECLARE PickingDetailLot CURSOR  for

		----线边仓领料自动发料
		--SELECT PickingListItemId FROM PickingListItem WHERE PickingListId=@PickingListId AND QtyIssued<QtyRequired AND DeleteFlag IN(NULL,'','0') AND WorkcenterId=@ToWareHouseId

		--OPEN PickingDetailLot
		--FETCH NEXT FROM PickingDetailLot INTO @PickingListItemId
		--WHILE @@FETCH_STATUS =0
		--BEGIN
		--	IF NOT EXISTS(SELECT 1 FROM PickingListItem WHERE PickingListItemId=@PickingListItemId AND QtyIssued<QtyRequired)
		--	BEGIN
		--		FETCH NEXT FROM PickingDetailLot INTO @PickingListItemId
		--		CONTINUE;
		--	END
						
		--	SELECT TOP 1 @WareHouseId=WorkcenterId,@ProductId=ProductId FROM PickingListItem WHERE PickingListItemId=@PickingListItemId AND QtyIssued<QtyRequired

		--	SET @LotSN=''
		--	IF EXISTS(SELECT D.ProductFamilyName FROM PickingListItem A
		--	INNER JOIN Product B ON A.ProductId=B.ProductId
		--	INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
		--	INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
		--	WHERE A.PickingListItemId=@PickingListItemId AND D.ProductFamilyName IN('102850','102855','102857','102858','102859'))
		--	BEGIN
		--		SELECT @ProductName=TProductName FROM Product WHERE ProductId=@ProductId
		--		SET @LotSN='MES'+@ProductName;
		--	END
		--	ELSE
		--	BEGIN
		--		SELECT @LotSN=LotSN FROM WW_RMInventory WITH(NOLOCK)
		--		WHERE LotStatus='1' AND IsStorage=1 AND WorkcenterId=@WareHouseId AND ProductId=@ProductId AND ValidityEndDate>GETDATE() AND IsExceedPicking=1
		--		ORDER BY IsSM DESC,EntryDate
		--	END

		--	IF NOT EXISTS(SELECT 1 FROM WW_RMInventory WHERE LotSN=@LotSN AND LotStatus='1' AND IsStorage=1 AND Qty>0) AND @PickingListClass<>'01'
		--	BEGIN
		--		ROLLBACK TRANSACTION PickLot
		--		SET @I_ReturnMessage ='ServerMessage:产品['+@ProductName+']库存不足'
		--		RETURN -1
		--	END
					
		--	IF EXISTS(SELECT 1 FROM WW_RMInventory WHERE LotSN=@LotSN AND LotStatus='1' AND IsStorage=1 AND Qty>0)
		--	BEGIN
		--		EXEC @return_value=[dbo].[PDA_MaterialToPickingListPR]
		--		@I_Sender=@I_Sender,
		--		@I_ReturnMessage=@I_ReturnMessage OUTPUT,
		--		@I_OrBitUserId=@I_OrBitUserId,
		--		@I_ResourceId=@I_ResourceId,
		--		@PickingListName=@PickingListName,
		--		@BoxOrLotSN=@LotSN

		--		IF @return_value<>0
		--		BEGIN
		--			ROLLBACK TRANSACTION PickLot
		--			return @return_value
		--		END
		--	END	
			
						
		--	FETCH NEXT FROM PickingDetailLot INTO @PickingListItemId
		--END
		--CLOSE PickingDetailLot --关闭游标
		--DEALLOCATE PickingDetailLot --释放游标

		IF @@ERROR <>0
			ROLLBACK TRANSACTION PickLot
		ELSE
			COMMIT TRANSACTION PickLot
					
		/************************************************** 自动发料 END ******************************************************/


		DECLARE @NewLotSN VARCHAR(32)=''
		DECLARE @SNRuleId CHAR(12)

		IF @PickingListClass='01'
		BEGIN
			--获取已发完物料待过账的工单
			DECLARE @PickingListMO TABLE
			(
				PickingListItemId CHAR(12)
			)

			INSERT INTO @PickingListMO(PickingListItemId)
			SELECT DISTINCT PickingListItemId FROM PickingListItem WHERE PickingListId=@PickingListId AND QtyIssued>=QtyRequired
			AND ISNULL(ToSAPStates,'')=''

			IF NOT EXISTS(SELECT 1 FROM @PickingListMO)
			BEGIN

			IF @PickingListClass='01'
			BEGIN			 
		       DECLARE cursor1  CURSOR LOCAL FAST_FORWARD FOR --创建游标   
			   SELECT pli.PickingListItemId,pli.ItemSequence
			   FROM dbo.PickingListItem AS pli
			   WHERE pli.QtyRequired=QtyIssued AND ISNULL(pli.ToSAPStates,'') ='过账失败'
			    AND pli.PickingListId=@PickingListId
			   OPEN cursor1 --打开游标
			   FETCH NEXT  FROM  Cursor1 INTO @SPickingListItemId,@SItemSequence --从游标变量中读取值		   
			   WHILE @@FETCH_STATUS=0 --判断FETCH语句是否执行成功	   
			   BEGIN
			     IF NOT EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE  ui.ISUpload=1 AND ui.UploadInterfaceId='IFIT000000T5') 
			   BEGIN
				IF NOT  EXISTS(SELECT ui.MatDoc FROM dbo.UploadIng AS ui WHERE ui.UploadDateId=@SPickingListItemId AND ISNULL(ui.MatDoc,'')<>'' AND ui.MatDoc!='ServerMessage:物料或类型错误，暂时不支持上传SAP，请检查！！！！！')
				--AND NOT EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE ui.UploadDateId= AND ui.ISUpload=1)
				BEGIN  
				 IF EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE ui.UploadDateId=@SPickingListItemId AND ui.ISUpload=1)
				 BEGIN 

			     	EXEC dbo.RfcSAPSync @I_ReturnMessage =@RFC_ReturnMessage OUTPUT,
						@ItemName =N'U_PickingListPR',
							@UploadIngId=@UploadIngId

					IF  @RFC_ReturnMessage LIKE '%成功%'
					BEGIN 
					  UPDATE dbo.PickingListItem set ToSAPStates='过账成功',SAPInfor=REPLACE(@RFC_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId

					END 
					ELSE 
					BEGIN 
					   UPDATE dbo.PickingListItem set ToSAPStates='过账失败',SAPInfor=REPLACE(@RFC_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId
					END 

				SET @I_ReturnMessage=ISNULL(@I_ReturnMessage,'')+@RFC_ReturnMessage+@Enter

				 END  
				 ELSE
				 BEGIN 
					SELECT  @InterfaceItemId=InterfaceItemId FROM dbo.InterfaceItem WHERE ItemName='U_PickingListPR'

					EXEC  SysGetObjectPKId '','UploadIng',@UploadIngId OUTPUT
					INSERT INTO dbo.UploadIng
					(
						UploadIngId,
						UploadInterfaceId,
						UploadDateId,
						ISUpload,
						UserId,
						BillsMark,
						MatDoc,
						CreateDate
					)
					VALUES
					(	@UploadIngId,       -- UploadIngId - char(12)
						@InterfaceItemId,       -- UploadInterfaceId - char(12)
						@SPickingListItemId,       -- UploadDateId - char(12)
						'true',     -- ISUpload - bit
						@I_OrBitUserId,       -- UserId - char(12)
						@PickingListName+','+@SItemSequence,      -- BillsMark - nvarchar(50)
						N'',      -- MatDoc - nvarchar(50)
						GETDATE() -- CreateDate - datetime
					)

					EXEC dbo.RfcSAPSync @I_ReturnMessage =@RFC_ReturnMessage OUTPUT,
							@ItemName =N'U_PickingListPR',
							@UploadIngId=@UploadIngId

					IF  @RFC_ReturnMessage LIKE '%成功%'
					BEGIN 
					  UPDATE dbo.PickingListItem set ToSAPStates='过账成功',SAPInfor=REPLACE(@RFC_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId

					END 
					ELSE 
					BEGIN 
					   UPDATE dbo.PickingListItem set ToSAPStates='过账失败',SAPInfor=REPLACE(@RFC_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId
					END 

				   SET @I_ReturnMessage=ISNULL(@I_ReturnMessage,'')+@RFC_ReturnMessage+@Enter
				END  
			   END 
			   ELSE 
			   BEGIN 
				  UPDATE dbo.PickingListItem set ToSAPStates='过账成功',SAPInfor='' WHERE PickingListItemId=@SPickingListItemId
			   END 

			    UPDATE dbo.UploadIng SET ISUpload=0 WHERE UploadIngId=@UploadIngId
				END 
			   FETCH NEXT FROM Cursor1 INTO @SPickingListItemId,@SItemSequence --读取游标变量中的数据

			   END

			   CLOSE cursor1 --关闭游标

			   DEALLOCATE cursor1; --释放游标

				--2023.9.27 注释  by HL0445
				--IF NOT EXISTS(SELECT 1 FROM dbo.PickingList AS pl inner JOIN dbo.PickingListItem AS plm ON plm.PickingListId = pl.PickingListId
				--					WHERE ISNULL(plm.ToSAPStates ,'')='' AND pl.PickingListId=@PickingListId )	   
				--BEGIN

				--IF EXISTS(SELECT 1 FROM dbo.PickingList AS pl inner JOIN dbo.PickingListItem AS plm ON plm.PickingListId = pl.PickingListId
				--					WHERE (plm.ToSAPStates='过账失败' OR ISNULL(plm.ToSAPStates ,'')='') AND pl.PickingListId=@PickingListId )
				--					BEGIN 
				--					  UPDATE dbo.PickingList SET 
				--							PickingListStates='41'
				--						WHERE PickingListId=@PickingListId
				--					END 
				--					ELSE 
				--					BEGIN 
				--					   UPDATE dbo.PickingList SET 
				--							PickingListStates='40'
				--						WHERE PickingListId=@PickingListId
				--					END 

				--END

				--更新领料单状态  2023.9.27 增加 by HL0445
				BEGIN 
					DELETE FROM @TempPickingListItem
					--获取领料单明细数据
					INSERT INTO @TempPickingListItem(PickingListItemId,ProductId,QtyRequired,QtyIssued,ToSAPStates)
					SELECT PickingListItemId,ProductId,QtyRequired,QtyIssued,ToSAPStates 
					FROM dbo.PickingListItem 
					WHERE PickingListId=@PickingListId AND ISNULL(DeleteFlag,'')='' 

					--检查领料单是否全部发料
					IF (SELECT COUNT(1) FROM @TempPickingListItem WHERE (ISNULL(QtyRequired,0)-ISNULL(QtyIssued,0))>0)>0
					BEGIN
						--更新明细行状态 20 领料中
						UPDATE dbo.PickingListItem SET ItemStates='20'
						WHERE PickingListItemId IN (SELECT PickingListItemId FROM @TempPickingListItem)

						--更新领料单状态 21 领料中
						UPDATE dbo.PickingList SET PickingListStates='20'WHERE PickingListId=@PickingListId 
					END 
					ELSE BEGIN 
						--检查是否全部过账成功
						IF (SELECT COUNT(1) FROM @TempPickingListItem WHERE ISNULL(ToSAPStates,'')<>'过账成功')>0
						BEGIN 
							UPDATE dbo.PickingList SET PickingListStates='41'WHERE PickingListId=@PickingListId 
						END 
						ELSE BEGIN 
							UPDATE dbo.PickingList SET PickingListStates='40'WHERE PickingListId=@PickingListId 
						END

						--更新明细行状态 30 已完成
						UPDATE dbo.PickingListItem SET ItemStates='30'
						WHERE PickingListItemId IN (SELECT PickingListItemId FROM @TempPickingListItem)
					END 
				END



			END 
			  IF ISNULL(@I_ReturnMessage,'')=''
			  BEGIN 
				SET @I_ReturnMessage ='ServerMessage:没有可过账的数据！'
				RETURN -1
              END 
			  IF  @RFC_ReturnMessage LIKE '%成功%'
			  RETURN 0
			  ELSE RETURN -1
				
			END

			BEGIN TRANSACTION SplitLot
			--自动生成新批次
			SELECT ROW_NUMBER() OVER(ORDER BY A.CreateDate) AS RowId,F.PickingListItemLotId,F.LotSN,F.Qty INTO #BCNewLotMO FROM PickingListItem A
			INNER JOIN Product B ON A.ProductId=B.ProductId
			INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
			INNER JOIN ProductFamily D ON C.ProductFamilyId =D.ProductFamilyId
			INNER JOIN @PickingListMO E ON A.PickingListItemId=E.PickingListItemId
			INNER JOIN PickingListItemLot F ON A.PickingListItemId=F.PickingListItemId
			WHERE A.PickingListId=@PickingListId AND A.QtyIssued>0
			AND A.DeleteFlag IN(NULL,'','0') AND ISNULL(F.OrgLotSN,'')=''
			AND D.ProductFamilyName IN('102850','102855','102857','102858','102859')

			SET @RowCount=0
			SET @RowId=1
			SET @PLotSN=''
			

			SELECT @SNRuleId=SNRuleId FROM dbo.SNRule WHERE SNRuleName='WW_MP_LotSN' AND IsActivity=1

			SELECT @RowCount=COUNT(1) FROM #BCNewLotMO

			WHILE @RowId<=@RowCount
			BEGIN
				SELECT 
					@PQty=Qty,
					@PickingListItemLotId=PickingListItemLotId,
					@PLotSN=LotSN
				FROM #BCNewLotMO WHERE RowId=@RowId

				IF EXISTS(SELECT 1 FROM WW_RMInventory WHERE LotSN=@PLotSN)
				BEGIN
					--再加批次数量原因：领料时已扣一次，拆批时又扣一次，需要加回来
					UPDATE WW_RMInventory SET Qty+=@PQty,LotStatus='1' WHERE LotSN=@PLotSN


					EXEC @return_value = [dbo].[StartRuleSNDoMethod]
							@I_ReturnMessage = @I_ReturnMessage OUTPUT,
							@SNRuleId = @SNRuleId,
							@RCharStr = N'',
							@JumpQty=1,
							@NewSN = @NewLotSN OUTPUT

					EXEC @return_value=[dbo].[PDA_LotSplitToEmptyLot]
					@I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@I_PlugInCommand=@I_PlugInCommand,
					@I_OrBitUserId=@I_OrBitUserId,
					@I_ResourceId=@I_ResourceId,
					@SplitLotSN=@PLotSN,
					@SplitQty=@PQty,
					@CombineLotSN=@NewLotSN

					IF @return_value<>0
					BEGIN
						ROLLBACK TRANSACTION SplitLot
						RETURN @return_value
					END

					UPDATE PickingListItemLot SET LotSN=@NewLotSN,OrgLotSN=@PLotSN WHERE PickingListItemLotId=@PickingListItemLotId

					--UPDATE WW_RMInventory SET IsStorage=0 WHERE LotSN=@NewLotSN
				END
				SET @RowId+=1;
			END
			
			--自动生成新批次
			SELECT ROW_NUMBER() OVER(ORDER BY A.CreateDate) AS RowId,F.PickingListItemLotId,F.LotSN,F.Qty INTO #NewLotMO FROM PickingListItem A
			INNER JOIN Product B ON A.ProductId=B.ProductId
			INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
			INNER JOIN ProductFamily D ON C.ProductFamilyId =D.ProductFamilyId
			INNER JOIN @PickingListMO E ON A.PickingListItemId=E.PickingListItemId
			INNER JOIN PickingListItemLot F ON A.PickingListItemId=F.PickingListItemId
			WHERE A.PickingListId=@PickingListId AND A.QtyIssued>0
			AND A.DeleteFlag IN(NULL,'','0') AND ISNULL(F.OrgLotSN,'')=''
			AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')

			SET @RowCount=0
			SET @RowId=1
			SET @PLotSN=''
			
			SELECT @RowCount=COUNT(1) FROM #NewLotMO

			WHILE @RowId<=@RowCount
			BEGIN
				SELECT 
					@PQty=ISNULL(Qty,0),
					@PickingListItemLotId=PickingListItemLotId,
					@PLotSN=LotSN
				FROM #NewLotMO WHERE RowId=@RowId

				IF EXISTS(SELECT 1 FROM WW_RMInventory WHERE LotSN=@PLotSN AND Qty>@PQty)				            
				BEGIN

					EXEC @return_value = [dbo].[StartRuleSNDoMethod]
							@I_ReturnMessage = @I_ReturnMessage OUTPUT,
							@SNRuleId = @SNRuleId,
							@RCharStr = N'',
							@JumpQty=1,
							@NewSN = @NewLotSN OUTPUT

					EXEC @return_value=[dbo].[PDA_LotSplitToEmptyLot]
					@I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@I_PlugInCommand=@I_PlugInCommand,
					@I_OrBitUserId=@I_OrBitUserId,
					@I_ResourceId=@I_ResourceId,
					@SplitLotSN=@PLotSN,
					@SplitQty=@PQty,
					@CombineLotSN=@NewLotSN

					IF @return_value<>0
					BEGIN
						ROLLBACK TRANSACTION SplitLot
						RETURN @return_value
					END

					UPDATE PickingListItemLot SET LotSN=@NewLotSN,OrgLotSN=@PLotSN WHERE PickingListItemLotId=@PickingListItemLotId

					--UPDATE WW_RMInventory SET IsStorage=0 WHERE LotSN=@NewLotSN
				END
				SET @RowId+=1;
			END



			--1.1如果有超发料，则需要“创建调拨单 和 寄存账记录”
			IF EXISTS(SELECT 1 FROM dbo.PickingListItem A INNER JOIN PickingListItemLot B ON A.PickingListItemId=B.PickingListItemId 
			INNER JOIN @PickingListMO C ON A.PickingListItemId=C.PickingListItemId
			WHERE A.PickingListId=@PickingListId AND B.Qty<B.ActualPickQty AND A.DeleteFlag IN(NULL,'','0'))
			BEGIN
				--必须存在寄存仓
				--IF ISNULL(@ToWarehouseId,'')=''
				--BEGIN
				--	 SET @I_ReturnMessage='ServerMessage:领料单['+@PickingListName+']存在超发物料，工厂【'+@FactoryName+'】没有指定寄存仓库？必须指定寄存仓库！'
				--	 ROLLBACK TRANSACTION SplitLot
				--	 RETURN -1
				--END

				--领料单确认操作时，超发部分物料转为超发料管理
				DECLARE cursor1 CURSOR LOCAL FAST_FORWARD FOR  
				SELECT A.PickingListItemId,A.ProductId,B.Qty,B.ActualPickQty,WorkcenterId,UOMId,B.LotSN
				FROM dbo.PickingListItem A
				INNER JOIN PickingListItemLot B ON A.PickingListItemId=B.PickingListItemId
				INNER JOIN @PickingListMO C ON A.PickingListItemId=C.PickingListItemId
				WHERE PickingListId=@PickingListId AND B.Qty<B.ActualPickQty AND A.DeleteFlag IN(NULL,'','0')
				OPEN cursor1 
				FETCH NEXT FROM cursor1 
				INTO @PickingListItemId,@ProductId,@QtyRequired,@QtyIssued,@WarehouseId,@UOMId,@LotSN
				WHILE @@FETCH_STATUS = 0 
				BEGIN 
					SET @ExceedQty=0
					IF ISNULL(@QtyIssued,0)>ISNULL(@QtyRequired,0)
					BEGIN
						SET @ExceedQty=ISNULL(@QtyIssued,0)-ISNULL(@QtyRequired,0)
					END 

					--存在超发
					IF ISNULL(@ExceedQty,0)>0
					BEGIN
						SELECT @WarehouseId=WorkcenterId,@BoxSN=BoxSN,@CellId=CellId FROM WW_RMInventory WHERE LotSN=@LotSN
						IF @WarehouseId<>@ToWarehouseId
						BEGIN
							--1.******产生调拨单********
							SET @ProductAllotId=''

							SELECT @ProductAllotId=ProductAllotId
							FROM dbo.ProductAllot
							WHERE PickingListId=@PickingListId
							AND WorkcenterId=@WarehouseId AND ToWorkcenterId=@ToWarehouseId
							AND ProductAllotStates='30' --状态取已确认的
							AND CreateWay='1' AND ToErpLock=0

							IF ISNULL(@ProductAllotId,'')=''
							BEGIN
								--申请单据
								EXEC [dbo].[Txn_BillNewSN]
									@BillName = N'ProductAllot', --Bill表
									@NewSN = @ProductAllotName output

								--申请主键
								EXEC dbo.SysGetObjectPKId '','ProductAllot',@ProductAllotId OUTPUT
							   INSERT INTO dbo.ProductAllot
									(
										ProductAllotId,
										ProductAllotName,
										ProductAllotDescription,
										ProductAllotStates,
										ProductAllotType,
										FactoryId,
										ToFactoryId,
										WorkcenterId,
										ToWorkcenterId,
										ConfirmUserId,
										ConfirmDate,
										ApproveUserId,
										ApproveDate,
										PickingListId,
										OperateWay,
										CreateWay,
										CreateUserId,
										CreateDate,
										ModifyDate
									)
							   VALUES
									(
										@ProductAllotId,
										@ProductAllotName,
										'领料单['+@PickingListName+']超发产生调拨单，调拨到线边仓',
										'30',
										'',
										@FactoryId,
										@FactoryId,
										@WarehouseId,
										@ToWarehouseId,
										@I_OrBitUserId,
										GETDATE(),
										@I_OrBitUserId,
										GETDATE(),
										@PickingListId,
										'0',
										'1',
										@I_OrBitUserId,
										GETDATE(),
										GETDATE()
									)
							END

							IF EXISTS(SELECT 1 FROM dbo.ProductAllotItem WHERE ProductAllotId=@ProductAllotId AND ProductId=@ProductId)
							BEGIN
								UPDATE dbo.ProductAllotItem SET 
									   RealAllotQty=ISNULL(RealAllotQty,0)+@ExceedQty,
									   AllotQty=ISNULL(RealAllotQty,0)+@ExceedQty
								WHERE ProductAllotId=@ProductAllotId AND ProductId=@ProductId
							END
							ELSE
							BEGIN
								-- 获取调拨单行号
								IF EXISTS(SELECT 1 FROM ProductAllotItem WHERE ProductAllotId=@ProductAllotId)
									SELECT
										@ItemSequence = RIGHT('000'+CAST(MAX(CAST(ItemSequence AS INT))+1  AS VARCHAR),4)
									FROM ProductAllotItem
									WHERE ProductAllotId = @ProductAllotId
								ELSE
									SET @ItemSequence = RIGHT('000'+CAST(1 AS VARCHAR),4)
								--申请主键
								EXEC dbo.SysGetObjectPKId '','ProductAllotItem',@ProductAllotItemId OUTPUT
								INSERT INTO dbo.ProductAllotItem
									 (
										 ProductAllotItemId,
										 ProductAllotId,
										 ItemSequence,
										 ProductId,
										 AllotQty,
										 RealAllotQty,
										 ItemUOMId,
										 CreateDate,
										 ModifyDate
									 )
								VALUES
									 (
										 @ProductAllotItemId,
										 @ProductAllotId,
										 @ItemSequence,
										 @ProductId,
										 @ExceedQty,
										 @ExceedQty,
										 @UOMId,
										 GETDATE(),
										 GETDATE()
									 )

								--生成调拨明细批次
						
								EXEC SysGetObjectPKId '','ProductAllotItemLot',@ItemLotPKId OUTPUT
								INSERT INTO [dbo].[ProductAllotItemLot]
												([ProductAllotItemLotId]
												,[ProductAllotItemId]
												,[LotSN]
												,[BoxSN]
												,[Qty]
												,[CellId]
												,[ToCellId]
												,[IsAOScan]
												,[IsAEScan]
												,[AllotType]
												,[CreateUserId]
												,[MOProductionLotId])
											VALUES
												(@ItemLotPKId
												,@ProductAllotItemId
												,@LotSN
												,@BoxSN
												,@ExceedQty
												,@CellId
												,NULL
												,0
												,0
												,'R'
												,@I_OrBitUserId
												,'')
							END

						END
					


						--2.******产生寄存账********
						SET @ExceedPickingId=''

						SELECT @ExceedPickingId=ExceedPickingId 
						FROM dbo.ExceedPicking 
						WHERE ProductId=@ProductId AND FactoryId=@FactoryId
						AND DivisionId=@DivisionId AND WarehouseId=@ToWarehouseId
						AND WorkcenterId=@ToWorkcenterId AND VendorId=@VendorId

						IF ISNULL(@ExceedPickingId,'')=''
						BEGIN
							EXEC dbo.SysGetObjectPKId '','ExceedPicking',@ExceedPickingId OUTPUT
							INSERT INTO dbo.ExceedPicking
								 (
									 ExceedPickingId,
									 ProductId,
									 BeginExceedQty,
									 SurplusExceedQty,
									 FactoryId,
									 DivisionId,
									 WarehouseId,
									 WorkcenterId,
									 VendorId,
									 CreateDate,
									 ModifyDate
								 )
							VALUES
								 (
									 @ExceedPickingId,
									 @ProductId,
									 @ExceedQty,
									 @ExceedQty,
									 @FactoryId,
									 @DivisionId,
									 @ToWarehouseId,
									 @ToWorkcenterId,
									 @VendorId,
									 GETDATE(),
									 GETDATE()
								 )
						END
						ELSE
						BEGIN
							--更新超发数量
							UPDATE dbo.ExceedPicking SET 
								BeginExceedQty=ISNULL(BeginExceedQty,0)+@ExceedQty,
								SurplusExceedQty=ISNULL(SurplusExceedQty,0)+@ExceedQty,
								ModifyDate=GETDATE()
							WHERE ExceedPickingId=@ExceedPickingId
						END

						--SELECT TOP 1 @LotSN=LotSN FROM PickingListItemLot WHERE PickingListItemId=@PickingListItemId ORDER BY CreateDate DESC

						EXEC dbo.SysGetObjectPKId '','ExceedPickingItem',@ExceedPickingItemId OUTPUT
						INSERT INTO dbo.ExceedPickingItem(
								ExceedPickingItemId,
								ExceedPickingId,
								PickingListId,
								PickingListItemId,
								ProductId,
								ExceedQty,
								LotSN
								)
							VALUES(
								@ExceedPickingItemId,
								@ExceedPickingId,
								@PickingListId,
								@PickingListItemId,
								@ProductId,
								@ExceedQty,
								@LotSN
								)

						--获取当前批次使用数量
						--SELECT @PickingQty=SUM(C.Qty) FROM PickingList A
						--INNER JOIN PickingListItem B ON A.PickingListId=B.PickingListId
						--INNER JOIN PickingListItemLot C ON B.PickingListItemId=C.PickingListItemId
						--WHERE B.PickingListId=@PickingListId AND C.LotSN=@LotSN AND B.DeleteFlag IN(NULL,'','0')

						--IF ISNULL(@PickingQty,0)>0
						--BEGIN
						--	--拆分批次
						--	EXEC @return_value = [dbo].[StartRuleSNDoMethod]
						--			@I_ReturnMessage = @I_ReturnMessage OUTPUT,
						--			@SNRuleId = @SNRuleId,
						--			@RCharStr = N'',
						--			@JumpQty=1,
						--			@NewSN = @NewLotSN OUTPUT

						--	EXEC @return_value=[dbo].[PDA_LotSplitToEmptyLot]
						--	@I_ReturnMessage=@I_ReturnMessage OUTPUT,
						--	@I_PlugInCommand=@I_PlugInCommand,
						--	@I_OrBitUserId=@I_OrBitUserId,
						--	@I_ResourceId=@I_ResourceId,
						--	@SplitLotSN=@LotSN,
						--	@SplitQty=@PickingQty,
						--	@CombineLotSN=@NewLotSN

						--	UPDATE C SET C.LotSN=@NewLotSN,OrgLotSN=@LotSN FROM PickingList A
						--	INNER JOIN PickingListItem B ON A.PickingListId=B.PickingListId
						--	INNER JOIN PickingListItemLot C ON B.PickingListItemId=C.PickingListItemId
						--	WHERE B.PickingListId=@PickingListId AND C.LotSN=@LotSN AND B.DeleteFlag IN(NULL,'','0') 

						--	IF @return_value<>0
						--	BEGIN
						--		ROLLBACK TRANSACTION SplitLot
						--		RETURN @return_value
						--	END
						--END
					END

					FETCH NEXT FROM cursor1 
					INTO @PickingListItemId,@ProductId,@QtyRequired,@QtyIssued,@WarehouseId,@UOMId,@LotSN
				END
				CLOSE cursor1 
				DEALLOCATE cursor1
			END

			--1.2如果非杂发单，则更新工单 或 采购单 的物料明细的发料数
			IF @PickingListClass NOT IN('02')
			BEGIN 
				--如果工单不为空，更新工单行物料的实发数量
				DECLARE cursor1 CURSOR LOCAL FAST_FORWARD FOR  
				SELECT MOItemId,POItemMId,ProductId,QtyIssued,QtyRequired
				FROM dbo.PickingListItem A
				INNER JOIN @PickingListMO C ON A.PickingListItemId=C.PickingListItemId
				WHERE PickingListId=@PickingListId
				OPEN cursor1 
				FETCH NEXT FROM cursor1 
				INTO @MOItemId,@POItemMId,@ProductId,@QtyIssued,@QtyRequired
				WHILE @@FETCH_STATUS = 0 
				BEGIN 
					--更新已发数量，记住超发数，不算发料数
					IF @PickingListClass='04'
					BEGIN
						UPDATE dbo.POItemM SET 
							ItemQtyIssued=ISNULL(ItemQtyIssued,0)+ CASE WHEN ISNULL(@QtyIssued,0)>@QtyRequired THEN @QtyRequired ELSE @QtyIssued END 
						WHERE POItemMId=@POItemMId
					END
					ELSE
					BEGIN 
						UPDATE dbo.MOItem SET 
							ItemQtyIssued=ISNULL(ItemQtyIssued,0)+ CASE WHEN ISNULL(@QtyIssued,0)>@QtyRequired THEN @QtyRequired ELSE @QtyIssued END 
						WHERE MOItemId=@MOItemId 
					END

					FETCH NEXT FROM cursor1 
					INTO  @MOItemId,@POItemMId,@ProductId,@QtyIssued,@QtyRequired
				END
				CLOSE cursor1 
				DEALLOCATE cursor1 
			END



			--1.3更新物料批号信息
			DECLARE cursor2 CURSOR LOCAL FAST_FORWARD FOR
			SELECT LotSN,OrgLotSN
			FROM dbo.PickingListItemLot
			INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListItemId=PickingListItemLot.PickingListItemId 
			INNER JOIN @PickingListMO C ON PickingListItem.PickingListItemId=C.PickingListItemId
			WHERE PickingListId=@PickingListId
			OPEN cursor2 
			FETCH NEXT FROM cursor2 
			INTO @LotSN,@OrgLotSN
			WHILE @@FETCH_STATUS = 0 
			BEGIN 
				--更新批号状态
				UPDATE dbo.WW_RMInventory SET 
					LotStatus='1',
					IsStorage=0
					--WorkcenterId=@ToWorkcenterId, --目标工作中心
					--CellId=''
				WHERE LotSN=@LotSN

				IF ISNULL(@OrgLotSN,'')<>'' AND EXISTS(SELECT TOP 1 1 FROM WW_RMInventory A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LotSN=@OrgLotSN AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859'))
				BEGIN
					IF NOT EXISTS(SELECT 1 FROM PickingListItemLot A INNER JOIN PickingListItem B ON A.PickingListItemId=B.PickingListItemId WHERE B.PickingListId=@PickingListId AND A.LotSN=@OrgLotSN)
					BEGIN
						--获取建议储位
						EXEC @return_value=dbo.TxnBase_MAdviceCell
							 @I_ReturnMessage=@I_ReturnMessage OUTPUT, -- nvarchar(max)
							 @I_OrBitUserId=@I_OrBitUserId, -- char(12)
							 @I_OrBitUserName=@I_OrBitUserName, -- nvarchar(100)
							 @I_ResourceId=@I_ResourceId, -- char(12)
							 @I_ResourceName=@I_ResourceName, -- nvarchar(100)
							 @I_PlugInCommand=@I_PlugInCommand, -- varchar(5)
							 @AdviceWarehouseId=@ToWorkcenterId OUTPUT, -- char(12)
							 @AdviceCellId=@AdviceCellId OUTPUT, -- char(12)
							 @PreviousCellId='', -- char(12)
							 @ToWarehosueId=@ToWorkcenterId, -- char(12)
							 @SN=@OrgLotSN -- nvarchar(100)

						--库存移送到目标仓
						UPDATE dbo.WW_RMInventory SET 
							LotStatus='1',
							IsStorage=1,
							WorkcenterId=@ToWorkcenterId, --目标工作中心
							CellId=@AdviceCellId,
							IsExceedPicking=1
						WHERE LotSN=@OrgLotSN
					END
					
				END

				FETCH NEXT FROM cursor2 
				INTO @LotSN,@OrgLotSN
			END
			CLOSE cursor2 
			DEALLOCATE cursor2

			SET @I_ReturnMessage=''

			--UPDATE dbo.PickingList_MO SET IsPost=1 WHERE PickingListId=@PickingListId AND MOId IN(SELECT MOId FROM @PickingListMO)

			 ---1.4执行确认
			UPDATE dbo.PickingList SET 
				--PickingListStates='30', 
				ConfirmUserId=@I_OrBitUserId, 
				ConfirmDate=GETDATE(),
				ModifyDate=GETDATE()
			WHERE PickingListId=@PickingListId

			SET @I_ReturnMessage ='ServerMessage:领料单【'+@PickingListName+'】确认完成！'

			IF @@ERROR <>0
			ROLLBACK TRANSACTION SplitLot
			ELSE
			COMMIT TRANSACTION SplitLot
		END
		ELSE
		BEGIN
			DECLARE @PickProductName NVARCHAR(256)
			SELECT TOP 1 @PickProductName=C.ProductName+'  '+B.ProductDescription FROM PickingListItem A
			INNER JOIN Product B ON A.ProductId=B.ProductId
			INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
			INNER JOIN ProductFamily D ON C.ProductFamilyId =D.ProductFamilyId
			WHERE A.PickingListId=@PickingListId AND A.QtyRequired>A.QtyIssued
			AND A.DeleteFlag IN(NULL,'','0')
			IF ISNULL(@PickProductName,'')<>''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:领料单【'+@PickingListName+'】物料【'+@PickProductName+'】未完成领料'
					RETURN -1
			END

			--包材自动生成新批次
			SELECT ROW_NUMBER() OVER(ORDER BY A.CreateDate) AS RowId,A.ProductId,A.QtyIssued,A.PickingListItemId,C.ProductName INTO #BCNewLot FROM PickingListItem A
			INNER JOIN Product B ON A.ProductId=B.ProductId
			INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
			INNER JOIN ProductFamily D ON C.ProductFamilyId =D.ProductFamilyId
			WHERE A.PickingListId=@PickingListId AND D.ProductFamilyName IN('102850','102855','102857','102858','102859') AND A.QtyIssued>0
			AND A.DeleteFlag IN(NULL,'','0')

			SET @RowCount=0
			SET @RowId=1
			SET @PLotSN=''

			SELECT @SNRuleId=SNRuleId FROM dbo.SNRule WHERE SNRuleName='WW_MP_LotSN' AND IsActivity=1

			SELECT @RowCount=COUNT(1) FROM #BCNewLot

			WHILE @RowId<=@RowCount
			BEGIN
				SELECT 
					@PProductId=ProductId,
					@PQty=QtyIssued,
					@PickingListItemId=PickingListItemId,
					@ProductName=ProductName 
				FROM #BCNewLot WHERE RowId=@RowId

				SET @PLotSN='MES'+@ProductName

				IF EXISTS(SELECT 1 FROM WW_RMInventory WHERE LotSN=@PLotSN)
				BEGIN
					--再加批次数量原因：领料时已扣一次，拆批时又扣一次，需要加回来
					UPDATE WW_RMInventory SET Qty+=@PQty,LotStatus='1' WHERE LotSN=@PLotSN

					EXEC @return_value = [dbo].[StartRuleSNDoMethod]
							@I_ReturnMessage = @I_ReturnMessage OUTPUT,
							@SNRuleId = @SNRuleId,
							@RCharStr = N'',
							@JumpQty=1,
							@NewSN = @NewLotSN OUTPUT

					EXEC @return_value=[dbo].[PDA_LotSplitToEmptyLot]
					@I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@I_PlugInCommand=@I_PlugInCommand,
					@I_OrBitUserId=@I_OrBitUserId,
					@I_ResourceId=@I_ResourceId,
					@SplitLotSN=@PLotSN,
					@SplitQty=@PQty,
					@CombineLotSN=@NewLotSN

					IF @return_value<>0
					BEGIN
						ROLLBACK TRANSACTION SplitLot
						RETURN @return_value
					END

					UPDATE PickingListItemLot SET LotSN=@NewLotSN,OrgLotSN=@PLotSN WHERE PickingListItemId=@PickingListItemId AND LotSN=@PLotSN

					--UPDATE WW_RMInventory SET IsStorage=0 WHERE LotSN=@NewLotSN
				END
				SET @RowId+=1;
			END

			--1.1如果有超发料，则需要“创建调拨单 和 寄存账记录”
			IF EXISTS(SELECT 1 FROM dbo.PickingListItem A INNER JOIN PickingListItemLot B ON A.PickingListItemId=B.PickingListItemId WHERE A.PickingListId=@PickingListId AND B.Qty<B.ActualPickQty AND A.DeleteFlag IN(NULL,'','0'))
			BEGIN
				--必须存在寄存仓
				--IF ISNULL(@ToWarehouseId,'')=''
				--BEGIN
				--	 SET @I_ReturnMessage='ServerMessage:领料单['+@PickingListName+']存在超发物料，工厂【'+@FactoryName+'】没有指定寄存仓库？必须指定寄存仓库！'
				--	 ROLLBACK TRANSACTION SplitLot
				--	 RETURN -1
				--END

				--领料单确认操作时，超发部分物料转为超发料管理
				DECLARE cursor1 CURSOR LOCAL FAST_FORWARD FOR  
				SELECT A.PickingListItemId,A.ProductId,B.Qty,B.ActualPickQty,WorkcenterId,UOMId,B.LotSN
				FROM dbo.PickingListItem A
				INNER JOIN PickingListItemLot B ON A.PickingListItemId=B.PickingListItemId
				WHERE PickingListId=@PickingListId AND B.Qty<B.ActualPickQty AND A.DeleteFlag IN(NULL,'','0')
				OPEN cursor1 
				FETCH NEXT FROM cursor1 
				INTO @PickingListItemId,@ProductId,@QtyRequired,@QtyIssued,@WarehouseId,@UOMId,@LotSN
				WHILE @@FETCH_STATUS = 0 
				BEGIN 
					SET @ExceedQty=0
					IF ISNULL(@QtyIssued,0)>ISNULL(@QtyRequired,0)
					BEGIN
						SET @ExceedQty=ISNULL(@QtyIssued,0)-ISNULL(@QtyRequired,0)
					END 

					--存在超发
					IF ISNULL(@ExceedQty,0)>0
					BEGIN
						SELECT @WarehouseId=WorkcenterId,@BoxSN=BoxSN,@CellId=CellId FROM WW_RMInventory WHERE LotSN=@LotSN
						IF @WarehouseId<>@ToWarehouseId
						BEGIN
							--1.******产生调拨单********
							SET @ProductAllotId=''

							SELECT @ProductAllotId=ProductAllotId
							FROM dbo.ProductAllot
							WHERE PickingListId=@PickingListId
							AND WorkcenterId=@WarehouseId AND ToWorkcenterId=@ToWarehouseId
							AND ProductAllotStates='30' --状态取已确认的
							AND CreateWay='1' AND ToErpLock=0

							IF ISNULL(@ProductAllotId,'')=''
							BEGIN
								--申请单据
								EXEC [dbo].[Txn_BillNewSN]
									@BillName = N'ProductAllot', --Bill表
									@NewSN = @ProductAllotName output

								--申请主键
								EXEC dbo.SysGetObjectPKId '','ProductAllot',@ProductAllotId OUTPUT
							   INSERT INTO dbo.ProductAllot
									(
										ProductAllotId,
										ProductAllotName,
										ProductAllotDescription,
										ProductAllotStates,
										ProductAllotType,
										FactoryId,
										ToFactoryId,
										WorkcenterId,
										ToWorkcenterId,
										ConfirmUserId,
										ConfirmDate,
										ApproveUserId,
										ApproveDate,
										PickingListId,
										OperateWay,
										CreateWay,
										CreateUserId,
										CreateDate,
										ModifyDate
									)
							   VALUES
									(
										@ProductAllotId,
										@ProductAllotName,
										'领料单['+@PickingListName+']超发产生调拨单，调拨到线边仓',
										'30',
										'',
										@FactoryId,
										@FactoryId,
										@WarehouseId,
										@ToWarehouseId,
										@I_OrBitUserId,
										GETDATE(),
										@I_OrBitUserId,
										GETDATE(),
										@PickingListId,
										'0',
										'1',
										@I_OrBitUserId,
										GETDATE(),
										GETDATE()
									)
							END

							IF EXISTS(SELECT 1 FROM dbo.ProductAllotItem WHERE ProductAllotId=@ProductAllotId AND ProductId=@ProductId)
							BEGIN
								UPDATE dbo.ProductAllotItem SET 
									   RealAllotQty=ISNULL(RealAllotQty,0)+@ExceedQty,
									   AllotQty=ISNULL(RealAllotQty,0)+@ExceedQty
								WHERE ProductAllotId=@ProductAllotId AND ProductId=@ProductId
							END
							ELSE
							BEGIN
								-- 获取调拨单行号
								IF EXISTS(SELECT 1 FROM ProductAllotItem WHERE ProductAllotId=@ProductAllotId)
									SELECT
										@ItemSequence = RIGHT('000'+CAST(MAX(CAST(ItemSequence AS INT))+1  AS VARCHAR),4)
									FROM ProductAllotItem
									WHERE ProductAllotId = @ProductAllotId
								ELSE
									SET @ItemSequence = RIGHT('000'+CAST(1 AS VARCHAR),4)
								--申请主键
								EXEC dbo.SysGetObjectPKId '','ProductAllotItem',@ProductAllotItemId OUTPUT
								INSERT INTO dbo.ProductAllotItem
									 (
										 ProductAllotItemId,
										 ProductAllotId,
										 ItemSequence,
										 ProductId,
										 AllotQty,
										 RealAllotQty,
										 ItemUOMId,
										 CreateDate,
										 ModifyDate
									 )
								VALUES
									 (
										 @ProductAllotItemId,
										 @ProductAllotId,
										 @ItemSequence,
										 @ProductId,
										 @ExceedQty,
										 @ExceedQty,
										 @UOMId,
										 GETDATE(),
										 GETDATE()
									 )

								--生成调拨明细批次
						
								EXEC SysGetObjectPKId '','ProductAllotItemLot',@ItemLotPKId OUTPUT
								INSERT INTO [dbo].[ProductAllotItemLot]
												([ProductAllotItemLotId]
												,[ProductAllotItemId]
												,[LotSN]
												,[BoxSN]
												,[Qty]
												,[CellId]
												,[ToCellId]
												,[IsAOScan]
												,[IsAEScan]
												,[AllotType]
												,[CreateUserId]
												,[MOProductionLotId])
											VALUES
												(@ItemLotPKId
												,@ProductAllotItemId
												,@LotSN
												,@BoxSN
												,@ExceedQty
												,@CellId
												,NULL
												,0
												,0
												,'R'
												,@I_OrBitUserId
												,'')
							END

						END
					


						--2.******产生寄存账********
						SET @ExceedPickingId=''

						SELECT @ExceedPickingId=ExceedPickingId 
						FROM dbo.ExceedPicking 
						WHERE ProductId=@ProductId AND FactoryId=@FactoryId
						AND DivisionId=@DivisionId AND WarehouseId=@ToWarehouseId
						AND WorkcenterId=@ToWorkcenterId AND VendorId=@VendorId

						IF ISNULL(@ExceedPickingId,'')=''
						BEGIN
							EXEC dbo.SysGetObjectPKId '','ExceedPicking',@ExceedPickingId OUTPUT
							INSERT INTO dbo.ExceedPicking
								 (
									 ExceedPickingId,
									 ProductId,
									 BeginExceedQty,
									 SurplusExceedQty,
									 FactoryId,
									 DivisionId,
									 WarehouseId,
									 WorkcenterId,
									 VendorId,
									 CreateDate,
									 ModifyDate
								 )
							VALUES
								 (
									 @ExceedPickingId,
									 @ProductId,
									 @ExceedQty,
									 @ExceedQty,
									 @FactoryId,
									 @DivisionId,
									 @ToWarehouseId,
									 @ToWorkcenterId,
									 @VendorId,
									 GETDATE(),
									 GETDATE()
								 )
						END
						ELSE
						BEGIN
							--更新超发数量
							UPDATE dbo.ExceedPicking SET 
								BeginExceedQty=ISNULL(BeginExceedQty,0)+@ExceedQty,
								SurplusExceedQty=ISNULL(SurplusExceedQty,0)+@ExceedQty,
								ModifyDate=GETDATE()
							WHERE ExceedPickingId=@ExceedPickingId
						END

						--SELECT TOP 1 @LotSN=LotSN FROM PickingListItemLot WHERE PickingListItemId=@PickingListItemId ORDER BY CreateDate DESC

						EXEC dbo.SysGetObjectPKId '','ExceedPickingItem',@ExceedPickingItemId OUTPUT
						INSERT INTO dbo.ExceedPickingItem(
								ExceedPickingItemId,
								ExceedPickingId,
								PickingListId,
								PickingListItemId,
								ProductId,
								ExceedQty,
								LotSN
								)
							VALUES(
								@ExceedPickingItemId,
								@ExceedPickingId,
								@PickingListId,
								@PickingListItemId,
								@ProductId,
								@ExceedQty,
								@LotSN
								)

						--获取当前批次使用数量
						SELECT @PickingQty=SUM(C.Qty) FROM PickingList A
						INNER JOIN PickingListItem B ON A.PickingListId=B.PickingListId
						INNER JOIN PickingListItemLot C ON B.PickingListItemId=C.PickingListItemId
						WHERE B.PickingListId=@PickingListId AND C.LotSN=@LotSN AND B.DeleteFlag IN(NULL,'','0')

						IF ISNULL(@PickingQty,0)>0
						BEGIN

							--拆分批次
							EXEC @return_value = [dbo].[StartRuleSNDoMethod]
									@I_ReturnMessage = @I_ReturnMessage OUTPUT,
									@SNRuleId = @SNRuleId,
									@RCharStr = N'',
									@JumpQty=1,
									@NewSN = @NewLotSN OUTPUT

							EXEC @return_value=[dbo].[PDA_LotSplitToEmptyLot]
							@I_ReturnMessage=@I_ReturnMessage OUTPUT,
							@I_PlugInCommand=@I_PlugInCommand,
							@I_OrBitUserId=@I_OrBitUserId,
							@I_ResourceId=@I_ResourceId,
							@SplitLotSN=@LotSN,
							@SplitQty=@PickingQty,
							@CombineLotSN=@NewLotSN

							UPDATE C SET C.LotSN=@NewLotSN,OrgLotSN=@LotSN FROM PickingList A
							INNER JOIN PickingListItem B ON A.PickingListId=B.PickingListId
							INNER JOIN PickingListItemLot C ON B.PickingListItemId=C.PickingListItemId
							WHERE B.PickingListId=@PickingListId AND C.LotSN=@LotSN AND B.DeleteFlag IN(NULL,'','0') 

							IF @return_value<>0
							BEGIN
								ROLLBACK TRANSACTION SplitLot
								RETURN @return_value
							END
						END
					END

					FETCH NEXT FROM cursor1 
					INTO @PickingListItemId,@ProductId,@QtyRequired,@QtyIssued,@WarehouseId,@UOMId,@LotSN
				END
				CLOSE cursor1 
				DEALLOCATE cursor1
			END

			--1.2如果非杂发单，则更新工单 或 采购单 的物料明细的发料数
			IF @PickingListClass NOT IN('02')
			BEGIN 
				--如果工单不为空，更新工单行物料的实发数量
				DECLARE cursor1 CURSOR LOCAL FAST_FORWARD FOR  
				SELECT MOItemId,POItemMId,ProductId,QtyIssued,QtyRequired
				FROM dbo.PickingListItem
				WHERE PickingListId=@PickingListId
				OPEN cursor1 
				FETCH NEXT FROM cursor1 
				INTO @MOItemId,@POItemMId,@ProductId,@QtyIssued,@QtyRequired
				WHILE @@FETCH_STATUS = 0 
				BEGIN 
					--更新已发数量，记住超发数，不算发料数
					IF @PickingListClass='04'
					BEGIN
						UPDATE dbo.POItemM SET 
							ItemQtyIssued=ISNULL(ItemQtyIssued,0)+ CASE WHEN ISNULL(@QtyIssued,0)>@QtyRequired THEN @QtyRequired ELSE @QtyIssued END 
						WHERE POItemMId=@POItemMId
					END
					ELSE
					BEGIN 
						UPDATE dbo.MOItem SET 
							ItemQtyIssued=ISNULL(ItemQtyIssued,0)+ CASE WHEN ISNULL(@QtyIssued,0)>@QtyRequired THEN @QtyRequired ELSE @QtyIssued END 
						WHERE MOItemId=@MOItemId 
					END

					FETCH NEXT FROM cursor1 
					INTO  @MOItemId,@POItemMId,@ProductId,@QtyIssued,@QtyRequired
				END
				CLOSE cursor1 
				DEALLOCATE cursor1 
			END



			--1.3更新物料批号信息
			DECLARE cursor2 CURSOR LOCAL FAST_FORWARD FOR
			SELECT LotSN,OrgLotSN
			FROM dbo.PickingListItemLot
			INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListItemId=PickingListItemLot.PickingListItemId 
			WHERE PickingListId=@PickingListId
			OPEN cursor2 
			FETCH NEXT FROM cursor2 
			INTO @LotSN,@OrgLotSN
			WHILE @@FETCH_STATUS = 0 
			BEGIN 
				--更新批号状态
				UPDATE dbo.WW_RMInventory SET 
					LotStatus='1',
					IsStorage=0
					--WorkcenterId=@ToWorkcenterId, --目标工作中心
					--CellId=''
				WHERE LotSN=@LotSN

				IF ISNULL(@OrgLotSN,'')<>'' AND EXISTS(SELECT TOP 1 1 FROM WW_RMInventory A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LotSN=@OrgLotSN AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859'))
				BEGIN
					--获取建议储位
					EXEC @return_value=dbo.TxnBase_MAdviceCell
						 @I_ReturnMessage=@I_ReturnMessage OUTPUT, -- nvarchar(max)
						 @I_OrBitUserId=@I_OrBitUserId, -- char(12)
						 @I_OrBitUserName=@I_OrBitUserName, -- nvarchar(100)
						 @I_ResourceId=@I_ResourceId, -- char(12)
						 @I_ResourceName=@I_ResourceName, -- nvarchar(100)
						 @I_PlugInCommand=@I_PlugInCommand, -- varchar(5)
						 @AdviceWarehouseId=@ToWorkcenterId OUTPUT, -- char(12)
						 @AdviceCellId=@AdviceCellId OUTPUT, -- char(12)
						 @PreviousCellId='', -- char(12)
						 @ToWarehosueId=@ToWorkcenterId, -- char(12)
						 @SN=@OrgLotSN -- nvarchar(100)

					--库存移送到目标仓
					IF @PickingListClass NOT IN('02')
                    BEGIN
                        UPDATE dbo.WW_RMInventory SET
                            LotStatus='1',
                            IsStorage=1,
                            WorkcenterId=@ToWorkcenterId, --目标工作中心
                            CellId=@AdviceCellId,
                            IsExceedPicking=1
                        WHERE LotSN=@OrgLotSN
                    END
                    ELSE--杂发单不修改仓库
                    BEGIN
                        UPDATE dbo.WW_RMInventory SET
                            LotStatus='1',
                            IsStorage=1,
                            CellId=@AdviceCellId,
                            IsExceedPicking=1
                        WHERE LotSN=@OrgLotSN
                    END
				END

				FETCH NEXT FROM cursor2 
				INTO @LotSN,@OrgLotSN
			END
			CLOSE cursor2 
			DEALLOCATE cursor2


			 ---1.4执行确认
			UPDATE dbo.PickingList SET 
				--PickingListStates='30', 
				ConfirmUserId=@I_OrBitUserId, 
				ConfirmDate=GETDATE(),
				ModifyDate=GETDATE()
			WHERE PickingListId=@PickingListId

			SET @I_ReturnMessage ='ServerMessage:领料单【'+@PickingListName+'】确认完成！'
		END
		

	END

	IF @I_Sender='PickingListOtherConfirmMES'
	BEGIN
	 ---1.4MES下架平账，改变状态
			UPDATE dbo.PickingList SET 
				PickingListStates='42'
			WHERE PickingListId=@PickingListId

		RETURN 0
	END

	

	IF @PickingListClass='01'
		BEGIN
		 

		       DECLARE cursor1  CURSOR LOCAL FAST_FORWARD FOR --创建游标   
			   SELECT pli.PickingListItemId,pli.ItemSequence
			   FROM dbo.PickingListItem AS pli
			  -- INNER JOIN @PickingListMO M ON pli.PickingListItemId=M.PickingListItemId
			   WHERE pli.QtyRequired=QtyIssued AND ISNULL(pli.ToSAPStates,'') IN ('','过账失败')
			   AND pli.PickingListId=@PickingListId
			   OPEN cursor1 --打开游标
			   FETCH NEXT  FROM  Cursor1 INTO @SPickingListItemId,@SItemSequence --从游标变量中读取值		   
			   WHILE @@FETCH_STATUS=0 --判断FETCH语句是否执行成功	   
			   BEGIN
			   --IF NOT EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE  ui.ISUpload=1 AND ui.UploadInterfaceId='IFIT000000T5') 
			   --BEGIN 
				IF NOT  EXISTS(SELECT ui.MatDoc FROM dbo.UploadIng AS ui WHERE ui.UploadDateId=@SPickingListItemId AND ISNULL(ui.MatDoc,'')<>'' AND ui.MatDoc!='ServerMessage:物料或类型错误，暂时不支持上传SAP，请检查！！！！！')
				
				BEGIN  
				 IF EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE ui.UploadDateId=@SPickingListItemId AND ui.ISUpload=1)
				 BEGIN 

			     	EXEC dbo.RfcSAPSync @I_ReturnMessage =@RFC_ReturnMessage OUTPUT,
						@ItemName =N'U_PickingListPR',
							@UploadIngId=@UploadIngId

					IF  @RFC_ReturnMessage LIKE '%成功%'
					BEGIN 
					  UPDATE dbo.PickingListItem set ToSAPStates='过账成功',SAPInfor=REPLACE(@RFC_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId

					END 
					ELSE 
					BEGIN 
					   UPDATE dbo.PickingListItem set ToSAPStates='过账失败',SAPInfor=REPLACE(@RFC_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId
					END 

				SET @I_ReturnMessage=ISNULL(@I_ReturnMessage,'')+@RFC_ReturnMessage+@Enter

				 END  
				 ELSE
				 BEGIN 
					SELECT  @InterfaceItemId=InterfaceItemId FROM dbo.InterfaceItem WHERE ItemName='U_PickingListPR'

					EXEC  SysGetObjectPKId '','UploadIng',@UploadIngId OUTPUT
					INSERT INTO dbo.UploadIng
					(
						UploadIngId,
						UploadInterfaceId,
						UploadDateId,
						ISUpload,
						UserId,
						BillsMark,
						MatDoc,
						CreateDate
					)
					VALUES
					(	@UploadIngId,       -- UploadIngId - char(12)
						@InterfaceItemId,       -- UploadInterfaceId - char(12)
						@SPickingListItemId,       -- UploadDateId - char(12)
						'true',     -- ISUpload - bit
						@I_OrBitUserId,       -- UserId - char(12)
						@PickingListName+','+@SItemSequence,      -- BillsMark - nvarchar(50)
						N'',      -- MatDoc - nvarchar(50)
						GETDATE() -- CreateDate - datetime
					)

					EXEC dbo.RfcSAPSync @I_ReturnMessage =@RFC_ReturnMessage OUTPUT,
							@ItemName =N'U_PickingListPR',
							@UploadIngId=@UploadIngId

					IF  @RFC_ReturnMessage LIKE '%成功%'
					BEGIN 
					  UPDATE dbo.PickingListItem set ToSAPStates='过账成功',SAPInfor=REPLACE(@RFC_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId

					END 
					ELSE 
					BEGIN 
					   UPDATE dbo.PickingListItem set ToSAPStates='过账失败',SAPInfor=REPLACE(@RFC_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId
					END 

				   SET @I_ReturnMessage=ISNULL(@I_ReturnMessage,'')+@RFC_ReturnMessage+@Enter
				END  
			   END 
			   ELSE 
			   BEGIN 
				  UPDATE dbo.PickingListItem set ToSAPStates='过账成功',SAPInfor='' WHERE PickingListItemId=@SPickingListItemId
			   END 
			    UPDATE dbo.UploadIng SET ISUpload=0 WHERE UploadIngId=@UploadIngId


				--END 
			   FETCH NEXT FROM Cursor1 INTO @SPickingListItemId,@SItemSequence --读取游标变量中的数据

			   END

			   CLOSE cursor1 --关闭游标

			   DEALLOCATE cursor1; --释放游标

			   --2023.9.27 注释 by HL0445
				--IF NOT EXISTS(SELECT 1 FROM dbo.PickingList AS pl inner JOIN dbo.PickingListItem AS plm ON plm.PickingListId = pl.PickingListId
				--					WHERE ISNULL(plm.ToSAPStates ,'')='' AND pl.PickingListId=@PickingListId )	   
				--BEGIN

				--IF EXISTS(SELECT 1 FROM dbo.PickingList AS pl inner JOIN dbo.PickingListItem AS plm ON plm.PickingListId = pl.PickingListId
				--					WHERE (plm.ToSAPStates='过账失败' OR ISNULL(plm.ToSAPStates ,'')='') AND pl.PickingListId=@PickingListId )
				--					BEGIN 
				--					  UPDATE dbo.PickingList SET 
				--							PickingListStates='41'
				--						WHERE PickingListId=@PickingListId
				--					END 
				--					ELSE 
				--					BEGIN 
				--					   UPDATE dbo.PickingList SET 
				--							PickingListStates='40'
				--						WHERE PickingListId=@PickingListId
				--					END 

				--END
 
				--更新领料单状态  2023.9.27 增加 by HL0445
				BEGIN 
					DELETE FROM @TempPickingListItem
					--获取领料单明细数据
					INSERT INTO @TempPickingListItem(PickingListItemId,ProductId,QtyRequired,QtyIssued,ToSAPStates)
					SELECT PickingListItemId,ProductId,QtyRequired,QtyIssued,ToSAPStates 
					FROM dbo.PickingListItem 
					WHERE PickingListId=@PickingListId AND ISNULL(DeleteFlag,'')='' 

					--检查领料单是否全部发料
					IF (SELECT COUNT(1) FROM @TempPickingListItem WHERE (ISNULL(QtyRequired,0)-ISNULL(QtyIssued,0))>0)>0
					BEGIN
						--更新明细行状态 20 领料中
						UPDATE dbo.PickingListItem SET ItemStates='20'
						WHERE PickingListItemId IN (SELECT PickingListItemId FROM @TempPickingListItem)

						--更新领料单状态 21 领料中
						UPDATE dbo.PickingList SET PickingListStates='20'WHERE PickingListId=@PickingListId 
					END 
					ELSE BEGIN 
						--检查是否全部过账成功
						IF (SELECT COUNT(1) FROM @TempPickingListItem WHERE ISNULL(ToSAPStates,'')<>'过账成功')>0
						BEGIN 
							UPDATE dbo.PickingList SET PickingListStates='41'WHERE PickingListId=@PickingListId 
						END 
						ELSE BEGIN 
							UPDATE dbo.PickingList SET PickingListStates='40'WHERE PickingListId=@PickingListId 
						END

						--更新明细行状态 30 已完成
						UPDATE dbo.PickingListItem SET ItemStates='30'
						WHERE PickingListItemId IN (SELECT PickingListItemId FROM @TempPickingListItem)
					END 
				END

		END 

	IF @PickingListClass='02'
	BEGIN
	IF NOT  EXISTS(SELECT ui.MatDoc FROM dbo.UploadIng AS ui WHERE ui.UploadDateId=@PickingListId AND ISNULL(ui.MatDoc,'')<>'')
		    BEGIN  
			 IF EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE ui.UploadDateId=@PickingListId AND ui.ISUpload=1)
			 BEGIN 

			EXEC dbo.RfcSAPSync @I_ReturnMessage =@I_ReturnMessage OUTPUT,
                    @ItemName =N'U_PickingListOther',
							@UploadIngId=@UploadIngId

        --   SET @I_ReturnMessage=@I_ReturnMessage+@RFC_ReturnMessage+@Enter

			 END  
			 ELSE
			 BEGIN 
			 SELECT  @InterfaceItemId=InterfaceItemId FROM dbo.InterfaceItem WHERE ItemName='U_PickingListOther'

			exec SysGetObjectPKId '','UploadIng',@UploadIngId OUTPUT
			INSERT INTO dbo.UploadIng
			(
				UploadIngId,
				UploadInterfaceId,
				UploadDateId,
				ISUpload,
				UserId,
				BillsMark,
				MatDoc,
				CreateDate
			)
			VALUES
			(	@UploadIngId,       -- UploadIngId - char(12)
				@InterfaceItemId,       -- UploadInterfaceId - char(12)
				@PickingListId,       -- UploadDateId - char(12)
				'true',     -- ISUpload - bit
				@I_OrBitUserId,       -- UserId - char(12)
				@PickingListName,      -- BillsMark - nvarchar(50)
				N'',      -- MatDoc - nvarchar(50)
				GETDATE() -- CreateDate - datetime
			)

			EXEC dbo.RfcSAPSync @I_ReturnMessage =@API_ReturnMessage OUTPUT,
                    @ItemName =N'U_PickingListOther',
							@UploadIngId=@UploadIngId

				  IF @API_ReturnMessage LIKE '%成功%' 
					BEGIN 
					  UPDATE dbo.PickingList SET 
							PickingListStates='40',
							SAPInfor=REPLACE(@API_ReturnMessage, 'ServerMessage:', '')
						WHERE PickingListId=@PickingListId
					END 
					ELSE 
					BEGIN 

					   UPDATE dbo.PickingList SET 
							PickingListStates='41',
							SAPInfor=REPLACE(@API_ReturnMessage, 'ServerMessage:', '')
						WHERE PickingListId=@PickingListId
					END 

         --  SET @I_ReturnMessage=@I_ReturnMessage+@RFC_ReturnMessage+@Enter
            END  
          UPDATE dbo.UploadIng SET ISUpload=0 WHERE UploadIngId=@UploadIngId
      END 
	  ELSE 
	  BEGIN
                 UPDATE dbo.PickingList SET 
							PickingListStates='40'
						WHERE PickingListId=@PickingListId
	  END 


		--EXEC @Api_ReturnValue=dbo.APISyncU_PickingListOtherToERP
		--	@I_ReturnMessage = @API_ReturnMessage OUTPUT, -- nvarchar(max)
		--	@ItemName = N'U_PickingListOther', -- nvarchar(50)
		--	@PickingListName = @PickingListName -- nvarchar(50)
	END
	ELSE IF @PickingListClass='03'
	BEGIN
		EXEC @Api_ReturnValue=dbo.APISyncU_PickingListOMToERP
			@I_ReturnMessage = @API_ReturnMessage OUTPUT, -- nvarchar(max)
			@ItemName = N'U_PickingListOM', -- nvarchar(50)
			@PickingListName = @PickingListName -- nvarchar(50)
	END
	ELSE IF @PickingListClass='04'
	BEGIN
		EXEC @Api_ReturnValue=dbo.APISyncU_PickingListPOToERP
			@I_ReturnMessage = @API_ReturnMessage OUTPUT, -- nvarchar(max)
			@ItemName = N'U_PickingListPO', -- nvarchar(50)
			@PickingListName = @PickingListName -- nvarchar(50)
	END

	--提示信息
	IF ISNULL(@I_ReturnMessage,'')=''
	BEGIN 
		SET @I_ReturnMessage=@API_ReturnMessage

		RETURN @Api_ReturnValue
	END
	ELSE
	BEGIN 
		SET @I_ReturnMessage =@I_ReturnMessage
			+@Enter
			+REPLACE(ISNULL(@API_ReturnMessage,''),'ServerMessage:','')
	END

	DECLARE PALLOT CURSOR LOCAL FAST_FORWARD FOR
	SELECT ProductAllotId FROM ProductAllot WHERE PickingListId=@PickingListId
	OPEN PALLOT 
	FETCH NEXT FROM PALLOT 
	INTO @ProductAllotId
	WHILE @@FETCH_STATUS = 0 
	BEGIN 
		--	DECLARE @API_ReturnMessage NVARCHAR(MAX)=''
	--DECLARE @Api_ReturnValue INT=-1

	DECLARE @SProductAllotItemId CHAR(12)=''
--	DECLARE @SItemSequence NVARCHAR(30)=''
	
			   DECLARE cursor1  CURSOR LOCAL FAST_FORWARD FOR --创建游标   
			   SELECT DISTINCT pli.ProductAllotItemId,pli.ItemSequence
			   FROM dbo.ProductAllotItem AS pli
			   INNER JOIN dbo.ProductAllotItemLot AS pail ON pail.ProductAllotItemId = pli.ProductAllotItemId
			   WHERE pli.AllotQty<=pli.RealAllotQty AND (ISNULL(pli.ToSAPStates,'') ='过账失败' OR ISNULL(pli.ToSAPStates,'') ='')
			    AND pli.ProductAllotId=@ProductAllotId
			   OPEN cursor1 --打开游标
			   FETCH NEXT  FROM  Cursor1 INTO @SProductAllotItemId,@SItemSequence --从游标变量中读取值		   
			   WHILE @@FETCH_STATUS=0 --判断FETCH语句是否执行成功	   
			   BEGIN
			    IF NOT EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE  ui.ISUpload=1 AND ui.UploadInterfaceId='IFIT000000TB') 
			   BEGIN
				IF NOT  EXISTS(SELECT ui.MatDoc FROM dbo.UploadIng AS ui WHERE ui.UploadDateId=@SProductAllotItemId AND ISNULL(ui.MatDoc,'')<>'' AND ui.MatDoc!='ServerMessage:物料或类型错误，暂时不支持上传SAP，请检查！！！！！')
				--AND NOT EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE ui.UploadDateId=@SProductAllotItemId AND ui.ISUpload=1)
				BEGIN  
				 IF EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE ui.UploadDateId=@SProductAllotItemId AND ui.ISUpload=1)
				 BEGIN 

			     	EXEC dbo.RfcSAPSync @I_ReturnMessage =@API_ReturnMessage OUTPUT,
						@ItemName =N'U_ProductAllot',
							@UploadIngId=@UploadIngId

					IF  @API_ReturnMessage LIKE '%成功%'
					BEGIN 
					  UPDATE dbo.ProductAllotItem set ToSAPStates='过账成功',SAPInfor=REPLACE(@API_ReturnMessage, 'ServerMessage:','') WHERE ProductAllotItemId=@SProductAllotItemId

					END 
					ELSE 
					BEGIN 
					   UPDATE dbo.ProductAllotItem set ToSAPStates='过账失败',SAPInfor=REPLACE(@API_ReturnMessage, 'ServerMessage:','') WHERE ProductAllotItemId=@SProductAllotItemId
					END 

				SET @I_ReturnMessage=ISNULL(@I_ReturnMessage,'')+@API_ReturnMessage+@Enter

				 END  
				 ELSE
				 BEGIN 
					SELECT  @InterfaceItemId=InterfaceItemId FROM dbo.InterfaceItem WHERE ItemName='U_ProductAllot'
					SELECT @ProductAllotName =ISNULL(pa.ProductAllotName,'') FROM dbo.ProductAllot AS pa INNER JOIN dbo.ProductAllotItem AS pai ON pai.ProductAllotId = pa.ProductAllotId WHERE pai.ProductAllotItemId=@SProductAllotItemId

					EXEC  SysGetObjectPKId '','UploadIng',@UploadIngId OUTPUT
					INSERT INTO dbo.UploadIng
					(
						UploadIngId,
						UploadInterfaceId,
						UploadDateId,
						ISUpload,
						UserId,
						BillsMark,
						MatDoc,
						CreateDate
					)
					VALUES
					(	@UploadIngId,       -- UploadIngId - char(12)
						@InterfaceItemId,       -- UploadInterfaceId - char(12)
						@SProductAllotItemId,       -- UploadDateId - char(12)
						'true',     -- ISUpload - bit
						@I_OrBitUserId,       -- UserId - char(12)
						@ProductAllotName+','+@SItemSequence,      -- BillsMark - nvarchar(50)
						N'',      -- MatDoc - nvarchar(50)
						GETDATE() -- CreateDate - datetime
					)

					EXEC dbo.RfcSAPSync @I_ReturnMessage =@API_ReturnMessage OUTPUT,
							@ItemName =N'U_ProductAllot',
							@UploadIngId=@UploadIngId

					IF  @API_ReturnMessage LIKE '%成功%'
					BEGIN 
					  UPDATE dbo.ProductAllotItem set ToSAPStates='过账成功',SAPInfor=REPLACE(@API_ReturnMessage, 'ServerMessage:','') WHERE ProductAllotItemId=@SProductAllotItemId

					END 
					ELSE 
					BEGIN 
					   UPDATE dbo.ProductAllotItem set ToSAPStates='过账失败',SAPInfor=REPLACE(@API_ReturnMessage, 'ServerMessage:','') WHERE ProductAllotItemId=@SProductAllotItemId
					END 

				   SET @I_ReturnMessage=ISNULL(@I_ReturnMessage,'')+@API_ReturnMessage+@Enter
				END  
			   END 
			   ELSE 
			   BEGIN 
				  UPDATE dbo.ProductAllotItem set ToSAPStates='过账成功',SAPInfor='' WHERE ProductAllotItemId=@SProductAllotItemId
			   END 

			    UPDATE dbo.UploadIng SET ISUpload=0 WHERE UploadIngId=@UploadIngId
				END 
			   FETCH NEXT FROM Cursor1 INTO @SProductAllotItemId,@SItemSequence --读取游标变量中的数据

			   END

			   CLOSE cursor1 --关闭游标

			   DEALLOCATE cursor1; --释放游标

					IF NOT EXISTS(SELECT 1 FROM dbo.ProductAllot AS pl inner JOIN dbo.ProductAllotItem AS plm ON plm.ProductAllotId = pl.ProductAllotId
										WHERE ISNULL(plm.ToSAPStates ,'')='' AND pl.ProductAllotId=@ProductAllotId )	   
					BEGIN

					IF EXISTS(SELECT 1 FROM dbo.ProductAllot AS pl inner JOIN dbo.ProductAllotItem AS plm ON plm.ProductAllotId = pl.ProductAllotId
										WHERE (plm.ToSAPStates='过账失败' OR ISNULL(plm.ToSAPStates ,'')='') AND pl.ProductAllotId=@ProductAllotId )
										BEGIN 
										  UPDATE dbo.ProductAllot SET 
												ProductAllotStates='41'
											WHERE ProductAllotId=@ProductAllotId
										END 
										ELSE 
										BEGIN 
										   UPDATE dbo.ProductAllot SET 
												ProductAllotStates='40'
											WHERE ProductAllotId=@ProductAllotId
										END 

					END

		FETCH NEXT FROM PALLOT 
		INTO @ProductAllotId
	END
	CLOSE PALLOT 
	DEALLOCATE PALLOT 

END TRY

BEGIN CATCH
 SET @I_ReturnMessage
                = 'ServerMessage:发生错误：' + CHAR(13) + CHAR(10) + '['
                  + LTRIM(RTRIM(CONVERT(CHAR(100), ERROR_NUMBER()))) + ']' + ERROR_MESSAGE()+LTRIM(RTRIM(CONVERT(CHAR(100), ERROR_LINE())))+ERROR_PROCEDURE();

            RETURN -1;

END CATCH


	

	RETURN 0
END
go

