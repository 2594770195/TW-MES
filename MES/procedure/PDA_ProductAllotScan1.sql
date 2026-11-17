SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OrBit Team Ben>
-- Create date: <2017.8.11>
-- Description: PDA插件-调拨扫描
-- Rev: 15.00
-- Update comment:1.改为先有调拨单明细，再调拨扫描;orbchay,HH0102;2020/09/18 11:14:18:7292
-- Update date:
-- =============================================
CREATE  PROCEDURE  [dbo].[PDA_ProductAllotScan1]
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
@I_Parameter NVARCHAR(MAX)='',  		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.

@ProductAllotName NVARCHAR(50)='',
@ToCellName NVARCHAR(50)='',
@LotOrBoxSN NVARCHAR(100) = '',
@PreviousCellId CHAR(12)='',
@CodeStatus NVARCHAR(50)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--如果工单物料指定了批次，则调用工单调拨的方法
	--IF EXISTS(SELECT 1 FROM ProductAllot A
	--INNER JOIN MOAllotMODetail B ON A.MOAllotRequestId=B.MOAllotRequestId AND A.FactoryId=B.TempFactoryId AND A.WorkcenterId=B.TempWorkcenterId AND A.ToFactoryId=B.ToFactoryId AND A.ToWorkcenterId=B.ToWarehouseId
	--INNER JOIN MOAllotDetail C ON B.MOAllotRequestId=C.MOAllotRequestId AND B.TempFactoryId=C.FromFactoryId AND B.TempWorkcenterId=C.FromWareHouseId AND B.ToFactoryId=C.ToFactoryId AND B.ToWarehouseId=C.ToWareHouseId AND B.ProductId=C.ProductId
	--WHERE A.ProductAllotName=@ProductAllotName AND B.ProductId=(SELECT TOP 1 ProductId FROM WW_RMInventory WHERE LotSN=@LotOrBoxSN) AND ISNULL(B.ProductionLotNO,'')<>'')
	--BEGIN
	--    DECLARE @RESULT INT=0
	--	EXEC @RESULT=[dbo].[PDA_ProductAllotScanOfMO]
	--	@I_Sender=@I_Sender,
	--	@I_ReturnMessage=@I_ReturnMessage OUTPUT,
	--	@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
	--	@I_LanguageId=@I_LanguageId,
	--	@I_PlugInCommand=@I_PlugInCommand,
	--	@I_OrBitUserId=@I_OrBitUserId,
	--	@I_OrBitUserName=@I_OrBitUserName,
	--	@I_ResourceId=@I_ResourceId,
	--	@I_ResourceName=@I_ResourceName,
	--	@I_PKid=@I_PKid,
	--	@I_ParentPKId=@I_ParentPKId,
	--	@I_Parameter=@I_Parameter,
	--	@ProductAllotName=@ProductAllotName,
	--	@ToCellName=@ToCellName,
	--	@LotOrBoxSN=@LotOrBoxSN,
	--	@PreviousCellId=@PreviousCellId

	--	RETURN @RESULT
	--END
	--通用
	DECLARE @return_value INT=-1
	DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10)
	DECLARE @InObject VARCHAR(20)='' --上架对象：lot/box

	--调拨单
	--bill
	DECLARE @OperateWay CHAR(1)=''--操作方式
	DECLARE @ProductAllotId CHAR(12)= ''         --调拨单ID
	DECLARE @ProductAllotStates VARCHAR(10)=''
	DECLARE @FromWorkcenterId CHAR(12)=''
	DECLARE @ToWorkcenterId CHAR(12)=''
	DECLARE @FromWorkcenterName NVARCHAR(50)=''
	DECLARE @ToWorkcenterName NVARCHAR(50)=''
	DECLARE @FromFactoryId CHAR(12)=''
	DECLARE @FromFactoryName NVARCHAR(50)=''
	DECLARE @ToFactoryId CHAR(12)=''
	DECLARE @ToFactoryName NVARCHAR(50)=''
	--billitem
	DECLARE @ProductAllotItemId CHAR(12)=''
	DECLARE @RealAllotQty FLOAT=0
	DECLARE @AllotQty FLOAT=0
	DECLARE @ItemSequence VARCHAR(10)=''
	--billitemlot
	DECLARE @ProductAllotItemLotId CHAR(12)=''


	--物料信息
	DECLARE @LotSN NVARCHAR(100)=''
	DECLARE @BoxSN NVARCHAR(100)=''
	DECLARE @ProductId CHAR(12)=''
	DECLARE @ProductName NVARCHAR(50)=''
	DECLARE @LotStatus CHAR(1)=''
	DECLARE @LotStatusDesc NVARCHAR(50)=''
	DECLARE @IsStorage BIT=0
	DECLARE @LotQty FLOAT=0 --单个批号的数量
	DECLARE @Qty FLOAT=0 --扫描的总数量（箱号或批号）
	DECLARE @LotWorkcenterId CHAR(12)=''
	DECLARE @LotWorkcenterName NVARCHAR(50)=''
	DECLARE @LotFactoryId CHAR(12)=''
	DECLARE @LotFatoryName NVARCHAR(50)=''
	DECLARE @LotCellId CHAR(12)=''
	DECLARE @LotUOMId CHAR(12)=''
	DECLARE @LotType VARCHAR(10)=''              --类别 R/B
	DECLARE @LotTypeDesc NVARCHAR(50)=''
	DECLARE @ProductionLotNO NVARCHAR(50)=''
	DECLARE @BagsCount INT=0  --有多少包

	--储位信息
	DECLARE @StorageBags INT=0
	DECLARE @MaxInventory DECIMAL(18,6)=0
	DECLARE @AdviceCellId CHAR(12)='' --建议储位
	DECLARE @AdviceCellName NVARCHAR(50)=''
	DECLARE @AdviceWareHouseId CHAR(12)='' --建议仓库
	DECLARE @AdviceWareHouseName CHAR(12)='' --建议仓库

	--输入参数
	DECLARE @ToCellId CHAR(12)=''


	DECLARE @LotTemp TABLE(
		ProductId CHAR(12),
		CellId CHAR(12),
		LotSN NVARCHAR(50),
		BoxSN NVARCHAR(50),
		Qty FLOAT,
		ItemUOMId CHAR(12)
	)

	select @ProductAllotName=ProductAllotName from ProductAllot 
	inner join ProductAllotItem on ProductAllot.ProductAllotId=ProductAllotItem.ProductAllotId
	inner join ProductAllotItemLot on ProductAllotItem.ProductAllotItemId=ProductAllotItemLot.ProductAllotItemId
	where LotSN=@LotOrBoxSN and ProductAllotStates=20

	select ProductAllotName=ProductAllotName from ProductAllot 
	inner join ProductAllotItem on ProductAllot.ProductAllotId=ProductAllotItem.ProductAllotId
	inner join ProductAllotItemLot on ProductAllotItem.ProductAllotItemId=ProductAllotItemLot.ProductAllotItemId
	where LotSN=@LotOrBoxSN and ProductAllotStates=20

	SET @I_ExceptionFieldName = 'LotOrBoxSN'

		-- ============================ 2026年1月16日 15:14:25  截取箱号（防止录错）      ==============================================----
    IF ISNULL(@LotOrBoxSN,'') !=''
    BEGIN
        SET @LotOrBoxSN = LEFT(@LotOrBoxSN, CHARINDEX('+', @LotOrBoxSN + '+') - 1)
        SELECT @LotOrBoxSN AS LotOrBoxSN
    END
    -- ============================ 2026年1月16日 15:14:29  截取箱号（防止录错）      ==============================================----

	IF ISNULL(@ProductAllotName,'')=''
	BEGIN
		SELECT '' AS ProductAllotName,'' AS ToWarehouseName,'' AS AdviceCellName,'' AS ToCellName,'' AS LotOrBoxSN,'' AS CurProductId
		SET @I_ReturnMessage='ServerMessage:请先选择要操作的调拨单据!'+@Enter
		RETURN -1
	END

	IF NOT EXISTS(SELECT 1 FROM dbo.ProductAllot WHERE ProductAllotName=@ProductAllotName)
	BEGIN
		SELECT '' AS ProductAllotName,'' AS ToWarehouseName,'' AS AdviceCellName,'' AS ToCellName,'' AS LotOrBoxSN,'' AS CurProductId
		SET @I_ReturnMessage='ServerMessage:调拨单【'+@ProductAllotName+'】无效，请确认!'+@Enter
		RETURN -1
	END

	--获取调拨单信息
	SELECT 
		@ProductAllotId=ProductAllotId,
		@ProductAllotStates=ProductAllotStates,
		@FromFactoryId=FactoryId,
		@ToFactoryId=ToFactoryId,
		@FromWorkcenterId=WorkcenterId,
		@ToWorkcenterId=ToWorkcenterId,
		@OperateWay=OperateWay
	FROM dbo.ProductAllot 
	WHERE ProductAllotName=@ProductAllotName


	IF ISNULL(@ProductAllotStates,'') NOT IN ('20')
	BEGIN
		SELECT '' AS ProductAllotName,'' AS ToWarehouseName,'' AS AdviceCellName,'' AS ToCellName,'' AS LotOrBoxSN,'' AS CurProductId
		SET @I_ReturnMessage='ServerMessage:调拨单【'+@ProductAllotName+'】不是[已审核]状态，不允许使用!'+@Enter
		RETURN -1
	END

	IF ISNULL(@OperateWay,'')='2'
	BEGIN
		SELECT '' AS ProductAllotName,'' AS ToWarehouseName,'' AS AdviceCellName,'' AS ToCellName,'' AS LotOrBoxSN,'' AS CurProductId
		SET @I_ReturnMessage='ServerMessage:'+CHAR(13)+CHAR(10)
		+'调拨单【'+@ProductAllotName+'】已使用过“调拨出库”扫描，不能再用“调拨扫描”！'+CHAR(13)+CHAR(10)
		+'请更换调拨单 或者 把扫描的批号撤销！'+@Enter
		RETURN -1
	END

	--获取调拨单信息
	SELECT @FromWorkcenterName=WorkcenterName FROM dbo.Workcenter WHERE WorkcenterId=@FromWorkcenterId
	SELECT @ToWorkcenterName=WorkcenterName FROM dbo.Workcenter WHERE WorkcenterId=@ToWorkcenterId
	SELECT @FromFactoryName=FactoryName FROM dbo.Factory WHERE FactoryId=@FromFactoryId
	SELECT @ToFactoryName=FactoryName FROM dbo.Factory WHERE FactoryId=@ToFactoryId

	IF EXISTS(SELECT 1 FROM dbo.Workcenter WHERE WorkcenterId=@FromWorkcenterId AND IsClosed=1)
	BEGIN
		SELECT '' AS ToWarehouseName,'' AS AdviceCellName,'' AS ToCellName,'' AS LotOrBoxSN,'' AS CurProductId
		SET @I_ReturnMessage='ServerMessage:调拨单【'+@ProductAllotName+'】源仓库【'+@FromWorkcenterName+'】已关闭，请检查!'+@Enter
		RETURN -1
	END 

	IF EXISTS(SELECT 1 FROM dbo.Workcenter WHERE WorkcenterId=@ToWorkcenterId AND IsClosed=1)
	BEGIN
		SELECT '' AS ToWarehouseName,'' AS AdviceCellName,'' AS ToCellName,'' AS LotOrBoxSN,'' AS CurProductId
		SET @I_ReturnMessage='ServerMessage:调拨单【'+@ProductAllotName+'】目标仓库【'+@ToWorkcenterName+'】已关闭，请检查!'+@Enter
		RETURN -1
	END 



	--****************【 1.扫描物料条码 】*****************
	IF ISNULL(@LotOrBoxSN,'')=''
	BEGIN
		SELECT '' AS LotOrBoxSN
		SET @I_ReturnMessage='ServerMessage:请扫描物料批次!'+@Enter
		RETURN -1
	END


	--检查是否小包或者外箱
	IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@LotOrBoxSN)
	BEGIN 
		SET @LotType='R'
		SET @LotTypeDesc='物料小包'
		SET @InObject='Lot'
	END

	IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN=@LotOrBoxSN)
	BEGIN 
		SET @LotType='B'
		SET @LotTypeDesc='物料箱号' 
		SET @InObject='Box'
	END

	IF @LotType NOT IN ('R','B')
	BEGIN
		SELECT '' AS LotOrBoxSN
		SET @I_ReturnMessage='ServerMessage:请扫描有效的小包/外箱条码!'+@Enter
		RETURN -1
	END


	--按小包扫描
	IF @LotType='R'
	BEGIN
		SET @LotSN=@LotOrBoxSN

		IF NOT EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN = @LotSN)
		BEGIN
			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】无效，请确认!'+@Enter
			RETURN -1
		END

		--获取物料批号库存信息
		SELECT 
			@LotStatus=LotStatus,
			@LotQty=Qty,
			@Qty=Qty,
			@LotWorkcenterId=WorkcenterId,
			@LotFactoryId=FactoryId,
			@LotCellId=CellId,
			@ProductId=ProductId,
			@BoxSN=BoxSN,
			@IsStorage=IsStorage,
			@ProductionLotNO=ProductionLotNO,
			@LotUOMId=UOMId
		FROM dbo.WW_RMInventory 
		WHERE LotSN=@LotSN

		--1包
		SET @BagsCount=1 

		--DECLARE @AllotProductionLotNO VARCHAR(64)
		--SELECT TOP 1 @AllotProductionLotNO=ISNULL(B.ProductionLotNO,'') FROM ProductAllot A
		--INNER JOIN MOAllotMODetail B ON A.MOAllotRequestId=B.MOAllotRequestId AND A.FactoryId=B.TempFactoryId AND A.WorkcenterId=B.TempWorkcenterId AND A.ToFactoryId=B.ToFactoryId AND A.ToWorkcenterId=B.ToWarehouseId
		--INNER JOIN MOAllotDetail C ON B.MOAllotRequestId=C.MOAllotRequestId AND B.TempFactoryId=C.FromFactoryId AND B.TempWorkcenterId=C.FromWareHouseId AND B.ToFactoryId=C.ToFactoryId AND B.ToWarehouseId=C.ToWareHouseId AND B.ProductId=C.ProductId
		--WHERE A.ProductAllotName=@ProductAllotName AND B.ProductId=(SELECT TOP 1 ProductId FROM WW_RMInventory WHERE LotSN=@LotOrBoxSN) AND ISNULL(B.ProductionLotNO,'')<>''
		--IF ISNULL(@AllotProductionLotNO,'')<>'' AND @ProductionLotNO NOT IN(SELECT col FROM DB_Split(@AllotProductionLotNO,','))
		--BEGIN
		--	SELECT '' AS LotOrBoxSN
		--	SET @I_ReturnMessage = 'ServerMessage:请扫描调拨指定的物料!'+@Enter
		--	RETURN -1
		--END

		SELECT 
			@ProductName=ProductName
		FROM dbo.Product
		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
		WHERE ProductId=@ProductId

		SELECT @LotFatoryName=FactoryName
		FROM dbo.Factory WHERE FactoryId=@LotFactoryId

		SELECT @LotWorkcenterName=WorkcenterName
		FROM dbo.Workcenter WHERE WorkcenterId=@LotWorkcenterId

		IF ISNULL(@IsStorage,0)=0   
		BEGIN
			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】不在库存中，不可操作!'+@Enter
			RETURN -1
		END

		--IF ISNULL(@LotStatus,'')<>'1'
		--BEGIN
		--	--WES WW_RMInventory LotStatus/库存表状态信息:URC100000AA9
		--	SELECT @LotStatusDesc=UserCodeDescription
		--	FROM dbo.UserCode
		--	WHERE ParentUserCodeId='URC100000AA9' AND UserCodeName=@LotStatus

		--	SELECT '' AS LotOrBoxSN
		--	SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】当前状态['+@LotStatusDesc+']，不可操作!'+@Enter
		--	RETURN -1
		--END

		IF ISNULL(@LotQty,0)<=0
		BEGIN
			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】可用数量已为零，不可操作!'+@Enter
			RETURN -1
		END

		IF ISNULL(@LotFactoryId,'')<>ISNULL(@FromFactoryId,'')
		BEGIN
			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】所属工厂【'+ISNULL(@LotFatoryName,'')+'】，'
				+CHAR(13)+CHAR(10)+'当前调拨单要求从原工厂【'+@FromFactoryName+'】进行调拨，请确认!'+@Enter
			RETURN -1
		END

		IF ISNULL(@LotWorkcenterId,'')<>ISNULL(@FromWorkcenterId,'')
		BEGIN
			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】所属仓库【'+ISNULL(@LotWorkcenterName,'')+'】，'
				+CHAR(13)+CHAR(10)+'当前调拨单要求从原仓库【'+@FromWorkcenterName+'】进行调拨，请确认!'+@Enter

			RETURN -1
		END

		--检查调拨单是否存在此料号
		IF NOT EXISTS(SELECT 1 FROM dbo.ProductAllotItem WHERE ProductAllotId=@ProductAllotId AND ProductId=@ProductId)
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:调拨单['+@ProductAllotName+']没有此物料['+@ProductName+']，请检查！物料条码['+@LotOrBoxSN+']'+@Enter
			RETURN -1
		END 

        --检查本次扫描调拨单中是否已经存在
		-- IF EXISTS (SELECT 1 FROM dbo.ProductAllotItem
		-- INNER JOIN dbo.ProductAllotItemLot ON ProductAllotItemLot.ProductAllotItemId = ProductAllotItem.ProductAllotItemId
		-- WHERE LotSN=@LotSN AND ProductAllotId=@ProductAllotId AND IsAOScan=1 AND IsAEScan=1)
		-- BEGIN
		-- 	SELECT '' AS LotOrBoxSN
		-- 	SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+ '】在当前调拨单中已扫描，不需要重复操作!'+@Enter
		-- 	RETURN -1
		-- END
		

        declare @currProductAllotItemLotId CHAR(12)=''
        SELECT @currProductAllotItemLotId=ProductAllotItemLotId FROM dbo.ProductAllotItem
		INNER JOIN dbo.ProductAllotItemLot ON ProductAllotItemLot.ProductAllotItemId = ProductAllotItem.ProductAllotItemId
		WHERE LotSN=@LotSN AND ProductAllotId=@ProductAllotId AND IsAOScan=1 AND IsAEScan=1

        --目标仓库不是线边仓且没有指定货位的需要扫描批次+货位
        IF ISNULL(@currProductAllotItemLotId,'')<>'' 
        AND NOT EXISTS(select 1 from Warehouse_ProductLine where warehousename=@ToWorkcenterName and ISNULL(productline,'')<>'')
        BEGIN
            --货位码(CodeStatus)不能为空
            IF ISNULL(@CodeStatus,'')=''
            BEGIN
                SET @I_ReturnMessage = 'ServerMessage:请扫描货位码!'+@Enter
                SET @I_ExceptionFieldName='CodeStatus'
                RETURN 0
            END

            --已存在容器/货位记录：根据@CodeStatus修改
            IF EXISTS (select 1 from ProductAllotItemLotContainer where ProductAllotItemLotId=@currProductAllotItemLotId)
            BEGIN
                UPDATE ProductAllotItemLotContainer set CodeStatus=@CodeStatus where ProductAllotItemLotId=@currProductAllotItemLotId
                SELECT '' AS LotOrBoxSN,'' AS CodeStatus
		        SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+ '】指定货位成功!'+@Enter
            END
        END



		--获取物料调拨单需要调拨的数量
		SELECT 
			@AllotQty=SUM(ISNULL(AllotQty,0)),
			@RealAllotQty=SUM(ISNULL(RealAllotQty,0))
		FROM dbo.ProductAllotItem 
		WHERE ProductAllotId=@ProductAllotId AND ProductId=@ProductId


		--已调拨数量+当前数量不允许大于调拨单的计划调拨数/改：允许超发
		--IF CAST(ISNULL(@RealAllotQty,0) + @Qty AS DECIMAL(18,8))> CAST(ISNULL(@AllotQty,0) AS DECIMAL(18,8))
		--BEGIN
		--	SELECT '' AS BoxOrLotSN
		--	SET @I_ReturnMessage = 'ServerMessage:物料【'+@ProductName+'】实际已调拨扫描【'+CAST(@RealAllotQty AS VARCHAR)+'】'
		--		+@Enter+'加上当前批号的数量 【'+CAST(@Qty AS VARCHAR)+']】不允许超出调拨单的计划调拨数 ['+CAST(@AllotQty AS VARCHAR)+'] '+@Enter
		--	RETURN -1
		--END

		--取得批号基本信息插入临时表
		INSERT INTO @LotTemp(ProductId,CellId,LotSN,Qty,BoxSN,ItemUOMId)VALUES(@ProductId,@LotCellId,@LotSN,@LotQty,@BoxSN,@LotUOMId)

	END


	--检查箱号基本信息，取得箱号中批号插入临时表
	IF @LotType='B'
	BEGIN
		SET @BoxSN=@LotOrBoxSN

		IF NOT EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN = @BoxSN)
		BEGIN
			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料箱号【'+@BoxSN+'】无效，请确认!'+@Enter
			RETURN -1
		END

		--是否存在出库的批号
		IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN = @BoxSN AND IsStorage=0 AND Qty>0)
		BEGIN
			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料箱号【'+@BoxSN+'】已拆箱，存在不在库的批号，请按小包调拨!'+@Enter
			RETURN -1
		END

		--检查状态
		IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE  BoxSN = @BoxSN AND Qty>0 AND LotStatus<>'1')
		BEGIN 
			SET @LotSN=''
			SET @LotStatus=''

			SELECT @LotStatus=LotStatus,
				   @LotSN=LotSN
			FROM dbo.WW_RMInventory 
			WHERE  BoxSN = @BoxSN AND Qty>0 AND LotStatus<>'1'

			--WES WW_RMInventory LotStatus/库存表状态信息:URC100000AA9
			SELECT @LotStatusDesc=UserCodeDescription
			FROM dbo.UserCode
			WHERE ParentUserCodeId='URC100000AA9' AND UserCodeName=@LotStatus

			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:箱号【'+@BoxSN+'】中的物料批号【'+@LotSN+'】当前状态['+@LotStatusDesc+']，不可操作！'+@Enter
			RETURN -1
		END

		--取得总数量信息
		SELECT  TOP 1
			@LotFactoryId=FactoryId,
			@LotWorkcenterId=WorkcenterId,
			@LotCellId=CellId,
			@ProductId = ProductId ,
			@ProductionLotNO=ProductionLotNO,
			@Qty = ISNULL(SUM(Qty),0)
		FROM  dbo.WW_RMInventory
		WHERE  BoxSN = @BoxSN AND Qty>0
		GROUP BY FactoryId,WorkcenterId,CellId,ProductId,ProductionLotNO

		SELECT @BagsCount=COUNT(1)
		FROM dbo.WW_RMInventory
		WHERE BoxSN=@BoxSN AND Qty>0


		--查找产品相关信息
		SELECT 
			@ProductName=ProductName
		FROM dbo.Product
		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
		WHERE ProductId= @ProductId

		-- 检查物料批号剩余数是否大于零
		IF CAST(ISNULL(@Qty,0) AS DECIMAL(18,8)) <= 0
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage = 'ServerMessage:物料外箱【'+@BoxSN+'] 剩余数量 '+CAST(@Qty AS VARCHAR) +' 已为零，无法操作 !'+@Enter
			RETURN -1
		END

		--检查是否有工厂、产品、仓库、储位是否一致
		IF (SELECT ISNULL(SUM(Qty),0) FROM dbo.WW_RMInventory WHERE BoxSN=@BoxSN)<>CAST(@Qty AS DECIMAL(18,6))
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage = 'ServerMessage:物料外箱【'+@LotOrBoxSN+'】已经拆过箱了，里面的单批号信息存在不一致的情况，请按小包调拨 !'+@Enter
			RETURN -1
		END

		IF ISNULL(@LotFactoryId,'')<>ISNULL(@FromFactoryId,'')
		BEGIN
			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料外箱【'+@BoxSN+'】所属工厂【'+ISNULL(@LotFatoryName,'')+'】，'
				+CHAR(13)+CHAR(10)+'当前调拨单要求从原工厂【'+@FromFactoryName+'】进行调拨，请确认!'+@Enter
			RETURN -1
		END

		IF ISNULL(@LotWorkcenterId,'')<>ISNULL(@FromWorkcenterId,'')
		BEGIN
			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:箱号【'+@BoxSN+'】不属于原仓库【'+@FromWorkcenterName+']，请确认!'+@Enter
			RETURN -1
		END


		--检查调拨单是否存在此料号
		IF NOT EXISTS(SELECT 1 FROM dbo.ProductAllotItem WHERE ProductAllotId=@ProductAllotId AND ProductId=@ProductId)
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:调拨单['+@ProductAllotName+']没有此物料['+@ProductName+']，请检查！物料条码['+@LotOrBoxSN+']'+@Enter
			RETURN -1
		END 

		--获取物料调拨单需要调拨的数量
		SELECT 
			@AllotQty=SUM(ISNULL(AllotQty,0)),
			@RealAllotQty=SUM(ISNULL(RealAllotQty,0))
		FROM dbo.ProductAllotItem 
		WHERE ProductAllotId=@ProductAllotId AND ProductId=@ProductId

		--已调拨数量+当前数量不允许大于调拨单的计划调拨数/改：允许超发
		--IF CAST(ISNULL(@RealAllotQty,0) + @Qty AS DECIMAL(18,8))> CAST(ISNULL(@AllotQty,0) AS DECIMAL(18,8))
		--BEGIN
		--	SELECT '' AS BoxOrLotSN
		--	SET @I_ReturnMessage = 'ServerMessage:物料【'+@ProductName+'】实际已调拨扫描【'+CAST(@RealAllotQty AS VARCHAR)+'】'
		--		+@Enter+'加上当前批号的数量 【'+CAST(@Qty AS VARCHAR)+']】不允许超出调拨单的计划调拨数 ['+CAST(@AllotQty AS VARCHAR)+'] '+@Enter
		--	RETURN -1
		--END

		--取得批号基本信息插入临时表
		INSERT INTO @LotTemp(ProductId,CellId,LotSN,Qty,BoxSN,ItemUOMId)
		SELECT ProductId,CellId,LotSN,Qty,BoxSN,UOMId 
		FROM dbo.WW_RMInventory 
		WHERE BoxSN=@BoxSN AND Qty>0


		--检查本次扫描调拨单中是否已经存在
		IF EXISTS (SELECT 1 FROM dbo.ProductAllotItem
		INNER JOIN dbo.ProductAllotItemLot ON ProductAllotItemLot.ProductAllotItemId = ProductAllotItem.ProductAllotItemId
		INNER JOIN @LotTemp a ON a.LotSN = ProductAllotItemLot.LotSN
		WHERE ProductAllotId=@ProductAllotId AND IsAOScan=1 AND IsAEScan=1)
		BEGIN
			SET @LotSN=''

			SELECT @LotSN=ProductAllotItemLot.LotSN 
			FROM dbo.ProductAllotItem
			INNER JOIN dbo.ProductAllotItemLot ON ProductAllotItemLot.ProductAllotItemId = ProductAllotItem.ProductAllotItemId
			INNER JOIN @LotTemp a ON a.LotSN = ProductAllotItemLot.LotSN
			WHERE ProductAllotId=@ProductAllotId AND IsAOScan=1 AND IsAEScan=1

			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:箱号【'+@BoxSN+'】中的物料批号【'+@LotSN+ '】在当前调拨单中已扫描，不需要重复操作!'+@Enter
			RETURN -1
		END
	END 




	--判断临时表有无数据
	IF NOT EXISTS (SELECT 1 FROM @LotTemp)
	BEGIN
		SELECT '' AS LotOrBoxSN
		SET @I_ReturnMessage = 'ServerMessage:没有发现任何可以调拨的数据!'+@Enter
		RETURN -1
	END



	--****************【 2.扫描储位 】*****************
	-- 《检查储位》：为空，则获取建议储位；否则执行上逻辑检查
	IF ISNULL(@ToCellName,'')=''
	BEGIN
		--获取建议储位
		 EXEC @return_value=dbo.TxnBase_MAdviceCell
			 @I_ReturnMessage=@I_ReturnMessage OUTPUT, -- nvarchar(max)
			 @I_OrBitUserId=@I_OrBitUserId, -- char(12)
			 @I_OrBitUserName=@I_OrBitUserName, -- nvarchar(100)
			 @I_ResourceId=@I_ResourceId, -- char(12)
			 @I_ResourceName=@I_ResourceName, -- nvarchar(100)
			 @I_PlugInCommand=@I_PlugInCommand, -- varchar(5)
			 @AdviceWarehouseId=@AdviceWareHouseId OUTPUT, -- char(12)
			 @AdviceCellId=@AdviceCellId OUTPUT, -- char(12)
			 @PreviousCellId=@PreviousCellId, -- char(12)
			 @ToWarehosueId=@ToWorkcenterId, -- char(12)
			 @SN=@LotOrBoxSN -- nvarchar(100)

		SELECT @AdviceCellName=CellName,@ToCellName=CellName
		FROM dbo.Cell
		WHERE CellId=@AdviceCellId


		--SELECT @ToWorkcenterName AS ToWareHouseName,@AdviceCellName AS AdviceCellName
		--SET @I_ReturnMessage='ServerMessage:请扫描储位号!'+@Enter
		--SET @I_ExceptionFieldName='ToCellName'
		--RETURN 0
	END
	ELSE
	BEGIN
		IF NOT EXISTS(SELECT 1 FROM dbo.Cell WHERE CellName=@ToCellName AND IsActivity=1)
		BEGIN
			SELECT '' AS ToCellName,'' AS LotOrBoxSN, @ToWorkcenterName AS ToWareHouseName,'' AS AdviceCellName
			SET @I_ReturnMessage='ServerMessage:目标储位【'+@ToCellName+'】不存在 或 没有激活，请确认'+@Enter
			RETURN -1
		END

		IF NOT EXISTS(SELECT 1 FROM dbo.Cell WHERE CellName=@ToCellName AND IsActivity=1 AND WorkcenterId=@ToWorkcenterId)
		BEGIN
			SELECT '' AS ToCellName,'' AS LotOrBoxSN, @ToWorkcenterName AS ToWareHouseName,'' AS AdviceCellName
			SET @I_ReturnMessage='ServerMessage:目标储位【'+@ToCellName+'】不属于目标仓库【'+@ToWorkcenterName+'】，请确认'+@Enter
			RETURN -1
		END

		--获取目标储位
		SELECT @ToCellId=CellId,
			   @StorageBags=ISNULL(StorageBags,0),
			   @MaxInventory=ISNULL(MaxInventory,0)
		FROM dbo.Cell 
		WHERE CellName=@ToCellName AND IsActivity=1 AND WorkcenterId=@ToWorkcenterId


