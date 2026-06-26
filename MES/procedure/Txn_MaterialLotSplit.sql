SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OrBit Ben>
-- Create date: <2017.08.09>
-- Description:	<物料拆分:可用于库存批号拆分，产线物料拆分>
-- =============================================
CREATE PROCEDURE  [dbo].[Txn_MaterialLotSplit]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
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

@SplitLotSN NVARCHAR(100)='',		--被拆批号
@SplitQty DECIMAL(18,6)=0           --拆出数量


AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @return_value INT
	DECLARE @ProductId CHAR(12)
	DECLARE @ProductName NVARCHAR(50)=''
	DECLARE @ProductDescription NVARCHAR(100)=''
	DECLARE @WWId CHAR(12)=''
	DECLARE @WWQty DECIMAL(18,4)=0

	DECLARE @NewSN NVARCHAR(100)=''
	DECLARE @NewWWId CHAR(12)=''
	DECLARE @SNRuleName_LotSN NVARCHAR(50)='WW_MP_LotSN'
	DECLARE @SNRuleId CHAR(12)=''



	--通用变量
	DECLARE @Temp_Qty FLOAT=0
	DECLARE @Remark NVARCHAR(200)='' --备注

	--记录当前PKID
	DECLARE @LotTemp TABLE(
		WWId CHAR(12)
	)

	SET @SplitLotSN=UPPER(RTRIM(LTRIM(@SplitLotSN)))

	--检查材料批次规则
	IF NOT EXISTS(SELECT 1 FROM dbo.SNRule WHERE SNRuleName=@SNRuleName_LotSN AND IsActivity=1)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:未维护或没有激活 材料批次拆分 序列号规则【MP_LotSN】，请检查！请联系IT人员处理'
		SELECT '' AS SplitLotSN
		RETURN -1
	END

	SELECT @SNRuleId=SNRuleId FROM dbo.SNRule WHERE SNRuleName=@SNRuleName_LotSN AND IsActivity=1
	

	
	IF ISNULL(@SplitLotSN,'') =''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请扫描拆分批次!'
		SELECT '' AS SplitLotSN
		SET @I_ExceptionFieldName = 'SplitLotSN'
		RETURN -1
	END
	
	--检查物料批号是否存在
	IF NOT EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@SplitLotSN)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:原批号【'+@SplitLotSN+'】不存在!'
		SELECT '' AS SplitLotSN
		SET @I_ExceptionFieldName = 'SplitLotSN'
		RETURN -1
	END
	
	IF NOT EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@SplitLotSN AND LotStatus='1')
	BEGIN
		SET @I_ReturnMessage='ServerMessage:原批号【'+@SplitLotSN+'】状态不可用!'
		SELECT '' AS SplitLotSN
		SET @I_ExceptionFieldName = 'SplitLotSN'
		RETURN -1
	END

	--获取物料批号库存信息
	SELECT 
		@WWId=WW.WWId,
		@WWQty=WW.Qty,
		@ProductId =WW.ProductId
	FROM dbo.WW_RMInventory WW
	WHERE WW.LotSN=@SplitLotSN

	SELECT 
		@ProductName=ProductName,
		@ProductDescription=ProductDescription
	FROM dbo.Product
	INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
	WHERE ProductId=@ProductId
	
	--原批号是否存在
	IF ISNULL(@WWId,'') =''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:物料库存中未找到原批号【'+@SplitLotSN+'】,请检查!'
		SELECT '' AS SplitLotSN
		SET @I_ExceptionFieldName = 'SplitLotSN'
		RETURN -1	
	END
			
	--显示批次信息
	IF ISNULL(@I_Sender,'')='LotShow'
	BEGIN
		SELECT @ProductName AS ProductName,@ProductDescription AS ProductDescription,0 AS SplitQty,@WWQty AS LotQty

		SET @I_ReturnMessage='ServerMessage:物料批次【'+@SplitLotSN+'】有效!'
		SET @I_ExceptionFieldName='SplitQty'
		RETURN 0
	END

	IF ISNULL(@SplitQty,0) <= 0
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:请输入拆分数量,且数量必须大于零!' 
		SELECT '' AS SplitQty
		SET @I_ExceptionFieldName = 'SplitQty'
		RETURN -1
	END

	--检查数量
	IF (ISNULL(@WWQty,0) <= 0)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:原批号【'+@SplitLotSN+'】数量已为零，不能对其拆分!'
		SET @I_ExceptionFieldName = 'SplitLotSN'
		RETURN -1	
	END

	--比较数量
	IF (ISNULL(@WWQty,0) < ISNULL(@SplitQty,0))
	BEGIN
		SET @I_ReturnMessage='ServerMessage:源批号【'+@SplitLotSN+'】数量不足【' + CAST(@SplitQty AS VARCHAR)+ '】,不能对其拆分!'
		SET @I_ExceptionFieldName = 'SplitLotSN'
		RETURN -1	
	END

	--生成物料批号
	EXEC @return_value = [dbo].[StartRuleSNDoMethod]
		@I_ReturnMessage = @I_ReturnMessage OUTPUT,
		@SNRuleId = @SNRuleId,
		@RCharStr = N'',
		@JumpQty=1,
		@NewSN = @NewSN OUTPUT

	IF @return_value=-1
	BEGIN
		SET @I_ReturnMessage=@I_ReturnMessage
		RETURN -1
	END

	-- 检查是否有重复
	IF EXISTS(SELECT 1 FROM dbo.Lot WHERE LotSN = @NewSN)
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:拆分生成批号失败！条码【'+@NewSN+'】已存在'
		RETURN -1
	END
	
	IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN = @NewSN)
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:拆分生成批号失败！条码【'+@NewSN+'】已存在'
		RETURN -1
	END
	
	--更新库存表中原批号的数量（源批号数量）
	UPDATE dbo.WW_RMInventory SET 
		Qty=Qty-@SplitQty,
		BoxSN='',
		IsSM=1 --拆分批次，属于散料
	WHERE WWId=@WWId

	
	--如果条码存Lot表，则更新数量
	IF EXISTS(SELECT 1 FROM dbo.Lot WHERE LotSN=@SplitLotSN)
	BEGIN
		UPDATE dbo.Lot SET 
			Qty=ISNULL(@WWQty-@SplitQty,0)
		WHERE LotSN=@SplitLotSN  
	END


	--由于当做物料，可以不插入Lot表
	--在库存表节点中增加刚刚拆出来的新物料标签。
	EXEC dbo.SysGetObjectPKId '','WW',@NewWWId OUTPUT
	INSERT INTO dbo.WW_RMInventory (
			WWId,
			LotSN,
			Qty,
			LotStatus,
			QCStatus,
			IsolateStatus,
			OrgQty,
			OrgLotSN,
			ProductId,
			POId,
			VendorId,
			UOMId,
			FactoryId,
			WorkcenterId,
			CellId,
			ProductionDate,
			ProductionLotNO,
			ReceiveDate,
			EntryDate,
			ValidityEndDate,
			IsStorage,
			IsInternalLot,
			LotSType,
			IsSM --拆分批次，属于散料
			)
	SELECT @NewWWId,@NewSN,@SplitQty,LotStatus,QCStatus,IsolateStatus,@SplitQty,LotSN,ProductId,POId,VendorId,UOMId,FactoryId,WorkcenterId,
		CellId,ProductionDate,ProductionLotNO,ReceiveDate,EntryDate,ValidityEndDate,IsStorage,IsInternalLot,
		'5',1
	FROM dbo.WW_RMInventory 
	WHERE LotSN=@SplitLotSN


	--插入物料批号追踪表：
	SET @Temp_Qty=@WWQty-@SplitQty
	SET @Remark='物料条码['+@SplitLotSN+'],原始数量['+CAST(CAST(@WWQty AS FLOAT) AS VARCHAR)+']，拆分出['+CAST(CAST(@SplitQty AS FLOAT) AS VARCHAR)+']到新条码['+@NewSN+'],剩余['+CAST(@Temp_Qty AS VARCHAR)+']'
	EXEC dbo.TxnBase_MLotTrack
		@I_OrBitUserId =@I_OrBitUserId, -- char(12)
		@I_PlugInCommand=@I_PlugInCommand,
		@I_ResourceId =@I_ResourceId, -- char(12)
		@LotSN = @SplitLotSN, -- nvarchar(50) --物料批号
		@LotQty = @Temp_Qty, -- decimal(18, 6)--数量
		@TxnCode = 'M-物料批次拆分', -- nvarchar(50) --事务码
		@OrderName =N'' , -- nvarchar(50) --单据号
		@Remark = @Remark -- nvarchar(200) --备注

	--插入物料批号追踪表：
	SET @Remark='物料条码['+@NewSN+'],数量['+CAST(CAST(@SplitQty AS FLOAT) AS VARCHAR)+'],由条码['+@SplitLotSN+']拆分得到！'
	EXEC dbo.TxnBase_MLotTrack
		@I_OrBitUserId =@I_OrBitUserId, -- char(12)
		@I_PlugInCommand=@I_PlugInCommand,
		@I_ResourceId =@I_ResourceId, -- char(12)
		@LotSN = @NewSN, -- nvarchar(50) --物料批号
		@LotQty = @SplitQty, -- decimal(18, 6)--数量
		@TxnCode = 'M-物料批次拆分', -- nvarchar(50) --事务码
		@OrderName =N'' , -- nvarchar(50) --单据号
		@Remark = @Remark -- nvarchar(200) --备注

    
	--写入新批号
	INSERT @LotTemp(WWId) VALUES(@NewWWId),(@WWId)
	--2025.07.11 暂时注释，测试太卡
	-- 打印标签
