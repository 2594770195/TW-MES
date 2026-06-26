
-- =============================================
-- Author:		<OBit Team HK0313 >
-- Create date: <2021.09.30>
-- Description:	<超发料领料>
-- Rev: 10.00
-- =============================================
CREATE PROCEDURE  [dbo].[Txn_PickingOfOverIssuedMaterials]
@I_Sender nvarchar(200)='', --客户端执行按钮
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_ExceptionFieldName nvarchar(100)='' output, --向客户端报告引起冲突的字段
@I_LanguageId char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKId char(12) = '',				--主键
@I_SourcePKId char(12)='',			--执行拷贝时传入的源主键  
@I_ParentPKId char(12)='',			--父级主键
@I_Parameter nvarchar(100)='',		--插件参数	
@MOName VARCHAR(32)='',
@ExceedId VARCHAR(256)='',
@ToFactoryId char(12)='',
@ToWareHouseId char(12)='',
@RequiredDate datetime=null

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10)
	DECLARE @RESULT INT =0

	IF @I_Sender='PageLoad'
	BEGIN
		SELECT CAST(0 AS BIT) AS Sel,'' AS ProductName,'' AS ProductDescription,'' AS LotSN,''  AS BeginExceedQty,'' AS SurplusExceedQty,'' AS ItemQtyRequired,'' AS FactoryName,'' AS WorkcenterName,'' AS PickingListName
	END

	IF @I_Sender='PickingQuery'
	BEGIN
		IF ISNULL(@MOName,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择工单！' +@Enter
			RETURN -1
		END

		IF NOT EXISTS(SELECT 1 FROM MO WHERE MOName=@MOName)
		BEGIN
			SET @I_ReturnMessage='ServerMessage:工单信息错误！' +@Enter
			RETURN -1
		END
			
		--SELECT CAST(0 AS BIT) AS Sel,A.ExceedPickingId,F.ProductName,E.ProductDescription,A.BeginExceedQty,A.SurplusExceedQty,C.FactoryName,D.WorkcenterName,G.PickingListName FROM ExceedPicking A
		--INNER JOIN ExceedPickingItem B ON A.ExceedPickingId=B.ExceedPickingId
		--INNER JOIN PickingListItem PLI ON B.PickingListItemId=PLI.PickingListItemId
		--INNER JOIN PickingListItemLot PLIL ON PLI.PickingListItemId=PLIL.PickingListItemId AND PLIL.IsPicking=1
		--INNER JOIN (SELECT PickingListItemId,COUNT(1) AS LOTNUM FROM PickingListItemLot GROUP BY PickingListItemId) AS P ON B.PickingListItemId=P.PickingListItemId AND P.LOTNUM=1
		--INNER JOIN Factory C ON A.FactoryId=C.FactoryId
		--INNER JOIN Workcenter D ON A.WorkcenterId=D.WorkcenterId
		--INNER JOIN Product E ON A.ProductId=E.ProductId
		--INNER JOIN ProductRoot F ON E.ProductRootId=F.ProductRootId
		--INNER JOIN PickingList G ON B.PickingListId=G.PickingListId
		--WHERE A.ProductId IN(SELECT MOItem.ProductId FROM MO 
		--INNER JOIN MOItem ON MO.MOId=MOItem.MOId 
		--WHERE MO.MOName=@MOName AND ISNULL(MOItem.DeleteFlag,'')<>'X')

		SELECT CAST(0 AS BIT) AS Sel,A.ExceedPickingId,F.ProductName,E.ProductDescription,PLIL.LotSN,A.BeginExceedQty,A.SurplusExceedQty,(MOI.ItemQtyRequired-MOI.ItemQtyIssued) AS ItemQtyRequired,C.FactoryName,D.WorkcenterName,G.PickingListName 
        FROM MO
		INNER JOIN MOItem MOI ON MO.MOId=MOI.MOId AND ISNULL(MOI.DeleteFlag,'')<>'X'
		INNER JOIN ExceedPicking A ON MOI.ProductId=A.ProductId
		INNER JOIN ExceedPickingItem B ON A.ExceedPickingId=B.ExceedPickingId
		INNER JOIN PickingListItem PLI ON B.PickingListItemId=PLI.PickingListItemId
		INNER JOIN PickingListItemLot PLIL ON PLI.PickingListItemId=PLIL.PickingListItemId AND PLIL.IsPicking=1
		INNER JOIN (SELECT PickingListItemId,COUNT(1) AS LOTNUM FROM PickingListItemLot GROUP BY PickingListItemId) AS P ON B.PickingListItemId=P.PickingListItemId AND P.LOTNUM=1
		INNER JOIN Factory C ON A.FactoryId=C.FactoryId
		INNER JOIN Workcenter D ON A.WorkcenterId=D.WorkcenterId
		INNER JOIN Product E ON A.ProductId=E.ProductId
		INNER JOIN ProductRoot F ON E.ProductRootId=F.ProductRootId
		INNER JOIN PickingList G ON B.PickingListId=G.PickingListId
		WHERE MO.MOName=@MOName
	END

	IF @I_Sender='CreatePicking'
	BEGIN
		IF ISNULL(@MOName,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择工单！' +@Enter
			RETURN -1
		END

		IF NOT EXISTS(SELECT 1 FROM MO WHERE MOName=@MOName)
		BEGIN
			SET @I_ReturnMessage='ServerMessage:工单信息错误！' +@Enter
			RETURN -1
		END

		IF ISNULL(@ExceedId,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择要领料的物料！' +@Enter
			RETURN -1
		END
		--判定是否有无法自动发料的物料（同时包含多个批号，无法确定发料批号）

		DECLARE @MOId CHAR(12)
		DECLARE @DivisionId CHAR(12)
		DECLARE @NowDate DATETIME =GETDATE()
		DECLARE @PickingListDescription NVARCHAR(100)='超领料发料'
		DECLARE @PickingListId CHAR(12)
		SELECT @MOId=MOId FROM MO WHERE MOName=@MOName

		--开启事务
		BEGIN TRANSACTION Exceed

		select top 1 @DivisionId=DivisionId from Division where FactoryId=@ToFactoryId
		--创建领料单
		EXEC SysGetObjectPKId '','PickingList',@PickingListId OUTPUT
	    --调用生产领料单保存事件
		EXEC @RESULT= PickingListPRSaveData 
		@I_ReturnMessage=@I_ReturnMessage OUTPUT,
		@I_OrBitUserId=@I_OrBitUserId,
		@I_OrBitUserName=@I_OrBitUserName,
		@I_PKId=@PickingListId,
		@CreateUserName=@I_OrBitUserName,
		@CreateDate=@NowDate,
		@DateRequired=@RequiredDate,
		@PickingListTypeCode='02',
		@FactoryId=@ToFactoryId,
		@DivisionId=@DivisionId,
		@ToWorkcenterId=@ToWareHouseId,
		@PickingListDescription=@PickingListDescription

		IF ISNULL(@RESULT,0)<>0
		BEGIN 
			ROLLBACK transaction Exceed
			RETURN -1
		END

		--生成生产领料单工单
		DECLARE @PickingList_MOId char(12)=''
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
			ROLLBACK transaction Exceed
			RETURN -1
		END

		--循环插入选择领料的物料
		SELECT ROW_NUMBER() OVER (ORDER BY A.col) AS ROWKEY,A.col AS ExceedPickingId,B.ProductId,B.SurplusExceedQty,
		C.MOItemId,C.ItemQtyRequired,B.WorkcenterId,E.UOMName,PLIL.LotSN INTO #TEMP
		FROM DB_Split(@ExceedId,',') A
		INNER JOIN ExceedPicking B ON A.col=B.ExceedPickingId
		INNER JOIN (SELECT MOItem.ProductId,MOItem.MOItemId,(MOItem.ItemQtyRequired-MOItem.ItemQtyIssued) AS ItemQtyRequired FROM MO 
		INNER JOIN MOItem ON MO.MOId=MOItem.MOId 
		WHERE MO.MOName=@MOName AND ISNULL(MOItem.DeleteFlag,'')<>'X' AND ItemQtyRequired-ItemQtyIssued>0) C ON B.ProductId=C.ProductId
		INNER JOIN Product D ON B.ProductId=D.ProductId
		LEFT JOIN UOM E ON D.UsageUOMId=E.UOMId
		INNER JOIN ExceedPickingItem F ON A.col=F.ExceedPickingId
		INNER JOIN PickingListItem PLI ON F.PickingListItemId=PLI.PickingListItemId
		INNER JOIN PickingListItemLot PLIL ON PLI.PickingListItemId=PLIL.PickingListItemId AND PLIL.IsPicking=1

		DECLARE @EXCOUNT INT=0
		DECLARE @CURREX INT=1
		DECLARE @MOItemId CHAR(12)
		DECLARE @ProductId CHAR(12)
		DECLARE @WorkcenterId CHAR(12)
		DECLARE @ExceedPickingId CHAR(12)
		DECLARE @QtyRequired DECIMAL(18,3)
		DECLARE @UOMName NVARCHAR(64)
		DECLARE @SurplusExceedQty DECIMAL(18,3)
		DECLARE @LotSN LotSN
		DECLARE @PickingListName NVARCHAR(64)

		SELECT @EXCOUNT=COUNT(1) FROM #TEMP
		
		WHILE @CURREX<=@EXCOUNT
		BEGIN
			SELECT 
				@ExceedPickingId=ExceedPickingId,
				@ProductId=ProductId,
				@MOItemId=MOItemId,
				@QtyRequired=ItemQtyRequired,
				@WorkcenterId=WorkcenterId,
				@UOMName=UOMName,
				@SurplusExceedQty=SurplusExceedQty,
				@LotSN=LotSN
			FROM #TEMP WHERE ROWKEY=@CURREX

			IF @SurplusExceedQty<@QtyRequired
				SET @QtyRequired=@SurplusExceedQty

			DECLARE @PickingListItemId char(12)=''
			EXEC SysGetObjectPKId '','PickingListItem',@PickingListItemId OUTPUT
			--生成领料单明细
			EXEC @RESULT= dbo.[PickingListItemPRSaveData] 
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_OrBitUserName=@I_OrBitUserName,
			@I_PKId=@PickingListItemId,
			@I_ParentPKId=@PickingListId,
			@MOItemIdNO=@MOItemId,
			@MOName=@MOName,
			@ProductId=@ProductId,
			@QtyRequired=@QtyRequired,
			@QtyIssued=0,
			@WareHouseId=@WorkcenterId,
			@UOMName=@UOMName

			IF ISNULL(@RESULT,0)<>0
			BEGIN 
				ROLLBACK transaction Exceed
				RETURN -1
			END

			--生成调拨明细批次
			DECLARE @PickingListItemLotId char(12)=''
			EXEC SysGetObjectPKId '','PickingListItemLot',@PickingListItemLotId OUTPUT
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
						CreateDate,
						IsPicking
						)
			VALUES
						(
						@PickingListItemLotId, -- PickingListItemLotId - char(12)
						@PickingListItemId, -- PickingListItemId - char(12)
						@ProductId, -- ProductId - char(12)
						@LotSN, -- LotSN - nvarchar(50)
						@QtyRequired, -- Qty - decimal(18, 8)
						'R', -- PickType - char(1)
						'', -- CellId - char(12)
						@I_OrBitUserId, -- CreateUserId - char(12)
						GETDATE(), -- CreateDate - datetime
						1
						)

			UPDATE ExceedPicking SET SurplusExceedQty-=@QtyRequired WHERE ExceedPickingId=@ExceedPickingId

			UPDATE dbo.MOItem SET 
				ItemQtyIssued=ISNULL(ItemQtyIssued,0)+ CASE WHEN ISNULL(@QtyRequired,0)>@QtyRequired THEN @QtyRequired ELSE @QtyRequired END 
			WHERE MOItemId=@MOItemId 

			SET @CURREX+=1
		END

		UPDATE PickingList SET PickingListStates='30' WHERE PickingListId=@PickingListId

		IF @@ERROR<>0
		BEGIN
			ROLLBACK TRANSACTION Exceed
			set @I_ReturnMessage='ServerMessage:超发领料单创建失败!'
			RETURN -1
		END
		ELSE
		BEGIN
			COMMIT TRANSACTION Exceed
			SELECT CAST(0 AS BIT) AS Sel,'' AS ProductName,'' AS ProductDescription,'' AS LotSN,''  AS BeginExceedQty,'' AS SurplusExceedQty,'' AS ItemQtyRequired,'' AS FactoryName,'' AS WorkcenterName,'' AS PickingListName

			SELECT '' AS ToFactoryId,'' AS ToFactoryName,'' AS ToWareHouseName,'' AS ToWareHouseId,'' AS RequiredDate,'' AS ExceedId,'' AS MOName
			select top 1 @PickingListName=ISNULL(PickingListName,'') from PickingList where PickingListId=@PickingListId
			set @I_ReturnMessage='ServerMessage:超发领料单已创建，领料单号['+@PickingListName+']!'
		END
		
	END

	RETURN @RESULT
END
go

