SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2020/09/22 10:09:04:7475>
-- Description:   <PDA 来料点收,同时上架。按“送货单”启动条码>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[PDA_DeliveryReceivePutaway_DO]
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

@VendorDeliveryName NVARCHAR(50) ='',
@PreviousCellId CHAR(12)='', --前一个储位，即前一个上架OK的储位Id,为了找建议储位
@CellName NVARCHAR(50)='',
@NewFactoryName NVARCHAR(50) ='',
@BoxOrLotSN  NVARCHAR(50)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	SET @I_ExceptionFieldName  = 'BoxOrLotSN'
	--1、公共变量
	DECLARE @Enter NVARCHAR(20)=CHAR(13)+CHAR(10)
	DECLARE @return_value INT=-1
	DECLARE @Date VARCHAR(20)=CONVERT(VARCHAR,GETDATE(),23)

	--储位信息
	DECLARE @WareHouseId CHAR(12)=''
	DECLARE @WareHouseName NVARCHAR(50)=''
	DECLARE @CellId CHAR(12)=''
	DECLARE @StorageBags INT=0
	DECLARE @MaxInventory DECIMAL(18,6)=0
	DECLARE @AdviceCellId CHAR(12)='' --建议储位
	DECLARE @AdviceCellName NVARCHAR(50)=''
	DECLARE @AdviceWareHouseId CHAR(12)='' --建议仓库
	DECLARE @AdviceWareHouseName CHAR(12)='' --建议仓库


	--2、送货单信息
	--bill
	DECLARE @LotStartWay CHAR(1)=''
	DECLARE @VendorDeliveryId CHAR(12)=''
	DECLARE @VendorDeliveryStates NVARCHAR(10)=''
	DECLARE @VendorDeliveryStatesDesc NVARCHAR(10)=''
	DECLARE @VendorId CHAR(12)=''
	DECLARE @VendorName NVARCHAR(20)=''
	DECLARE @FactoryId CHAR(12)=''
	DECLARE @FactoryName NVARCHAR(100)=''
	--billItem
	DECLARE @VendorDeliveryItemId CHAR(12)=''	
	DECLARE @ProductId CHAR(12)=''
	DECLARE @ProductName NVARCHAR(200)=''
	DECLARE @ItemQtyDelivery FLOAT=0 -- 行发货数
	DECLARE @ItemQtySpare FLOAT=0 -- 备品数
	--billitemlot
	DECLARE @VendorDeliveryItemLotId CHAR(12)=''
	DECLARE @ProductionLotNO  NVARCHAR(50)=''
	DECLARE @LotSN NVARCHAR(50)='' --单个批号
	DECLARE @LotQty FLOAT=0 --单个批号的数量
	DECLARE @BoxSN NVARCHAR(50)='' --箱号
	DECLARE @IsSpareLot BIT=0                --是否备品
	DECLARE @LotType CHAR(1)=''              --类别 R/B
	DECLARE @LotTypeCode VARCHAR(20)=''      --扫描类别编码：lot、Box
	DECLARE @TotalReceiveQty FLOAT=0 --已点收数
	--
	DECLARE @ReceiveQty FLOAT=0 --本次接受数
	DECLARE @MBoxCount INT=0  --箱号中的批次数

	--3、采购订明细行
	DECLARE @POId CHAR(12)=''
	DECLARE @POItemId CHAR(12)=''
	DECLARE @POName NVARCHAR(50)=''
	DECLARE @DaysUrgent INT=0       --采购订单行交货日期，前几天，自动定义为急料
	DECLARE @DateRequired DATETIME=NULL

	--4、供应商物料接受管控
	DECLARE @ReceiveCode NVARCHAR(20)='' --收货CODE
	DECLARE @ReceiveMode NVARCHAR(40)=''--收货提示
	
	DECLARE @Tips NVARCHAR(MAX)
	--五、获取扫描所含的批号条码
	DECLARE @Temp TABLE(
		LotSN NVARCHAR(50),
		Qty DECIMAL(18,6)
	)

	SET @I_ExceptionFieldName  = 'BoxOrLotSN'
	--转为大写
	SET @BoxOrLotSN = UPPER(LTRIM(RTRIM(@BoxOrLotSN)))

	--获取按采购订单行交期，定义急料的天数
	IF EXISTS(SELECT 1 FROM dbo.SysParameter WHERE ParameterName='[WES SysControl]' AND ParameterValue='VendorDelivery_UrgentDays')
		SELECT @DaysUrgent=ParameterValueEx FROM dbo.SysParameter WHERE ParameterName='[WES SysControl]' AND ParameterValue='VendorDelivery_UrgentDays'
	ELSE
		SET @DaysUrgent=0


	IF ISNULL(@VendorDeliveryName,'') = ''
	BEGIN
		SET @Tips='请扫描送货单号!'
		SELECT '' AS VendorDeliveryName,'' AS BoxOrLotSN,'' AS AdviceCellName,@Tips AS Tips
		SET @I_ReturnMessage='ServerMessage:'+@Tips+@Enter
		SET @I_ExceptionFieldName='VendorDeliveryName' 
		RETURN -1
	END

	--检查扫描送货单是否存在系统内
	IF NOT EXISTS(SELECT 1 FROM dbo.VendorDelivery WHERE VendorDeliveryName = @VendorDeliveryName)
	BEGIN
		SET @Tips='送货单号【'+@VendorDeliveryName+'】不存在，请检查！'
		SELECT '' AS VendorDeliveryName,'' AS BoxOrLotSN,'' AS AdviceCellName,@Tips AS Tips
		SET @I_ReturnMessage = 'ServerMessage:'+@Tips+@Enter
		SET @I_ExceptionFieldName='VendorDeliveryName'
		RETURN -1 
	END

	--获取送货单信息
	SELECT  
		@VendorDeliveryId = VendorDeliveryId ,
		@VendorId = VendorDelivery.VendorId ,
		@VendorName=VendorShortName,
		@VendorDeliveryStates = VendorDeliveryStates,
		@LotStartWay=LotStartWay,
		@FactoryId=FactoryId
	FROM  dbo.VendorDelivery
	LEFT JOIN dbo.Vendor ON Vendor.VendorId=VendorDelivery.VendorId
	WHERE VendorDeliveryName = @VendorDeliveryName

	SELECT @FactoryName=FactoryName FROM dbo.Factory WHERE FactoryId=@FactoryId

	--检查发货单状态
	IF ISNULL(@VendorDeliveryStates,'')NOT IN( '30','41','51') 
	BEGIN
		SELECT  
			@VendorDeliveryStatesDesc = BillStatesDescription
		FROM    dbo.Bill
		INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
		WHERE   BillName = 'VendorDelivery' AND BillStatesName = @VendorDeliveryStates
		AND IsERP=0

		SET @Tips='送货单['+@VendorDeliveryName+']状态不可用，送货单状态【'+ISNULL(@VendorDeliveryStatesDesc,'')+'】,不允许点收!'
		SELECT '' AS VendorDeliveryName,'' AS BoxOrLotSN,'' AS AdviceCellName,@Tips AS Tips
		SET @I_ReturnMessage='ServerMessage:'+@Tips+@Enter	
		SET @I_ExceptionFieldName='VendorDeliveryName'   
		RETURN -1
	END

	IF ISNULL(@LotStartWay,'')<>'1'
	BEGIN
		SET @Tips='送货单['+@VendorDeliveryName+'] 不允许用在[送货单启动批号]的情况下点收！'
		SELECT '' AS VendorDeliveryName,'' AS BoxOrLotSN,'' AS AdviceCellName,@Tips AS Tips
		SET @I_ExceptionFieldName='VendorDeliveryName' 
		SET @I_ReturnMessage='ServerMessage:'+@Tips+@Enter
		RETURN -1
	END 


	--**********************************************【 1.扫描物料条码 】**********************************************************************************
	IF ISNULL(@BoxOrLotSN,'') = ''
	BEGIN
		SET @Tips='请扫描来料的最小包装条码或者外箱'
		SELECT '' AS BoxOrLotSN,@Tips AS Tips
		SET @I_ReturnMessage='ServerMessage:'+@Tips+@Enter	   
		RETURN -1
	END

	--检查是否小包或者外箱
	IF EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE LotSN=@BoxOrLotSN AND DeleteFlag='')
	BEGIN 
		SET @LotType='R'
		SET @LotTypeCode='Lot'
	END

	IF EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE BoxSN=@BoxOrLotSN AND DeleteFlag='')
	BEGIN 
		SET @LotType='B'
		SET @LotTypeCode='Box'
	END


	--检查扫描来料批号是否是R / B 开头的
	IF LEFT(@LotType,1) NOT IN ('R','B')
	BEGIN
		SET @Tips='扫描条码【'+@BoxOrLotSN+'】不是来料条码，请检查！'+CHAR(13)+CHAR(10)+'请扫描来料的最小包装条码/外箱！在送货单中启动的物料条码！'
		SELECT ' ' AS BoxOrLotSN,@Tips AS Tips
		SET @I_ReturnMessage = 'ServerMessage:'+@Tips+@Enter
		RETURN -1 
	END


	--扫描小包条码
	IF LEFT(@LotType,1)='R'
	BEGIN
		--检查小包标签批号是否存在系统中
		IF NOT EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE LotSN=@BoxOrLotSN)
		BEGIN
			SET @Tips='最小包批号【'+@BoxOrLotSN+'】不存在，请确认！'
			SELECT '' AS BoxOrLotSN,@Tips AS Tips
			SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			RETURN -1
		END

		IF NOT EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE LotSN=@BoxOrLotSN AND DeleteFlag='')
		BEGIN
			SET @Tips='最小包批号【'+@BoxOrLotSN+'】已被取消，请确认！'
			SELECT '' AS BoxOrLotSN,@Tips AS Tips
			SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			RETURN -1
		END

		--检查小包是否已执行点收
		IF EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE LotSN=@BoxOrLotSN AND IsReceiveScan=1)
		BEGIN
			SET @Tips='最小包批号【'+@BoxOrLotSN+'】已点收，不允许重复点收！'
			SELECT '' AS BoxOrLotSN,@Tips AS Tips
			SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			RETURN -1
		END


		--检查小包是否已收货拒收
		IF EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE LotSN=@BoxOrLotSN AND IsArrivalReject=1)
		BEGIN
			SET @Tips='最小包批号【'+@BoxOrLotSN+'】已收货拒收，不能再点收！（已拒收啦）'
			SELECT '' AS BoxOrLotSN,@Tips AS Tips
			SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			RETURN -1
		END


		-- 检查扫描小包是否属于此送货单
		IF NOT EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot 
		INNER JOIN dbo.VendorDeliveryItem ON VendorDeliveryItem.VendorDeliveryItemId=VendorDeliveryItemLot.VendorDeliveryItemId
		WHERE VendorDeliveryId = @VendorDeliveryId AND LotSN = @BoxOrLotSN AND DeleteFlag='')
		BEGIN
			SET @Tips='扫描小包批号【'+@BoxOrLotSN+'】不属于该送货单【'+@VendorDeliveryName+'】请确认！'
			SELECT '' AS BoxOrLotSN,@Tips AS Tips
			SET @I_ReturnMessage = 'ServerMessage:'+@Tips+@Enter
			RETURN -1
		END


		--获取送货批号信息
		SELECT 
			@VendorDeliveryItemId=VendorDeliveryItemId,
			@ProductionLotNO=ProductionLotNO,
			@BoxSN=BoxSN,
			@IsSpareLot=IsSpareLot
		FROM dbo.VendorDeliveryItemLot 
		WHERE LotSN=@BoxOrLotSN AND DeleteFlag=''

		--获取送货单行信息
		SELECT TOP 1
			@VendorDeliveryId = VendorDeliveryId ,
			@POItemId=POItemId,
			@POName=POName,
			@ProductId=ProductId,
			@ItemQtyDelivery = ISNULL(ItemQtyDelivery,0),
			@ItemQtySpare = ISNULL(ItemQtySpare,0)
		FROM  dbo.VendorDeliveryItem
		LEFT JOIN dbo.PO ON PO.POId=VendorDeliveryItem.POId
		WHERE VendorDeliveryItemId = @VendorDeliveryItemId

		SELECT  
			@ReceiveQty=ISNULL(SUM(Qty),0),
			@MBoxCount=COUNT(LotSN)
		FROM dbo.VendorDeliveryItemLot
		WHERE VendorDeliveryItemId=@VendorDeliveryItemId AND LotSN = @BoxOrLotSN
			AND IsReceiveScan = 0 AND DeleteFlag=''

		--获取物料批号信息
		INSERT INTO @Temp
			 (
				 LotSN,
				 Qty
			 )
		VALUES
			 (
				 @BoxOrLotSN,
				 @ReceiveQty
			 )
	END
 

	--扫描外箱
	IF LEFT(@LotType,1)='B'
	BEGIN
		--检查外箱是否存在系统中
		IF NOT EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE BoxSN=@BoxOrLotSN)
		BEGIN
			SET @Tips='外箱【'+@BoxOrLotSN+'】不存在，请确认！'
			SELECT '' AS BoxOrLotSN,@Tips AS Tips
			SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			RETURN -1
		END

		IF NOT EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE BoxSN=@BoxOrLotSN AND DeleteFlag='')
		BEGIN
			SET @Tips='外箱【'+@BoxOrLotSN+'】已被取消，请确认！'
			SELECT '' AS BoxOrLotSN,@Tips AS Tips
			SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			RETURN -1
		END

		--检查外箱是否已执行点收
		IF EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE BoxSN=@BoxOrLotSN AND IsReceiveScan=1 AND DeleteFlag='')
		BEGIN
			IF EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE BoxSN=@BoxOrLotSN AND IsReceiveScan=0 AND DeleteFlag='')
			BEGIN
				SET @Tips='外箱【'+@BoxOrLotSN+'】中的部分批号 已点收，请按小包点收！'
				SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			END
			ELSE
			BEGIN
				SET @Tips='外箱【'+@BoxOrLotSN+'】已点收，不允许重复点收！'
				SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			END

			SELECT '' AS BoxOrLotSN
			RETURN -1
		END

		--检查外箱是否已收货拒收
		IF EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE BoxSN=@BoxOrLotSN AND IsArrivalReject=1 AND DeleteFlag='')
		BEGIN
			IF EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot WHERE BoxSN=@BoxOrLotSN AND IsArrivalReject=0 AND DeleteFlag='')
			BEGIN
				SET @Tips='外箱【'+@BoxOrLotSN+'】中的部分批号 已收货拒收，请按小包点收！'
				SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			END
			ELSE
			BEGIN
				SET @Tips='外箱【'+@BoxOrLotSN+'】已收货拒收，不能再点收！（已拒收啦）'
				SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			END

			SELECT '' AS BoxOrLotSN
			RETURN -1
		END

		-- 检查外箱是否属于此送货单
		IF NOT EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot 
						INNER JOIN dbo.VendorDeliveryItem ON VendorDeliveryItem.VendorDeliveryItemId=VendorDeliveryItemLot.VendorDeliveryItemId
						WHERE VendorDeliveryId = @VendorDeliveryId AND BoxSN = @BoxOrLotSN AND DeleteFlag='')
		BEGIN
			SET @Tips='外箱【'+@BoxOrLotSN+'】不属于此送货单【'+@VendorDeliveryName+'】，请确认！'
			SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			SELECT '' AS BoxOrLotSN,@Tips AS Tips
			RETURN -1
		END

		--获取送货批号信息
		SELECT TOP 1
			@VendorDeliveryItemId=VendorDeliveryItemId,
			@ProductionLotNO=ProductionLotNO,
			@BoxSN=BoxSN,
			@IsSpareLot=IsSpareLot
		FROM dbo.VendorDeliveryItemLot 
		WHERE BoxSN=@BoxOrLotSN AND DeleteFlag=''

		--获取送货单行信息
		SELECT TOP 1
			@VendorDeliveryId = VendorDeliveryId ,
			@POItemId=POItemId,
			@POName=POName,
			@ProductId=ProductId,
			@ItemQtyDelivery = ISNULL(ItemQtyDelivery,0),
			@ItemQtySpare = ISNULL(ItemQtySpare,0)
		FROM  dbo.VendorDeliveryItem
		LEFT JOIN dbo.PO ON PO.POId=VendorDeliveryItem.POId
		WHERE VendorDeliveryItemId = @VendorDeliveryItemId

		SELECT  
			@ReceiveQty=ISNULL(SUM(Qty),0),
			@MBoxCount=COUNT(LotSN)
		FROM dbo.VendorDeliveryItemLot
		WHERE VendorDeliveryItemId=@VendorDeliveryItemId AND BoxSN = @BoxOrLotSN
			AND IsReceiveScan = 0 AND IsArrivalReject=0 AND DeleteFlag='' 

		--获取物料批号信息
		INSERT INTO @Temp
			 (
				 LotSN,
				 Qty
			 )
		SELECT LotSN,
			   Qty
		FROM dbo.VendorDeliveryItemLot
		WHERE VendorDeliveryItemId=@VendorDeliveryItemId AND BoxSN = @BoxOrLotSN
			AND IsReceiveScan = 0 AND IsArrivalReject=0 AND DeleteFlag='' 
	END


	--获取送货单行累计点收数量
	SELECT 
		@TotalReceiveQty=SUM(Qty)
	FROM dbo.VendorDeliveryItemLot
	INNER JOIN dbo.VendorDeliveryItem ON VendorDeliveryItem.VendorDeliveryItemId=VendorDeliveryItemLot.VendorDeliveryItemId
	WHERE VendorDeliveryItem.VendorDeliveryItemId = @VendorDeliveryItemId AND DeleteFlag='' 
		AND IsReceiveScan = 1 AND IsSpareLot=@IsSpareLot


	SELECT  
		@ProductName = ProductName + ' '+ ProductRevision
	FROM dbo.Product
	INNER JOIN dbo.ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId
	WHERE ProductId = @ProductId



	--如果累计点收数量 + 本次点收数 > 行需求数量，则提示
	IF @IsSpareLot=1
	BEGIN
		IF CAST(ISNULL(@TotalReceiveQty,0)+ISNULL(@ReceiveQty,0) AS DECIMAL(18,6))>CAST(ISNULL(@ItemQtySpare,0) AS DECIMAL(18,6))
		BEGIN
			 SET @Tips='送货单行累计点收备品数【'+CAST(ISNULL(@TotalReceiveQty,0) AS VARCHAR)+'】'
			 +CHAR(13)+CHAR(10)++'加上本次点收数【'+CAST(@ReceiveQty AS VARCHAR)+'】大于行备品数【'+CAST(@ItemQtySpare AS VARCHAR)+']，已超出，请确认!'
			 SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			 SELECT '' AS BoxOrLotSN,'' AS Tips
			 RETURN -1
		END 
	END 
	ELSE
	BEGIN
		IF CAST(ISNULL(@TotalReceiveQty,0)+ISNULL(@ReceiveQty,0) AS DECIMAL(18,6))>CAST(ISNULL(@ItemQtyDelivery,0) AS DECIMAL(18,6))
		BEGIN
			 SET @Tips='送货单行累计点收数【'+CAST(ISNULL(@TotalReceiveQty,0) AS VARCHAR)+'】'
			 +CHAR(13)+CHAR(10)++'加上本次点收数【'+CAST(@ReceiveQty AS VARCHAR)+'】大于行送货数【'+CAST(@ItemQtyDelivery AS VARCHAR)+']，已超出，请确认!'
			 SET @I_ReturnMessage ='ServerMessage:'+@Tips+@Enter
			 SELECT '' AS BoxOrLotSN,'' AS Tips
			 RETURN -1
		END 		
	END 

	--根据供应商 查找 供应商产品相关信息  
	--SELECT  
	--	@ReceiveCode = ISNULL(t1.ParameterValueEx,'') ,--R/B
	--	@ReceiveMode = ISNULL(t1.ParameterDescription,'') --按箱号点收/按小包点收
	--FROM    dbo.Vendor_Product
	--LEFT OUTER JOIN ( SELECT ParameterValue ,ParameterDescription ,ParameterValueEx
	--					FROM dbo.SysParameter WHERE ParameterName = N'[Receive Mode]'
	--				) AS t1 ON ReceiveMode = t1.ParameterValue
	--WHERE ProductId = @ProductId AND VendorId = @VendorId

	--检查是否已设置点收方式（按箱号点收、按小包点收）
	--IF ISNULL(@ReceiveCode,'')=''
	--BEGIN
	--	SELECT '' AS BoxOrLotSN
	--	SET @I_ReturnMessage ='ServerMessage:供应商物料【'+@ProductName+'】未设置来料点收方式，请确认！'+@Enter
	--	RETURN -1
	--END


	SET @Tips=ISNULL(@Tips,'')+CHAR(13)+CHAR(10)++'------------------------------'
	SET @Tips=ISNULL(@Tips,'')+CHAR(13)+CHAR(10)++'@ScanResult'
	SET @Tips=ISNULL(@Tips,'')+CHAR(13)+CHAR(10)++'条码：['+ISNULL(@BoxOrLotSN,'')+']'    
	SET @Tips=ISNULL(@Tips,'')+CHAR(13)+CHAR(10)++'供应商：['+ISNULL(@VendorName,'')+']'
   
	---查找产品信息
	SET @Tips=ISNULL(@Tips,'')+CHAR(13)+CHAR(10)++'产品：['+ISNULL(@ProductName,'')+']'
	SET @Tips=ISNULL(@Tips,'')+CHAR(13)+CHAR(10)++'箱号：['+ISNULL(@BoxSN,'')+']'  
	SET @Tips=ISNULL(@Tips,'')+CHAR(13)+CHAR(10)++'小包：['+ISNULL(CAST(@MBoxCount AS VARCHAR),'')+']'  
	 


	--检查是否要求按小包点收
	IF ISNULL(@ReceiveCode,'')<>'' AND ISNULL(@ReceiveCode,'')='R'
	BEGIN
		IF @LotType<>ISNULL(@ReceiveCode,'')
		BEGIN
			SELECT '' AS BoxOrLotSN,@Tips AS Tips
			SET @Tips=REPLACE(@Tips,'@ScanResult','错误消息：收货方式【'+ISNULL(@ReceiveMode,'')+']')
			SET @I_ReturnMessage='ServerMessage:'+@Tips+CHAR(13)+CHAR(10)++'------------------------------'+@Enter
			RETURN -1
		END
	END  
	 
	--根据收货方式更新相关信息
	--SET @I_ReturnMessage=@I_ReturnMessage+CHAR(13)+CHAR(10)++'收货方式：['+ISNULL(@ReceiveMode,'')+']'






	--**********************************************【 2.扫描储位 】**********************************************************************************
	-- 《检查储位》：为空，则获取建议储位；否则执行上逻辑检查
	IF ISNULL(@CellName,'')=''
	BEGIN
		--获取建议储位
		 EXEC @return_value=dbo.TxnBase_MAdviceCell
			 @I_ReturnMessage=@I_ReturnMessage OUTPUT, -- nvarchar(max)
			 @I_OrBitUserId=@I_OrBitUserId, -- char(12)
			 @I_OrBitUserName=@I_OrBitUserName, -- nvarchar(100)
			 @I_ResourceId=@I_ResourceId, -- char(12)
			 @I_ResourceName=@I_ResourceName, -- nvarchar(100)
			 @I_PlugInCommand=@I_PlugInCommand, -- varchar(5)
			 @AdviceWarehouseId=@AdviceWarehouseId OUTPUT, -- char(12)
			 @AdviceCellId=@AdviceCellId OUTPUT, -- char(12)
			 @PreviousCellId=@PreviousCellId, -- char(12)
			 @ToWarehosueId='', -- char(12)
			 @SN=@BoxOrLotSN -- nvarchar(100)

		SELECT @AdviceCellName=CellName
		FROM dbo.Cell
		WHERE CellId=@AdviceCellId

		SELECT @AdviceWareHouseName=WorkcenterName
		FROM dbo.Workcenter
		WHERE WorkcenterId=@AdviceWareHouseId

		SET @Tips='请扫描储位号!'
		SELECT @AdviceWareHouseName AS WareHouseName,@AdviceCellName AS AdviceCellName,@Tips AS Tips
		SET @I_ReturnMessage='ServerMessage:'+@Tips+@Enter
		SET @I_ExceptionFieldName='CellName'
		RETURN 0
	END
	ELSE
	BEGIN
		IF NOT EXISTS(SELECT 1 FROM dbo.Cell WHERE CellName=@CellName AND IsActivity=1)
		BEGIN
			SET @Tips='储位号【'+@CellName+'】不存在 或 没有激活，请检查!'
			SELECT '' AS BoxOrLotSN,'' AS CellName,'' AS WareHouseName,'' AS AdviceCellName,@Tips AS Tips
			SET @I_ReturnMessage='ServerMessage:'+@Tips+@Enter
			SET @I_ExceptionFieldName='BoxOrLotSN'
			RETURN -1
		END
		--获取储位信息
		SELECT 
			@CellId=CellId,
			@WareHouseId=WorkcenterId,
			@StorageBags=ISNULL(StorageBags,0),
			@MaxInventory=ISNULL(MaxInventory,0)
		FROM dbo.Cell
		WHERE CellName=@CellName

		SELECT @WareHouseName=WorkcenterName FROM dbo.Workcenter WHERE WorkcenterId=@WareHouseId

		--检查包材入库仓库是否正确

		 IF EXISTS(SELECT 1 FROM dbo.Product AS p INNER JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p.ProductRootId
		                                          INNER JOIN dbo.ProductFamily AS pf ON pf.ProductFamilyId = pr.ProductFamilyId
												  WHERE p.ProductId =@ProductId AND pf.ProductFamilyName IN ('102859','102858','102850','102855','102857')) AND @NewFactoryName='保税区厂'
         BEGIN 
		  DECLARE @ProductFamilyName NVARCHAR(50)=''
		  SELECT @ProductFamilyName=pf.ProductFamilyName FROM dbo.Product AS p INNER JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p.ProductRootId
		                                          INNER JOIN dbo.ProductFamily AS pf ON pf.ProductFamilyId = pr.ProductFamilyId
												  WHERE p.ProductId =@ProductId 
		   
					IF(@CellName !=CASE WHEN @ProductFamilyName = '102859' THEN 'BC1E001'
										WHEN @ProductFamilyName = '102858' THEN 'BC7E001'  
										WHEN @ProductFamilyName = '102850' THEN 'BC7E001' 
										WHEN @ProductFamilyName = '102855' OR @ProductFamilyName = '102857' THEN 'BC7H001'END  )
					BEGIN 

						SET @Tips='储位号【'+@CellName+'】错误，包材【'+@ProductName+'】请入建议储位号【'+ CASE WHEN @ProductFamilyName = '102859' THEN 'BC1E001' 
																												WHEN @ProductFamilyName = '102858' THEN 'BC7E001'  
																												WHEN @ProductFamilyName = '102850' THEN 'BC7E001' 
																												WHEN @ProductFamilyName = '102855' OR @ProductFamilyName = '102857' THEN 'BC7H001'END+'】，请检查!'
						SELECT @Tips AS Tips
						SET @I_ReturnMessage='ServerMessage:'+@Tips+@Enter
						SET @I_ExceptionFieldName='CellName'
						RETURN -1
					END 
        END 

		IF EXISTS(SELECT 1 FROM dbo.Product AS p INNER JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p.ProductRootId
		                                          INNER JOIN dbo.ProductFamily AS pf ON pf.ProductFamilyId = pr.ProductFamilyId
												  WHERE p.ProductId =@ProductId AND pf.ProductFamilyName IN ('102859','102858','102850','102855','102857')) AND @NewFactoryName='金湾区厂'
         BEGIN 
		  SELECT @ProductFamilyName=pf.ProductFamilyName FROM dbo.Product AS p INNER JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p.ProductRootId
		                                          INNER JOIN dbo.ProductFamily AS pf ON pf.ProductFamilyId = pr.ProductFamilyId
												  WHERE p.ProductId =@ProductId 
		   
					IF(@CellName !=CASE WHEN @ProductFamilyName = '102859' THEN 'A401'
										WHEN @ProductFamilyName = '102858' THEN 'A501'  
										WHEN @ProductFamilyName = '102850' THEN 'A501' 
										WHEN @ProductFamilyName = '102855' OR @ProductFamilyName = '102857' THEN 'A502'END  )
					BEGIN 

						SET @Tips='储位号【'+@CellName+'】错误，包材【'+@ProductName+'】请入建议储位号【'+ CASE WHEN @ProductFamilyName = '102859' THEN 'A401' 
																												WHEN @ProductFamilyName = '102858' THEN 'A501'  
																												WHEN @ProductFamilyName = '102850' THEN 'A501' 
																												WHEN @ProductFamilyName = '102855' OR @ProductFamilyName = '102857' THEN 'A502'END+'】，请检查!'
						SELECT @Tips AS Tips
						SET @I_ReturnMessage='ServerMessage:'+@Tips+@Enter
						SET @I_ExceptionFieldName='CellName'
						RETURN -1
					END 
        END 
	
	    	--检查共用物料入库仓库是否正确
		--排除9302 FAC1000000T7
		declare @ZR_FactoryId nvarchar(50)
         select @ZR_FactoryId = factoryid from VendorDelivery where VendorDeliveryName = @VendorDeliveryName
		 IF EXISTS(SELECT 1 FROM dbo.Product AS p INNER JOIN MixProduct mp ON p.ProductId=mp.ProductId
									  WHERE p.ProductId =@ProductId ) and (@ZR_FactoryId != 'FAC1000000T7')
         BEGIN 
		 
					IF(@WareHouseName !=(SELECT mp.WorkCenterName FROM MixProduct mp WHERE mp.ProductId =@ProductId) )
					BEGIN 

						SET @Tips='储位号【'+@CellName+'】错误，共用物料请入建议仓库【'+(SELECT mp.WorkCenterName FROM MixProduct mp WHERE mp.ProductId =@ProductId)+'】，请检查!'
						SELECT @Tips AS Tips
						SET @I_ReturnMessage='ServerMessage:'+@Tips+@Enter
						SET @I_ExceptionFieldName='CellName'
						RETURN -1
					END 
        END 

		--检查仓库是否有效
		IF NOT EXISTS(SELECT 1 FROM dbo.Workcenter WHERE WorkcenterId=@WareHouseId)
		BEGIN
			SET @Tips='储位【'+@CellName+'】没有关联仓库，请检查!'
			SELECT '' AS BoxOrLotSN,'' AS CellName,'' AS WareHouseName,'' AS AdviceCellName,@Tips AS Tips
			SET @I_ReturnMessage='ServerMessage:'+@Tips+@Enter
			SET @I_ExceptionFieldName='BoxOrLotSN'
			RETURN -1
		END

		IF NOT EXISTS(SELECT 1 FROM dbo.Workcenter
		WHERE WorkcenterId=@WareHouseId AND Workcenter.FactoryId=@FactoryId)
		BEGIN
			SET @Tips='送货单【'+@VendorDeliveryName+'】属于工厂【'+@FactoryName+'】,'
				+@Enter+'储位【'+@CellName+'】对应的仓库【'+@WareHouseName+'】不属于此工厂，请检查!'
			SELECT '' AS BoxOrLotSN,'' AS CellName,'' AS WareHouseName,'' AS AdviceCellName,@Tips AS Tips
			SET @I_ReturnMessage='ServerMessage:'+@Tips+@Enter
			SET @I_ExceptionFieldName='BoxOrLotSN'
			RETURN -1
		END
	END


	--入库策略检查
	EXEC @return_value=dbo.TxnBase_MLotInCellCheck
		@I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
		@I_OrBitUserId = @I_OrBitUserId, -- char(12)
		@I_OrBitUserName = @I_OrBitUserName, -- nvarchar(100)
		@I_ResourceId = @I_ResourceId, -- char(12)
		@I_ResourceName = @I_ResourceName, -- nvarchar(100)
		@I_PlugInCommand = @I_PlugInCommand, -- varchar(5)
		@InObject = @LotTypeCode, -- nvarchar(50)
		@InLotNO=@ProductionLotNO,
		@InProductId = @ProductId, -- char(12)
		@InWarehouseId = @WareHouseId, -- char(12)
		@InCellId = @CellId, -- char(12)
		@InStorageBags=@MBoxCount,
		@InSumQty=@ReceiveQty

	IF @return_value<>0
	BEGIN
		SET @Tips=@I_ReturnMessage
							+CASE @LotType WHEN 'R' THEN '小包' WHEN 'B' THEN '外箱' ELSE '' END
							+ '【'+@BoxOrLotSN+'】点收上架失败!'

		SELECT '' AS BoxOrLotSN,'' AS CellName,'' AS WareHouseName,'' AS AdviceCellName,@Tips AS Tips
		SET @I_ExceptionFieldName='BoxOrLotSN'
		SET @I_ReturnMessage=@Tips+@Enter
		RETURN -1
	END

	








	--**********************************************【 3.保存数据 】**********************************************************************************
	--按外箱点收
	IF LEFT(@LotType,1)='B'
	BEGIN  
		--更新送货单批号状态
		UPDATE dbo.VendorDeliveryItemLot SET 
			IsReceiveScan=1,
			ReceiveDate=GETDATE(),
			WorkcenterId=@WareHouseId,
			CellId=@CellId,
			IsPutaway=1,
			PutawayDate=GETDATE()
		WHERE BoxSN=@BoxOrLotSN AND IsArrivalReject=0 AND DeleteFlag=''

		--更新发货单行物料接收数量
		UPDATE dbo.VendorDeliveryItem SET 
			ItemQtyReceived = ISNULL(ItemQtyReceived,0)+@ReceiveQty
		WHERE VendorDeliveryItemId = @VendorDeliveryItemId

		--更新采购单行物料接收数量,对于是备品的，不算采购订单的拒收数
		IF @IsSpareLot=0
		BEGIN 
			UPDATE dbo.POItem SET 
				ItemQtyReceived = ISNULL(ItemQtyReceived,0)+@ReceiveQty
			WHERE POItemId = @POItemId
		END 

		SET @Tips=@I_ReturnMessage+CHAR(13)+CHAR(10)++'整箱接收数量：['+ISNULL(CAST(@ReceiveQty AS VARCHAR),'')+']'
		SELECT @Tips AS Tips
		SET @I_ReturnMessage=@Tips+@Enter
	END

	--按最小包装点收
	IF LEFT(@LotType,1)='R'
	BEGIN 
		--更新送货单批号状态
		UPDATE dbo.VendorDeliveryItemLot SET 
			IsReceiveScan=1,
			ReceiveDate=GETDATE(),
			WorkcenterId=@WareHouseId,
			CellId=@CellId,
			IsPutaway=1,
			PutawayDate=GETDATE()
		WHERE LotSN=@BoxOrLotSN AND DeleteFlag=''

		--更新发货单行物料接收数量
		UPDATE dbo.VendorDeliveryItem SET 
			ItemQtyReceived=ISNULL(ItemQtyReceived,0)+@ReceiveQty
		WHERE VendorDeliveryItemId = @VendorDeliveryItemId

		--更新采购单行物料接收数量,对于是备品的，不算采购订单的接受数
		IF @IsSpareLot=0
		BEGIN 
			UPDATE dbo.POItem SET 
				ItemQtyReceived = ISNULL(ItemQtyReceived,0)+@ReceiveQty
			WHERE POItemId = @POItemId
		END 

		SET @Tips=@I_ReturnMessage+CHAR(13)+CHAR(10)+'小包接收数量：['+ISNULL(CAST(@ReceiveQty AS VARCHAR),'')+']'
		SELECT @Tips AS Tips
		SET @I_ReturnMessage=@Tips+@Enter
	END


	--插入物料追踪表
	DECLARE cursorItem CURSOR LOCAL FAST_FORWARD FOR  
	SELECT  LotSN,Qty FROM @Temp
	OPEN cursorItem
	FETCH NEXT FROM cursorItem 
	INTO @LotSN,@LotQty
	WHILE @@FETCH_STATUS = 0 
	BEGIN		
		--插入物料批号追踪表
		EXEC dbo.TxnBase_MLotTrack
			@I_OrBitUserId =@I_OrBitUserId, -- char(12)
			@I_PlugInCommand=@I_PlugInCommand,
			@I_ResourceId =@I_ResourceId, -- char(12)
			@LotSN =@LotSN , -- nvarchar(50) --物料批号
			@LotQty = @LotQty, -- decimal(18, 6)--数量
			@TxnCode = 'M-来料点收上架', -- nvarchar(50) --事务码
			@OrderName =@VendorDeliveryName , -- nvarchar(50) --单据号
			@Remark = N'' -- nvarchar(200) --备注

		FETCH NEXT FROM cursorItem 
		INTO @LotSN,@LotQty
	END
	CLOSE cursorItem
	DEALLOCATE cursorItem 

	--检查是否定义为急料,按急料定义
	IF EXISTS(SELECT 1 FROM dbo.UrgentMaterial WHERE CONVERT(VARCHAR,StartDate,23)<=@Date AND CONVERT(VARCHAR,EndDate,23)>=@Date)
	BEGIN
		IF EXISTS(SELECT 1 FROM dbo.UrgentMaterialItem 
			INNER JOIN dbo.UrgentMaterial ON UrgentMaterial.UrgentMaterialId=UrgentMaterialItem.UrgentMaterialId
			WHERE CONVERT(VARCHAR,StartDate,23)<=@Date AND CONVERT(VARCHAR,EndDate,23)>=@Date 
				AND ProductId=@ProductId)
		BEGIN
			--定义为急料
			UPDATE dbo.VendorDeliveryItem SET 
				IsUrgent=1
			WHERE VendorDeliveryItemId=@VendorDeliveryItemId
		END
	END

	--检查是否定义为急料,按采购订单行交期定义
	IF @DaysUrgent>0
	BEGIN
		--获取采购订单行交期
		SELECT TOP 1
			@DateRequired=DateRequired
		FROM dbo.POItem 
		WHERE POItemId=@POItemId

		--在天数范围内
		IF DATEDIFF(DAY,@DateRequired,GETDATE())<=@DaysUrgent
			--定义为急料
			UPDATE dbo.VendorDeliveryItem SET 
				IsUrgent=1
			WHERE VendorDeliveryItemId=@VendorDeliveryItemId
	END

	--计算是否清除储位
	IF @StorageBags>0
	BEGIN
		--存满，则清空
		IF(SELECT COUNT(1) FROM dbo.WW_RMInventory WHERE CellId=@CellId AND IsStorage=1 AND LotStatus<>'2')>=@StorageBags
		BEGIN
			SET @CellName=''
		END
	END

	IF @MaxInventory>0	AND @CellName<>''
	BEGIN
		--存满，则清空
		IF(SELECT ISNULL(SUM(Qty),0) FROM dbo.WW_RMInventory WHERE CellId=@CellId AND IsStorage=1 AND LotStatus<>'2')>=@MaxInventory
		BEGIN
			SET @CellName=''
		END
	END

	DECLARE @ProductDescription NVARCHAR(100)
	SELECT @ProductDescription=ProductDescription FROM Product WHERE ProductId=@ProductId


	--返回界面数据
	SET @Tips=REPLACE(@I_ReturnMessage,'@ScanResult','收货结果：[收货成功]')+'--------------------------'
	SELECT '' AS BoxOrLotSN,
		  @ProductId AS CurProductId, --为了表示当前扫描的产品
		  @CellId AS PreviousCellId,--为了计算建议储位,
		  @CellName AS CellName,
		  @ProductDescription AS ProductDescription,
		  @Tips AS Tips
	
	SET @I_ExceptionFieldName='BoxOrLotSN'
	
	SET @I_ReturnMessage='ServerMessage：'+@Tips +@Enter

	RETURN 0


END
GO
