SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:        <OrBit Team Owen HK0313 >
-- Create date:   <2021/07/03 11:01:37:9179>
-- Description:   <PDA  工单生产-上料完成>
-- Rev: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[PDA_ProductionMakingSubmit]
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
@LoadingItemLotId VARCHAR(100)='',        --制作编号
@CurrWeight DECIMAL(18,3)=0 OUTPUT,      --本次下线重量
@TonBarrelSN  NVARCHAR(100)=''      --批次条码/工单物料条码

AS
BEGIN
	-- set NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--TY
	DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10)
	DECLARE @CurDate DATETIME=GETDATE()
	DECLARE @RESULT INT=0
	DECLARE @WorkcenterId IDType
	DECLARE @WorkcenterName VARCHAR(32)
	DECLARE @FactoryId IDType
	DECLARE @DivisionId CHAR(12)
	DECLARE @LotNum INT
	DECLARE @CostCenterName VARCHAR(50)=''

	DECLARE @API_ReturnMessage NVARCHAR(MAX)=''
	DECLARE @Api_ReturnValue INT=-1

	--获取基本信息
	DECLARE @MOId IDType,
	@MOName VARCHAR(50),
	@MOItemLotId IDType,
	@Weight SysNumberType,
	@MOItemSpecificationId IDType,
	@SpecificationCode NVARCHAR(50),
	@SpecificationId IDType,
	@IsComplete BIT,
	@Operator IDType,
	@LotId IDType,
	@DataChainId IDType,
	@TxnCode varchar(10)='START',
	@MOProductId IDType,
	@WorkflowId IDType,
	@WorkflowStepId IDType,
	@MOItemId IDType,
	@MOItemTaskId IDType,
	@EquipmentId IDType,
	@EquipmentNumber VARCHAR(32)

	DECLARE @SPickingListItemId CHAR(12)
	DECLARE @SItemSequence VARCHAR(16)
	
	--制作完成修改状态
	IF @I_Sender='MakingComplete'
	BEGIN
		SELECT @MOId=MOId FROM LoadingItemLot 
		WHERE LoadingItemLotId=@LoadingItemLotId

		SELECT @MOName=MOName,@DivisionId=DivisionId FROM MO WHERE MOId=@MOId

		DECLARE @RowCount INT
		DECLARE @RowId INT=1
		DECLARE @PickingListId CHAR(12)
		DECLARE @PickingListOtherId CHAR(12)
		DECLARE @PickingList_MOId char(12)=''
		DECLARE @PickingListItemId char(12)=''
		DECLARE @PickingListItemLotId char(12)=''
		DECLARE @PickingListDescription NVARCHAR(64)='工单生产领料'

		DECLARE @LotSN VARCHAR(100)
		DECLARE @ProductId CHAR(12)
		DECLARE @Qty DECIMAL(18,3)
		DECLARE @SQty DECIMAL(18,3)
		DECLARE @UOMName VARCHAR(50)
		DECLARE @CellId CHAR(12)
		DECLARE @PickingListName VARCHAR(50)
		DECLARE @OtherPickingListName VARCHAR(50)
		DECLARE @InterfaceItemId CHAR(12)
		DECLARE @UploadIngId CHAR(12)
		DECLARE @WaterProductId CHAR(12)

		SELECT @WaterProductId=P.ProductId FROM ProductRoot PR INNER JOIN Product P ON PR.ProductRootId=P.ProductRootId WHERE PR.ProductName='9999999999'

		--修改上料状态为上料完成
		UPDATE LoadingItemLot SET IsComplete=1,CompleteDate=getdate() WHERE LoadingItemLotId=@LoadingItemLotId
		--制作完成关闭工单
		--UPDATE MO SET MOStates='40' WHERE MOId=@PMOId

		--********************************************* BEGIN 正常BOM领料（生产领料单） ********************************************

		--修改去离子水已发放数量

		UPDATE A SET A.ItemQtyDone=(ISNULL(A.ItemQtyDone,0)+B.Qty),A.ItemQtyIssued=(ISNULL(A.ItemQtyIssued,0)+B.Qty) FROM MOItem A
		INNER JOIN (SELECT C.MOItemId,SUM(A.Qty) AS Qty FROM LoadingItemLotRecord A 
		INNER JOIN LoadingItemLotDetail B ON A.LoadingItemLotDetailId=B.LoadingItemLotDetailId
		INNER JOIN MOItem C ON B.MOItemId=C.MOItemId
		INNER JOIN WW_RMInventory D ON A.LotSN=D.LotSN WHERE  B.LoadingItemLotId=@LoadingItemLotId
		AND A.IsPicking=0 AND C.ProductId=@WaterProductId
		GROUP BY C.MOItemId) B ON A.MOItemId=B.MOItemId

		SELECT A.LotSN,D.FactoryId,D.WorkcenterId,C.ProductId,E.UOMName,C.MOItemId,D.CellId,SUM(A.Qty) AS Qty,SUM(ISNULL(D.Qty,0)) AS SQty INTO #PickingLot FROM LoadingItemLotRecord A 
		INNER JOIN LoadingItemLotDetail B ON A.LoadingItemLotDetailId=B.LoadingItemLotDetailId
		INNER JOIN MOItem C ON B.MOItemId=C.MOItemId
		INNER JOIN WW_RMInventory D ON A.LotSN=D.LotSN
		INNER JOIN UOM E ON D.UOMId=E.UOMId WHERE  B.LoadingItemLotId=@LoadingItemLotId
		AND A.IsPicking=0 AND C.ProductId<>@WaterProductId
		--AND A.LotSN NOT IN(SELECT DISTINCT PLIL.LotSN FROM PickingListItemLot PLIL
		--INNER JOIN PickingListItem PLI ON PLIL.PickingListItemId=PLI.PickingListItemId
  --      WHERE PLI.PickingListId IN(SELECT PickingListId FROM PickingList_MO WHERE MOId=@MOId))
		GROUP BY A.LotSN,D.FactoryId,D.WorkcenterId,C.ProductId,E.UOMName,C.MOItemId,D.CellId
		--自动生成生产领料单，不属于原BOM物料生成杂发单

		SELECT @RowCount=COUNT(1) FROM #PickingLot

		BEGIN TRANSACTION PickingLot

		IF @RowCount>0
		BEGIN
		    SELECT TOP 1 @FactoryId=FactoryId,@WorkcenterId=WorkcenterId FROM #PickingLot

			EXEC SysGetObjectPKId '','PickingList',@PickingListId OUTPUT
			--调用生产领料单保存事件
			EXEC @RESULT= PickingListPRSaveData 
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_OrBitUserName=@I_OrBitUserName,
			@I_PKId=@PickingListId,
			@CreateUserName=@I_OrBitUserName,
			@CreateDate=@CurDate,
			@DateRequired=@CurDate,
			@PickingListTypeCode='02',
			@FactoryId=@FactoryId,
			@DivisionId=@DivisionId,
			@ToWorkcenterId=@WorkcenterId,
			@PickingListDescription=@PickingListDescription

			IF @RESULT<>0
			BEGIN
				ROLLBACK TRANSACTION PickingLot
				RETURN @RESULT
			END
			SELECT @PickingListName=PickingListName FROM PickingList WHERE PickingListId=@PickingListId

			--生成生产领料单工单
			EXEC SysGetObjectPKId '','PickingList_MO',@PickingList_MOId OUTPUT
			--调用生产领料单保存事件
			EXEC @RESULT= dbo.[PickingList_MOSaveData] 
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_OrBitUserName=@I_OrBitUserName,
			@I_PKId=@PickingList_MOId,
			@I_ParentPKId=@PickingListId,
			@MOId=@MOId,
			@MOName=@MOName

			IF ISNULL(@RESULT,0)<>0
			BEGIN 
				ROLLBACK TRANSACTION PickingLot
				RETURN @RESULT
			END

			DECLARE PLISOR CURSOR FOR
			SELECT MOItemId,ProductId,UOMName,FactoryId,WorkcenterId,SUM(Qty) AS Qty FROM #PickingLot GROUP BY MOItemId,ProductId,UOMName,FactoryId,WorkcenterId

			OPEN PLISOR
			FETCH NEXT FROM PLISOR INTO @MOItemId,@ProductId,@UOMName,@FactoryId,@WorkcenterId,@Qty
			WHILE @@FETCH_STATUS =0
			BEGIN
				--生成领料单明细
				EXEC SysGetObjectPKId '','PickingListItem',@PickingListItemId OUTPUT
				--调用生产领料单保存事件
				EXEC @RESULT= dbo.[PickingListItemPRSaveData] 
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_OrBitUserName=@I_OrBitUserName,
				@I_PKId=@PickingListItemId,
				@I_ParentPKId=@PickingListId,
				@MOItemIdNO=@MOItemId,
				@MOName=@MOName,
				@ProductId=@ProductId,
				@QtyRequired=@Qty,
				@QtyIssued=@Qty,
				@WareHouseId=@WorkcenterId,
				@UOMName=@UOMName

				IF ISNULL(@RESULT,0)<>0
				BEGIN 
					ROLLBACK TRANSACTION PickingLot
					RETURN @RESULT
				END

				UPDATE MOItem SET ItemQtyDone=(ISNULL(ItemQtyDone,0)+@Qty),ItemQtyIssued=(ISNULL(ItemQtyIssued,0)+@Qty) WHERE MOItemId=@MOItemId

				DECLARE PLILSOR CURSOR FOR
				SELECT LotSN,Qty,SQty,CellId FROM #PickingLot WHERE MOItemId=@MOItemId AND FactoryId=@FactoryId AND WorkcenterId=@WorkcenterId

				OPEN PLILSOR
				FETCH NEXT FROM PLILSOR INTO @LotSN,@Qty,@SQty,@CellId
				WHILE @@FETCH_STATUS =0
				BEGIN
					--生成调拨明细批次
					EXEC SysGetObjectPKId '','PickingListItemLot',@PickingListItemLotId OUTPUT
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
								@ProductId, -- ProductId - char(12)
								@LotSN, -- LotSN - nvarchar(50)
								@Qty, -- Qty - decimal(18, 8)
								@Qty,
								'R', -- PickType - char(1)
								@CellId, -- CellId - char(12)
								@I_OrBitUserId, -- CreateUserId - char(12)
								GETDATE(), -- CreateDate - datetime
								1
								)
					FETCH NEXT FROM PLILSOR INTO @LotSN,@Qty,@SQty,@CellId
				END
				CLOSE PLILSOR --关闭游标
				DEALLOCATE PLILSOR --释放游标

				FETCH NEXT FROM PLISOR INTO @MOItemId,@ProductId,@UOMName,@FactoryId,@WorkcenterId,@Qty
			END

			CLOSE PLISOR --关闭游标
			DEALLOCATE PLISOR --释放游标

			UPDATE A SET A.IsStorage=0 FROM WW_RMInventory A
			INNER JOIN LoadingItemLotRecord B ON A.LotSN=B.LotSN
			INNER JOIN LoadingItemLotDetail C ON B.LoadingItemLotDetailId=C.LoadingItemLotDetailId
			INNER JOIN MOItem D ON C.MOItemId=D.MOItemId
			WHERE C.LoadingItemLotId=@LoadingItemLotId  AND B.IsPicking=0 AND A.Qty<=0

			UPDATE A SET A.IsPicking=1 FROM LoadingItemLotRecord AS A
			INNER JOIN LoadingItemLotDetail B ON A.LoadingItemLotDetailId=B.LoadingItemLotDetailId
			INNER JOIN MOItem C ON B.MOItemId=C.MOItemId
			WHERE B.LoadingItemLotId=@LoadingItemLotId AND IsPicking=0 

			--EXEC dbo.RfcSAPSync @I_ReturnMessage =@I_ReturnMessage OUTPUT,
			--			@ItemName =N'U_PickingListPR'

			--IF @I_ReturnMessage LIKE '%过账成功%'
			--	UPDATE PickingList SET PickingListStates='40' WHERE PickingListId=@PickingListId
			--ELSE
			--	UPDATE PickingList SET PickingListStates='41' WHERE PickingListId=@PickingListId
			
		END

		--********************************************* END 正常BOM领料（生产领料单） ********************************************
		
		TRUNCATE TABLE #PickingLot
		DROP TABLE #PickingLot

		SET @RowCount=0
		SET @RowId=0


		--********************************************* BEGIN 调整BOM领料（杂发单） ********************************************

		--SELECT A.LotSN,D.FactoryId,D.WorkcenterId,C.ProductId,E.UOMName,C.MOItemId,D.CellId,SUM(A.Qty) AS Qty,SUM(ISNULL(D.Qty,0)) AS SQty INTO #PickingLotOther FROM LoadingItemLotRecord A 
		--INNER JOIN LoadingItemLotDetail B ON A.LoadingItemLotDetailId=B.LoadingItemLotDetailId
		--INNER JOIN MOItem C ON B.MOItemId=C.MOItemId
		--INNER JOIN WW_RMInventory D ON A.LotSN=D.LotSN AND D.IsStorage=1
		--INNER JOIN UOM E ON D.UOMId=E.UOMId WHERE  B.LoadingItemLotId=@LoadingItemLotId AND C.IsNewItem=1
		--AND A.IsPicking=0 AND C.ProductId<>@WaterProductId
		----AND A.LotSN NOT IN(SELECT DISTINCT PLIL.LotSN FROM PickingListItemLot PLIL
		----INNER JOIN PickingListItem PLI ON PLIL.PickingListItemId=PLI.PickingListItemId
  ----      WHERE PLI.PickingListId IN(SELECT PickingListId FROM PickingList_MO WHERE MOId=@MOId))
		--GROUP BY A.LotSN,D.FactoryId,D.WorkcenterId,C.ProductId,E.UOMName,C.MOItemId,D.CellId
		----自动生成生产领料单，不属于原BOM物料生成杂发单

		--SET @PickingListDescription='工单生产领料产生杂发单'
		--SELECT @RowCount=COUNT(1) FROM #PickingLotOther

		--IF @RowCount>0
		--BEGIN
		--    SELECT TOP 1 @FactoryId=FactoryId,@WorkcenterId=WorkcenterId FROM #PickingLotOther

		--	SELECT @WorkcenterName=WorkcenterName FROM Workcenter WHERE WorkcenterId=@WorkcenterId
		--	SET @CostCenterName=(CASE @WorkcenterName 
		--	WHEN 'FSXB' THEN '0000336110'
		--	WHEN 'UVXB' THEN '0000336100'
		--	WHEN 'HXXB' THEN '0000336170'
		--	WHEN 'SXXB' THEN '0000336120'
		--	WHEN 'SOXB' THEN '0000336130' END)

		--	EXEC SysGetObjectPKId '','PickingList',@PickingListOtherId OUTPUT
		--	--调用生产领料单保存事件
		--	EXEC @RESULT= PickingListOtherSaveData 
		--	@I_ReturnMessage=@I_ReturnMessage OUTPUT,
		--	@I_OrBitUserId=@I_OrBitUserId,
		--	@I_OrBitUserName=@I_OrBitUserName,
		--	@I_PKId=@PickingListOtherId,
		--	@CreateUserName=@I_OrBitUserName,
		--	@CreateDate=@CurDate,
		--	@DateRequired=@CurDate,
		--	@PickingListTypeCode='01',
		--	@FactoryId=@FactoryId,
		--	@DivisionId=@DivisionId,
		--	@ToWorkcenterId=@WorkcenterId,
		--	@PickingListDescription=@PickingListDescription

		--	IF @RESULT<>0
		--	BEGIN
		--		ROLLBACK TRANSACTION PickingLot
		--		RETURN @RESULT
		--	END
		--	SELECT @OtherPickingListName=PickingListName FROM PickingList WHERE PickingListId=@PickingListOtherId

		--	DECLARE PLIOTHERSOR CURSOR FOR
		--	SELECT MOItemId,ProductId,UOMName,FactoryId,WorkcenterId,SUM(Qty) AS Qty FROM #PickingLotOther GROUP BY MOItemId,ProductId,UOMName,FactoryId,WorkcenterId

		--	OPEN PLIOTHERSOR
		--	FETCH NEXT FROM PLIOTHERSOR INTO @MOItemId,@ProductId,@UOMName,@FactoryId,@WorkcenterId,@Qty
		--	WHILE @@FETCH_STATUS =0
		--	BEGIN
		--		--生成领料单明细
		--		EXEC SysGetObjectPKId '','PickingListItem',@PickingListItemId OUTPUT
		--		--调用生产领料单保存事件
		--		EXEC @RESULT= dbo.[PickingListItemOtherSaveData] 
		--		@I_ReturnMessage=@I_ReturnMessage OUTPUT,
		--		@I_OrBitUserId=@I_OrBitUserId,
		--		@I_OrBitUserName=@I_OrBitUserName,
		--		@I_PKId=@PickingListItemId,
		--		@I_ParentPKId=@PickingListOtherId,
		--		@ProductId=@ProductId,
		--		@QtyRequired=@Qty,
		--		@QtyIssued=@Qty,
		--		@WareHouseId=@WorkcenterId,
		--		@UOMName=@UOMName,
		--		@CostCenterName=@CostCenterName

		--		IF ISNULL(@RESULT,0)<>0
		--		BEGIN 
		--			ROLLBACK TRANSACTION PickingLot
		--			RETURN @RESULT
		--		END

		--		UPDATE MOItem SET ItemQtyDone=(ISNULL(ItemQtyDone,0)+@Qty),ItemQtyIssued=(ISNULL(ItemQtyIssued,0)+@Qty) WHERE MOItemId=@MOItemId

		--		DECLARE PLILOTHERSOR CURSOR FOR
		--		SELECT LotSN,Qty,SQty,CellId FROM #PickingLotOther WHERE MOItemId=@MOItemId AND FactoryId=@FactoryId AND WorkcenterId=@WorkcenterId

		--		OPEN PLILOTHERSOR
		--		FETCH NEXT FROM PLILOTHERSOR INTO @LotSN,@Qty,@SQty,@CellId
		--		WHILE @@FETCH_STATUS =0
		--		BEGIN
		--			--生成调拨明细批次
		--			EXEC SysGetObjectPKId '','PickingListItemLot',@PickingListItemLotId OUTPUT
		--			-- 写入发料表
		--			INSERT INTO dbo.PickingListItemLot
		--						(
		--						PickingListItemLotId,
		--						PickingListItemId,
		--						ProductId,
		--						LotSN,
		--						Qty,
		--						ActualPickQty,
		--						PickType,
		--						CellId,
		--						CreateUserId,
		--						CreateDate,
		--						IsPicking
		--						)
		--			VALUES
		--						(
		--						@PickingListItemLotId, -- PickingListItemLotId - char(12)
		--						@PickingListItemId, -- PickingListItemId - char(12)
		--						@ProductId, -- ProductId - char(12)
		--						@LotSN, -- LotSN - nvarchar(50)
		--						@Qty, -- Qty - decimal(18, 8)
		--						@Qty,
		--						'R', -- PickType - char(1)
		--						@CellId, -- CellId - char(12)
		--						@I_OrBitUserId, -- CreateUserId - char(12)
		--						GETDATE(), -- CreateDate - datetime
		--						1
		--						)
		--			FETCH NEXT FROM PLILOTHERSOR INTO @LotSN,@Qty,@SQty,@CellId
		--		END
		--		CLOSE PLILOTHERSOR --关闭游标
		--		DEALLOCATE PLILOTHERSOR --释放游标

		--		FETCH NEXT FROM PLIOTHERSOR INTO @MOItemId,@ProductId,@UOMName,@FactoryId,@WorkcenterId,@Qty
		--	END

		--	CLOSE PLIOTHERSOR --关闭游标
		--	DEALLOCATE PLIOTHERSOR --释放游标

		--	UPDATE A SET A.IsStorage=0 FROM WW_RMInventory A
		--	INNER JOIN LoadingItemLotRecord B ON A.LotSN=B.LotSN
		--	INNER JOIN LoadingItemLotDetail C ON B.LoadingItemLotDetailId=C.LoadingItemLotDetailId
		--	INNER JOIN MOItem D ON C.MOItemId=D.MOItemId
		--	WHERE C.LoadingItemLotId=@LoadingItemLotId  AND B.IsPicking=0 AND D.IsNewItem=1 AND A.Qty<=0

		--	UPDATE A SET A.IsPicking=1 FROM LoadingItemLotRecord AS A
		--	INNER JOIN LoadingItemLotDetail B ON A.LoadingItemLotDetailId=B.LoadingItemLotDetailId
		--	INNER JOIN MOItem C ON B.MOItemId=C.MOItemId
		--	WHERE B.LoadingItemLotId=@LoadingItemLotId AND IsPicking=0 AND C.IsNewItem=1

			
		--	--EXEC @Api_ReturnValue=dbo.APISyncU_PickingListOtherToERP
		--	--	@I_ReturnMessage = @API_ReturnMessage OUTPUT, -- nvarchar(max)
		--	--	@ItemName = N'U_PickingListOther', -- nvarchar(50)
		--	--	@PickingListName = @PickingListName -- nvarchar(50)

		--	--IF @API_ReturnMessage LIKE '%过账成功%'
		--	--	UPDATE PickingList SET PickingListStates='40' WHERE PickingListId=@PickingListOtherId
		--	--ELSE
		--	--	UPDATE PickingList SET PickingListStates='41' WHERE PickingListId=@PickingListOtherId

		--	--SAP过账/杂发单
			
		--END

		--TRUNCATE TABLE #PickingLotOther
		--DROP TABLE #PickingLotOther

		--********************************************* END 调整BOM领料（杂发单） ********************************************
		
		

		IF @@ERROR<>0
			ROLLBACK TRANSACTION PickingLot
		ELSE
			COMMIT TRANSACTION PickingLot

		IF ISNULL(@PickingList_MOId,'')<>''
		BEGIN
			--SAP过账/生产领料单
			DECLARE cursor1  CURSOR LOCAL FAST_FORWARD FOR --创建游标   
			SELECT pli.PickingListItemId,pli.ItemSequence
			FROM dbo.PickingListItem AS pli
			WHERE pli.PickingListId=@PickingListId
			OPEN cursor1 --打开游标
			FETCH NEXT  FROM  Cursor1 INTO @SPickingListItemId,@SItemSequence --从游标变量中读取值		   
			WHILE @@FETCH_STATUS=0 --判断FETCH语句是否执行成功	   
			BEGIN
				IF NOT  EXISTS(SELECT ui.MatDoc FROM dbo.UploadIng AS ui WHERE ui.UploadDateId=@SPickingListItemId AND ISNULL(ui.MatDoc,'')<>'' AND ui.MatDoc!='ServerMessage:物料或类型错误，暂时不支持上传SAP，请检查！！！！！')
				AND NOT EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE ui.UploadDateId=@SPickingListItemId AND ui.ISUpload=1)
				BEGIN  
					IF EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE ui.UploadDateId=@SPickingListItemId AND ui.ISUpload=1)
					BEGIN 

					EXEC dbo.RfcSAPSync @I_ReturnMessage =@API_ReturnMessage OUTPUT,
						@ItemName =N'U_PickingListPR',
							@UploadIngId=@UploadIngId

					IF  @API_ReturnMessage LIKE '%成功%'
					BEGIN 
						UPDATE dbo.PickingListItem set ToSAPStates='过账成功',SAPInfor=REPLACE(@API_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId

					END 
					ELSE 
					BEGIN 
						UPDATE dbo.PickingListItem set ToSAPStates='过账失败',SAPInfor=REPLACE(@API_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId
					END 

					SET @I_ReturnMessage=ISNULL(@I_ReturnMessage,'')+@API_ReturnMessage+@Enter

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

					EXEC dbo.RfcSAPSync @I_ReturnMessage =@API_ReturnMessage OUTPUT,
							@ItemName =N'U_PickingListPR',
							@UploadIngId=@UploadIngId

					IF  @API_ReturnMessage LIKE '%成功%'
					BEGIN 
						UPDATE dbo.PickingListItem set ToSAPStates='过账成功',SAPInfor=REPLACE(@API_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId

					END 
					ELSE 
					BEGIN 
						UPDATE dbo.PickingListItem set ToSAPStates='过账失败',SAPInfor=REPLACE(@API_ReturnMessage, 'ServerMessage:','') WHERE PickingListItemId=@SPickingListItemId
					END 

					SET @I_ReturnMessage=ISNULL(@I_ReturnMessage,'')+@API_ReturnMessage+@Enter
				END  
				END 
				ELSE 
				BEGIN 
					UPDATE dbo.PickingListItem set ToSAPStates='过账成功',SAPInfor='' WHERE PickingListItemId=@SPickingListItemId
				END 
				UPDATE dbo.UploadIng SET ISUpload=0 WHERE UploadIngId=@UploadIngId

				FETCH NEXT FROM Cursor1 INTO @SPickingListItemId,@SItemSequence --读取游标变量中的数据
			END
			CLOSE cursor1 --关闭游标
			DEALLOCATE cursor1; --释放游标

			IF NOT EXISTS(SELECT 1 FROM dbo.PickingList AS pl inner JOIN dbo.PickingListItem AS plm ON plm.PickingListId = pl.PickingListId
								WHERE ISNULL(plm.ToSAPStates ,'')='' AND pl.PickingListId=@PickingListId )	   
			BEGIN
				IF EXISTS(SELECT 1 FROM dbo.PickingList AS pl inner JOIN dbo.PickingListItem AS plm ON plm.PickingListId = pl.PickingListId
				WHERE (plm.ToSAPStates='过账失败' OR ISNULL(plm.ToSAPStates ,'')='') AND pl.PickingListId=@PickingListId )
				BEGIN 
					UPDATE dbo.PickingList SET 
						PickingListStates='41'
					WHERE PickingListId=@PickingListId
				END 
				ELSE 
				BEGIN 
					UPDATE dbo.PickingList SET 
						PickingListStates='40'
					WHERE PickingListId=@PickingListId
				END 
			END
		END

		IF ISNULL(@PickingListOtherId,'')<>''
		BEGIN
			IF NOT EXISTS(SELECT ui.MatDoc FROM dbo.UploadIng AS ui WHERE ui.UploadDateId=@PickingListOtherId AND ISNULL(ui.MatDoc,'')<>'')
			BEGIN  
				IF EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE ui.UploadDateId=@PickingListOtherId AND ui.ISUpload=1)
				BEGIN 
					EXEC dbo.RfcSAPSync @I_ReturnMessage =@I_ReturnMessage OUTPUT,
							@ItemName =N'U_PickingListOther',
							@UploadIngId=@UploadIngId

					--SET @I_ReturnMessage=@I_ReturnMessage+@RFC_ReturnMessage+@Enter
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
						@PickingListOtherId,       -- UploadDateId - char(12)
						'true',     -- ISUpload - bit
						@I_OrBitUserId,       -- UserId - char(12)
						@OtherPickingListName,      -- BillsMark - nvarchar(50)
						N'',      -- MatDoc - nvarchar(50)
						GETDATE() -- CreateDate - datetime
					)

					EXEC dbo.RfcSAPSync @I_ReturnMessage =@API_ReturnMessage OUTPUT,
							@ItemName =N'U_PickingListOther',
							@UploadIngId=@UploadIngId

					IF @API_ReturnMessage LIKE '%成功%' 
					BEGIN 
						UPDATE dbo.PickingList SET 
							PickingListStates='40'
						WHERE PickingListId=@PickingListOtherId
					END 
					ELSE 
					BEGIN 
						UPDATE dbo.PickingList SET 
							PickingListStates='41'
						WHERE PickingListId=@PickingListOtherId
					END 

					--  SET @I_ReturnMessage=@I_ReturnMessage+@RFC_ReturnMessage+@Enter
				END  
			END
		END
		RETURN 0
	END

	--过站处理
	IF @I_Sender IN('LotMove' ,'TonBarrelSNScan')
	BEGIN
		SELECT @MOId=MOId,@SpecificationId=SpecificationId ,@IsComplete=IsComplete,@EquipmentId=EquipmentId FROM LoadingItemLot WHERE LoadingItemLotId=@LoadingItemLotId

		IF @IsComplete<>0
		BEGIN
			SET @I_ReturnMessage='ServerMessage:本次制作已经完成，无法进行下料操作!'+@Enter
			RETURN -1
		END

		SELECT TOP 1 @WorkcenterId=WorkcenterId,@EquipmentNumber=EquipmentNumber FROM Equipment WHERE EquipmentId=@EquipmentId

		--if isnull(@WorkcenterId,'')=''
		--BEGIN
		--	set @I_ReturnMessage='ServerMessage:设备【'+@EquipmentNumber+'】未维护工作中心，请检查!'
		--	return -1
		--end
		
		--验证工单批号是否存在
		SELECT TOP 1 @MOItemId=MOI.MOItemId,@WorkflowStepId=Lot.WorkflowStepId,@MOItemLotId=MOIL.MOItemLotId,
		@MOItemSpecificationId=Lot.SpecificationId,
		@LotId=Lot.LotId,@MOProductId=MO.ProductId,@MOItemTaskId=MOIL.MOItemTaskId,
		@WorkflowId=MO.WorkflowId
		FROM MOItemLot MOIL INNER JOIN MOItem MOI ON MOIL.MOItemId=MOI.MOItemId
		INNER JOIN Lot ON MOIL.LotId=Lot.LotId
		INNER JOIN MO ON MOI.MOId=MO.MOId
		WHERE MOI.MOId=@MOId AND MOIL.LotSN=@TonBarrelSN
	    
		IF ISNULL(@MOItemLotId,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:批次条码【'+@TonBarrelSN+'】错误，请重新扫描!'+@Enter
			RETURN -1
		END
		
		--验证批次是否还在当前工序没有过站
		IF ISNULL(@MOItemSpecificationId,'')<>ISNULL(@SpecificationId,'')
		BEGIN
			SET @I_ReturnMessage='ServerMessage:批次【'+@TonBarrelSN+'】已经扫描过站，请核对!'+@Enter
			RETURN -1
		END
		IF @I_Sender = 'TonBarrelSNScan'
		BEGIN
			SELECT @LotNum=COUNT(1) FROM Lot WHERE MOId=@MOId AND LotStatus='1'
			IF @LotNum<=0 SET @LotNum=1
			--获取标准重量
			SELECT @CurrWeight=SUM(ISNULL(A.Qty,0))/@LotNum FROM LoadingItemLotRecord A
			INNER JOIN LoadingItemLotDetail B ON A.LoadingItemLotDetailId=B.LoadingItemLotDetailId
			INNER JOIN LoadingItemLot C ON B.LoadingItemLotId=C.LoadingItemLotId 
			WHERE C.MOId=@MOId 
			--AND B.LoadingItemLotId=@LoadingItemLotId

			RETURN 0
			--SELECT TOP 1 @CurrWeight=OriginalQty FROM Lot WHERE LotSN=@TonBarrelSN
		END
		IF @I_Sender = 'LotMove'
		BEGIN
			IF @CurrWeight < 0
			BEGIN
				SET @I_ReturnMessage='ServerMessage:批次【'+@TonBarrelSN+'】重量必须大于O，请核对!'+@Enter
				RETURN -1
			END

			SELECT @LotNum=COUNT(1) FROM Lot WHERE MOId=@MOId AND LotStatus='1'
			IF @LotNum<=0 SET @LotNum=1
			SELECT @Weight=SUM(ISNULL(A.Qty,0))/@LotNum FROM LoadingItemLotRecord A
			INNER JOIN LoadingItemLotDetail B ON A.LoadingItemLotDetailId=B.LoadingItemLotDetailId 
			INNER JOIN LoadingItemLot C ON B.LoadingItemLotId=C.LoadingItemLotId 
			WHERE C.MOId=@MOId 
			--AND B.LoadingItemLotId=@LoadingItemLotId

			IF ABS(@CurrWeight-@Weight) >@Weight*0.1
			BEGIN
				SET @I_ReturnMessage='ServerMessage:批次【'+@TonBarrelSN+'】重量录入异常，不能超出原料重量的10%，请核对!'+@Enter
				RETURN -1
			END
			
			BEGIN TRANSACTION LOTMOVE
			DECLARE @LoadingItemLotMoveId IDType
			--插入数据链
			EXEC [dbo].[TxnBase_DataChainMainLine]
				   @DataChainId = @DataChainId OUTPUT,
				   @TxnCode =@TxnCode,
				   @I_PlugInCommand = @I_PlugInCommand,
				   @I_OrBitUserId = @I_OrBitUserId,
				   @I_ResourceId = @I_ResourceId,
				   @LotId = @LotId,
				   @MOId= @MOId,
				   @ProductId = @MOProductId,
				   @WorkcenterId = @WorkcenterId,
				   @SpecificationId = @SpecificationId,
				   @WorkflowStepId = @WorkflowStepId

				   

			EXEC SysGetObjectPKId '','LoadingItemLotMove',@LoadingItemLotMoveId OUTPUT
			--生成下料记录
			INSERT INTO [dbo].[LoadingItemLotMove]
					   ([LoadingItemLotMoveId]
					   ,[LoadingItemLotId]
					   ,[DataChainId]
					   ,[LotId]
					   ,[LotSN]
					   ,[InQty]
					   ,[OutQty]
					   ,[MOId]
					   ,[MOItemId]
					   ,[MOItemTaskId]
					   ,[ProductId]
					   ,[WorkflowId]
					   ,[WorkflowStepId]
					   ,[SpecificationId]
					   ,[Operator]
					   ,[WorkcenterId]
					   ,[EquipmentId]
					   ,[ResourceId]
					   ,[UserId])
				 VALUES
					   (@LoadingItemLotMoveId
					   ,@LoadingItemLotId
					   ,@DataChainId
					   ,@LotId
					   ,@TonBarrelSN
					   ,@CurrWeight
					   ,0
					   ,@MOId
					   ,@MOItemId
					   ,@MOItemTaskId
					   ,@MOProductId
					   ,@WorkflowId
					   ,@WorkflowStepId
					   ,@SpecificationId
					   ,@I_OrBitUserId
					   ,@WorkcenterId
					   ,@EquipmentId
					   ,@I_ResourceId
					   ,@I_OrBitUserId)

			--同步工单和上料表物料用量
			UPDATE L SET L.ItemQtyRequired=M.ItemQtyRequired FROM LoadingItemLotDetail L INNER JOIN MOItem M ON L.MOItemId=M.MOItemId
			WHERE L.LoadingItemLotId=@LoadingItemLotId

			--修改工单批号表，D浆重量
			IF EXISTS(SELECT 1 FROM MOItemLot WHERE MOItemLotId=@MOItemLotId)
				UPDATE MOItemLot SET Qty=@CurrWeight WHERE MOItemLotId=@MOItemLotId

			--修改批次数量
			IF EXISTS(SELECT 1 FROM Lot WHERE LotSN=@TonBarrelSN)
				UPDATE Lot SET Qty=@CurrWeight WHERE LotSN=@TonBarrelSN

			----传送 LotSN 到工作流下一节点
			EXEC @RESULT= [dbo].[TxnBase_LotMove] 
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@LotSN=@TonBarrelSN,
			@LotInDate=@CurDate	
			
			IF @RESULT<>0
			BEGIN
				ROLLBACK TRANSACTION LOTMOVE
				RETURN @RESULT
			END
			

			IF @@ERROR<>0
				ROLLBACK TRANSACTION LOTMOVE
			ELSE
				COMMIT TRANSACTION LOTMOVE

			--工单报工
			IF NOT EXISTS(SELECT 1 FROM dbo.UploadIng WHERE UploadDateId=@MOId AND Line='10')
			AND EXISTS(SELECT 1 FROM MoCraftPath WHERE MoId=@MOId AND WorkstageNO='10')
			BEGIN
				EXEC [dbo].[MOProductionOrder]
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@MOID=@MOId,
				@Line='10',
				@Qty=@CurrWeight
			END
		END
	END
	
	RETURN 0
END
GO
