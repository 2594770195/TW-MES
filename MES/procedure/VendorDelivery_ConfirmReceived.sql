SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Modify by <HH0082 Sunshineding>
-- Create date:   <2020/06/11>
-- Description:   <来料收货：确认收货>
-- Rev: 1.00
-- =============================================
CREATE PROC [dbo].[VendorDelivery_ConfirmReceived]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
-----------------------------------------------

@VendorDeliveryName NVARCHAR(50) ='', --送货单
@I_PKid CHAR(12)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--通用变量
	DECLARE @return_value INT=-1
	DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10)
	DECLARE @UploadIngId CHAR(12)=''
	DECLARE @VendorDeliveryId CHAR(12)=''
	DECLARE @FinishingEntryName NVARCHAR(50)=''
	DECLARE @Remark NVARCHAR(200) --备注
	--送货单（采购/委外/其他）。是否允许分批送检，1表示可以(一个送货单行可以分多次送检)，0表示不可以
	DECLARE @IsAllowInBatches VARCHAR(2)='' 
	--送货单（采购/委外/其他）。是否允许合并多行，1表示允许（同一个送货单，同一个产品由多行，允许合并成一个送货单）,0表示不可以
	DECLARE @IsAllowCombineMultiline VARCHAR(2)=''

	--送货单
	--bill
	DECLARE @VendorDeliveryType VARCHAR(20)=''
	DECLARE @VendorDeliveryStates VARCHAR(20)=''
	DECLARE @StatesName NVARCHAR(50)=''
	DECLARE @StatesDesc NVARCHAR(100)=''
	DECLARE @InterfaceItemId CHAR(12)=''
	DECLARE @FactoryId CHAR(12)=''
	DECLARE @VendorId CHAR(12)='' --供应商
	DECLARE @IQCType_Product CHAR(1)='' --产品检验类别
	DECLARE @IQCInspectionType_Product CHAR(1)='' --产品检验方式
	--billItem
	DECLARE @VendorDeliveryItemId CHAR(12)=''
	DECLARE @POId CHAR(12)=''
	DECLARE @POItemId CHAR(12)=''
	DECLARE @ProductId CHAR(12)=''
	DECLARE @ProductName NVARCHAR(50)=''
	DECLARE @DeliveryUOMId CHAR(12)=''
	--billItemLot
	DECLARE @VendorDeliveryItemLotId CHAR(12)=''
	DECLARE @LotSN NVARCHAR(50)=''
	DECLARE @LotQty DECIMAL(18,6)=0
	DECLARE @ProductionLotNO NVARCHAR(50)=''

	--IQC检验单
	--bill
	DECLARE @ReceiveQty FLOAT=0
	DECLARE @IQCCheckName NVARCHAR(50)=''
	DECLARE @IQCCheckId CHAR(12)=''
	DECLARE @IQCCheckLotId CHAR(12)=''
	DECLARE @ObjectName NVARCHAR(50)=''
	DECLARE @WorkflowStepId CHAR(12)=''

	--送货到货单
	--bill
	DECLARE @DeliveryArrivalId CHAR(12)=''
	DECLARE @DeliveryArrivalName NVARCHAR(50)=''
	DECLARE @DeliveryArrivalStates VARCHAR(20)=''
	--billItem
	DECLARE @DeliveryArrivalItemId CHAR(12)=''
	DECLARE @VendorDeliveryItemNO VARCHAR(20)='' --到货单明细行号
	DECLARE @ReceiptQty DECIMAL(18,6)=0 --收货数量（不含备品）
	DECLARE @SpareReceiptQty DECIMAL(18,6)=0 --备品收货数量
	DECLARE @WorkcenterId CHAR(12)
	DECLARE @TempSpareReceiptQty TABLE(Id INT IDENTITY(1,1),
	                          WorkcenterId CHAR(12),
	                          SpareReceiptQty DECIMAL(18,6))
	DECLARE @TempRecQty TABLE(Id INT IDENTITY(1,1),
	                          WorkcenterId CHAR(12),
							  ReceiptQty DECIMAL(18,6),
	                          SpareReceiptQty DECIMAL(18,6))

	--本次可收货确认的送货单明细
	DECLARE @VendorDeliveryItemTemp TABLE(
		VendorDeliveryItemId CHAR(12),
		ProductId CHAR(12),
		ProductionLotNO VARCHAR(50)
	)

	--统计生成了多少个IQC检验单，为了方便创建送货到货明细
	DECLARE @Temp_IQCBill TABLE(
		IQCCheckId CHAR(12)
	)

	--获取是否允许分批
	SELECT @IsAllowInBatches=ParameterValueEx
	FROM dbo.SysParameter WHERE ParameterName='[WES SysControl]' 
	AND ParameterValue='VendorDelivery_IQCBatchSend'
	--是否允许合并多行
	SELECT @IsAllowCombineMultiline=ParameterValueEx
	FROM dbo.SysParameter WHERE ParameterName='[WES SysControl]' 
	AND ParameterValue='VendorDelivery_IQCMultilineSend'

	IF ISNULL(@IsAllowInBatches,'') NOT IN('0','1')
	   SET @IsAllowInBatches='0'

	IF ISNULL(@IsAllowCombineMultiline,'') NOT IN ('0','1')
		SET @IsAllowCombineMultiline='0'

	IF ISNULL(@VendorDeliveryName,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请选择:送货单！'
		RETURN -1
	END

	SELECT 
		@VendorDeliveryId=VendorDeliveryId,
		@VendorDeliveryStates=VendorDeliveryStates,
		@VendorDeliveryType=VendorDeliveryType,
		@VendorId=VendorId,
		@FactoryId=FactoryId
	FROM dbo.VendorDelivery 
	WHERE VendorDeliveryName=@VendorDeliveryName

	IF ISNULL(@VendorDeliveryId,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:送货单【'+@VendorDeliveryName+'】不存在！'
		RETURN -1
	END

	SELECT 
		@StatesName=BillStatesName,
		@StatesDesc=BillStatesDescription
	FROM dbo.BillStates
	INNER JOIN dbo.Bill ON Bill.BillId = BillStates.BillId
	WHERE BillName ='VendorDelivery' AND BillStatesName = @VendorDeliveryStates
	AND IsERP=0

	IF ISNULL(@VendorDeliveryId,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:送货单['+@VendorDeliveryName+']不存在，请输入送货单号！'
		RETURN -1    
	END 

	IF ISNULL(@VendorDeliveryStates,'') NOT IN('30','41','51')
	BEGIN
		SET @I_ReturnMessage='ServerMessage:送货单['+@VendorDeliveryName+']当前状态不是[正在送货 / 部分收货 / 部分入库]，不能收货确认！'
		RETURN -1
	END 
	
	-- 检查送货明细中是否有数据
	IF NOT EXISTS(SELECT 1 FROM dbo.VendorDeliveryItem WHERE VendorDeliveryId = @VendorDeliveryId)
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:送货单['+@VendorDeliveryName+']明细中没有数据,不允许确认到货！'
		RETURN -1 
	END


	--检查是否有收获数
	IF NOT EXISTS(SELECT 1 FROM dbo.VendorDeliveryItem
	INNER JOIN dbo.VendorDeliveryItemLot ON VendorDeliveryItemLot.VendorDeliveryItemId = VendorDeliveryItem.VendorDeliveryItemId
	WHERE VendorDeliveryId=@VendorDeliveryId AND IsReceiveScan=1 AND IsReceiveAck=0 AND DeleteFlag='')
	BEGIN
		SET @I_ReturnMessage='ServerMessage:送货单['+@VendorDeliveryName+']明细批次中，没有待收货确认的批次,请检查'
		RETURN -1
	END 

	--可收货的行，写入临时表
	IF @IsAllowInBatches='0'
	BEGIN
		--这里为什么不用表VendorDeliveryItem的状态，主要是为了方式 突然更换方案
		INSERT INTO @VendorDeliveryItemTemp
			 (
				 VendorDeliveryItemId,
				 ProductId,
				 ProductionLotNO
			 )
		SELECT DISTINCT VendorDeliveryItem.VendorDeliveryItemId,VendorDeliveryItem.ProductId, VendorDeliveryItemlot.ProductionLotNO
		FROM dbo.VendorDeliveryItem 
		INNER JOIN dbo.VendorDeliveryItemLot ON VendorDeliveryItemLot.VendorDeliveryItemId = VendorDeliveryItem.VendorDeliveryItemId
		WHERE VendorDeliveryId=@VendorDeliveryId AND  ItemQtyReceived=ItemQtyDelivery+ItemQtySpare  --一定要加上这个条件
		AND IsReceiveAck=0 AND IsReceiveScan=1 AND DeleteFlag=''
	END
	ELSE IF @IsAllowInBatches='1'
	BEGIN
		INSERT INTO @VendorDeliveryItemTemp
			 (
				 VendorDeliveryItemId,
				 ProductId,
				 ProductionLotNO
			 )
		SELECT DISTINCT VendorDeliveryItem.VendorDeliveryItemId,VendorDeliveryItem.ProductId, VendorDeliveryItemlot.ProductionLotNO
		FROM dbo.VendorDeliveryItem 
		INNER JOIN dbo.VendorDeliveryItemLot ON VendorDeliveryItemLot.VendorDeliveryItemId = VendorDeliveryItem.VendorDeliveryItemId
		WHERE VendorDeliveryId=@VendorDeliveryId
		AND IsReceiveAck=0 AND IsReceiveScan=1 AND DeleteFlag=''
	END 


	--检查是否有可确认收货的行项
	IF NOT EXISTS(SELECT 1 FROM @VendorDeliveryItemTemp)
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:送货单['+@VendorDeliveryName+']没有可【确认收货】的行项！'
		RETURN -1 
	END


	-- 1.1创建：送货到货单
	--申请单据
	EXEC [dbo].[Txn_BillNewSN]
		@BillName = N'DeliveryArrival', --Bill表
		@NewSN = @DeliveryArrivalName OUTPUT,
		@BillStates=@DeliveryArrivalStates OUTPUT --输出的默认状态

	--申请主键
	EXEC dbo.SysGetObjectPKId '','DeliveryArrival',@DeliveryArrivalId OUTPUT
	INSERT INTO dbo.DeliveryArrival
	(
		DeliveryArrivalId,
		DeliveryArrivalName,
		VendorDeliveryId,
		DeliveryArrivalType,
		DeliveryArrivalStates,
		VendorId,
		FactoryId,
		ReceiptDate,
		ConfirmUserId,
		ConfirmDate,
		CreateUserId,
		CreateDate
	)
	VALUES
	(  
		@DeliveryArrivalId,  --char(12)
		@DeliveryArrivalName,  --nvarchar(50)
		@VendorDeliveryId,  --char(12)
		@VendorDeliveryType,  --varchar(20)
		@DeliveryArrivalStates,  --varchar(20)
		@VendorId,  --char(12)
		@FactoryId,  --char(12)
		GETDATE(),  --datetime
		'',  --char(12)
		NULL,  --datetime
		@I_OrBitUserId,  --char(12)
		GETDATE() --datetime
	)



	--游标循环表变量数据
	--如果不允许合并多行送检
	IF @IsAllowCombineMultiline=0
	BEGIN 
		DECLARE cursor_1 CURSOR LOCAL FAST_FORWARD FOR
		SELECT DISTINCT VendorDeliveryItemId,ProductionLotNO FROM @VendorDeliveryItemTemp
		OPEN cursor_1
		FETCH NEXT FROM cursor_1	  
		INTO @VendorDeliveryItemId,@ProductionLotNO
		WHILE @@FETCH_STATUS = 0  
		BEGIN
			SET @ReceiveQty=0

			-- 获取发货单行物料送货数、接收数
			SELECT
				@ProductId=ProductId,
				@DeliveryUOMId=DeliveryUOMId
			FROM dbo.VendorDeliveryItem
			WHERE VendorDeliveryItemId = @VendorDeliveryItemId
			
			--物料编码
			SELECT 
				@ProductName=ProductName
			FROM dbo.Product 
			INNER JOIN dbo.ProductRoot ON Product.ProductRootId=ProductRoot.ProductRootId
			WHERE ProductId=@ProductId

			--获取送检数
			SELECT @ReceiveQty=SUM(Qty)
			FROM dbo.VendorDeliveryItemLot
			WHERE VendorDeliveryItemId=@VendorDeliveryItemId
			AND IsReceiveScan=1 AND IsReceiveAck=0 AND DeleteFlag=''
			and ProductionLotNO=@ProductionLotNO

			--执行规则转移
			EXEC dbo.IQCCheckRuleShiftDoMethod
				@VendorId = @VendorId, -- char(12)
				@ProductId = @ProductId -- char(12)
			

			--获取检验类别
			SELECT @IQCType_Product=IQCType,
				   @IQCInspectionType_Product=InspectionType
			FROM dbo.Vendor_Product WHERE ProductId=@ProductId
			AND VendorId=@VendorId

			--默认抽检
			IF ISNULL(@IQCType_Product,'') NOT IN('0','1','2')
			   SET @IQCType_Product='1'
			--默认正常抽检
			IF ISNULL(@IQCInspectionType_Product,'') NOT IN('1','2','3')
			   SET @IQCInspectionType_Product='1'


			-- 2.1创建：来料检验单
			EXEC dbo.Txn_BillNewSN
				@BillName = N'IQCCheck',
				@NewSN = @IQCCheckName OUTPUT
			
			--写入IQC检验数据			 
			EXEC dbo.SysGetObjectPKId '','IQCCheck',@IQCCheckId OUTPUT
			INSERT INTO dbo.IQCCheck(
					IQCCheckId,
					IQCCheckName,
					VendorDeliveryId,
					DeliveryArrivalId,
					ProductId,
					SendQty,
					SendDate,
					CreateUserId,
					CreateDate,
					SendTimes,
					UOMId,
					IQCType,
					InspectionType,
					FactoryId)
				VALUES(
					@IQCCheckId,
					@IQCCheckName,
					@VendorDeliveryId,
					@DeliveryArrivalId,
					@ProductId,
					@ReceiveQty,
					GETDATE(),
					@I_OrBitUserId,
					GETDATE(),
					1,
					@DeliveryUOMId,
					@IQCType_Product,
					@IQCInspectionType_Product,
					@FactoryId
					)

			--记录所有的IQC单据，为了创建送货到货明细
			INSERT INTO @Temp_IQCBill
				 (
					 IQCCheckId
				 )
			VALUES
				 (
					 @IQCCheckId -- IQCCheckId - char(12)
				 )

			-- 设置写入协同数据链名称
			SET @ObjectName = @IQCCheckName+'.'+'待检'+'.'+CONVERT(NVARCHAR(20),GETDATE(),20)

			--启动协同工作流数据链
			EXEC @return_value =dbo.Txn_SynchroFlowStart
				@I_ReturnMessage = @I_ReturnMessage OUTPUT,
				@I_PKid = @IQCCheckId ,
				@ObjectName = @ObjectName ,
				@WorkflowStepId = @WorkflowStepId OUTPUT ,
				@I_ResourceName = @I_ResourceName ,
				@I_OrBitUserId = @I_OrBitUserId
		
			--不管启动工作流的是否成功，都要继续往下执行	
			--IF @return_value = -1
			--BEGIN
			--	set @I_ReturnMessage = @I_ReturnMessage
			--	RETURN -1
			--END

			-- 更新 IQCCheck 表中工作流节点Id
			IF ISNULL(@return_value,0)<>-1 
			BEGIN
				UPDATE dbo.IQCCheck SET 
					WorkflowStepId = @WorkflowStepId ,
					WorkflowStatus = '1' 
				WHERE IQCCheckId = @IQCCheckId
			END

			SET @Remark='送货单['+@VendorDeliveryName+']物料['+@ProductName+']收货确认['+CAST(@ReceiveQty AS VARCHAR(50))+'],产生IQC送检单['+@IQCCheckName+']'

			--插入IQC送检批次表
			--游标写入数据
			DECLARE cursorItemLot CURSOR LOCAL FAST_FORWARD FOR  
			SELECT  VendorDeliveryItemLotId,LotSN,Qty 
			FROM dbo.VendorDeliveryItemLot
			WHERE VendorDeliveryItemId=@VendorDeliveryItemId AND IsReceiveScan=1 AND IsReceiveAck=0 AND DeleteFlag='' and ProductionLotNO=@ProductionLotNO
			OPEN cursorItemLot
			FETCH NEXT FROM cursorItemLot 
			INTO @VendorDeliveryItemLotId,@LotSN,@LotQty
			WHILE @@FETCH_STATUS = 0 
			BEGIN		
				--申请主键
				EXEC dbo.SysGetObjectPKId '','IQCCheckLot',@IQCCheckLotId OUTPUT
				INSERT INTO dbo.IQCCheckLot
					 (
						 IQCCheckLotId,
						 IQCCheckId,
						 LotSN,
						 Qty,
						 VendorDeliveryItemId,
						 CreateDate
					 )
				VALUES
					 (
						 @IQCCheckLotId, -- IQCCheckLotId - char(12)
						 @IQCCheckId, -- IQCCheckId - char(12)
						 @LotSN, -- LotSN - nvarchar(50)
						 @LotQty, -- Qty - decimal(18, 6)
						 @VendorDeliveryItemId,
						 GETDATE() -- CreateDate - datetime
					 )
				
				
				--插入物料批号追踪表
				EXEC dbo.TxnBase_MLotTrack
					@I_OrBitUserId =@I_OrBitUserId, -- char(12)
					@I_PlugInCommand=@I_PlugInCommand,
					@I_ResourceId =@I_ResourceId, -- char(12)
					@LotSN = @LotSN, -- nvarchar(50) --物料批号
					@LotQty = @LotQty, -- decimal(18, 6)--数量
					@TxnCode = 'M-收货确认', -- nvarchar(50) --事务码
					@OrderName =@VendorDeliveryName , -- nvarchar(50) --单据号
					@Remark = @Remark -- nvarchar(200) --备注

				--更新已送检
				UPDATE dbo.VendorDeliveryItemLot SET 
					   IsReceiveAck=1,
					   ReceiveAckDate=GETDATE(),
					   IQCCheckId=@IQCCheckId,
					   DeliveryBatch=@IQCCheckName --送货批就保存收货的时的IQC单
				WHERE VendorDeliveryItemLotId=@VendorDeliveryItemLotId

				FETCH NEXT FROM cursorItemLot 
				INTO @VendorDeliveryItemLotId,@LotSN,@LotQty
			END
			CLOSE cursorItemLot
			DEALLOCATE cursorItemLot 

			--更新送货单行状态
			IF EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot
			WHERE VendorDeliveryItemId=@VendorDeliveryItemId AND DeleteFlag='' AND IsReceiveAck=0)
			BEGIN
				UPDATE dbo.VendorDeliveryItem SET
					ItemStates='21'
				WHERE VendorDeliveryItemId=@VendorDeliveryItemId
			END 
			ELSE
			BEGIN
				UPDATE dbo.VendorDeliveryItem SET
					ItemStates='20'
				WHERE VendorDeliveryItemId=@VendorDeliveryItemId
			END 

			FETCH NEXT FROM cursor_1 
			INTO @VendorDeliveryItemId,@ProductionLotNO
		END
		CLOSE cursor_1
		DEALLOCATE cursor_1 
	END 
	ELSE--否则表示允许多行合并送检
	BEGIN
		--游标2循环处理：合并创建IQC检验单单
		DECLARE cursor_2 CURSOR LOCAL FAST_FORWARD FOR
		SELECT DISTINCT ProductId,ProductionLotNO FROM @VendorDeliveryItemTemp
		OPEN cursor_2
		FETCH NEXT FROM cursor_2	  
		INTO @ProductId,@ProductionLotNO
		WHILE @@FETCH_STATUS = 0  
		BEGIN
			SET @ReceiveQty=0
			
			--物料编码
			SELECT 
				@ProductName=ProductName
			FROM dbo.Product 
			INNER JOIN dbo.ProductRoot ON Product.ProductRootId=ProductRoot.ProductRootId
			WHERE ProductId=@ProductId

			--获取送检数
			SELECT @ReceiveQty=SUM(Qty)
			FROM dbo.VendorDeliveryItem
			INNER JOIN dbo.VendorDeliveryItemLot ON VendorDeliveryItemLot.VendorDeliveryItemId = VendorDeliveryItem.VendorDeliveryItemId
			WHERE VendorDeliveryId=@VendorDeliveryId AND VendorDeliveryItem.ProductId=@ProductId and ProductionLotNO=@ProductionLotNO
			AND IsReceiveScan=1 AND IsReceiveAck=0 AND DeleteFlag=''

			--获取单位
			SELECT TOP 1 @DeliveryUOMId=DeliveryUOMId
			FROM  dbo.VendorDeliveryItem
			WHERE VendorDeliveryId=@VendorDeliveryId AND ProductId=@ProductId

			--执行规则转移
			EXEC dbo.IQCCheckRuleShiftDoMethod
				@VendorId = @VendorId, -- char(12)
				@ProductId = @ProductId -- char(12)

			--获取检验类别
			SELECT @IQCType_Product=IQCType,
				   @IQCInspectionType_Product=InspectionType
			FROM dbo.Vendor_Product WHERE ProductId=@ProductId
			AND VendorId=@VendorId

			--默认抽检
			IF ISNULL(@IQCType_Product,'') NOT IN('0','1','2')
			   SET @IQCType_Product='1'
			--默认正常
			IF ISNULL(@IQCInspectionType_Product,'') NOT IN('1','2','3')
				SET @IQCInspectionType_Product='1'


			--来料检验批次产生
			EXEC dbo.Txn_BillNewSN
				@BillName = N'IQCCheck',
				@NewSN = @IQCCheckName OUTPUT
			
			--写入IQC检验数据			 
			EXEC dbo.SysGetObjectPKId '','IQCCheck',@IQCCheckId OUTPUT
			INSERT INTO dbo.IQCCheck(
					IQCCheckId,
					IQCCheckName,
					VendorDeliveryId,
					DeliveryArrivalId,
					ProductId,
					SendQty,
					SendDate,
					CreateUserId,
					CreateDate,
					SendTimes,
					UOMId,
					IQCType,
					InspectionType,
					FactoryId)
				VALUES(
					@IQCCheckId,
					@IQCCheckName,
					@VendorDeliveryId,
					@DeliveryArrivalId,
					@ProductId,
					@ReceiveQty,
					GETDATE(),
					@I_OrBitUserId,
					GETDATE(),
					1,
					@DeliveryUOMId,
					@IQCType_Product,
					@IQCInspectionType_Product,
					@FactoryId
					)

			--记录所有的IQC单据，为了创建送货到货明细
			INSERT INTO @Temp_IQCBill
				 (
					 IQCCheckId
				 )
			VALUES
				 (
					 @IQCCheckId -- IQCCheckId - char(12)
				 )

			-- 设置写入协同数据链名称
			SET @ObjectName = @IQCCheckName+'.'+'待检'+'.'+CONVERT(NVARCHAR(20),GETDATE(),20)

			--启动协同工作流数据链
			EXEC @return_value =dbo.Txn_SynchroFlowStart
				@I_ReturnMessage = @I_ReturnMessage OUTPUT,
				@I_PKid = @IQCCheckId ,
				@ObjectName = @ObjectName ,
				@WorkflowStepId = @WorkflowStepId OUTPUT ,
				@I_ResourceName = @I_ResourceName ,
				@I_OrBitUserId = @I_OrBitUserId
		
			--不管启动工作流的是否成功，都要继续往下执行	
			--IF @return_value = -1
			--BEGIN
			--	set @I_ReturnMessage = @I_ReturnMessage
			--	RETURN -1
			--END

			-- 更新 IQCCheck 表中工作流节点Id
			IF ISNULL(@return_value,0)<>-1 
			BEGIN
				UPDATE dbo.IQCCheck SET 
					WorkflowStepId = @WorkflowStepId ,
					WorkflowStatus = '1' 
				WHERE IQCCheckId = @IQCCheckId
			END

			SET @Remark='送货单['+@VendorDeliveryName+']物料['+@ProductName+']收货确认['+CAST(@ReceiveQty AS VARCHAR(50))+'],产生IQC送检单['+@IQCCheckName+']'

			--插入IQC送检批次表
			--游标写入数据
			DECLARE cursorItemLot CURSOR LOCAL FAST_FORWARD FOR  
			SELECT  VendorDeliveryItem.VendorDeliveryItemId,VendorDeliveryItemLotId,LotSN,Qty 
			FROM dbo.VendorDeliveryItem
			INNER JOIN dbo.VendorDeliveryItemLot ON VendorDeliveryItemLot.VendorDeliveryItemId = VendorDeliveryItem.VendorDeliveryItemId
			WHERE VendorDeliveryId=@VendorDeliveryId AND VendorDeliveryItem.ProductId=@ProductId
			AND IsReceiveScan=1 AND IsReceiveAck=0 AND DeleteFlag='' and ProductionLotNO=@ProductionLotNO
			OPEN cursorItemLot
			FETCH NEXT FROM cursorItemLot 
			INTO @VendorDeliveryItemId,@VendorDeliveryItemLotId,@LotSN,@LotQty
			WHILE @@FETCH_STATUS = 0 
			BEGIN		
				--申请主键
				EXEC dbo.SysGetObjectPKId '','IQCCheckLot',@IQCCheckLotId OUTPUT
				INSERT INTO dbo.IQCCheckLot
					 (
						 IQCCheckLotId,
						 IQCCheckId,
						 LotSN,
						 Qty,
						 VendorDeliveryItemId,
						 CreateDate
					 )
				VALUES
					 (
						 @IQCCheckLotId, -- IQCCheckLotId - char(12)
						 @IQCCheckId, -- IQCCheckId - char(12)
						 @LotSN, -- LotSN - nvarchar(50)
						 @LotQty, -- Qty - decimal(18, 6)
						 @VendorDeliveryItemId,
						 GETDATE() -- CreateDate - datetime
					 )

				--插入物料批号追踪表
				EXEC dbo.TxnBase_MLotTrack
					@I_OrBitUserId =@I_OrBitUserId, -- char(12)
					@I_PlugInCommand=@I_PlugInCommand,
					@I_ResourceId =@I_ResourceId, -- char(12)
					@LotSN = @LotSN, -- nvarchar(50) --物料批号
					@LotQty = @LotQty, -- decimal(18, 6)--数量
					@TxnCode = 'M-收货确认', -- nvarchar(50) --事务码
					@OrderName =@VendorDeliveryName , -- nvarchar(50) --单据号
					@Remark = @Remark -- nvarchar(200) --备注

				--更新已送检
				UPDATE dbo.VendorDeliveryItemLot SET 
					   IsReceiveAck=1,
					   ReceiveAckDate=GETDATE(),
					   IQCCheckId=@IQCCheckId,
					   DeliveryBatch=@IQCCheckName --送货批就保存收货的时的IQC单
				WHERE VendorDeliveryItemLotId=@VendorDeliveryItemLotId

				FETCH NEXT FROM cursorItemLot 
				INTO @VendorDeliveryItemId,@VendorDeliveryItemLotId,@LotSN,@LotQty
			END
			CLOSE cursorItemLot
			DEALLOCATE cursorItemLot 

			FETCH NEXT FROM cursor_2	  
			INTO @ProductId,@ProductionLotNO
		END
		CLOSE cursor_2
		DEALLOCATE cursor_2  

		--游标3循环处理：更新单据行状态
		DECLARE cursor_3 CURSOR LOCAL FAST_FORWARD FOR
		SELECT DISTINCT VendorDeliveryItemId FROM @VendorDeliveryItemTemp
		OPEN cursor_3
		FETCH NEXT FROM cursor_3
		INTO @VendorDeliveryItemId
		WHILE @@FETCH_STATUS = 0  
		BEGIN
			--更新送货单行状态
			IF EXISTS(SELECT 1 FROM dbo.VendorDeliveryItemLot
			WHERE VendorDeliveryItemId=@VendorDeliveryItemId AND DeleteFlag='' AND IsReceiveAck=0) 
			BEGIN
				UPDATE dbo.VendorDeliveryItem SET
					ItemStates='21'
				WHERE VendorDeliveryItemId=@VendorDeliveryItemId
			END 
			ELSE
			BEGIN
				UPDATE dbo.VendorDeliveryItem SET
					ItemStates='20'
				WHERE VendorDeliveryItemId=@VendorDeliveryItemId
			END 

			FETCH NEXT FROM cursor_3
			INTO @VendorDeliveryItemId
		END
		CLOSE cursor_3
		DEALLOCATE cursor_3		 
	END 


	-- 1.2
	--游标4循环处理：创建送货到货明细
	DECLARE cursor_4 CURSOR LOCAL FAST_FORWARD FOR  
	SELECT DISTINCT VendorDeliveryItem.VendorDeliveryItemId,
			POId,
			POItemId,
			VendorDeliveryItem.ProductId,
			DeliveryUOMId,
			VendorDeliveryItemLot.IQCCheckId
	FROM @Temp_IQCBill a
	INNER JOIN dbo.VendorDeliveryItemLot ON VendorDeliveryItemLot.IQCCheckId = a.IQCCheckId
	INNER JOIN dbo.VendorDeliveryItem ON VendorDeliveryItem.VendorDeliveryItemId = VendorDeliveryItemLot.VendorDeliveryItemId
	WHERE VendorDeliveryId=@VendorDeliveryId AND VendorDeliveryItemLot.DeleteFlag=''
	OPEN cursor_4
	FETCH NEXT FROM cursor_4 
	INTO @VendorDeliveryItemId,@POId,@POItemId,@ProductId,@DeliveryUOMId,@IQCCheckId
	WHILE @@FETCH_STATUS = 0 
	BEGIN	
		SET @ReceiptQty=0
		SET @SpareReceiptQty=0

		--收货数量
		DELETE @TempRecQty
		DELETE @TempSpareReceiptQty
		INSERT @TempRecQty
		(
		    WorkcenterId,
		    ReceiptQty
		)	
		SELECT  WorkcenterId,SUM(Qty)
		FROM dbo.VendorDeliveryItemLot
		WHERE VendorDeliveryItemId=@VendorDeliveryItemId
		AND IQCCheckId=@IQCCheckId AND DeleteFlag=''
		AND IsSpareLot=0
		GROUP BY WorkcenterId

		INSERT @TempSpareReceiptQty
		(
		    WorkcenterId,
		    SpareReceiptQty
		)
		SELECT WorkcenterId,SUM(Qty)
		FROM dbo.VendorDeliveryItemLot
		WHERE VendorDeliveryItemId=@VendorDeliveryItemId
		AND IQCCheckId=@IQCCheckId AND DeleteFlag=''
		AND IsSpareLot=1
		GROUP BY WorkcenterId

		DECLARE @TempRecQtyCnt INT 
		DECLARE @MaxCount INT 
		SELECT @TempRecQtyCnt=MIN(Id),@MaxCount=MAX(Id) FROM @TempRecQty
		WHILE @TempRecQtyCnt<=@MaxCount AND 0 < @MaxCount
		BEGIN

			SELECT @ReceiptQty=ReceiptQty,@WorkcenterId=WorkcenterId
			FROM @TempRecQty
			WHERE Id=@TempRecQtyCnt

			--备品收货数量
			SELECT @SpareReceiptQty=SpareReceiptQty
			FROM @TempSpareReceiptQty WHERE WorkcenterId=@WorkcenterId

			--产生送货到货单行号
			IF EXISTS(SELECT 1 FROM dbo.DeliveryArrivalItem WHERE DeliveryArrivalId=@DeliveryArrivalId)	
			BEGIN
				SELECT @VendorDeliveryItemNO=RIGHT('0000'+CAST(MAX(CAST(ItemSequence AS INT))+1 AS VARCHAR),4)
				FROM dbo.DeliveryArrivalItem
				WHERE DeliveryArrivalId=@DeliveryArrivalId
			END
			ELSE
			BEGIN
				SET @VendorDeliveryItemNO='0001'
			END

			--申请主键
			EXEC dbo.SysGetObjectPKId '','DeliveryArrivalItem',@DeliveryArrivalItemId OUTPUT
			INSERT INTO dbo.DeliveryArrivalItem
					(
						DeliveryArrivalItemId,
						DeliveryArrivalId,
						VendorDeliveryItemId,
						ItemSequence,
						POId,
						POItemId,
						ProductId,
						ReceiptQty, --收货数（不含备品）
						SpareReceiptQty, --备品收货数
						WorkcenterId,
						UOMId,
						CreateDate
					)
			VALUES
					(
						@DeliveryArrivalItemId, -- DeliveryArrivalItemId - char(12)
						@DeliveryArrivalId, -- DeliveryArrivalId - char(12)
						@VendorDeliveryItemId, -- VendorDeliveryItemId - char(12)
						@VendorDeliveryItemNO, -- ItemSequence - varchar(20)
						@POId, -- POId - char(12)
						@POItemId, -- POItemId - char(12)
						@ProductId, -- ProductId - char(12)
						ISNULL(@ReceiptQty,0), -- ReceiptQty - decimal(18, 6)
						ISNULL(@SpareReceiptQty,0), -- SpareReceiptQty - decimal(18, 6)
						@WorkcenterId,
						@DeliveryUOMId, -- UOMId - char(12)
						GETDATE() -- CreateDate - datetime
					)

			 SET @TempRecQtyCnt=@TempRecQtyCnt+1
		END


		
		FETCH NEXT FROM cursor_4 
		INTO  @VendorDeliveryItemId,@POId,@POItemId,@ProductId,@DeliveryUOMId,@IQCCheckId
	END
	CLOSE cursor_4
	DEALLOCATE cursor_4 

	--送货到货单确认过账
	IF ISNULL(@DeliveryArrivalId,'')<>''
	BEGIN 
	EXEC dbo.DeliveryArrivalConfirmDoMethod @I_Sender = N'',                                      -- nvarchar(200)
	                                        @I_ReturnMessage = @I_ReturnMessage OUTPUT,           -- nvarchar(max)	                                
	                                     --   @I_LanguageId =@I_LanguageId,                                   -- char(1)
	                                        @I_PlugInCommand = @I_PlugInCommand,                                -- varchar(5)
	                                        @I_OrBitUserId =@I_OrBitUserId,                                  -- char(12)
	                                        @I_OrBitUserName = @I_OrBitUserName,                               -- nvarchar(100)
	                                        @I_ResourceId = @I_ResourceId,                                   -- char(12)
	                                        @I_ResourceName =@I_ResourceName,                                -- nvarchar(100)
	                                        @I_PKid = @DeliveryArrivalId,                                         -- char(12)
	                                        @I_ParentPKId = '',                                   -- char(12)
	                                        @I_Parameter = N''                                    -- nvarchar(100)
	
	 END 

	--更新送货单行状态，送检状态 40/41；送货单状态显示最大的
	IF NOT EXISTS(SELECT 1 FROM dbo.VendorDeliveryItem WHERE VendorDeliveryId=@VendorDeliveryId AND ItemStates IN('10','21'))
	BEGIN
		--收货完成
		IF ISNULL(@VendorDeliveryStates,'') NOT IN('50','51')
		BEGIN
			UPDATE dbo.VendorDelivery SET 
				VendorDeliveryStates ='40'
			WHERE VendorDeliveryId = @VendorDeliveryId
		END 
	END
	ELSE
	BEGIN
		--部分收货
		IF ISNULL(@VendorDeliveryStates,'') NOT IN('50','51')
		BEGIN
			UPDATE dbo.VendorDelivery SET 
				VendorDeliveryStates ='41'
			WHERE VendorDeliveryId = @VendorDeliveryId
		END 
	END		

	--更新实际送达日期
	UPDATE dbo.VendorDelivery SET
		ArrivalTrueDate=GETDATE()
	WHERE VendorDeliveryId=@VendorDeliveryId

	--获得接口的信息
--   SELECT  @InterfaceItemId=InterfaceItemId FROM dbo.InterfaceItem WHERE ItemName='U_FinishingEntry'
-- 
--   exec SysGetObjectPKId '','UploadIng',@UploadIngId OUTPUT
--   INSERT INTO dbo.UploadIng
--   (
--    UploadIngId,
--    UploadInterfaceId,
--    UploadDateId,
--    ISUpload,
--    UserId,
--    BillsMark,
--    MatDoc,
--    CreateDate
--   )
--   VALUES
--   (  @UploadIngId,       -- UploadIngId - char(12)
--    @InterfaceItemId,       -- UploadInterfaceId - char(12)
--    @I_PKid,       -- UploadDateId - char(12)
--    'true',     -- ISUpload - bit
--    @I_OrBitUserId,       -- UserId - char(12)
--    @FinishingEntryName,      -- BillsMark - nvarchar(50)
--    N'',      -- MatDoc - nvarchar(50)
--    GETDATE() -- CreateDate - datetime
--      )
--**************begin邮件发送功能begin*********************************	
	--DECLARE @SubjectName NVARCHAR(100)=''
	--DECLARE @ContentText NVARCHAR(MAX)=''
	--DECLARE @MailReceiveGroup NVARCHAR(50)=''
	--SET @SubjectName = '【IQC检验通知】！'
	--SET @ContentText=N'<H1 style="color:red;text-align:center;font-size:20px;letter-spacing:8px">来料送货单号【'+@VendorDeliveryName+'】</H1>'--标题
	--			+N'<table border="1" cellpadding="10" cellspacing="0" align="center" margin-left="3px" width="100%" height="13%"> '--表宽
	--			+N'<tr style=border:#000000 solid 1px; >
	--					<th style="width:60px" >序号</th>
	--					<th style="width:200px" >检验单号</th>
	--					<th style="width:200px">物料</th>
	--					<th style="width:200px">送检数</th>
	--					<th style="width:200px">急料类别</th>
						
	--			</tr>'
	--			+CAST((SELECT 
	--				'font-size:15px;border:#000000 solid 1px;text-align:center;' as "td/@style",
	--				td=ROW_NUMBER() over(order by ProductName) ,'',
	--				'font-size:15px;border:#000000 solid 1px;text-align:center;' as "td/@style",	 
	--				td=IQCCheckNO ,'',
	--				'font-size:15px;border:#000000 solid 1px;text-align:center;' as "td/@style",
	--				td=ProductName ,'',
	--				'font-size:15px;border:#000000 solid 1px;text-align:center;' as "td/@style",
	--				td=CAST(SendQty AS char(10)) ,'',
	--				'font-size:15px;border:#000000 solid 1px;text-align:center;' as "td/@style",
	--				td=RadMaterType 
	--		FROM @VendorContent 
	--	ORDER by IQCCheckNO
	--	FOR XML PATH('tr'),TYPE)	
		
	--	  AS nvarchar(max))+N'</table>'
	--	  +N'<p style="font-size:15px">部门:...</p>'
	--	  +N'<p style="font-size:15px">公司名：...</p>'
	--	  +N'<p style="font-size:15px">公司地址：...</p>'
	--	  +N'<p style="font-size:15px">感谢您使用深圳华磊迅拓科技 OrBit 系统！</p>'
	--	  +N'<p style="font-size:15px">我司公司网站：<a href="http://www.OrBitmes.com">http://www.orbitmes.com  </a></p>'
	--	  +N'<p style="font-size:15px">本邮件由系统自动发出，请勿回复</p>'

	---- 发送邮件
	--EXEC [dbo].[SendMailDoMethod]
	--	@MailReceiveGroup  = @MailReceiveGroup,	 --接收组
	--	@SubjectName = @SubjectName, --主题
	--	@ContentText = @ContentText	 --邮件正文
	--  @ContentText_format ='HTML' --。格式有TEXT、HTML
--**************end邮件发送功能end*********************************	


	SET @I_ReturnMessage='ServerMessage:送货单['+@VendorDeliveryName+']已点收物料已确认完成！ '+@Enter +ISNULL(@I_ReturnMessage,'');

	RETURN 0	

END
GO
