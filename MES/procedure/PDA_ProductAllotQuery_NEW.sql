SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OrBit Team Orbchay>
-- Create date: <2020.05.08>
-- Description:	PDA插件-调拨单查询-新
--  
-- =============================================
ALTER PROCEDURE  [dbo].[PDA_ProductAllotQuery_NEW]
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
@FromWareHouseId CHAR(12)='',
@FromWareHouseName NVARCHAR(100)='',
@FromCellName NVARCHAR(100)='',
@ToWareHouseId CHAR(12)='',
@ToWareHouseName NVARCHAR(100)='',
@ToCellName NVARCHAR(100)='',
@LotOrBoxSN NVARCHAR(100)='',
@Grid_ProductAllotItem CHAR(12)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	
	--通用
	DECLARE @return_value INT=-1
	DECLARE @Enter NVARCHAR(100)=CHAR(13)+CHAR(10)
	DECLARE @IPKId CHAR(12)=''
    

	DECLARE @LotType VARCHAR(10)=''              --类别 R/B
	DECLARE @LotTypeDesc NVARCHAR(50)=''
	DECLARE @InObject VARCHAR(20)='' --上架对象：lot/box

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
	DECLARE @ProductionLotNO NVARCHAR(50)=''
	DECLARE @BagsCount INT=0  --有多少包

	--工厂信息
	DECLARE @FromFactoryId CHAR(12)=''
	DECLARE @FromFactoryName NVARCHAR(50)=''
	DECLARE @ToFactoryId CHAR(12)=''
	DECLARE @ToFactoryName NVARCHAR(50)=''

	declare @QtyZero decimal(18, 8)=0.0
	DECLARE @ItemPKId CHAR(12)=''
	DECLARE @ItemPKIdLot CHAR(12)=''
	DECLARE @ProductAllotName NVARCHAR(16)
	DECLARE @ProductClassifyTemp CHAR(10)=''
	DECLARE @ProductAllotItemId CHAR(12)='',@LotSn1 NVARCHAR(50)='',@BoxSN1 NVARCHAR(50)='',@Qty1 NVARCHAR(50)='',@FromCellId1 CHAR(12)='',@AllotType CHAR(1)=''

	DECLARE @LotTemp TABLE(
		ProductId CHAR(12),
		CellId CHAR(12),
		LotSN NVARCHAR(50),
		BoxSN NVARCHAR(50),
		Qty FLOAT,
		ItemUOMId CHAR(12)
	)

	DECLARE @Temp_Picking TABLE(
		MOAllotRequestId CHAR(12),
		FromFactoryId CHAR(12),
		FromWareHouseId CHAR(12),
		ToFactoryId CHAR(12),
		ToWareHouseId CHAR(12),
		ProductId CHAR(12),
		ProductClassify VARCHAR(10),
		ProductionLotNO VARCHAR(32),
		AllotQty DECIMAL(18,8),
		AllotQtyCurrent DECIMAL(18,8),
		WQty DECIMAL(18,8)
	)

	DECLARE @RESULT INT=0,@ProductAllotDescription NVARCHAR(50)='多工单合并发料',
	@NowDate datetime =getdate(),@NewSN nvarchar(256)='',@MOId char(12),@ProductAllotId nvarchar(256)='',@ProductClassify char(10)
	,@AllotQty decimal(18,8),@WQty DECIMAL(18,8),@UsageUOMId char(12),@LineSequence INT
	--游标使用参数


    -- ============================ 2026年1月16日 15:14:25  截取箱号（防止录错）      ==============================================----
        SET @LotOrBoxSN = LEFT(@LotOrBoxSN, CHARINDEX('+', @LotOrBoxSN + '+') - 1)
    -- ============================ 2026年1月16日 15:14:29  截取箱号（防止录错）      ==============================================----

	IF @FromWareHouseId IS NULL OR @FromWareHouseId =''
	BEGIN
		SET @I_ExceptionFieldName = 'FromWareHouseName'
		SET @I_ReturnMessage='ServerMessage:原仓库不能为空！'+@Enter
		RETURN -1
	END

	IF @ToWareHouseId IS NULL OR @ToWareHouseId =''
	BEGIN
		SET @I_ExceptionFieldName = 'ToWareHouseName'
		SET @I_ReturnMessage='ServerMessage:目标仓库不能为空！'+@Enter
		RETURN -1
	END

	IF @ToWareHouseId=@FromWareHouseId
	BEGIN
		SET @I_ExceptionFieldName = 'FromWareHouseName'
		SET @I_ReturnMessage='ServerMessage:原仓库和目标仓库不能相同，请检查！'+@Enter
		RETURN -1
	END

	--校验工厂是否一致
	SELECT @FromFactoryId=Factory.FactoryId,@FromFactoryName=FactoryName FROM dbo.WorkCenter_Factory INNER JOIN dbo.Factory ON Factory.FactoryId = WorkCenter_Factory.FactoryID WHERE WorkCenterID=@FromWareHouseId
	SELECT @ToFactoryId=Factory.FactoryID,@ToFactoryName=FactoryName FROM dbo.WorkCenter_Factory INNER JOIN dbo.Factory ON Factory.FactoryId = WorkCenter_Factory.FactoryID WHERE WorkCenterID=@ToWareHouseId
    
    --20260401取消跨工厂的检查，过账失败由仓库人员后期再手动处理
	-- IF @FromFactoryId<>@ToFactoryId
	-- BEGIN
	-- 	SET @I_ReturnMessage='ServerMessage:原仓库所属工厂【'+@FromFactoryName+'】与目标仓库所属工厂【'+@ToFactoryName+'】不一致，不能调拨，请检查!'+@Enter
	-- 	RETURN -1
	-- END;
	--************begin 查询界面 begin******************
	IF @I_Sender='Get_Bill'
	BEGIN
			--返回网格数据
			SELECT 
				pat.ProductAllotTempId,
				pat.ProductName,
				pr.ProductDescription,
				pat.LotSn,
				pat.Qty,  -- 原始单行数量
				-- 核心：按ProductName分组计算汇总值（独立汇总，不影响其他列显示）
				SUM(pat.Qty) OVER (PARTITION BY pat.ProductName,pat.UserId) AS SummaryQty,
				CONCAT(fw.WorkcenterName, ' ', fw.WorkcenterDescription) AS FromWareHouseName,
				CONCAT(tw.WorkcenterName, ' ', tw.WorkcenterDescription) AS ToWareHouseName
			FROM dbo.ProductAllotTemp pat  -- 简化别名，提升可读性
			LEFT JOIN dbo.Product pr ON pr.ProductId = pat.ProductId
			LEFT JOIN dbo.Workcenter fw ON pat.FromWareHouseId = fw.WorkcenterId
			LEFT JOIN dbo.Workcenter tw ON pat.ToWareHouseId = tw.WorkcenterId
			WHERE 
				pat.FromWareHouseId = @FromWareHouseId 
				AND pat.ToWareHouseId = @ToWareHouseId 
				AND pat.UserId = @I_OrBitUserId
			-- 可选：按ProductName排序，让同产品的行相邻，汇总值更直观
			ORDER BY 
				pat.ProductName ASC,
				pat.LotSn ASC;  
		--返回提示
		SELECT '' AS LotOrBoxSN
		SET @I_ExceptionFieldName = 'LotOrBoxSN'
		SET @I_ReturnMessage='ServerMessage:请扫描小包/外箱！'+@Enter
		RETURN 0
	END

	SET @I_ExceptionFieldName = 'LotOrBoxSN'
	--************end 扫描界面 end*******************

	--************begin 删除批号 begin******************
	IF @I_Sender='DeleteLotSn'
	BEGIN
			IF ISNULL(@Grid_ProductAllotItem,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:请选择有效的删除数据，选中表格对应行！'+@Enter
				RETURN -1
			END

			SET @Grid_ProductAllotItem= RTRIM(LTRIM(@Grid_ProductAllotItem))

			DELETE FROM dbo.ProductAllotTemp WHERE ProductAllotTempId=CASE 
                              WHEN ISNUMERIC(@Grid_ProductAllotItem) = 1 
                              THEN CAST(CAST(@Grid_ProductAllotItem AS DECIMAL(18,2)) AS INT)
                              ELSE NULL 
                           END
            
			--返回网格数据
			SELECT 
				pat.ProductAllotTempId,
				pat.ProductName,
				pr.ProductDescription,
				pat.LotSn,
				pat.Qty,  -- 原始单行数量
				-- 核心：按ProductName分组计算汇总值（独立汇总，不影响其他列显示）
				SUM(pat.Qty) OVER (PARTITION BY pat.ProductName,pat.UserId) AS SummaryQty,
				CONCAT(fw.WorkcenterName, ' ', fw.WorkcenterDescription) AS FromWareHouseName,
				CONCAT(tw.WorkcenterName, ' ', tw.WorkcenterDescription) AS ToWareHouseName
			FROM dbo.ProductAllotTemp pat  -- 简化别名，提升可读性
			LEFT JOIN dbo.Product pr ON pr.ProductId = pat.ProductId
			LEFT JOIN dbo.Workcenter fw ON pat.FromWareHouseId = fw.WorkcenterId
			LEFT JOIN dbo.Workcenter tw ON pat.ToWareHouseId = tw.WorkcenterId
			WHERE 
				pat.FromWareHouseId = @FromWareHouseId 
				AND pat.ToWareHouseId = @ToWareHouseId 
				AND pat.UserId = @I_OrBitUserId
			-- 可选：按ProductName排序，让同产品的行相邻，汇总值更直观
			ORDER BY 
				pat.ProductName ASC,
				pat.LotSn ASC;  
		--返回提示
		SELECT '' AS LotOrBoxSN
		SET @I_ExceptionFieldName = 'LotOrBoxSN'
		SET @I_ReturnMessage='ServerMessage:删除批号成功！'+@Enter
		RETURN 0
	END

	SET @I_ExceptionFieldName = 'LotOrBoxSN'
	--************end 删除批号 end*******************


	IF @I_Sender='ProductAllotScan'
	BEGIN
		--****************【 1.扫描物料条码 】*****************
		IF ISNULL(@LotOrBoxSN,'')=''
		BEGIN
			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage='ServerMessage:请扫描物料批次!'+@Enter
			RETURN -1
		END

		-- 截取 + 号之前的数据
		SET @LotOrBoxSN = 
		CASE WHEN CHARINDEX('+', @LotOrBoxSN) > 0 
			 THEN LEFT(@LotOrBoxSN, CHARINDEX('+', @LotOrBoxSN) - 1)
			 ELSE @LotOrBoxSN 
		END;
		
		-- ============================ 2026年3月16日 13:47:40  截取箱号（防止录错）      ==============================================----
		IF ISNULL(@LotOrBoxSN,'') !=''
        BEGIN
            SET @LotOrBoxSN = LEFT(@LotOrBoxSN, CHARINDEX('+', @LotOrBoxSN + '+') - 1)
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
			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage='ServerMessage:请扫描有效的小包/外箱条码!'+@Enter
			RETURN -1
		END

	--按小包扫描
	IF @LotType='R'
	BEGIN
		SET @LotSN=@LotOrBoxSN
		SET @AllotType=@LotType

		IF NOT EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN = @LotSN)
		BEGIN
			--SELECT '' AS LotOrBoxSN
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
			@ProductId=WW_RMInventory.ProductId,
			@BoxSN=BoxSN,
			@IsStorage=IsStorage,
			@ProductionLotNO=ProductionLotNO,
			@ProductClassify=ProductClassify,
			@LotUOMId=UOMId
		FROM dbo.WW_RMInventory 
		LEFT JOIN dbo.Product ON Product.ProductId = WW_RMInventory.ProductId
		WHERE LotSN=@LotSN 

		--1包
		SET @BagsCount=1 

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
			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】不在库存中，不可操作!'+@Enter
			RETURN -1
		END

		IF ISNULL(@LotStatus,'')<>'1'
		BEGIN
			--WES WW_RMInventory LotStatus/库存表状态信息:URC100000AA9
			SELECT @LotStatusDesc=UserCodeDescription
			FROM dbo.UserCode
			WHERE ParentUserCodeId='URC100000AA9' AND UserCodeName=@LotStatus

			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】当前状态['+@LotStatusDesc+']，不可操作!'+@Enter
			RETURN -1
		END

		IF ISNULL(@LotQty,0)<=0
		BEGIN
			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】可用数量已为零，不可操作!'+@Enter
			RETURN -1
		END

		IF ISNULL(@LotFactoryId,'')<>ISNULL(@FromFactoryId,'')
		BEGIN
			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】所属工厂【'+ISNULL(@LotFatoryName,'')+'】，'
				+CHAR(13)+CHAR(10)+'当前调拨单要求从原工厂【'+@FromFactoryName+'】进行调拨，请确认!'+@Enter
			RETURN -1
		END

		IF ISNULL(@LotWorkcenterId,'')<>ISNULL(@FromWareHouseId,'')
		BEGIN
			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】所属仓库【'+ISNULL(@LotWorkcenterName,'')+'】，'
				+CHAR(13)+CHAR(10)+'当前要求从原仓库【'+@FromWareHouseName+'】进行调拨，请确认!'+@Enter
			RETURN -1
		END

		--检查本次扫描中是否已经存在
		IF EXISTS (SELECT 1 FROM dbo.ProductAllotTemp WHERE FromWareHouseId=@FromWareHouseId AND ToWareHouseId=@ToWareHouseId AND LotSN=@LotSN AND UserId=@I_OrBitUserId)
		BEGIN
			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+ '】已扫描，不需要重复操作!'+@Enter
			RETURN -1
		END

		--不能是成品
