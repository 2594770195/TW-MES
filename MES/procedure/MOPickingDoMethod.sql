-- =============================================
-- Author:		<OrBit Team：HK0313 >
-- Create date: <2022.1.13>
-- Description:	补料
-- =============================================
CREATE PROCEDURE  [dbo].[MOPickingDoMethod]
@I_Sender nvarchar(200)='', --客户端执行按钮
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_ExceptionFieldName nvarchar(100)='' output, --向客户端报告引起冲突的字段
@I_LanguageId char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKid char(12) ='',				--主键
@I_ParentPKId char(12)='',			--父级主键
@I_Parameter nvarchar(100)=''		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.


AS
BEGIN

	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @return_value  int
	DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10)
	DECLARE @MOId CHAR(12)
	DECLARE @MOName NVARCHAR(50)
	DECLARE @MOStates CHAR(10)
	DECLARE @ProductName NVARCHAR(50)
	DECLARE @ProductLine VARCHAR(50)
	DECLARE @WorkcenterId CHAR(12)
	DECLARE @InterfaceItemId CHAR(12)
	DECLARE @UploadIngId CHAR(12)

	SET @MOId =''
	SET @MOName =''
	SET @MOStates =''
	SET @return_value = -1

	DECLARE @RowId INT=1
	DECLARE @RowCount INT=0

	DECLARE @PickingListId CHAR(12)
	DECLARE @PickingList_MOId char(12)=''
	DECLARE @PickingListItemId char(12)=''
	DECLARE @PickingListItemLotId char(12)=''
	DECLARE @DivisionId CHAR(12)
	DECLARE @PickingListDescription NVARCHAR(64)='工单生产缺料，申请补料'

	DECLARE @LotSN VARCHAR(100)
	DECLARE @ProductId CHAR(12)
	DECLARE @Qty DECIMAL(18,3)
	DECLARE @SQty DECIMAL(18,3)
	DECLARE @UOMName VARCHAR(50)
	DECLARE @CellId CHAR(12)
	DECLARE @PickingListName VARCHAR(50)

	DECLARE @PickingQty DECIMAL(18,8)
	DECLARE @WWQty DECIMAL(18,8)
	DECLARE @FactoryId CHAR(12)
	DECLARE @CurDate DATETIME=GETDATE()
	DECLARE @MOItemId CHAR(12)
	DECLARE @UOMId CHAR(12)

	DECLARE @SNRuleId CHAR(12)
	DECLARE @NewLotSN VARCHAR(100)

	DECLARE @API_ReturnMessage NVARCHAR(MAX)=''

	SELECT @SNRuleId=SNRuleId FROM dbo.SNRule WHERE SNRuleName='WW_MP_LotSN' AND IsActivity=1

	--检查元对象方法用户是否有权限
	exec @return_value=[dbo].[MetadataPermissionCheckDoMethod]
		@I_ReturnMessage=@I_ReturnMessage output,
		@I_OrBitUserId=@I_OrBitUserId,
		@I_OrBitUserName=@I_OrBitUserName,
		@I_Sender=@I_Sender

	if @return_value=-1
	begin
		set @I_ReturnMessage=@I_ReturnMessage
		return -1
	end
	
	 --获取工单信息
	select 
		@MOId=MO.MOId,
		@MOName=MO.MOName, 
		@MOStates=MO.MOStates,
		@ProductLine=ProductLine
	from MO 
	where MOId=@I_PKid

	if ISNULL(@MOId,'')=''
	begin
		set @I_ReturnMessage='ServerMessage:请选择有效项!'
		return -1
	END

	IF @MOStates='10'
	BEGIN
		set @I_ReturnMessage='ServerMessage:工单未审核!'
		return -1
	END

	IF ISNULL(@ProductLine,'')=''
	BEGIN
		set @I_ReturnMessage='ServerMessage:请选择【工作产线】!'
		return -1
	END

	IF EXISTS(SELECT 1 FROM MOItem 
	WHERE MOId=@MOId AND DeleteFlag IN(NULL,'','0') AND LineSequence<>'000' AND ISNULL(ItemQtyIssued,0)<=0)
	BEGIN
		set @I_ReturnMessage='ServerMessage:工单有物料还未进行领料，请使用【工单领料申请】进行领料!'
		return -1
	END

	SELECT @WorkcenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName=(CASE @ProductLine 
	WHEN 'FS' THEN 'FSXB'
	WHEN 'UV' THEN 'UVXB'
	WHEN 'HX' THEN 'HXXB'
	WHEN 'SX' THEN 'SXXB'
	WHEN 'TZ' THEN 'SOXB'
	ELSE '' END)

	DECLARE @MOProduct TABLE(
		RowId INT IDENTITY(1,1) NOT NULL,
		MOItemId CHAR(12),
		ProductId CHAR(12),
		PickingQty DECIMAL(18,8),
		UOMId CHAR(12)
	)

	--获取需要进行补料的物料
	INSERT INTO @MOProduct(MOItemId,ProductId,PickingQty,UOMId)
	SELECT MOItemId,ProductId,(ItemQtyRequired-ItemQtyIssued) AS PickingQty,UOMId FROM MOItem 
	WHERE MOId=@MOId AND DeleteFlag IN(NULL,'','0') AND LineSequence<>'000' AND ItemQtyIssued<ItemQtyRequired


	SELECT @RowCount=COUNT(1) FROM @MOProduct

	IF @RowCount<=0
	BEGIN
		set @I_ReturnMessage='ServerMessage:没有需要补料的物料!'
		return -1
	END

	--检查线边仓库存是否充足
	WHILE @RowId<=@RowCount
	BEGIN
		--
		SELECT @ProductId=ProductId,@PickingQty=PickingQty FROM @MOProduct WHERE RowId=@RowId

		SELECT @WWQty=SUM(Qty) FROM WW_RMInventory WHERE ProductId=@ProductId AND LotStatus='1' AND IsStorage=1 AND Qty>0 AND WorkcenterId=@WorkcenterId

		SELECT @ProductName=TProductName FROM Product WHERE ProductId=@ProductId

		IF ISNULL(@WWQty,0)<@PickingQty OR ISNULL(@WWQty,0)<=0
		BEGIN
			set @I_ReturnMessage='ServerMessage:工单['+@MOName+']需要补料的物料['+@ProductName+']线边仓库存不足，无法进行补料!'
			return -1
		END

		SET @RowId+=1;
	END

	--创建领料单
	SELECT TOP 1 @FactoryId=FactoryId FROM Workcenter where WorkcenterId=@WorkcenterId

	SELECT TOP 1 @DivisionId=DivisionId FROM Division WHERE FactoryId=@FactoryId

	BEGIN TRANSACTION PickingLot

	EXEC SysGetObjectPKId '','PickingList',@PickingListId OUTPUT
	--调用生产领料单保存事件
	EXEC @return_value= PickingListPRSaveData 
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

	IF @return_value<>0
	BEGIN
		ROLLBACK TRANSACTION PickingLot
		RETURN @return_value
	END

	SELECT @PickingListName=PickingListName FROM PickingList WHERE PickingListId=@PickingListId

	--生成生产领料单工单
	EXEC SysGetObjectPKId '','PickingList_MO',@PickingList_MOId OUTPUT
	--调用生产领料单保存事件
	EXEC @return_value= dbo.[PickingList_MOSaveData] 
	@I_ReturnMessage=@I_ReturnMessage OUTPUT,
	@I_OrBitUserId=@I_OrBitUserId,
	@I_OrBitUserName=@I_OrBitUserName,
	@I_PKId=@PickingList_MOId,
	@I_ParentPKId=@PickingListId,
	@MOId=@MOId,
	@MOName=@MOName

	IF ISNULL(@return_value,0)<>0
	BEGIN 
		ROLLBACK TRANSACTION PickingLot
		RETURN @return_value
	END

	SET @RowId=1
	WHILE @RowId<=@RowCount
	BEGIN
		--
		SELECT @MOItemId=MOItemId,@ProductId=ProductId,@UOMId=UOMId,@PickingQty=PickingQty FROM @MOProduct WHERE RowId=@RowId

		SELECT @UOMName=UOMName FROM UOM WHERE UOMId=@UOMId
		--生成领料单明细
		EXEC SysGetObjectPKId '','PickingListItem',@PickingListItemId OUTPUT
		--调用生产领料单保存事件
		EXEC @return_value= dbo.[PickingListItemPRSaveData] 
		@I_ReturnMessage=@I_ReturnMessage OUTPUT,
		@I_OrBitUserId=@I_OrBitUserId,
		@I_OrBitUserName=@I_OrBitUserName,
		@I_PKId=@PickingListItemId,
		@I_ParentPKId=@PickingListId,
		@MOItemIdNO=@MOItemId,
		@MOName=@MOName,
		@ProductId=@ProductId,
		@QtyRequired=@PickingQty,
		@QtyIssued=@PickingQty,
		@WareHouseId=@WorkcenterId,
		@UOMName=@UOMName

		IF ISNULL(@return_value,0)<>0
		BEGIN 
			ROLLBACK TRANSACTION PickingLot
			RETURN @return_value
		END

		UPDATE MOItem SET ItemQtyDone+=@PickingQty WHERE MOItemId=@MOItemId

		--自动发料
		DECLARE PLILSOR CURSOR FOR
		SELECT LotSN,Qty,CellId FROM WW_RMInventory WHERE ProductId=@ProductId AND LotStatus='1' AND IsStorage=1 AND Qty>0 AND WorkcenterId=@WorkcenterId ORDER BY EntryDate,IsSM DESC

		OPEN PLILSOR
		FETCH NEXT FROM PLILSOR INTO @LotSN,@Qty,@CellId
		WHILE @@FETCH_STATUS =0
		BEGIN
			--
			IF @Qty>@PickingQty
			BEGIN
				--批次拆分
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

				IF @return_value<>0
				BEGIN
					ROLLBACK TRANSACTION SplitLot
					RETURN @return_value
				END

				SET @LotSN=@NewLotSN
			END

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
						0
						)

			--更新批号状态
			UPDATE dbo.WW_RMInventory SET 
				LotStatus='1',
				IsStorage=0
			WHERE LotSN=@LotSN

			FETCH NEXT FROM PLILSOR INTO @LotSN,@Qty,@CellId
		END
		CLOSE PLILSOR --关闭游标
		DEALLOCATE PLILSOR --释放游标
		
		SET @RowId+=1;
	END
	IF @@ERROR<>0
		ROLLBACK TRANSACTION PickingLot
	ELSE
		COMMIT TRANSACTION PickingLot


    DECLARE @SPickingListItemId CHAR(12)=''
	DECLARE @SItemSequence NVARCHAR(30)=''
	
	DECLARE @RFC_ReturnMessage NVARCHAR(MAX)=''
	--DECLARE @PickingList_MOId CHAR(12)=''
	DECLARE @MOName1 NVARCHAR(50)=''


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
			   IF NOT EXISTS(SELECT 1 FROM  dbo.UploadIng AS ui WHERE  ui.ISUpload=1 AND ui.UploadInterfaceId='IFIT000000T5') 
			   BEGIN 
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


				END 
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
 
	--自动确认过账
	--EXEC dbo.RfcSAPSync @I_ReturnMessage =@I_ReturnMessage OUTPUT,
	--			@ItemName =N'U_PickingListPR'

	--IF @I_ReturnMessage LIKE '%过账成功%'
	--	UPDATE PickingList SET PickingListStates='40' WHERE PickingListId=@PickingListId
	--ELSE
	--	UPDATE PickingList SET PickingListStates='41' WHERE PickingListId=@PickingListId
	
END
go

