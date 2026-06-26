-- =============================================
-- Author:		<OrBit Team orbchay>
-- Create Date: <2019.04.15>
-- Description:	PDA 杂发单出库扫描
-- Version: 12
-- =============================================
CREATE PROC [dbo].[PDA_MaterialToPickingListOther]
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

@PickingListName NVARCHAR(50)='',      --杂发单
@BoxOrLotSN NVARCHAR(100)=''            --最小包/外箱 SN

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @return_value INT=-1
	DECLARE @Enter VARCHAR(2)=CHAR(13)+CHAR(10)

	--杂发单信息
	DECLARE @DivisionId CHAR(12)=''
	DECLARE @FactoryId CHAR(12)=''
	DECLARE @PickingListStates VARCHAR(20)=''
	DECLARE @PickingListClass VARCHAR(20)=''
	DECLARE @PickingListId CHAR(12)=''

	--杂发单行信息
	DECLARE @QtyRequired FLOAT=0
	DECLARE @QtyIssued FLOAT=0-- 已发数
	DECLARE @OweQty FLOAT=0 --欠料数
	DECLARE @PickingListItemId CHAR(12)=''
	DECLARE @ItemWarehouseId CHAR(12)=''
	DECLARE @ItemWarehouseName NVARCHAR(50)=''

	--杂发单明细批号
	DECLARE @PickingListItemLotId CHAR(12)=''

	--物料信息
	DECLARE @MLotSN NVARCHAR(100)=''
	DECLARE @MLotQty FLOAT=0
	DECLARE @LotStatus CHAR(1)=''
	DECLARE @LotStatusDesc NVARCHAR(50)=''
	DECLARE @LotProductId CHAR(12)=''
	DECLARE @LotProductName NVARCHAR(50)=''
	DECLARE @LotProductDescription NVARCHAR(500)=''
	DECLARE @WWId CHAR(12)=''
	DECLARE @WareHouseId CHAR(12)=''
	DECLARE @WarehouseName NVARCHAR(50)=''
	DECLARE @CellName NVARCHAR(50)=''
	DECLARE @CellId CHAR(12)=''
	DECLARE @IsExceedPicking BIT=0				-- 物料是否超发
	DECLARE @OutQty FLOAT=0  --当前批号或箱号的数量
	DECLARE @LotType CHAR(1)=''              --类别 R/B


	DECLARE @LotTemp TABLE(
		WWId CHAR(12),
		LotSN NVARCHAR(50),
		Qty FLOAT,
		ProductId CHAR(12),
		WarehouseId CHAR(12),
		CellId CHAR(12),
		LotUOMId CHAR(12)
	)
     -- ============================ 2026年1月16日 15:14:25  截取箱号（防止录错）      ==============================================----
       
            SET @BoxOrLotSN = LEFT(@BoxOrLotSN, CHARINDEX('+', @BoxOrLotSN + '+') - 1)
        -- ============================ 2026年1月16日 15:14:29  截取箱号（防止录错）      ==============================================----


	SET @I_ExceptionFieldName='BoxOrLotSN'

	--转换大写
	SET @BoxOrLotSN =UPPER(LTRIM(RTRIM(@BoxOrLotSN)))


	-- 检查杂发单好 
	IF  ISNULL(@PickingListName,'')=''
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'
		SET @I_ReturnMessage='ServerMessage:请选择杂发单号!'+@Enter

		SELECT '' AS PickingListName,'' AS BoxOrLotSN,
			   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
		RETURN -1
	END


	--检查杂发单号是否存在
	IF NOT EXISTS(SELECT 1 FROM dbo.PickingList WHERE PickingListName=@PickingListName)
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'
		SET @I_ReturnMessage='ServerMessage:杂发单号【'+@PickingListName+'】不存在，请检查!'+@Enter
		SELECT '' AS PickingListName,'' AS BoxOrLotSN,
			   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
		RETURN -1
	END

	--获取杂发单信息
	SELECT 
		@PickingListStates = PickingListStates,
		@PickingListClass=PickingListClass,
		@DivisionId=DivisionId,
		@FactoryId=FactoryId,
		@PickingListId=PickingListId
	FROM dbo.PickingList 
	WHERE PickingListName=@PickingListName

	IF ISNULL(@PickingListClass,'')<>'02'
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'
		SET @I_ReturnMessage='ServerMessage:该单据【'+@PickingListName+'】不是杂发单，不允许发料!'+@Enter
		SELECT '' AS BoxOrLotSN,
			   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
		RETURN -1   
	END 

	-- 检查领料是否有审核
	IF ISNULL(@PickingListStates,'')<>'20'
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'
		SET @I_ReturnMessage='ServerMessage:该杂发单【'+@PickingListName+'】不是 [已审核] 状态，不允许发料!'+@Enter
		SELECT '' AS BoxOrLotSN,
			   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
		RETURN -1
	END

	 
	-- 检查该杂发单是否存在杂发单物料明细
	IF NOT EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId = @PickingListId)
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'
		SET @I_ReturnMessage='ServerMessage:该杂发单【'+@PickingListName+'】的没有找到明细行项，不允许发料!'+@Enter
		SELECT '' AS BoxOrLotSN,
			   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
		RETURN -1
	END

	--一次性检查该发料单的明细行是否符合要求，因为同一个物料可能有多行。
	--IF EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId = @PickingListId AND ISNULL(WorkcenterId,'')='')
	--BEGIN 
	--	SET @I_ExceptionFieldName='PickingListName'
	--	SET @I_ReturnMessage='ServerMessage:该杂发单 ['+@PickingListName+'] 存在没有维护发料【仓库】的明细行项，不允许发料!'+@Enter
	--	SELECT '' AS BoxOrLotSN,
	--		   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
	--	RETURN -1 
	--END






	-- 检查是否扫描框是否为空
	IF ISNULL(@BoxOrLotSN,'') = ''
	BEGIN
		SET @I_ReturnMessage= 'ServerMessage:请扫描箱号或者小包条码!'+@Enter 
		SELECT '' AS BoxOrLotSN
		RETURN -1
	END

	--检查是否小包或者外箱
	IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@BoxOrLotSN)
		SET @LotType='R'

	IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN=@BoxOrLotSN)
		SET @LotType='B'

	-- 检查扫描批号有效性
	IF @LotType NOT IN ('R','B')
	BEGIN
		SELECT '' AS BoxOrLotSN
		SET @I_ReturnMessage='ServerMessage:请扫描有效的箱号或者小包条码!'+@Enter
		RETURN -1
	END

	--按箱号发料
	IF @LotType='B'
	BEGIN
		--检查外箱号是否存在
		IF NOT EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN=@BoxOrLotSN)
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage= 'ServerMessage:物料外箱【'+@BoxOrLotSN+'】在库存中不存在，请检查!'+@Enter
			RETURN -1
		END
		
		--检查外箱中是否有最小包已执行出库,1代表出库，0代表未出库
		IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN=@BoxOrLotSN AND IsStorage=0)
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage= 'ServerMessage:物料外箱【'+@BoxOrLotSN+'】已部分出库，请按小包批号执行仓库下架，请检查!'+@Enter
			RETURN -1
		END

		--检查批号状态
		IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN=@BoxOrLotSN AND LotStatus<>'1')
		BEGIN
			--WES WW_RMInventory LotStatus/库存表状态信息
			SELECT TOP 1 @LotStatus=LotStatus,
				@MLotSN=LotSN
			FROM dbo.WW_RMInventory WHERE BoxSN=@BoxOrLotSN  AND LotStatus<>'1'

			SELECT @LotStatusDesc=UserCodeDescription
			FROM dbo.UserCode
			WHERE ParentUserCodeId='URC100000AA9' AND UserCodeName=@LotStatus

			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage= 'ServerMessage:物料外箱【'+@BoxOrLotSN+'】中的批号【'+@MLotSN+'】当前状态【'+@LotStatusDesc+'】，请检查!'+@Enter
			RETURN -1
		END
		
		--获取 LotSN 库存表物料信息
		SELECT TOP 1 
			@WareHouseId=WorkcenterId,
			@CellId=CellId,
			@LotProductId=ProductId,
			@MLotQty=SUM(ISNULL(Qty,0))
		FROM dbo.WW_RMInventory 
		WHERE BoxSN=@BoxOrLotSN
		GROUP BY BoxSN,ProductId,WorkcenterId,CellId

		--获取物料信息
		SELECT 
			@LotProductName=ProductName ,
			@LotProductDescription=ProductDescription,
			@IsExceedPicking = IsExceedPicking      --是否允许超发
		FROM dbo.Product 
		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
		WHERE ProductId=@LotProductId
	SET @IsExceedPicking='0';
		SELECT @WarehouseName=WorkcenterName+' '+ISNULL(WorkcenterDescription,'')
		FROM dbo.Workcenter WHERE WorkcenterId=@WareHouseId

		--检查通过分组后获取的箱号总数量是否与单独获取的数量是否相同
		IF CAST(ISNULL(@MLotQty,0) AS DECIMAL(18,8))<>(SELECT SUM(ISNULL(Qty,0)) FROM dbo.WW_RMInventory WHERE BoxSN=@BoxOrLotSN)
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:箱号【'+@BoxOrLotSN+'】中装有不同【仓库/库位/料号】的物料批号，不能按箱号发料，请按小包发料!'+@Enter
			RETURN -1        
		END 


		--检查该杂发单是否存在此物料
		IF NOT EXISTS(SELECT 1 PickingListItemId FROM dbo.PickingListItem WHERE PickingListId=@PickingListId AND ProductId=@LotProductId)
		BEGIN
			--检查是否存在转换后的产品ID
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:该杂发单【'+@PickingListName+'】明细行不存在行物料【'+@LotProductName+'】!'+@Enter
			RETURN -1
		END	

		--获取杂发单行信息
		SELECT 
			@PickingListItemId=PickingListItemId,
			@ItemWarehouseId=WorkcenterId,
			@QtyRequired=ISNULL(QtyRequired,0) ,  --行需求数
			@QtyIssued = ISNULL(QtyIssued,0)       --行已发数
		FROM dbo.PickingListItem 
		WHERE PickingListId=@PickingListId AND ProductId=@LotProductId	
		
		SELECT @ItemWarehouseName=WorkcenterName
		FROM dbo.Workcenter WHERE WorkcenterId=@ItemWarehouseId

		--IF ISNULL(@ItemWarehouseId,'')=''
		--BEGIN
		--	SELECT '' AS BoxOrLotSN
		--	SET @I_ReturnMessage='ServerMessage:该杂发单【'+@PickingListName+'】明细行物料【'+@LotProductName+'】没有设置发料仓库!'+@Enter
		--	RETURN -1
		--END 
			 
		--IF ISNULL(@ItemWarehouseId,'')<>ISNULL(@WareHouseId,'')
		--BEGIN
		--	--检查是否存在转换后的产品ID
		--	SELECT '' AS BoxOrLotSN
		--	SET @I_ReturnMessage='ServerMessage:该杂发单【'+@PickingListName+'】行物料【'+@LotProductName+'】要求从仓库【'+ISNULL(@ItemWarehouseName,'')+'】中发料，'+
		--	CHAR(13)+CHAR(10)+'当前箱号【'+@BoxOrLotSN+'】是仓库【'+@WarehouseName+'】中的物料!'+@Enter
		--	RETURN -1       
		--END 
		

		--欠料数
		SET @OweQty=CASE WHEN (@QtyRequired-@QtyIssued)<0 THEN 0 ELSE  @QtyRequired-@QtyIssued END 


		IF CAST(ISNULL(@QtyIssued,0) AS DECIMAL(18,8)) >=CAST(ISNULL(@QtyRequired,0) AS DECIMAL(18,8))
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:行物料【'+@LotProductName+'】已发数【'+CAST(@QtyIssued AS VARCHAR)+'】已满足需求数【'+CAST(@QtyRequired AS VARCHAR)+']，不允许继续发料!'+@Enter
			RETURN -1
		END

		--不允许超发
		IF ISNULL(@IsExceedPicking ,0 )= 0
		BEGIN
			IF CAST(ISNULL(@QtyIssued,0)+ISNULL(@MLotQty,0) AS DECIMAL(18,8))>CAST(ISNULL(@QtyRequired,0) AS DECIMAL(18,8))
			BEGIN
				SELECT '' AS BoxOrLotSN
				SET @I_ReturnMessage='ServerMessage:行物料【'+@LotProductName+'】已发数【'+CAST(@QtyIssued AS VARCHAR)+'】加上发料数【'+CAST(ISNULL(@MLotQty,0) AS VARCHAR)+'】'
					+CHAR(13)+CHAR(10)+'已超出需求数【'+CAST(@QtyRequired AS VARCHAR)+'】，不允许超发!'+@Enter

				RETURN -1
			END
		END


		--物料出库策略检查:先进先出以及超期检查、
		--EXEC @return_value=dbo.TxnBase_MLotOutCellCheck
		--	@I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
		--	@I_OrBitUserId = @I_OrBitUserId, -- char(12)
		--	@I_OrBitUserName = @I_OrBitUserName, -- nvarchar(100)
		--	@I_PlugInCommand = @I_PlugInCommand, -- varchar(5)
		--	@LotSN = N'', -- nvarchar(50)
		--	@BoxSN = @BoxOrLotSN -- nvarchar(50)

		--IF @return_value=-1
		--BEGIN
		--	SELECT '' AS BoxOrLotSN
		--	SET @I_ReturnMessage=@I_ReturnMessage+@Enter
		--	RETURN -1
		--END

		INSERT INTO @LotTemp(WWId,LotSN,Qty,ProductId,WarehouseId,CellId,LotUOMId)
		SELECT WWId,LotSN,Qty,ProductId,WorkcenterId,CellId,UOMId FROM dbo.WW_RMInventory WHERE BoxSN=@BoxOrLotSN AND IsStorage=1
	END
	
	--按小包发料
	IF @LotType='R'
	BEGIN
		--检查外箱号是否存在
		IF NOT EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@BoxOrLotSN)
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage= 'ServerMessage:物料批号【'+@BoxOrLotSN+'】在库存中不存在，请检查!'+@Enter
			RETURN -1
		END
		
		--检查外箱中是否有最小包已执行出库,1代表出库，0代表未出库
		IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@BoxOrLotSN AND IsStorage=0)
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage= 'ServerMessage:物料批号【'+@BoxOrLotSN+'】已出库，请确认!'+@Enter
			RETURN -1
		END

		--检查批号状态
		IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@BoxOrLotSN AND LotStatus<>'1')
		BEGIN
			--WES WW_RMInventory LotStatus/库存表状态信息
			SELECT TOP 1 @LotStatus=LotStatus
			FROM dbo.WW_RMInventory WHERE LotSN=@BoxOrLotSN  AND LotStatus<>'1'

			SELECT @LotStatusDesc=UserCodeDescription
			FROM dbo.UserCode
			WHERE ParentUserCodeId='URC100000AA9' AND UserCodeName=@LotStatus

			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage= 'ServerMessage:物料批号【'+@BoxOrLotSN+'】当前状态【'+@LotStatusDesc+'】，请检查!'+@Enter
			RETURN -1
		END

		--获取 LotSN 库存表物料信息
		SELECT TOP 1 
			@WareHouseId=WorkcenterId,
			@CellId=CellId,
			@LotProductId=ProductId,
			@MLotQty=ISNULL(Qty,0)
		FROM dbo.WW_RMInventory 
		WHERE LotSN=@BoxOrLotSN


		--获取物料信息
		SELECT 
			@LotProductName=ProductName ,
			@LotProductDescription=ProductDescription,
			@IsExceedPicking = IsExceedPicking      --是否允许超发
		FROM dbo.Product 
		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
		WHERE ProductId=@LotProductId

		SELECT @WarehouseName=WorkcenterName+' '+ISNULL(WorkcenterDescription,'')
		FROM dbo.Workcenter WHERE WorkcenterId=@WareHouseId

		--检查该杂发单是否存在此物料
		IF NOT EXISTS(SELECT 1 PickingListItemId FROM dbo.PickingListItem WHERE PickingListId=@PickingListId AND ProductId=@LotProductId)
		BEGIN
			--检查是否存在转换后的产品ID
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:该杂发单【'+@PickingListName+'】明细行不存在行物料【'+@LotProductName+'】!'+@Enter
			RETURN -1
		END	


		--获取杂发单行信息
		SELECT 
			@PickingListItemId=PickingListItemId,
			@ItemWarehouseId=WorkcenterId,
			@QtyRequired=ISNULL(QtyRequired,0) ,  --行需求数
			@QtyIssued = ISNULL(QtyIssued,0)      --行已发数
		FROM dbo.PickingListItem 
		WHERE PickingListId=@PickingListId AND ProductId=@LotProductId	

		SELECT @ItemWarehouseName=WorkcenterName
		FROM dbo.Workcenter WHERE WorkcenterId=@ItemWarehouseId

		--IF ISNULL(@ItemWarehouseId,'')=''
		--BEGIN
		--	SELECT '' AS BoxOrLotSN
		--	SET @I_ReturnMessage='ServerMessage:该杂发单【'+@PickingListName+'】明细行物料【'+@LotProductName+'】没有设置发料仓库!'+@Enter
		--	RETURN -1
		--END 

			
		--IF ISNULL(@ItemWarehouseId,'')<>ISNULL(@WareHouseId,'')
		--BEGIN
		--	--检查是否存在转换后的产品ID
		--	SELECT '' AS BoxOrLotSN
		--	SET @I_ReturnMessage='ServerMessage:该杂发单【'+@PickingListName+'】行物料【'+@LotProductName+'】要求从仓库【'+ISNULL(@ItemWarehouseName,'')+'】中发料，'+
		--	CHAR(13)+CHAR(10)+'当前批号【'+@BoxOrLotSN+'】是仓库【'+@WarehouseName+'】中的物料!'+@Enter
		--	RETURN -1            
		--END 

 		--欠料数
		SET @OweQty=CASE WHEN (@QtyRequired-@QtyIssued)<0 THEN 0 ELSE  @QtyRequired-@QtyIssued END 
		

		IF CAST(ISNULL(@QtyIssued,0) AS DECIMAL(18,8)) >=CAST(ISNULL(@QtyRequired,0) AS DECIMAL(18,8))
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:行物料【'+@LotProductName+'】已发数【'+CAST(@QtyIssued AS VARCHAR)+'】已满足需求数【'+CAST(@QtyRequired AS VARCHAR)+']，不允许继续发料!'+@Enter
			RETURN -1
		END


		--不允许超发
		--IF ISNULL(@IsExceedPicking ,0 )= 0
		--BEGIN
		--	IF CAST(ISNULL(@QtyIssued,0)+ISNULL(@MLotQty,0) AS DECIMAL(18,8))>CAST(ISNULL(@QtyRequired,0) AS DECIMAL(18,8))
		--	BEGIN
		--		SELECT @BoxOrLotSN AS 'MaterialLotSplitP.SplitLotSN',  --数据传给“物料拆分”界面
		--				@LotProductName AS 'MaterialLotSplitP.ProductName',
		--				@LotProductDescription AS 'MaterialLotSplitP.ProductDescription',
		--				@MLotQty AS 'MaterialLotSplitP.LotQty',
		--			    @OweQty AS 'MaterialLotSplitP.SplitQty'

		--		SET @I_ExceptionFieldName='MaterialLotSplitP.SplitQty' --进入“物料拆分界面”

		--		SET @I_ReturnMessage='ServerMessage:行物料【'+@LotProductName+'】已发数【'+CAST(@QtyIssued AS VARCHAR)+'】加上发料数【'+CAST(ISNULL(@MLotQty,0) AS VARCHAR)+'】'
		--			+CHAR(13)+CHAR(10)+'已超出需求数【'+CAST(@QtyRequired AS VARCHAR)+'】，不允许超发!'+@Enter
		--			+'*********执行拆批*********'+@Enter

		--		RETURN -1
		--	END
		--END
  
        --20260327取消超期检查
		--物料出库策略检查:先进先出以及超期检查、
		-- EXEC @return_value=dbo.TxnBase_MLotOutCellCheck
		-- 	@I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
		-- 	@I_OrBitUserId = @I_OrBitUserId, -- char(12)
		-- 	@I_OrBitUserName = @I_OrBitUserName, -- nvarchar(100)
		-- 	@I_PlugInCommand = @I_PlugInCommand, -- varchar(5)
		-- 	@LotSN = @BoxOrLotSN, -- nvarchar(50)
		-- 	@BoxSN = N'' -- nvarchar(50)