-- 		IF @ProductClassify = '1'
-- 		BEGIN
-- 			--SELECT '' AS LotOrBoxSN
-- 			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+ '】是成品，不能使用调拨功能!'+@Enter
-- 			RETURN -1
-- 		END

		IF @Grid_ProductAllotItem<>''
		BEGIN
			SELECT @ProductClassifyTemp=ProductClassify FROM dbo.ProductAllotTemp WHERE ProductAllotTempId=CASE 
                              WHEN ISNUMERIC(@Grid_ProductAllotItem) = 1 
                              THEN CAST(CAST(@Grid_ProductAllotItem AS DECIMAL(18,2)) AS INT)
                              ELSE NULL 
                           END
			IF ISNULL(@ProductClassifyTemp,'')<>'' AND @ProductClassifyTemp<>@ProductClassify
			BEGIN
				SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】中的产品分类是【'+@ProductClassify+'】与已扫描物料的产品分类【'+@ProductClassifyTemp+'】不一致！(产品分类 (1:成品,2:半成品&半制品,3:原材料,4:包材&杂项))，请检查!'+@Enter
				RETURN -1
			END;
		END;
        EXEC @return_value=dbo.TxnBase_MLotOutCellCheck
                           @I_ReturnMessage=@I_ReturnMessage OUTPUT,
                           @I_OrBitUserId=@I_OrBitUserId,
                           @I_OrBitUserName=@I_OrBitUserName,
                           @I_ResourceId=@I_ResourceId,
                           @I_ResourceName=@I_ResourceName,
                           @I_PlugInCommand=@I_PlugInCommand,
                           @LotSN=@LotSN,
                           @BoxSN=N''
        IF @return_value=-1
        BEGIN
            SET @I_ReturnMessage=@I_ReturnMessage+@Enter
            RETURN -1
        END

		--插入数据到表中
		INSERT INTO dbo.ProductAllotTemp (ProductId, FromWareHouseId, FromWareHouseName,FromCellId, ToWareHouseId, ToWareHouseName,ToCellName, ProductName, LotSn,BoxSN, Qty,ProductClassify,AllotType, UserId, MetadataName)
		VALUES (@ProductId, @FromWareHouseId, @FromFactoryName,@LotCellId, @ToWareHouseId, @ToWareHouseName, @ToCellName,@ProductName, @LotSN, @BoxSN,@Qty,@ProductClassify,@AllotType, @I_OrBitUserId, @I_PlugInCommand);


	END


	--检查箱号基本信息，取得箱号中批号插入临时表
	IF @LotType='B'
	BEGIN
		SET @BoxSN=@LotOrBoxSN
		SET @AllotType=@LotType

		IF NOT EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN = @BoxSN)
		BEGIN
			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料箱号【'+@BoxSN+'】无效，请确认!'+@Enter
			RETURN -1
		END

		--是否存在出库的批号
		IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN = @BoxSN AND IsStorage=0 AND Qty>0)
		BEGIN
			--SELECT '' AS LotOrBoxSN
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

			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:箱号【'+@BoxSN+'】中的物料批号【'+@LotSN+'】当前状态['+@LotStatusDesc+']，不可操作！'+@Enter
			RETURN -1
		END

		--取得总数量信息
		SELECT  TOP 1
			@LotFactoryId=FactoryId,
			@LotWorkcenterId=WorkcenterId,
			@LotCellId=CellId,
			@ProductId = WW_RMInventory.ProductId ,
			@ProductionLotNO=ProductionLotNO,
			@ProductClassify=ProductClassify,
			@Qty = ISNULL(SUM(Qty),0)
		FROM  dbo.WW_RMInventory
		LEFT JOIN dbo.Product  ON Product.ProductId = WW_RMInventory.ProductId
		WHERE  BoxSN = @BoxSN AND Qty>0
		GROUP BY FactoryId,WorkcenterId,CellId,WW_RMInventory.ProductId,ProductionLotNO,ProductClassify

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
			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料外箱【'+@BoxSN+'] 剩余数量 '+CAST(@Qty AS VARCHAR) +' 已为零，无法操作 !'+@Enter
			RETURN -1
		END

		--检查是否有工厂、产品、仓库、储位是否一致
		IF (SELECT ISNULL(SUM(Qty),0) FROM dbo.WW_RMInventory WHERE BoxSN=@BoxSN)<>CAST(@Qty AS DECIMAL(18,6))
		BEGIN
			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料外箱【'+@LotOrBoxSN+'】已经拆过箱了，里面的单批号信息存在不一致的情况，请按小包调拨 !'+@Enter
			RETURN -1
		END

		IF ISNULL(@LotFactoryId,'')<>ISNULL(@FromFactoryId,'')
		BEGIN
			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料外箱【'+@BoxSN+'】所属工厂【'+ISNULL(@LotFatoryName,'')+'】，'
				+CHAR(13)+CHAR(10)+'当前调拨单要求从原工厂【'+@FromFactoryName+'】进行调拨，请确认!'+@Enter
			RETURN -1
		END

		IF ISNULL(@LotWorkcenterId,'')<>ISNULL(@FromWareHouseId,'')
		BEGIN
			SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:箱号【'+@BoxSN+'】不属于原仓库【'+@FromFactoryName+']，请确认!'+@Enter
			RETURN -1
		END
		
		--不能是成品
		IF @ProductClassify='1'
		BEGIN
			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+ '】是成品，不能使用调拨功能!'+@Enter
			RETURN -1
		END

		--取得批号基本信息插入临时表
		INSERT INTO @LotTemp(ProductId,CellId,LotSN,Qty,BoxSN,ItemUOMId)
		SELECT ProductId,CellId,LotSN,Qty,BoxSN,UOMId 
		FROM dbo.WW_RMInventory 
		WHERE BoxSN=@BoxSN AND Qty>0

		--检查本次扫描调拨单中是否已经存在
		IF EXISTS (SELECT 1 FROM dbo.ProductAllotTemp
		INNER JOIN @LotTemp a ON a.LotSN = ProductAllotTemp.LotSN
		WHERE FromWareHouseId=@FromWareHouseId AND ToWareHouseId=@ToWareHouseId AND A.LotSN=@LotSN AND UserId=@I_OrBitUserId)
		BEGIN
			SET @LotSN=''

			SELECT @LotSN=ProductAllotTemp.LotSN 
			FROM dbo.ProductAllotTemp
			INNER JOIN @LotTemp a ON a.LotSN = ProductAllotTemp.LotSN
			WHERE FromWareHouseId=@FromWareHouseId AND ToWareHouseId=@ToWareHouseId AND A.LotSN=@LotSN AND UserId=@I_OrBitUserId

			--SELECT '' AS LotOrBoxSN
			SET @I_ReturnMessage = 'ServerMessage:箱号【'+@BoxSN+'】中的物料批号【'+@LotSN+ '】在当前已扫描，不需要重复操作!'+@Enter
			RETURN -1
		END

		IF @Grid_ProductAllotItem<>''
		BEGIN
			
			SELECT @ProductClassifyTemp=ProductClassify FROM dbo.ProductAllotTemp WHERE ProductAllotTempId=CASE 
                              WHEN ISNUMERIC(@Grid_ProductAllotItem) = 1 
                              THEN CAST(CAST(@Grid_ProductAllotItem AS DECIMAL(18,2)) AS INT)
                              ELSE NULL 
                           END
			IF ISNULL(@ProductClassifyTemp,'')<>'' AND @ProductClassifyTemp<>@ProductClassify
			BEGIN
				SET @I_ReturnMessage = 'ServerMessage:箱号【'+@BoxSN+'】中的产品分类是【'+@ProductClassify+'】与已扫描物料的产品分类【'+@ProductClassifyTemp+'】不一致！(产品分类 (1:成品,2:半成品&半制品,3:原材料,4:包材&杂项))，请检查!'+@Enter
				RETURN -1
			END;
		END;

        EXEC @return_value=dbo.TxnBase_MLotOutCellCheck
                           @I_ReturnMessage=@I_ReturnMessage OUTPUT,
                           @I_OrBitUserId=@I_OrBitUserId,
                           @I_OrBitUserName=@I_OrBitUserName,
                           @I_ResourceId=@I_ResourceId,
                           @I_ResourceName=@I_ResourceName,
                           @I_PlugInCommand=@I_PlugInCommand,
                           @LotSN=@LotSN,
                           @BoxSN=N''
        IF @return_value=-1
        BEGIN
            SET @I_ReturnMessage=@I_ReturnMessage+@Enter
            RETURN -1
        END


		--插入数据到表中
		INSERT INTO dbo.ProductAllotTemp (ProductId, FromWareHouseId, FromWareHouseName,FromCellId, ToWareHouseId, ToWareHouseName,ToCellName, ProductName, LotSn,BoxSN, Qty,ProductClassify,AllotType, UserId, MetadataName)
		SELECT @ProductId, @FromWareHouseId, @FromFactoryName,CellId, @ToWareHouseId, @ToWareHouseName, @ToCellName,@ProductName,LotSn, @BoxSN,@Qty,@ProductClassify,@AllotType, @I_OrBitUserId, @I_PlugInCommand 
		FROM dbo.WW_RMInventory 
		WHERE BoxSN=@BoxSN AND Qty>0

	END 

	--返回网格数据
			SELECT 
				pat.ProductAllotTempId,
				pat.ProductName,
				pr.ProductDescription,
				pat.LotSn,
				pat.Qty,  -- 原始单行数量
				-- 核心：按ProductName分组计算汇总值（独立汇总，不影响其他列显示）
				SUM(pat.Qty) OVER (PARTITION BY pat.ProductName,pat.UserId) AS SummaryQty,
				CONCAT(fw.WorkcenterName, ' ', fw.WorkcenterDescription) AS FromWareHouseName,
				CONCAT(tw.WorkcenterName, ' ', tw.WorkcenterDescription) AS ToWareHouseName
			FROM dbo.ProductAllotTemp pat  -- 简化别名，提升可读性
			LEFT JOIN dbo.Product pr ON pr.ProductId = pat.ProductId
			LEFT JOIN dbo.Workcenter fw ON pat.FromWareHouseId = fw.WorkcenterId
			LEFT JOIN dbo.Workcenter tw ON pat.ToWareHouseId = tw.WorkcenterId
			WHERE 
				pat.FromWareHouseId = @FromWareHouseId 
				AND pat.ToWareHouseId = @ToWareHouseId 
				AND pat.UserId = @I_OrBitUserId
			-- 可选：按ProductName排序，让同产品的行相邻，汇总值更直观
			ORDER BY 
				pat.ProductName ASC,
				pat.LotSn ASC;  
		--返回提示
		SELECT '' AS LotOrBoxSN
		SET @I_ExceptionFieldName = 'LotOrBoxSN'
		SET @I_ReturnMessage='ServerMessage:扫描【'+@LotOrBoxSN+'】成功，请继续扫描小包/外箱！'+@Enter

		RETURN 0
	END;

	--点击提交调拨
	IF @I_Sender='ProductSubmitAllot'
	BEGIN
		--获取创建领料单所需数据（从A仓到B仓领料需求数量/可用库存）
		INSERT INTO @Temp_Picking(
			FromFactoryId,
			FromWareHouseId,
			ToFactoryId,
			ToWareHouseId,
			ProductId,
			ProductClassify,
			AllotQty
		)
		select @FromFactoryId AS TempFactoryId,pat.FromWareHouseId,@ToFactoryId AS ToFactoryId,ToWareHouseId,P.ProductId,P.ProductClassify,SUM(pat.Qty) AS AllotQty 
			FROM dbo.ProductAllotTemp pat
			INNER JOIN Product P ON pat.ProductId=P.ProductId
			where pat.FromWareHouseId = @FromWareHouseId 
				AND pat.ToWareHouseId = @ToWareHouseId 
				AND pat.UserId = @I_OrBitUserId
		group by pat.FromWareHouseId,ToWareHouseId,p.ProductId,p.ProductClassify

        IF (select count(1) from @Temp_Picking)=0
        BEGIN
            SET @I_ReturnMessage='ServerMessage:没有可调拨数据！'+@Enter
            return -1
        END


		--需求日期
		DECLARE @RequiredDate DATETIME= GETDATE()

		BEGIN transaction Request
		EXEC SysGetObjectPKId 'SOB1000000XC','ProductAllot',@IPKId OUTPUT
		set @ProductAllotId+=('['+ISNULL(cast(@IPKId as nvarchar(12)),'')+']')
		--调用仓库调拨单保存事件
		EXEC @RESULT= ProductAllotSaveData
		@I_ReturnMessage=@I_ReturnMessage OUTPUT,
		@I_OrBitUserId=@I_OrBitUserId,
		@I_OrBitUserName=@I_OrBitUserName,
		@I_PKId=@IPKId,
		@ProductAllotDescription=@ProductAllotDescription,
		@FromWareHouseId=@FromWareHouseId,
		@ToWareHouseId=@ToWareHouseId,
		@ToFactoryId=@ToFactoryId,
		@FromFactoryId=@FromFactoryId,
		@ProductAllotStates=10,
		@CreateUserName=@I_OrBitUserName,
		@CreateDate=@NowDate,
		@RequiredDate=@RequiredDate

				IF ISNULL(@RESULT,0)<>0
				BEGIN
					ROLLBACK transaction Request
					return -1
				END

				select top 1 @ProductAllotName=ISNULL(ProductAllotName,'') from ProductAllot where ProductAllotId=@IPKId


				IF ISNULL(@ProductAllotName,'')<>''
				BEGIN

					DECLARE AllotDetail CURSOR  for
					select allot.LineSequence,allot.ProductId,allot.AllotQty,PR.UsageUOMId from (SELECT ROW_NUMBER() OVER(ORDER BY ProductId) AS LineSequence,ProductId,
					SUM(AllotQty) AS AllotQty FROM (SELECT ProductId,AllotQty FROM @Temp_Picking
					where FromFactoryId=@FromFactoryId and FromWareHouseId=@FromWareHouseId and ToFactoryId=@ToFactoryId and ToWareHouseId=@ToWareHouseId-- AND ProductClassify=@ProductClassify
					AND AllotQty>0) AS T
					GROUP BY ProductId) as allot 
					LEFT JOIN Product PR on allot.ProductId=PR.ProductId

					OPEN AllotDetail
					FETCH NEXT FROM AllotDetail INTO @LineSequence,@ProductId,@AllotQty,@UsageUOMId
					WHILE @@FETCH_STATUS =0
					BEGIN
						IF @AllotQty>0
						BEGIN
							--生成仓库调拨单明细
							EXEC SysGetObjectPKId 'SOB1000000XD','ProductAllotItem',@ItemPKId OUTPUT
							INSERT INTO ProductAllotItem(
										ProductAllotItemId,
										ProductAllotId,
										ItemSequence,
										ProductId,
										AllotQty,
										RealAllotQty,
										ItemUOMId
								)VALUES(
										@ItemPKId,
										@IPKId,
										RIGHT('000'+CAST(@LineSequence AS VARCHAR),4),
										@ProductId,
										@AllotQty,
										@AllotQty,
										@UsageUOMId)

							--生成仓库调拨明细批号
							DECLARE AllotDetailLot CURSOR  for
							SELECT LotSn,BoxSN,Qty,FromCellId,AllotType FROM dbo.ProductAllotTemp WHERE FromWareHouseId=@FromWareHouseId AND ProductId=@ProductId AND ToWareHouseId=@ToWareHouseId AND UserId=@I_OrBitUserId

							OPEN AllotDetailLot
							FETCH NEXT FROM AllotDetailLot INTO @LotSn1,@BoxSN1,@Qty1,@FromCellId1,@AllotType
							WHILE @@FETCH_STATUS =0
							BEGIN
                                    -- =============================================
									-- 【出库策略检查】生成调拨明细批号前，逐批号调用物料出库策略检查(先进先出/超期等)
									-- 说明：任一批号检查不通过，则回滚整单事务并返回 -1，不允许生成调拨单
									-- =============================================
									SET @return_value=0  -- 每轮先重置返回值，避免上一行的检查结果串扰当前行

									-- 非空检查：批号为空则不参与出库策略检查
									IF ISNULL(@LotSn1,'')<>''
									BEGIN
										-- 物料出库策略检查：先进先出(FIFO)以及超期检查；此处按批号检查，箱号传空
										EXEC @return_value=dbo.TxnBase_MLotOutCellCheck
											@I_ReturnMessage=@I_ReturnMessage OUTPUT, -- 返回信息
											@I_OrBitUserId=@I_OrBitUserId,           -- 用户ID
											@I_OrBitUserName=@I_OrBitUserName,       -- 用户名
											@I_ResourceId=@I_ResourceId,             -- 资源ID
											@I_ResourceName=@I_ResourceName,         -- 资源名
											@I_PlugInCommand=@I_PlugInCommand,       -- 插件命令
											@LotSN=@LotSn1,                          -- 待出库批号
											@BoxSN=N''                               -- 箱号传空
									END

									-- 边界处理：检查不通过(返回-1)则关闭游标、回滚事务并直接返回
									IF ISNULL(@return_value,0)=-1
									BEGIN
										CLOSE AllotDetailLot
										DEALLOCATE AllotDetailLot
										CLOSE AllotDetail
										DEALLOCATE AllotDetail

										SELECT '' AS LotOrBoxSN
										SET @I_ReturnMessage=@I_ReturnMessage+@Enter
										ROLLBACK transaction Request
										RETURN -1
									END

                                    
									EXEC SysGetObjectPKId '','ProductAllotItemLot',@ItemPKIdLot OUTPUT
									INSERT INTO dbo.ProductAllotItemLot
									(
									    ProductAllotItemLotId,
									    ProductAllotItemId,
									    LotSN,
									    BoxSN,
									    Qty,
									    CellId,
									    ToCellId,
									    IsAEScan,
									    AllotType,
									    CreateUserId,
									    CreateDate,
									    IsAOScan,
									    ToLotSN,
									    MOProductionLotId
									)
									VALUES
									(   @ItemPKIdLot, -- ProductAllotItemLotId - char(12)
									    @ItemPKId,    -- ProductAllotItemId - char(12)
									    @LotSn1,    -- LotSN - nvarchar(50)
									    @BoxSN1,    -- BoxSN - nvarchar(50)
									    @Qty1, -- Qty - decimal(18, 6)
									    @FromCellId1,    -- CellId - char(12)
									    NULL,    -- ToCellId - char(12)
									    1, -- IsAEScan - bit
									    @AllotType,    -- AllotType - char(1)
									    @I_OrBitUserId,    -- CreateUserId - char(12)
									    GETDATE(), -- CreateDate - datetime
									    DEFAULT, -- IsAOScan - bit
									    1,    -- ToLotSN - nvarchar(50)
									    NULL     -- MOProductionLotId - char(12)
									    )

                                    --更新库存表为已发料
                                    UPDATE dbo.WW_RMInventory SET 
                                        LotStatus='9',
                                        ModifyDate=GETDATE()
                                    WHERE LotSN=@LotSn1

									FETCH NEXT FROM AllotDetailLot INTO @LotSn1,@BoxSN1,@Qty1,@FromCellId1,@AllotType
							END
							CLOSE AllotDetailLot --关闭游标
							DEALLOCATE AllotDetailLot --释放游标
						END


						FETCH NEXT FROM  AllotDetail INTO @LineSequence,@ProductId,@AllotQty,@UsageUOMId
						END
					CLOSE AllotDetail --关闭游标
					DEALLOCATE AllotDetail --释放游标

					UPDATE ProductAllot SET ProductAllotStates='20',ApproveDate=@NowDate,ApproveUserId=@I_OrBitUserId where ProductAllotId=@IPKId

					COMMIT transaction Request -- 提交事务

                        --20260707 分散调拨不再由仓库过账，由车间人员过账
                        --20260722 增加活性
                        IF EXISTS ( select 1 from Workcenter where WorkcenterId=@ToWareHouseId and WorkcenterName  in('LFS1','LFS2','LYM1','LYM2','HXXB','XBH1','XBH2','XBH3','SXXB','UVXB'))
                        --20260910全是半成品则不需要确认
                        AND EXISTS (select 1 from  ProductAllotItem a 
                        JOIN product b on a.ProductId=b.ProductId
                        where ProductAllotId=@IPKId and b.ProductClassify<>2)
                        BEGIN
                            DELETE FROM dbo.ProductAllotTemp WHERE FromWareHouseId = @FromWareHouseId AND ToWareHouseId = @ToWareHouseId AND UserId = @I_OrBitUserId
                            SET @I_ReturnMessage='请让车间人员在车间调拨扫描中点击过账！'+@Enter
                            --返回
                            IF @I_PlugInCommand='PAFSC'
                            BEGIN
                            	SELECT '' AS ProductName, '' AS ProductDescription, '' AS LotSn, NULL AS Qty, NULL AS SummaryQty, '' AS FromWareHouseName, '' AS ToWareHouseName
                            	SELECT '' AS LotOrBoxSN
                            	SET @I_ExceptionFieldName = 'LotOrBoxSN'
                            END;
                            return 0
                        END
                        --调用统一确认接口
                        EXEC @return_value=dbo.TxnBase_MBill_ProductAllotConfirm
                        @I_Sender=@I_Sender,
                        @I_ReturnMessage=@I_ReturnMessage OUTPUT, -- nvarchar(max)
                        @I_PlugInCommand=@I_PlugInCommand,
                        @I_OrBitUserId=@I_OrBitUserId,
                        @I_OrBitUserName=@I_OrBitUserName,
                        @I_ResourceId=@I_ResourceId,
                        @I_ResourceName=@I_ResourceName,
                        @I_Parameter=@I_Parameter,
                        @ProductAllotName=@ProductAllotName,
                        @I_PKid=@IPKId
                        IF @return_value<>0
                        BEGIN
                            DELETE FROM dbo.ProductAllotTemp WHERE FromWareHouseId = @FromWareHouseId AND ToWareHouseId = @ToWareHouseId AND UserId = @I_OrBitUserId
                            SET @I_ReturnMessage=@I_ReturnMessage+'请到【仓库调拨单】页面重新点击过账！'+@Enter
                            --返回
                            IF @I_PlugInCommand='PAFSC'
                            BEGIN
                                SELECT '' AS ProductName, '' AS ProductDescription, '' AS LotSn, NULL AS Qty, NULL AS SummaryQty, '' AS FromWareHouseName, '' AS ToWareHouseName
                                SELECT '' AS LotOrBoxSN
                                SET @I_ExceptionFieldName = 'LotOrBoxSN'
                            END;
                            RETURN @return_value
                        END
                        ELSE
                        BEGIN
                            DELETE FROM dbo.ProductAllotTemp WHERE FromWareHouseId = @FromWareHouseId AND ToWareHouseId = @ToWareHouseId AND UserId = @I_OrBitUserId
                            
                            --返回
                            IF @I_PlugInCommand='PAFSC'
                            BEGIN
                                SELECT '' AS ProductName, '' AS ProductDescription, '' AS LotSn, NULL AS Qty, NULL AS SummaryQty, '' AS FromWareHouseName, '' AS ToWareHouseName
                                SELECT '' AS LotOrBoxSN
                                SET @I_ExceptionFieldName = 'LotOrBoxSN'
                            END;
                            RETURN 0
                        END;
                        
                    
                    
				END
	END

	RETURN 0
		
END
GO
