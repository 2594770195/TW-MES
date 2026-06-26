SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		<OrBit Team Orbchay>
-- Create Date: <2020.05.07>
-- Description:	PDA 杂发单领料-自动创建杂发单
-- Version: 12
-- =============================================
CREATE PROCEDURE  [dbo].[PDA_PickingListOtherQuery_NEW]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT, --向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId CHAR(12)='',			--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKid CHAR(12) ='',				--主键
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(MAX)='',  		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@FromWareHouseId CHAR(12)='',
@FromWareHouseName NVARCHAR(100)='',
@BoxOrLotSN NVARCHAR(100)='',
@Grid_PickinglistItem char(12)='',
@CostCenterId NVARCHAR(50)='',
@CostCenterName NVARCHAR(50)='',
@PickingQty FLOAT=0,
@PickingUser  NVARCHAR(50)='',
@OrderName  NVARCHAR(50)=''


AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	--通用
	DECLARE @return_value INT=-1
	DECLARE @Enter NVARCHAR(100)=CHAR(13)+CHAR(10)
	DECLARE @CurDate DATE=GETDATE()
	--bill
	--通用
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

	declare @QtyZero decimal(18, 8)=0.0
	DECLARE @ItemPKId CHAR(12)=''
	DECLARE @ItemPKIdLot CHAR(12)=''
	DECLARE @PickingListOtherName NVARCHAR(16)
	DECLARE @ProductClassifyTemp CHAR(10)=''
	DECLARE @PickingListOtherItemId CHAR(12)=''



    DECLARE @Grid_PickinglistItemId Int =0 
    IF ISNULL(@Grid_PickinglistItem,'')<>''
    BEGIN
        Set @Grid_PickinglistItemid=(SELECT CAST(CAST(@Grid_PickinglistItem AS DECIMAL(10,2)) AS INT))
    END
    -- ============================ 2026年1月16日 15:14:25  截取箱号（防止录错）      ==============================================----
        SET @BoxOrLotSN = LEFT(@BoxOrLotSN, CHARINDEX('+', @BoxOrLotSN + '+') - 1)
    -- ============================ 2026年1月16日 15:14:29  截取箱号（防止录错）      ==============================================----


    DECLARE @LotSn1 NVARCHAR(50)='',@BoxSN1 NVARCHAR(50)='',@Qty1 NVARCHAR(50)='',@FromCellId1 CHAR(12)='',@AllotType CHAR(1)=''

    DECLARE @RESULT INT=0,@PickingListOtherDescription NVARCHAR(50)='多工单合并发料',
	@NowDate datetime =getdate(),@NewSN nvarchar(256)='',@MOId char(12),@PickingListOtherId nvarchar(256)='',@ProductClassify char(10)
	,@AllotQty decimal(18,8),@WQty DECIMAL(18,8),@UsageUOMId char(12),@LineSequence INT

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


	-- IF @FromWareHouseName IS NULL OR @FromWareHouseName =''
	-- BEGIN
	-- 	SET @I_ExceptionFieldName = 'FromWareHouseName'
	-- 	SET @I_ReturnMessage='ServerMessage:原仓库不能为空！'+@Enter
	-- 	RETURN -1
	-- END
    -- SELECT @FromFactoryId=Factory.FactoryId,@FromFactoryName=FactoryName FROM dbo.Workcenter 
    -- INNER JOIN dbo.Factory ON Factory.FactoryId = Workcenter.FactoryID WHERE WorkCenterID=@FromWareHouseId


    --************begin 查询界面 begin******************
	IF @I_Sender='Get_Bill'
	BEGIN
			--返回网格数据
			SELECT 
				plt.PickingListOtherTempId,
				plt.ProductName,
				pr.ProductDescription,
				plt.LotSn,
				plt.Qty,  -- 原始单行数量
				-- 核心：按ProductName分组计算汇总值（独立汇总，不影响其他列显示）
				SUM(plt.Qty) OVER (PARTITION BY plt.ProductId,plt.UserId) AS SummaryQty,
				CONCAT(fw.WorkcenterName, ' ', fw.WorkcenterDescription) AS FromWareHouseName
			FROM dbo.PickingListOtherTemp plt  -- 简化别名，提升可读性
			LEFT JOIN dbo.Product pr ON pr.ProductId = plt.ProductId
			LEFT JOIN dbo.Workcenter fw ON plt.FromWareHouseId = fw.WorkcenterId
			WHERE 
				--plt.FromWareHouseId = @FromWareHouseId  AND --20260513 不限制从同一个仓库杂发
                plt.UserId = @I_OrBitUserId
			-- 可选：按ProductName排序，让同产品的行相邻，汇总值更直观
			ORDER BY 
				plt.ProductName ASC,
				plt.LotSn ASC;  
		--返回提示
		-- SELECT '' AS BoxOrLotSN
		-- SET @I_ExceptionFieldName = 'BoxOrLotSN'
		--SET @I_ReturnMessage='ServerMessage:请扫描小包/外箱！'+@Enter
		RETURN 0
	END

	-- SET @I_ExceptionFieldName = 'BoxOrLotSN'
	--************end 扫描界面 end*******************

    
	--************begin 删除批号 begin******************
	IF @I_Sender='DeleteLotSn'
	BEGIN
 			IF @Grid_PickinglistItemid=0
			BEGIN
				SET @I_ReturnMessage='ServerMessage:请选择有效的删除数据，选中表格对应行！'+@Enter
				RETURN -1
			END

			DELETE FROM dbo.PickingListOtherTemp WHERE PickingListOtherTempId=@Grid_PickinglistItemid
            
			--返回网格数据
			SELECT 
				plt.PickingListOtherTempId,
				plt.ProductName,
				pr.ProductDescription,
				plt.LotSn,
				plt.Qty,  -- 原始单行数量
				-- 核心：按ProductName分组计算汇总值（独立汇总，不影响其他列显示）
				SUM(plt.Qty) OVER (PARTITION BY plt.ProductId,plt.UserId) AS SummaryQty,
				CONCAT(fw.WorkcenterName, ' ', fw.WorkcenterDescription) AS FromWareHouseName
			FROM dbo.PickingListOtherTemp plt  -- 简化别名，提升可读性
			LEFT JOIN dbo.Product pr ON pr.ProductId = plt.ProductId
			LEFT JOIN dbo.Workcenter fw ON plt.FromWareHouseId = fw.WorkcenterId
			WHERE 
				--plt.FromWareHouseId = @FromWareHouseId  AND 
                plt.UserId = @I_OrBitUserId
			-- 可选：按ProductName排序，让同产品的行相邻，汇总值更直观
			ORDER BY 
				plt.ProductName ASC,
				plt.LotSn ASC;  
		--返回提示
		SELECT '' AS BoxOrLotSN
		SET @I_ExceptionFieldName = 'BoxOrLotSN'
		SET @I_ReturnMessage='ServerMessage:删除批号成功！'+@Enter
		RETURN 0
	END

	SET @I_ExceptionFieldName = 'BoxOrLotSN'
	--************end 删除批号 end*******************
    IF @I_Sender='PickingListScan'
	BEGIN
		--****************【 1.扫描物料条码 】*****************
		IF ISNULL(@BoxOrLotSN,'')=''
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:请扫描物料批次!'+@Enter
			RETURN -1
		END
    
		--检查是否小包或者外箱
		IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@BoxOrLotSN)
		BEGIN 
			SET @LotType='R'
			SET @LotTypeDesc='物料小包'
			SET @InObject='Lot'
		END

		IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN=@BoxOrLotSN)
		BEGIN 
			SET @LotType='B'
			SET @LotTypeDesc='物料箱号' 
			SET @InObject='Box'
		END

		IF @LotType NOT IN ('R','B')
		BEGIN
			--SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:请扫描有效的小包/外箱条码!'+@Enter
			RETURN -1
		END

	    --按小包扫描
        IF @LotType='R'
        BEGIN
            SET @LotSN=@BoxOrLotSN
            SET @AllotType=@LotType

            IF NOT EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN = @LotSN)
            BEGIN
                --SELECT '' AS BoxOrLotSN
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

            -- IF ISNULL(@FromWareHouseId,'')=''
            -- Select @FromWareHouseId=Workcenter.WorkcenterId ,@FromWareHouseName=Workcenter.WorkcenterName
            -- FROM dbo.WW_RMInventory 
            -- LEFT JOIN Workcenter on WW_RMInventory.WorkcenterId=Workcenter.WorkcenterId WHERE LotSN=@LotSN 

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
                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】不在库存中，不可操作!'+@Enter
                RETURN -1
            END

            IF ISNULL(@LotStatus,'')<>'1'
            BEGIN
                --WES WW_RMInventory LotStatus/库存表状态信息:URC100000AA9
                SELECT @LotStatusDesc=UserCodeDescription
                FROM dbo.UserCode
                WHERE ParentUserCodeId='URC100000AA9' AND UserCodeName=@LotStatus

                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】当前状态['+@LotStatusDesc+']，不可操作!'+@Enter
                RETURN -1
            END

            IF ISNULL(@LotQty,0)<=0
            BEGIN
                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】可用数量已为零，不可操作!'+@Enter
                RETURN -1
            END

            -- IF ISNULL(@FromWareHouseId,'')<>'' AND  ISNULL(@LotWorkcenterId,'')<>ISNULL(@FromWareHouseId,'')
            -- BEGIN
            --     --SELECT '' AS BoxOrLotSN
            --     SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】所属仓库【'+ISNULL(@LotWorkcenterName,'')+'】，'
            --         +CHAR(13)+CHAR(10)+'当前要求从原仓库【'+@FromWareHouseName+'】进行杂发，请确认!'+@Enter
            --     RETURN -1
            -- END

            --检查本次扫描中是否已经存在
            IF EXISTS (SELECT 1 FROM dbo.PickingListOtherTemp WHERE --FromWareHouseId=@FromWareHouseId  AND 
            LotSN=@LotSN AND UserId=@I_OrBitUserId)
            BEGIN
                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+ '】已扫描，不需要重复操作!'+@Enter
                RETURN -1
            END

            --不能是成品
            IF @ProductClassify = '1'
            BEGIN
                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+ '】是成品，不能使用杂发功能!'+@Enter
                RETURN -1
            END

            --不能是同一个物料，如果有同一个物料，后续调用杂发下架的时候因为明细合并导致不知道每个批号用多少
            IF EXISTS(select 1 from PickingListOtherTemp where productid=@ProductId   AND UserId=@I_OrBitUserId)
            BEGIN
                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:已存在相同物料，如需进行同一物料多个批次的杂发请分别确认!'+@Enter
                RETURN -1
            END

            -- IF @Grid_PickinglistItemid<>0
            -- BEGIN
            --     SELECT @ProductClassifyTemp=ProductClassify FROM dbo.PickingListOtherTemp WHERE PickingListOtherTempid=@Grid_PickinglistItemid
            --     IF ISNULL(@ProductClassifyTemp,'')<>'' AND @ProductClassifyTemp<>@ProductClassify
            --     BEGIN
            --         SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+'】中的产品分类是【'+@ProductClassify+'】与已扫描物料的产品分类【'+@ProductClassifyTemp+'】不一致！(产品分类 (1:成品,2:半成品&半制品,3:原材料,4:包材&杂项))，请检查!'+@Enter
            --         RETURN -1
            --     END;
            -- END;
            IF @PickingQty=0 OR @PickingQty>@LotQty
            BEGIN
                SELECT  '' AS PickingQty
                SET @I_ExceptionFieldName = 'PickingQty'
                SET @I_ReturnMessage='ServerMessage:请输入杂发数量，当前批号【'+@LotSN+'】库存数量为：【'+CAST(@LotQty as nvarchar(20))+'】，领料数量不能超过批次数量!'+@Enter
                RETURN 0
            END
            -- --插入数据到表中
            INSERT INTO dbo.PickingListOtherTemp (ProductId, FromWareHouseId, FromWareHouseName, ProductName, LotSn,BoxSN, Qty,ProductClassify,AllotType, UserId, MetadataName,CostCenterId,PickingUser)
            VALUES (@ProductId, @LotWorkcenterId, @FromFactoryName,@ProductName, @LotSN, @BoxSN,@PickingQty,@ProductClassify,@AllotType, @I_OrBitUserId, @I_PlugInCommand,@CostCenterId,@PickingUser);
            SET @I_ReturnMessage='ServerMessage:添加物料成功!'+@Enter

            SELECT '' AS BoxOrLotSN, '' AS PickingQty, @FromWareHouseId AS FromWareHouseId,@FromWareHouseName AS FromWareHouseId

        END
        --检查箱号基本信息，取得箱号中批号插入临时表
        IF @LotType='B'
        BEGIN
            SET @BoxSN=@BoxOrLotSN
            SET @AllotType=@LotType

            IF NOT EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN = @BoxSN)
            BEGIN
                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:物料箱号【'+@BoxSN+'】无效，请确认!'+@Enter
                RETURN -1
            END

            --是否存在出库的批号
            IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN = @BoxSN AND IsStorage=0 AND Qty>0)
            BEGIN
                --SELECT '' AS BoxOrLotSN
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

                --SELECT '' AS BoxOrLotSN
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

            IF @PickingQty=0 OR @PickingQty>@Qty
            BEGIN
                SELECT  0 AS PickingQty
                SET @I_ReturnMessage='ServerMessage:请输入杂发数量，当前批号库存数量为：【'+@Qty+'】!'+@Enter
                RETURN 0
            END


            --查找产品相关信息
            SELECT 
                @ProductName=ProductName
            FROM dbo.Product
            INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
            WHERE ProductId= @ProductId

            -- 检查物料批号剩余数是否大于零
            IF CAST(ISNULL(@Qty,0) AS DECIMAL(18,8)) <= 0
            BEGIN
                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:物料外箱【'+@BoxSN+'] 剩余数量 '+CAST(@Qty AS VARCHAR) +' 已为零，无法操作 !'+@Enter
                RETURN -1
            END

            --检查是否有工厂、产品、仓库、储位是否一致
            IF (SELECT ISNULL(SUM(Qty),0) FROM dbo.WW_RMInventory WHERE BoxSN=@BoxSN)<>CAST(@Qty AS DECIMAL(18,6))
            BEGIN
                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:物料外箱【'+@BoxOrLotSN+'】已经拆过箱了，里面的单批号信息存在不一致的情况，请按小包调拨 !'+@Enter
                RETURN -1
            END

            IF ISNULL(@FromFactoryId,'')<>'' AND  ISNULL(@LotFactoryId,'')<>ISNULL(@FromFactoryId,'')
            BEGIN
                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:物料外箱【'+@BoxSN+'】所属工厂【'+ISNULL(@LotFatoryName,'')+'】，'
                    +CHAR(13)+CHAR(10)+'当前调拨单要求从原工厂【'+@FromFactoryName+'】进行调拨，请确认!'+@Enter
                RETURN -1
            END

            -- IF ISNULL(@LotWorkcenterId,'')<>ISNULL(@FromWareHouseId,'')
            -- BEGIN
            --     SELECT '' AS BoxOrLotSN
            --     SET @I_ReturnMessage = 'ServerMessage:箱号【'+@BoxSN+'】不属于原仓库【'+@FromFactoryName+']，请确认!'+@Enter
            --     RETURN -1
            -- END
            
            --不能是成品
            IF @ProductClassify='1'
            BEGIN
                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:物料批号【'+@LotSN+ '】是成品，不能使用调拨功能!'+@Enter
                RETURN -1
            END

            --取得批号基本信息插入临时表
            INSERT INTO @LotTemp(ProductId,CellId,LotSN,Qty,BoxSN,ItemUOMId)
            SELECT ProductId,CellId,LotSN,@PickingQty,BoxSN,UOMId 
            FROM dbo.WW_RMInventory 
            WHERE BoxSN=@BoxSN AND Qty>0

            --检查本次扫描调拨单中是否已经存在
            IF EXISTS (SELECT 1 FROM dbo.PickingListOtherTemp
            INNER JOIN @LotTemp a ON a.LotSN = PickingListOtherTemp.LotSN
            WHERE --FromWareHouseId=@FromWareHouseId  AND 
            A.LotSN=@LotSN AND UserId=@I_OrBitUserId)
            BEGIN
                SET @LotSN=''

                SELECT @LotSN=PickingListOtherTemp.LotSN 
                FROM dbo.PickingListOtherTemp
                INNER JOIN @LotTemp a ON a.LotSN = PickingListOtherTemp.LotSN
                WHERE --FromWareHouseId=@FromWareHouseId  AND 
                A.LotSN=@LotSN AND UserId=@I_OrBitUserId

                --SELECT '' AS BoxOrLotSN
                SET @I_ReturnMessage = 'ServerMessage:箱号【'+@BoxSN+'】中的物料批号【'+@LotSN+ '】在当前已扫描，不需要重复操作!'+@Enter
                RETURN -1
            END

            IF @Grid_PickinglistItemid<>0
            BEGIN
                
                SELECT @ProductClassifyTemp=ProductClassify FROM dbo.PickingListOtherTemp WHERE PickingListOtherTempid=@Grid_PickinglistItemid
                IF ISNULL(@ProductClassifyTemp,'')<>'' AND @ProductClassifyTemp<>@ProductClassify
                BEGIN
                    SET @I_ReturnMessage = 'ServerMessage:箱号【'+@BoxSN+'】中的产品分类是【'+@ProductClassify+'】与已扫描物料的产品分类【'+@ProductClassifyTemp+'】不一致！(产品分类 (1:成品,2:半成品&半制品,3:原材料,4:包材&杂项))，请检查!'+@Enter
                    RETURN -1
                END;
            END;


            --插入数据到表中
            INSERT INTO dbo.PickingListOtherTemp (ProductId, FromWareHouseId, FromWareHouseName,ProductName, LotSn,BoxSN, Qty,ProductClassify,AllotType, UserId, MetadataName,CostCenterId,PickingUser)
            SELECT @ProductId, @LotWorkcenterId, @FromFactoryName,@ProductName,LotSn, @BoxSN,@PickingQty,@ProductClassify,@AllotType, @I_OrBitUserId, @I_PlugInCommand,@CostCenterId ,@PickingUser
            FROM dbo.WW_RMInventory 
            WHERE BoxSN=@BoxSN AND Qty>0
            SET @I_ReturnMessage='ServerMessage:添加物料成功!'+@Enter

        END 
        --返回网格数据
		-- SELECT 
		-- 	plt.PickingListOtherTempId,
		-- 	plt.ProductName,
		-- 	pr.ProductDescription,
		-- 	plt.LotSn,
		-- 	plt.Qty,  -- 原始单行数量
		-- 	-- 核心：按ProductName分组计算汇总值（独立汇总，不影响其他列显示）
		-- 	SUM(plt.Qty) OVER (PARTITION BY plt.ProductId,plt.UserId) AS SummaryQty,
		-- 	CONCAT(fw.WorkcenterName, ' ', fw.WorkcenterDescription) AS FromWareHouseName
		-- FROM dbo.PickingListOtherTemp plt  -- 简化别名，提升可读性
		-- LEFT JOIN dbo.Product pr ON pr.ProductId = plt.ProductId
		-- LEFT JOIN dbo.Workcenter fw ON plt.FromWareHouseId = fw.WorkcenterId
		-- WHERE 
		-- 	plt.FromWareHouseId = @FromWareHouseId 
		-- 	AND plt.UserId = @I_OrBitUserId
		-- -- 可选：按ProductName排序，让同产品的行相邻，汇总值更直观
		-- ORDER BY 
		-- 	plt.ProductName ASC,
		-- 	plt.LotSn ASC;  
        
    end
    --创建杂发单并过账
	IF @I_Sender='PickingListConfirm'
	BEGIN
        
		--获取创建领料单所需数据（从A仓到B仓领料需求数量/可用库存）
		INSERT INTO @Temp_Picking(
			
			FromWareHouseId,
			ProductId,
			ProductClassify,
			AllotQty
		)
		select pat.FromWareHouseId,P.ProductId,P.ProductClassify,SUM(pat.Qty) AS AllotQty 
			FROM dbo.PickingListOtherTemp pat
			INNER JOIN Product P ON pat.ProductId=P.ProductId
			where-- pat.FromWareHouseId = @FromWareHouseId   
            pat.UserId = @I_OrBitUserId
		group by pat.FromWareHouseId,p.ProductId,p.ProductClassify

        SELECT top 1 @FromFactoryId=Workcenter.FactoryId FROM @Temp_Picking pat
        left join Workcenter on Workcenter.WorkcenterId=pat.FromWareHouseId


		BEGIN transaction Request
		EXEC SysGetObjectPKId '','PickingList',@IPKId OUTPUT
        DECLARE @RequiredDate DATETIME= GETDATE()
        declare @DivisionId CHAR(12) 
        select @DivisionId=Division from sysuser where UserId=@I_OrBitUserId
		--调用领料单保存事件
        declare @PickingListDescription NVARCHAR(100) = 'PDA 研发杂发 领料人：' + ISNULL(@PickingUser, '')
		EXEC @RESULT= PickingListOtherSaveData
		@I_ReturnMessage=@I_ReturnMessage OUTPUT,
		@I_OrBitUserId=@I_OrBitUserId,
		@I_OrBitUserName=@I_OrBitUserName,
		@I_PKId=@IPKId,
        @PickingListDescription= @PickingListDescription,
        @FactoryId=@FromFactoryId,
        @DateRequired=@RequiredDate,
        @DivisionId=@DivisionId--,
        --@ToWorkcenterId=@FromWareHouseId
        UPDATE PickingList SET PickingListStates='20',ApproveDate=@NowDate,ApproveUserId=@I_OrBitUserId where PickingListId=@IPKId

        IF ISNULL(@RESULT,0)<>0
		BEGIN
			ROLLBACK transaction Request
			return -1
		END
        select top 1 @PickingListOtherName=ISNULL(PickingListName,'') from PickingList where PickingListid=@IPKId

		IF ISNULL(@PickingListOtherName,'')<>''
		BEGIN
			DECLARE OtherDetail CURSOR  for
			select allot.LineSequence,allot.ProductId,allot.AllotQty,PR.UsageUOMId from (SELECT ROW_NUMBER() OVER(ORDER BY ProductId) AS LineSequence,ProductId,
					SUM(AllotQty) AS AllotQty FROM (SELECT ProductId,AllotQty FROM @Temp_Picking
					where --FromFactoryId=@FromFactoryId  and FromWareHouseId=@FromWareHouseId AND 
                    AllotQty>0) AS T
					GROUP BY ProductId) as allot 
					LEFT JOIN Product PR on allot.ProductId=PR.ProductId
            OPEN OtherDetail
			FETCH NEXT FROM OtherDetail INTO @LineSequence,@ProductId,@AllotQty,@UsageUOMId
                WHILE @@FETCH_STATUS =0
                BEGIN

                    IF @AllotQty>0
                    BEGIN
                        --生成杂发单明细
						EXEC SysGetObjectPKId '','PickingListItem',@ItemPKId OUTPUT
                        INSERT INTO dbo.PickingListItem(
                            PickingListItemId,
                            PickingListId,
                            ItemSequence ,
                            ProductId,
                            QtyRequired,
                            --WorkcenterId,
                            UOMId,
                            CostCenterId,
                            OrderName
                            )
                        VALUES(
                            @ItemPKId,
							@IPKId,
							RIGHT('000'+CAST(@LineSequence AS VARCHAR),4),
                            @ProductId,
                            @AllotQty,
                            --@FromWareHouseId,
                            @UsageUOMId,
                            @CostCenterId,
                            @OrderName
                        )
                        

                        --生成仓库调拨明细批号
						DECLARE OtherDetailLot CURSOR  for
						SELECT LotSn,BoxSN,Qty,AllotType FROM dbo.PickingListOtherTemp WHERE --FromWareHouseId=@FromWareHouseId AND 
                        ProductId=@ProductId AND UserId=@I_OrBitUserId
						OPEN OtherDetailLot
						FETCH NEXT FROM OtherDetailLot INTO @LotSn1,@BoxSN1,@Qty1,@AllotType
						WHILE @@FETCH_STATUS =0
						BEGIN
								-- EXEC SysGetObjectPKId '','PickingListItemLot',@ItemPKIdLot OUTPUT
								-- INSERT INTO dbo.PickingListItemLot( 
			                    -- 	PickingListItemLotId ,
			                    -- 	PickingListItemId ,
			                    -- 	ProductId ,
			                    -- 	LotSN ,
			                    -- 	Qty ,
			                    -- 	PickType,
			                    -- 	CreateUserId,
			                    -- 	CreateDate
			                    -- 	)
			                    -- VALUES ( 
			                    -- 	@ItemPKIdLot ,
			                    -- 	@ItemPKId,
			                    -- 	@ProductId,
			                    -- 	@LotSn1,
			                    -- 	ISNULL(@Qty1,0),
			                    -- 	@LotType,
			                    -- 	@I_OrBitUserId,
			                    -- 	GETDATE()
			                    -- 	)
                                -- --插入物料批号追踪表
                                -- EXEC dbo.TxnBase_MLotTrack
                                --     @I_OrBitUserId =@I_OrBitUserId, -- char(12)
                                --     @I_PlugInCommand=@I_PlugInCommand,
                                --     @I_ResourceId =@I_ResourceId, -- char(12)
                                --     @LotSN = @LotSn1, -- nvarchar(50) --物料批号
                                --     @LotQty = @Qty1, -- decimal(18, 6)--数量
                                --     @TxnCode ='M-杂发下架' , -- nvarchar(50) --事务码
                                --     @OrderName =@PickingListOtherName , -- nvarchar(50) --单据号
                                --     @Remark = N'' -- nvarchar(200) --备注

                                -- UPDATE dbo.PickingListItem SET 
                                --     QtyIssued =ISNULL( QtyIssued,0) + ISNULL(@Qty1,0)
                                -- WHERE PickingListItemId = @ItemPKId


                                --杂发下架
                                EXEC @RESULT= PDA_MaterialToPickingListOther
                                @I_ReturnMessage=@I_ReturnMessage OUTPUT,
                                @I_OrBitUserId=@I_OrBitUserId,
                                @I_OrBitUserName=@I_OrBitUserName,
                                @I_PKId=@IPKId,
                                @PickingListName=@PickingListOtherName,
                                @BoxOrLotSN=@LotSn1

								FETCH NEXT FROM OtherDetailLot INTO @LotSn1,@BoxSN1,@Qty1,@AllotType
						END
						CLOSE OtherDetailLot --关闭游标
						DEALLOCATE OtherDetailLot --释放游标

                    END
                    FETCH NEXT FROM OtherDetail INTO @LineSequence,@ProductId,@AllotQty,@UsageUOMId
                END
			CLOSE OtherDetail --关闭游标
			DEALLOCATE OtherDetail --释放游标
            COMMIT transaction Request -- 提交事务

            DELETE FROM dbo.PickingListOtherTemp WHERE  UserId = @I_OrBitUserId

            --调用领料单统一确认接口
            EXEC @return_value=dbo.TxnBase_MBill_PickingListConfirm
                @I_Sender=@I_Sender,
                @I_ReturnMessage=@I_ReturnMessage OUTPUT,
                @I_PlugInCommand=@I_PlugInCommand,
                @I_OrBitUserId=@I_OrBitUserId,
                @I_OrBitUserName=@I_OrBitUserName,
                @I_ResourceId=@I_ResourceId,
                @I_ResourceName=@I_ResourceName,
                @I_Parameter=@I_Parameter,
                @PickingListName=@PickingListOtherName
            IF @return_value<>0
            BEGIN
                SET @I_ReturnMessage=@I_ReturnMessage+'   请到【杂发单】页面重新点击过账！'+@Enter
                --返回
                IF @I_PlugInCommand='MPLOT'
                BEGIN
                    SELECT '' AS ProductName, '' AS ProductDescription, '' AS LotSn, NULL AS Qty, NULL AS SummaryQty, '' AS FromWareHouseName
                    SELECT '' AS LotOrBoxSN
                    SET @I_ExceptionFieldName = 'LotOrBoxSN'
                END
                RETURN @return_value
            END
            ELSE
            BEGIN
                
                --返回
                IF @I_PlugInCommand='MPLOT'
                BEGIN
                    SELECT '' AS ProductName, '' AS ProductDescription, '' AS LotSn, NULL AS Qty, NULL AS SummaryQty, '' AS FromWareHouseName
                    SELECT '' AS LotOrBoxSN
                    SET @I_ExceptionFieldName = 'LotOrBoxSN'
                END
                RETURN 0
            END;       
		END

	END

	RETURN 0


END
 












GO