-- 		IF @return_value=-1
-- 		BEGIN
-- 			SELECT '' AS BoxOrLotSN
-- 			SET @I_ReturnMessage=@I_ReturnMessage+@Enter
-- 			RETURN -1
-- 		END	      

		INSERT INTO @LotTemp(WWId,LotSN,Qty,ProductId,WarehouseId,CellId,LotUOMId)
		SELECT WWId,LotSN,Qty,ProductId,WorkcenterId,CellId,UOMId FROM dbo.WW_RMInventory WHERE LotSN=@BoxOrLotSN AND IsStorage=1
	END
	

	--检查是否存在发料批号
	IF NOT EXISTS(SELECT 1 FROM @LotTemp)
	BEGIN
		SELECT '' AS BoxOrLotSN
		SET @I_ReturnMessage='ServerMessage:没有找到可发料出库的物料批号，请检查!'+@Enter
		RETURN -1
	END
	
	DECLARE @SLotQty FLOAT=0

	DECLARE cursor1 CURSOR LOCAL FAST_FORWARD FOR 
	SELECT WWId,LotSN,Qty,ProductId,WarehouseId,CellId FROM @LotTemp
	OPEN cursor1 
	FETCH NEXT FROM cursor1 
	INTO @WWId,@MLotSN, @MLotQty, @LotProductId,@WareHouseId,@CellId 
	WHILE @@FETCH_STATUS = 0 
	BEGIN 
	 
			
		-- 获取杂发单物料明细id
		SELECT 
			@PickingListItemId = PickingListItemId
		FROM dbo.PickingListItem
		WHERE PickingListId = @PickingListId AND ProductId = @LotProductId

		IF @OweQty<@MLotQty
		BEGIN 
		   DECLARE @NewLotSN VARCHAR(32)=''
		   DECLARE @SNRuleId CHAR(12)

			SELECT @SNRuleId=SNRuleId FROM dbo.SNRule WHERE SNRuleName='WW_MP_LotSN' AND IsActivity=1

		  
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
					@SplitLotSN=@MLotSN,
					@SplitQty=@OweQty,
					@CombineLotSN=@NewLotSN

					SET @MLotSN=@NewLotSN
					SET @MLotQty=@OweQty
		END 

		--写入发料记录  select * from PickingListItemLot
		EXEC dbo.SysGetObjectPKId '','PickingListItemLot',@PickingListItemLotId OUTPUT

		-- 写入发料表
		INSERT INTO dbo.PickingListItemLot( 
				PickingListItemLotId ,
				PickingListItemId ,
				ProductId ,
				LotSN ,
				Qty ,
				PickType,
				CreateUserId,
				CreateDate,
				CellId
				)
			VALUES ( 
				@PickingListItemLotId ,
				@PickingListItemId,
				@LotProductId,
				@MLotSN,
				ISNULL(@MLotQty,0),
				@LotType,
				@I_OrBitUserId,
				GETDATE(),
				@CellId
				)
		
		--更新库存表为已发料
		UPDATE dbo.WW_RMInventory SET 
			LotStatus='9',
			ModifyDate=GETDATE()
		WHERE LotSN=@MLotSN

		--插入物料批号追踪表
		EXEC dbo.TxnBase_MLotTrack
			@I_OrBitUserId =@I_OrBitUserId, -- char(12)
			@I_PlugInCommand=@I_PlugInCommand,
			@I_ResourceId =@I_ResourceId, -- char(12)
			@LotSN = @MLotSN, -- nvarchar(50) --物料批号
			@LotQty = @MLotQty, -- decimal(18, 6)--数量
			@TxnCode ='M-杂发下架' , -- nvarchar(50) --事务码
			@OrderName =@PickingListName , -- nvarchar(50) --单据号
			@Remark = N'' -- nvarchar(200) --备注

		-- 更新杂发单明细仓库Id
		IF EXISTS(SELECT PickingListItemId FROM dbo.PickingListItem WHERE PickingListItemId = @PickingListItemId)
		BEGIN
			--更新杂发单明细发料数
			UPDATE dbo.PickingListItem SET 
				QtyIssued =ISNULL( QtyIssued,0) + ISNULL(@MLotQty,0)
			WHERE PickingListItemId = @PickingListItemId
		END

		FETCH NEXT FROM cursor1 
		INTO @WWId,@MLotSN, @MLotQty, @LotProductId,@WareHouseId,@CellId    
	END
	CLOSE cursor1 
	DEALLOCATE cursor1 
	



	SET @QtyRequired = 0
	SET @QtyIssued = 0
	SET @OutQty=0
	SET @OweQty=0

	--获取当次发料数
	SELECT @OutQty=SUM(Qty) FROM @LotTemp

	-- 获取发料需求数、已发数
	SELECT 
		@QtyRequired=ISNULL(QtyRequired,0) ,
		@QtyIssued = ISNULL(QtyIssued,0)
	FROM dbo.PickingListItem 
	WHERE PickingListId=@PickingListId AND ProductId=@LotProductId

	SET  @OweQty=CASE WHEN (@QtyRequired-@QtyIssued)<0 THEN 0 ELSE @QtyRequired-@QtyIssued END 

	--注意返回料号、仓库、储位是为智能提醒：建议批次信息、当前扫描的物料信息
	SELECT '' AS BoxOrLotSN,@LotProductId AS CurProductId,@WareHouseId AS CurWareHouseId,@CellId AS CurCellId
	SET @I_ReturnMessage= 'ServerMessage:物料【'+@BoxOrLotSN+'】出库成功，出库数量：'+CAST(@OutQty AS VARCHAR)+@Enter 

	RETURN 0

end
go

