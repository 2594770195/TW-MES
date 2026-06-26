
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/04/09 09:38:20:8166>
-- Description:   <外协发料>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[PDA_MaterialToPickingListPO]
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

@PickingListName NVARCHAR(50)='',      --领料单
@BoxOrLotSN NVARCHAR(100)=''            --最小包/外箱 SN

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @return_value INT=-1
	DECLARE @Enter NVARCHAR(100)=CHAR(13)+CHAR(10)

	--领料单信息
	DECLARE @PickingListId CHAR(12)=''
	DECLARE @PickingListStates VARCHAR(20)=''
	DECLARE @PickingListClass VARCHAR(20)=''

	--领料单行信息
	DECLARE @QtyRequired FLOAT=0
	DECLARE @QtyIssued FLOAT=0-- 已发数
	DECLARE @OweQty FLOAT=0 --欠料数
	DECLARE @PickingListItemId CHAR(12)=''
	DECLARE @ItemWarehouseId CHAR(12)=''
	DECLARE @ItemWarehouseName NVARCHAR(50)=''

	--领料单明细批号
	DECLARE @PickingListItemLotId CHAR(12)=''

	--物料信息
	DECLARE @MLotSN NVARCHAR(100)=''
	DECLARE @MLotQty FLOAT=0
	DECLARE @LotStatus CHAR(1)=''
	DECLARE @LotStatusDesc NVARCHAR(50)=''
	DECLARE @LotProductId CHAR(12)=''
	DECLARE @LotProductName NVARCHAR(50)=''
	DECLARE @LotProductDescription NVARCHAR(50)=''
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
	 
   
	SET @I_ExceptionFieldName='BoxOrLotSN'  

	--转换大写
	SET @BoxOrLotSN =UPPER(LTRIM(RTRIM(@BoxOrLotSN)))

	-- 检查领料单好 
	IF ISNULL(@PickingListName,'')=''
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'
		SET @I_ReturnMessage='ServerMessage:请选择领料单号!'+@Enter
		SELECT '' AS PickingListName,'' AS BoxOrLotSN,
			   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
		RETURN -1
	END

	--检查领料单号是否存在
	IF NOT EXISTS(SELECT 1 FROM dbo.PickingList WHERE PickingListName=@PickingListName)
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'
		SET @I_ReturnMessage='ServerMessage:领料单号【'+@PickingListName+'】不存在，请检查!'+@Enter
		SELECT '' AS PickingListName,'' AS BoxOrLotSN,
			   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
		RETURN -1
	END

	--获取领料单信息
	SELECT 
		@PickingListStates = PickingListStates,
		@PickingListClass=PickingListClass,
		@PickingListId=PickingListId
	FROM dbo.PickingList 
	WHERE PickingListName=@PickingListName


	IF ISNULL(@PickingListClass,'')<>'04'
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'
		SET @I_ReturnMessage='ServerMessage:该单据【'+@PickingListName+'】不是外协领料单，不允许发料!'+@Enter
		SELECT '' AS BoxOrLotSN,
			   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
		RETURN -1   
	END 

	-- 检查领料是否有审核
	IF ISNULL(@PickingListStates,'')<>'20'
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'
		SET @I_ReturnMessage='ServerMessage:该领料单【'+@PickingListName+'】不是 [已审核] 状态，不允许发料!'+@Enter
		SELECT '' AS BoxOrLotSN,
			   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
		RETURN -1
	END
	 
	-- 检查该领料单是否存在领料单物料明细
	IF NOT EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId = @PickingListId)
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'
		SET @I_ReturnMessage='ServerMessage:该领料单【'+@PickingListName+'】的没有找到明细行项，不允许发料!'+@Enter
		SELECT '' AS BoxOrLotSN,
			   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
		RETURN -1
	END

	--一次性检查该发料单的明细行是否符合要求，因为同一个物料可能有多行。
	IF EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId = @PickingListId AND ISNULL(WorkcenterId,'')='')
	BEGIN 
		SET @I_ExceptionFieldName='PickingListName'
		SET @I_ReturnMessage='ServerMessage:该领料单 ['+@PickingListName+'] 存在没有维护发料【仓库】的明细行项，不允许发料!'+@Enter
		SELECT '' AS BoxOrLotSN,
			   '' AS CurProductId,''AS CurWareHouseId,'' AS CurCellId
		RETURN -1    
	END






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

		SELECT @WarehouseName=WorkcenterName+' '+ISNULL(WorkcenterDescription,'')
		FROM dbo.Workcenter WHERE WorkcenterId=@WareHouseId

		--检查通过分组后获取的箱号总数量是否与单独获取的数量是否相同
		IF CAST(ISNULL(@MLotQty,0) AS DECIMAL(18,8))<>(SELECT SUM(ISNULL(Qty,0)) FROM dbo.WW_RMInventory WHERE BoxSN=@BoxOrLotSN)
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:箱号【'+@BoxOrLotSN+'】中装有不同【仓库/库位/料号】的物料批号，不能按箱号发料，请按小包发料!'+@Enter
			RETURN -1
		END 


		--检查该领料单是否存在此物料
		IF NOT EXISTS(SELECT 1 PickingListItemId FROM dbo.PickingListItem 
		WHERE PickingListId=@PickingListId AND ProductId=@LotProductId)
		BEGIN
			--检查是否存在转换后的产品ID
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:该领料单【'+@PickingListName+'】明细行不存在行物料【'+@LotProductName+'】!'+@Enter
			RETURN -1
		END	

		--检查仓库
		IF NOT EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@PickingListId
		AND ProductId=@LotProductId AND WorkcenterId=@WareHouseId )
		BEGIN
			--获取发料单行信息
			SELECT TOP 1
				@ItemWarehouseId=WorkcenterId
			FROM dbo.PickingListItem   
			WHERE  PickingListId=@PickingListId AND ProductId=@LotProductId	

			SELECT @ItemWarehouseName=WorkcenterName+':'+ISNULL(WorkcenterDescription,'')
			FROM dbo.Workcenter WHERE WorkcenterId=@ItemWarehouseId
				
			--检查是否存在转换后的产品ID
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:该领料单【'+@PickingListName+'】行物料【'+@LotProductName+'】要求从仓库['+ISNULL(@ItemWarehouseName,'')+']中发料，'+
			CHAR(13)+CHAR(10)+'当前箱号['+@BoxOrLotSN+']所在仓库为【'+@WarehouseName+'】!'+@Enter
			RETURN -1
		END 

		--获取领料单行信息
		SELECT 
			@QtyRequired=SUM(ISNULL(QtyRequired,0)) ,  --行需求数
			@QtyIssued = SUM(ISNULL(QtyIssued,0))       --行已发数
		FROM dbo.PickingListItem 
		WHERE PickingListId=@PickingListId AND ProductId=@LotProductId
		AND WorkcenterId=@WareHouseId


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
		EXEC @return_value=dbo.TxnBase_MLotOutCellCheck
			@I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
			@I_OrBitUserId = @I_OrBitUserId, -- char(12)
			@I_OrBitUserName = @I_OrBitUserName, -- nvarchar(100)
			@I_PlugInCommand = @I_PlugInCommand, -- varchar(5)
			@LotSN = N'', -- nvarchar(50)
			@BoxSN = @BoxOrLotSN -- nvarchar(50)

		IF @return_value=-1
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage=@I_ReturnMessage+@Enter
			RETURN -1
		END


		INSERT INTO @LotTemp(WWId,LotSN,Qty,ProductId,WarehouseId,CellId,LotUOMId)
		SELECT WWId,LotSN,Qty,ProductId,WorkcenterId,CellId,UOMId 
		FROM dbo.WW_RMInventory WHERE BoxSN=@BoxOrLotSN
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


		--检查该领料单是否存在此物料
		IF NOT EXISTS(SELECT 1 PickingListItemId FROM dbo.PickingListItem 
		WHERE PickingListId=@PickingListId AND ProductId=@LotProductId)
		BEGIN
			--检查是否存在转换后的产品ID
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:该领料单【'+@PickingListName+'】明细行不存在行物料【'+@LotProductName+'】!'+@Enter
			RETURN -1
		END	

		--检查仓库
		IF NOT EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@PickingListId
		AND ProductId=@LotProductId AND WorkcenterId=@WareHouseId )
		BEGIN
			--获取发料单行信息
			SELECT TOP 1
				@ItemWarehouseId=WorkcenterId
			FROM dbo.PickingListItem   
			WHERE  PickingListId=@PickingListId AND ProductId=@LotProductId	

			SELECT @ItemWarehouseName=WorkcenterName+':'+ISNULL(WorkcenterDescription,'')
			FROM dbo.Workcenter WHERE WorkcenterId=@ItemWarehouseId
				
			--检查是否存在转换后的产品ID
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage='ServerMessage:该领料单【'+@PickingListName+'】行物料【'+@LotProductName+'】要求从仓库['+ISNULL(@ItemWarehouseName,'')+']中发料，'+
			CHAR(13)+CHAR(10)+'当前批号['+@BoxOrLotSN+']所在仓库为【'+@WarehouseName+'】!'+@Enter
			RETURN -1
		END 

		--获取领料单行信息
		SELECT 
			@QtyRequired=SUM(ISNULL(QtyRequired,0)) ,  --行需求数
			@QtyIssued = SUM(ISNULL(QtyIssued,0))      --行已发数
		FROM dbo.PickingListItem 
		WHERE PickingListId=@PickingListId AND ProductId=@LotProductId
		AND WorkcenterId=@WareHouseId


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
				SELECT @BoxOrLotSN AS 'MaterialLotSplitP.SplitLotSN',  --数据传给“物料拆分”界面
						@LotProductName AS 'MaterialLotSplitP.ProductName',
						@LotProductDescription AS 'MaterialLotSplitP.ProductDescription',
						@MLotQty AS 'MaterialLotSplitP.LotQty',
					    @OweQty AS 'MaterialLotSplitP.SplitQty'

				SET @I_ExceptionFieldName='MaterialLotSplitP.SplitQty' --进入“物料拆分界面”

				SET @I_ReturnMessage='ServerMessage:行物料【'+@LotProductName+'】已发数【'+CAST(@QtyIssued AS VARCHAR)+'】加上发料数【'+CAST(ISNULL(@MLotQty,0) AS VARCHAR)+'】'
					+CHAR(13)+CHAR(10)+'已超出需求数【'+CAST(@QtyRequired AS VARCHAR)+'】，不允许超发!'+@Enter
					+'*********执行拆批*********'+@Enter

				RETURN -1
			END
		END


		--物料出库策略检查:先进先出以及超期检查、
		EXEC @return_value=dbo.TxnBase_MLotOutCellCheck
			@I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
			@I_OrBitUserId = @I_OrBitUserId, -- char(12)
			@I_OrBitUserName = @I_OrBitUserName, -- nvarchar(100)
			@I_PlugInCommand = @I_PlugInCommand, -- varchar(5)
			@LotSN = @BoxOrLotSN, -- nvarchar(50)
			@BoxSN = N'' -- nvarchar(50)

		IF @return_value=-1
		BEGIN
			SELECT '' AS BoxOrLotSN
			SET @I_ReturnMessage=@I_ReturnMessage+@Enter
			RETURN -1
		END
		
		INSERT INTO @LotTemp(WWId,LotSN,Qty,ProductId,WarehouseId,CellId,LotUOMId)
		SELECT WWId,LotSN,Qty,ProductId,WorkcenterId,CellId,UOMId 
		FROM dbo.WW_RMInventory WHERE LotSN=@BoxOrLotSN AND IsStorage=1
	END
	

	--检查是否存在发料批号
	IF NOT EXISTS(SELECT 1 FROM @LotTemp)
	BEGIN
		SELECT '' AS BoxOrLotSN
		SET @I_ReturnMessage='ServerMessage:没有找到可发料出库的物料批号，请检查!'+@Enter
		RETURN -1
	END
	

	DECLARE cursor1 CURSOR LOCAL FAST_FORWARD FOR 
	SELECT WWId,LotSN,Qty,ProductId,WarehouseId,CellId FROM @LotTemp
	OPEN cursor1 
	FETCH NEXT FROM cursor1 
	INTO @WWId,@MLotSN, @MLotQty, @LotProductId,@WareHouseId,@CellId 
	WHILE @@FETCH_STATUS = 0 
	BEGIN 
		--插入物料批号追踪表
		EXEC dbo.TxnBase_MLotTrack
			@I_OrBitUserId =@I_OrBitUserId, -- char(12)
			@I_PlugInCommand=@I_PlugInCommand,
			@I_ResourceId =@I_ResourceId, -- char(12)
			@LotSN = @MLotSN, -- nvarchar(50) --物料批号
			@LotQty = @MLotQty, -- decimal(18, 6)--数量
			@TxnCode ='M-委外领料下架' , -- nvarchar(50) --事务码
			@OrderName =@PickingListName , -- nvarchar(50) --单据号
			@Remark = N'' -- nvarchar(200) --备注


		 --分配数量
		 WHILE(CONVERT(DECIMAL(18,8),@MLotQty)>0)
		 BEGIN
			 SET @PickingListItemId=''

			 SELECT TOP 1 
					@PickingListItemId=PickingListItemId,
					@QtyRequired= ISNULL(QtyRequired,0),
					@QtyIssued=ISNULL(QtyIssued,0)
			 FROM dbo.PickingListItem
			 WHERE PickingListId = @PickingListId AND ProductId = @LotProductId
			 AND WorkcenterId=@WareHouseId
			 AND  QtyRequired>QtyIssued
			 ORDER BY ItemSequence

			 --如果没有数量，则退出
			 IF CONVERT(DECIMAL(18,8),@MLotQty)<=0
				BREAK

			--如果没获取到行，则统一放在最后一行上
			IF ISNULL(@PickingListItemId,'')=''
			BEGIN
				 SELECT TOP 1 
						@PickingListItemId=PickingListItemId,
						@QtyRequired= ISNULL(QtyRequired,0),
						@QtyIssued=ISNULL(QtyIssued,0)
				 FROM dbo.PickingListItem
				 WHERE PickingListId = @PickingListId AND ProductId = @LotProductId
				 AND WorkcenterId=@WareHouseId
				ORDER BY ItemSequence DESC
			END
			
			 --如果不等于空，则正常扣料（支持多行相同物料，如果等于空，说明）
			 IF CONVERT(DECIMAL(18,6),@MLotQty)<=CONVERT(DECIMAL(18,6),(@QtyRequired-@QtyIssued))
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
							PickType,
							CellId,
							CreateUserId,
							CreateDate
						 )
				VALUES
						 (
							@PickingListItemLotId, -- PickingListItemLotId - char(12)
							@PickingListItemId, -- PickingListItemId - char(12)
							@LotProductId, -- ProductId - char(12)
							@MLotSN, -- LotSN - nvarchar(50)
							@MLotQty, -- Qty - decimal(18, 8)
							@LotType, -- PickType - char(1)
							@CellId, -- CellId - char(12)
							@I_OrBitUserId, -- CreateUserId - char(12)
							GETDATE() -- CreateDate - datetime
						 )

				--更新领料单明细发料数
				UPDATE dbo.PickingListItem SET 
						QtyIssued =ISNULL( QtyIssued,0) + @MLotQty
				WHERE PickingListItemId = @PickingListItemId

				SET @MLotQty=0
			 END
			 ELSE
			 BEGIN
				--检查是否除了当前行，是否还有其他行有相同产品的行，如果有，则正常扣数，如果不是，则把所有剩余数放在最后一行上
				--即超发数只会在最后一行上
				IF EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@PickingListId
				AND PickingListItemId<>@PickingListItemId AND ProductId=@LotProductId 
				AND WorkcenterId=@WareHouseId  AND  QtyRequired>QtyIssued)
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
								PickType,
								CellId,
								CreateUserId,
								CreateDate
							 )
					VALUES
							 (
								@PickingListItemLotId, -- PickingListItemLotId - char(12)
								@PickingListItemId, -- PickingListItemId - char(12)
								@LotProductId, -- ProductId - char(12)
								@MLotSN, -- LotSN - nvarchar(50)
								@QtyRequired-@QtyIssued, -- Qty - decimal(18, 8)
								@LotType, -- PickType - char(1)
								@CellId, -- CellId - char(12)
								@I_OrBitUserId, -- CreateUserId - char(12)
								GETDATE() -- CreateDate - datetime
							 )

						--更新明细发料数
					UPDATE dbo.PickingListItem SET 
							QtyIssued =ISNULL( QtyIssued,0) + (@QtyRequired-@QtyIssued)
					WHERE PickingListItemId= @PickingListItemId    
					
					--当前批次剩余数
					SET @MLotQty=@MLotQty-(@QtyRequired-@QtyIssued)
				END 
				ELSE
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
								PickType,
								CellId,
								CreateUserId,
								CreateDate
							 )
					VALUES
							 (
								@PickingListItemLotId, -- PickingListItemLotId - char(12)
								@PickingListItemId, -- PickingListItemId - char(12)
								@LotProductId, -- ProductId - char(12)
								@MLotSN, -- LotSN - nvarchar(50)
								@MLotQty, -- Qty - decimal(18, 8)
								@LotType, -- PickType - char(1)
								@CellId, -- CellId - char(12)
								@I_OrBitUserId, -- CreateUserId - char(12)
								GETDATE() -- CreateDate - datetime
							 )

					--更新明细发料数
					UPDATE dbo.PickingListItem SET 
							QtyIssued =ISNULL( QtyIssued,0) + @MLotQty
					WHERE PickingListItemId = @PickingListItemId
					
					--当前批次剩余数
					SET @MLotQty=0
				END    
				--
			END 
			--
		END 

		
		--更新库存表为已发料
		UPDATE dbo.WW_RMInventory SET 
			LotStatus='9',
			ModifyDate=GETDATE()
		WHERE WWId=@WWId
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

END
 















go