-- 	IF EXISTS(SELECT 1 FROM @LotTemp)
-- 	BEGIN 
-- 		--打印信息
-- 		SELECT  		
-- 			'2' AS IsPrintSNOrBox,
-- 			WW.LotSN AS MLotSN,
-- 			VendorShortName AS VendorName,
-- 			POName,
-- 			ProductName AS MaterialName,
-- 			WW.BoxSN AS BoxSN,
-- 			ProductName+' '+ProductDescription AS MaterialDescription,
-- 			CAST(WW.Qty AS FLOAT) AS LotQty,
-- 			UOMName AS UOM,
-- 			WW.ProductionDate AS DateCode,
-- 			WW.ProductionLotNO AS LotNO,
-- 			CONVERT(NVARCHAR(10),WW.CreateDate,102) AS PrintDate ,
-- 			(SELECT CONVERT(FLOAT,SUM(Qty)) FROM dbo.WW_RMInventory WHERE BoxSN=WW.BoxSN) AS BoxQty,
-- 			(SELECT TOP 1 LotSN FROM dbo.WW_RMInventory WHERE BoxSN=WW.BoxSN ORDER BY LotSN) AS SNBegin,
-- 			(SELECT TOP 1 LotSN FROM dbo.WW_RMInventory WHERE BoxSN=WW.BoxSN ORDER BY LotSN DESC) AS SNEnd,
-- 			(SELECT COUNT(WWId) FROM dbo.WW_RMInventory WHERE BoxSN=WW.BoxSN ) AS SNCount,
-- 			CONVERT(NVARCHAR(10),WW.CreateDate,23) AS PrintDate
-- 		FROM dbo.WW_RMInventory WW 
-- 		INNER JOIN dbo.Product ON Product.ProductId=WW.ProductId
-- 		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
-- 		INNER JOIN dbo.UOM ON UOM.UOMId = PurchaseUOMId
-- 		LEFT JOIN dbo.PO ON PO.POId=WW.POId
-- 		LEFT JOIN dbo.Vendor ON Vendor.VendorId=WW.VendorId
-- 		WHERE WW.WWId IN (SELECT WWId FROM @LotTemp) 
-- 	END

	SELECT '' AS SplitLotSN,'' AS ProductName,'' AS LotQty,'' AS ProductDescription,0 AS SplitQty
	SET @I_ExceptionFieldName='SplitLotSN'
	SET @I_ReturnMessage='ServerMessage:批号【'+@SplitLotSN+'】成功将数量【' + CAST(CAST(@SplitQty AS FLOAT) AS VARCHAR)+ '】转移到新批号【'+@NewSN+'】!'
	
    ----------------------------------------------------同步WMS START--------------------------------------------------------------------------------
    --调整单
    Declare @I_WMSReturnMessage NVARCHAR(max) ='';
    Declare @Qty DECIMAL(18,6);
    DECLARE @return_value_WMS1  INT
    DECLARE @return_value_WMS2  INT
    Set @Qty=-1*@SplitQty
    EXEC @return_value_WMS1 = dbo.APISyncU_AdujstmentToWMS @I_ReturnMessage = @I_WMSReturnMessage OUTPUT, -- nvarchar(max)
                                                @lotsn =@SplitLotSN ,
                                                @adjustQuantity=@Qty, 
                                                @adjustReason='批次拆分',
                                                @Remark =''   
    DECLARE @ProductionLotNO NVARCHAR(100)=''                                            
    DECLARE @productionDate NVARCHAR(100)=''
    DECLARE @WarehouseId NVARCHAR(100)=''
    select @ProductionLotNO=ProductionLotNO,@productionDate=productionDate,@WarehouseId=WorkcenterId from WW_RMInventory where LotSN=@SplitLotSN
    --收货单
    EXEC @return_value_WMS2 = dbo.APISyncU_ReceiveToWMS @I_ReturnMessage = @I_WMSReturnMessage OUTPUT, -- nvarchar(max)
                                                @productId =@ProductId,
                                                @Qty  =@SplitQty,
                                                @WarehouseId =@WarehouseId,
                                                @LotSn  =@NewSN,
                                                @ProductionLotNO =@ProductionLotNO,
                                                @productionDate =@productionDate   
    IF @return_value_WMS1<>0 AND @return_value_WMS2<>0
    BEGIN
        SET @I_ReturnMessage='ServerMessage:批号【'+@SplitLotSN+'】调用WMS调整单失败!批号【'+@NewSN+'】调用WMS收货单失败！'
	    RETURN -1
    END
    ELSE IF @return_value_WMS1<>0 
    BEGIN
        SET @I_ReturnMessage='ServerMessage:批号【'+@SplitLotSN+'】调用WMS调整单失败!'
	    RETURN -1
    END
    ELSE IF @return_value_WMS2<>0
    BEGIN
        SET @I_ReturnMessage='ServerMessage:批号【'+@NewSN+'】调用WMS收货单失败'
	    RETURN -1
    END
    ----------------------------------------------------同步WMS END--------------------------------------------------------------------------------

	RETURN 0
	
END
GO