-- 		IF ISNULL(@ToCellId,'')=ISNULL(@LotCellId,'')
-- 		BEGIN 
-- 			SELECT '' AS ToCellName,'' AS LotOrBoxSN, @ToWorkcenterName AS ToWareHouseName,'' AS AdviceCellName
-- 			SET @I_ReturnMessage='ServerMessage:不能相同储位调拨，请检查！'
-- 			RETURN -1 
-- 		END 


		--入库策略检查
		EXEC @return_value=dbo.TxnBase_MLotInCellCheck
			@I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
			@I_OrBitUserId = @I_OrBitUserId, -- char(12)
			@I_OrBitUserName = @I_OrBitUserName, -- nvarchar(100)
			@I_ResourceId = @I_ResourceId, -- char(12)
			@I_ResourceName = @I_ResourceName, -- nvarchar(100)
			@I_PlugInCommand = @I_PlugInCommand, -- varchar(5)
			@InObject = @InObject, -- nvarchar(50)
			@InLotNO=@ProductionLotNO,
			@InProductId = @ProductId, -- char(12)
			@InWarehouseId = @ToWorkcenterId, -- char(12)
			@InCellId = @ToCellId, -- char(12)
			@InStorageBags=@BagsCount,
			@InSumQty=@Qty

		IF @return_value<>0
		BEGIN
			SELECT '' AS ToCellName,'' AS LotOrBoxSN, @ToWorkcenterName AS ToWareHouseName,'' AS AdviceCellName
			SET @I_ReturnMessage=@I_ReturnMessage+','+@LotTypeDesc+'【'+@LotOrBoxSN+'】上架失败!'+@Enter
			RETURN -1
		END
	END


	IF ISNULL(@ToCellName,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请维护物料仓库【'+@ToWorkcenterName+'】建议储位号!'+@Enter
		SET @I_ExceptionFieldName='LotOrBoxSN'
	END


   --****************【 3.保存 】*****************
	--保存：
	--1.虽然调拨单物料明细同种物料只有单行，但统一按允许相同物料可以多行。为了以后功能修改能快速兼容
	--游标1循环处理：
	DECLARE cursor_1 CURSOR LOCAL FAST_FORWARD FOR  
	SELECT ProductId,
		   ISNULL(CellId,''),
		   LotSN,
		   BoxSN,
		   Qty,
		   ItemUOMId FROM @LotTemp
	OPEN cursor_1
	FETCH NEXT FROM cursor_1 
	INTO @ProductId,@LotCellId,@LotSN,@BoxSN,@LotQty,@LotUOMId
	WHILE @@FETCH_STATUS = 0 
	BEGIN
		--插入物料批号追踪表
		EXEC dbo.TxnBase_MLotTrack
			@I_OrBitUserId =@I_OrBitUserId, -- char(12)
			@I_PlugInCommand=@I_PlugInCommand,
			@I_ResourceId =@I_ResourceId, -- char(12)
			@LotSN = @LotSN, -- nvarchar(50) --物料批号
			@LotQty = @LotQty, -- decimal(18, 6)--数量
			@TxnCode = 'M-调拨扫描', -- nvarchar(50) --事务码
			@OrderName =@ProductAllotName , -- nvarchar(50) --单据号
			@Remark = N'' -- nvarchar(200) --备注


		 --分配数量
		 WHILE(CONVERT(DECIMAL(18,8),@LotQty)>0)
		 BEGIN
			SET @ProductAllotItemId=''

			SELECT TOP 1 
					@ProductAllotItemId=ProductAllotItemId,
					@AllotQty= ISNULL(AllotQty,0),
					@RealAllotQty=ISNULL(RealAllotQty,0)
			FROM dbo.ProductAllotItem
			WHERE ProductAllotId = @ProductAllotId AND ProductId = @ProductId
			AND  AllotQty>RealAllotQty
			ORDER BY ItemSequence

			--如果没有数量，则退出
			IF CONVERT(DECIMAL(18,8),@LotQty)<=0
			   BREAK

			--如果没有获取到行，则统一放在最后一行上
			IF ISNULL(@ProductAllotItemId,'')=''
			BEGIN
				SELECT TOP 1 
						@ProductAllotItemId=ProductAllotItemId,
						@AllotQty= ISNULL(AllotQty,0),
						@RealAllotQty=ISNULL(RealAllotQty,0)
				FROM dbo.ProductAllotItem
				WHERE ProductAllotId = @ProductAllotId AND ProductId = @ProductId
				ORDER BY ItemSequence DESC
			END


			--如果不等于空，则正常扣数（支持多行相同物料，如果等于空，说明）
			IF CONVERT(DECIMAL(18,6),@LotQty)<=CONVERT(DECIMAL(18,6),(@AllotQty-@RealAllotQty))
			BEGIN
				IF EXISTS(SELECT 1 FROM ProductAllotItemLot WHERE ProductAllotItemId=@ProductAllotItemId AND LotSN=@LotSN)
				BEGIN
					UPDATE ProductAllotItemLot SET IsAEScan=1,IsAOScan=1 WHERE ProductAllotItemId=@ProductAllotItemId AND LotSN=@LotSN
				END
				ELSE
				BEGIN
					EXEC dbo.SysGetObjectPKId '','ProductAllotItemLot',@ProductAllotItemLotId OUTPUT

						--同步插入调拨明细批号对应的容器/货位记录（目标仓库非线边仓且货位码非空）
						IF ISNULL(@CodeStatus,'')<>'' AND NOT EXISTS(SELECT 1 FROM Warehouse_ProductLine WHERE warehousename=@ToWorkcenterName AND ISNULL(productline,'')<>'')
						BEGIN
							INSERT INTO dbo.ProductAllotItemLotContainer(ProductAllotItemLotId,CodeStatus,CreateUserId,CreateDate)
							VALUES(@ProductAllotItemLotId,@CodeStatus,@I_OrBitUserId,GETDATE())
						END

					-- 写入调拨表明细批号
					INSERT INTO dbo.ProductAllotItemLot
						 (
							 ProductAllotItemLotId,
							 ProductAllotItemId,
							 LotSN,
							 BoxSN,
							 Qty,
							 CellId,
							 ToCellId,
							 IsAOScan,
							 IsAEScan,
							 AllotType,
							 CreateUserId,
							 CreateDate
						 )
					VALUES
						 (
							 @ProductAllotItemLotId,
							 @ProductAllotItemId,
							 @LotSN,
							 @BoxSN,
							 @LotQty,
							 @LotCellId,
							 @ToCellId,
							 1,
							 1,
							 @LotType,
							 @I_OrBitUserId,
							 GETDATE()
						 )
				END

				--更新调拨数
				UPDATE dbo.ProductAllotItem SET 
					RealAllotQty =ISNULL( RealAllotQty,0) + @LotQty
				WHERE ProductAllotItemId = @ProductAllotItemId

				SET @LotQty=0
			END
			ELSE
			BEGIN
				--检查是否除了当前行，是否还有其他行有相同产品的行，如果有，则正常扣数，如果不是，则把所有剩余数放在最后一行上
				--即多的数量只会在最后一行上
				IF EXISTS(SELECT 1 FROM dbo.ProductAllotItem WHERE ProductAllotId=@ProductAllotId
				AND ProductAllotItemId<>@ProductAllotItemId AND ProductId=@ProductId 
				AND AllotQty>RealAllotQty)
				BEGIN 
					IF EXISTS(SELECT 1 FROM ProductAllotItemLot WHERE ProductAllotItemId=@ProductAllotItemId AND LotSN=@LotSN)
					BEGIN
						UPDATE ProductAllotItemLot SET IsAEScan=1,IsAOScan=1 WHERE ProductAllotItemId=@ProductAllotItemId AND LotSN=@LotSN
					END
					ELSE
					BEGIN
						EXEC dbo.SysGetObjectPKId '','ProductAllotItemLot',@ProductAllotItemLotId OUTPUT

						--同步插入调拨明细批号对应的容器/货位记录（目标仓库非线边仓且货位码非空）
						IF ISNULL(@CodeStatus,'')<>'' AND NOT EXISTS(SELECT 1 FROM Warehouse_ProductLine WHERE warehousename=@ToWorkcenterName AND ISNULL(productline,'')<>'')
						BEGIN
							INSERT INTO dbo.ProductAllotItemLotContainer(ProductAllotItemLotId,CodeStatus,CreateUserId,CreateDate)
							VALUES(@ProductAllotItemLotId,@CodeStatus,@I_OrBitUserId,GETDATE())
						END
						-- 写入调拨表明细批号
						INSERT INTO dbo.ProductAllotItemLot
							 (
								 ProductAllotItemLotId,
								 ProductAllotItemId,
								 LotSN,
								 BoxSN,
								 Qty,
								 CellId,
								 ToCellId,
								 IsAOScan,
								 IsAEScan,
								 AllotType,
								 CreateUserId,
								 CreateDate
							 )
						VALUES
							 (
								 @ProductAllotItemLotId,
								 @ProductAllotItemId,
								 @LotSN,
								 @BoxSN,
								 @AllotQty-@RealAllotQty,
								 @LotCellId,
								 @ToCellId,
								 1,
								 1,
								 @LotType,
								 @I_OrBitUserId,
								 GETDATE()
							 )
					END

					--更新调拨数
					UPDATE dbo.ProductAllotItem SET 
						RealAllotQty =ISNULL( RealAllotQty,0) + (@AllotQty-@RealAllotQty)
					WHERE ProductAllotItemId= @ProductAllotItemId    

					--当前批次剩余数
					SET @LotQty=@LotQty-(@AllotQty-@RealAllotQty)
				END 
				ELSE
				BEGIN
					IF EXISTS(SELECT 1 FROM ProductAllotItemLot WHERE ProductAllotItemId=@ProductAllotItemId AND LotSN=@LotSN)
					BEGIN
						UPDATE ProductAllotItemLot SET IsAEScan=1,IsAOScan=1 WHERE ProductAllotItemId=@ProductAllotItemId AND LotSN=@LotSN
					END
					ELSE
					BEGIN
						EXEC dbo.SysGetObjectPKId '','ProductAllotItemLot',@ProductAllotItemLotId OUTPUT

						--同步插入调拨明细批号对应的容器/货位记录（目标仓库非线边仓且货位码非空）
						IF ISNULL(@CodeStatus,'')<>'' AND NOT EXISTS(SELECT 1 FROM Warehouse_ProductLine WHERE warehousename=@ToWorkcenterName AND ISNULL(productline,'')<>'')
						BEGIN
							INSERT INTO dbo.ProductAllotItemLotContainer(ProductAllotItemLotId,CodeStatus,CreateUserId,CreateDate)
							VALUES(@ProductAllotItemLotId,@CodeStatus,@I_OrBitUserId,GETDATE())
						END
						-- 写入调拨表明细批号
						INSERT INTO dbo.ProductAllotItemLot
							 (
								 ProductAllotItemLotId,
								 ProductAllotItemId,
								 LotSN,
								 BoxSN,
								 Qty,
								 CellId,
								 ToCellId,
								 IsAOScan,
								 IsAEScan,
								 AllotType,
								 CreateUserId,
								 CreateDate
							 )
						VALUES
							 (
								 @ProductAllotItemLotId,
								 @ProductAllotItemId,
								 @LotSN,
								 @BoxSN,
								 @LotQty,
								 @LotCellId,
								 @ToCellId,
								 1,
								 1,
								 @LotType,
								 @I_OrBitUserId,
								 GETDATE()
							 )
					END

					--更新调拨数
					UPDATE dbo.ProductAllotItem SET 
						RealAllotQty =ISNULL( RealAllotQty,0) + @LotQty
					WHERE ProductAllotItemId = @ProductAllotItemId

					SET @LotQty=0
				END    
				--E
			END 
			--E
		END 


		--更新库存表为已发料
		UPDATE dbo.WW_RMInventory SET 
			LotStatus='9',
			ModifyDate=GETDATE()
		WHERE LotSN=@LotSN

		FETCH NEXT FROM cursor_1 
		INTO @ProductId,@LotCellId,@LotSN,@BoxSN,@LotQty,@LotUOMId
	END
	CLOSE cursor_1
	DEALLOCATE cursor_1 



	--更新调拨单的操作方式
	IF NOT EXISTS(SELECT  1 FROM dbo.ProductAllot WHERE ProductAllotId=@ProductAllotId
	AND OperateWay='1')
	BEGIN
		UPDATE dbo.ProductAllot SET OperateWay='1' WHERE ProductAllotId=@ProductAllotId
	END


	--计算是否清除储位
	IF @StorageBags>0
	BEGIN
		--存满，则清空
		IF(SELECT COUNT(1) FROM dbo.WW_RMInventory WHERE CellId=@ToCellId AND IsStorage=1 AND LotStatus IN('1','0'))>=@StorageBags
		BEGIN
			SET @ToCellName=''
		END
	END

	IF @MaxInventory>0 AND @ToCellName<>''
	BEGIN
		--存满，则清空
		IF(SELECT ISNULL(SUM(Qty),0) FROM dbo.WW_RMInventory WHERE CellId=@ToCellId AND IsStorage=1 AND LotStatus IN('1','0'))>=@MaxInventory
		BEGIN
			SET @ToCellName=''
		END
	END


	SELECT '' AS LotOrBoxSN,
			@ProductId AS CurProductId,
			@ToCellId AS PreviousCellId,--为了计算建议储位,
			@ToCellName AS ToCellName
	SET @I_ReturnMessage = 'ServerMessage:'+@LotTypeDesc+' ['+@LotOrBoxSN+']调拨OK,数量['+CAST(@Qty AS VARCHAR)+']'+@Enter

	RETURN 0

END
GO
