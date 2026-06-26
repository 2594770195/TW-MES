
-- =============================================
-- Author:		<OBit Team HK0313 >
-- Create date: <2021.11.10>
-- Description:	<线边仓领料>
-- Rev: 10.00
-- =============================================
CREATE PROCEDURE  [dbo].[Txn_PickingToProductionLine]
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

@PickingListName VARCHAR(32)='',
@ExceedId VARCHAR(256)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10)
	DECLARE @RESULT INT =0

	DECLARE @PickingListId CHAR(12)
	DECLARE @PickingListStates VARCHAR(20)

	DECLARE @FSWorkCenterId CHAR(12)
	DECLARE @UVWorkCenterId CHAR(12)
	

	IF @I_Sender='PageLoad'
	BEGIN
		SELECT CAST(0 AS BIT) AS Sel,'' AS ExceedPickingId,'' AS ProductName,'' AS ProductDescription,'' AS LotSN,''  AS BeginExceedQty,'' AS SurplusExceedQty,'' AS ItemQtyRequired,'' AS FactoryName,'' AS WorkcenterName
	END

	IF @I_Sender='PickingQuery'
	BEGIN
		IF ISNULL(@PickingListName,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择领料单！' +@Enter
			RETURN -1
		END

		SELECT @PickingListId=PickingListId,@PickingListStates=PickingListStates FROM PickingList WHERE PickingListName=@PickingListName

		IF ISNULL(@PickingListId,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:领料单信息错误！' +@Enter
			RETURN -1
		END

		IF @PickingListStates='10'
		BEGIN
			SET @I_ReturnMessage='ServerMessage:领料单未审核！' +@Enter
			RETURN -1
		END

		IF @PickingListStates='30'
		BEGIN
			SET @I_ReturnMessage='ServerMessage:领料单已完成过账！' +@Enter
			RETURN -1
		END

		IF @PickingListStates<>'20'
		BEGIN
			SET @I_ReturnMessage='ServerMessage:领料单不是[已审核]状态！' +@Enter
			RETURN -1
		END


		SELECT 
			CAST(0 AS BIT) AS Sel,
			C.ExceedPickingId,
			K.ProductName,
			J.ProductDescription,
			F.LotSN,
			C.BeginExceedQty,
			C.SurplusExceedQty,
			(B.QtyRequired-B.QtyIssued) AS ItemQtyRequired,
			H.FactoryName,
			I.WorkcenterName
		FROM PickingList A
		INNER JOIN PickingListItem B ON A.PickingListId=B.PickingListId
		INNER JOIN ExceedPicking C ON B.ProductId=C.ProductId AND B.WorkcenterId=C.WorkcenterId
		INNER JOIN ExceedPickingItem D ON C.ExceedPickingId=D.ExceedPickingId AND B.ProductId = D.ProductId
		INNER JOIN PickingListItem E ON D.PickingListItemId=E.PickingListItemId
		INNER JOIN PickingListItemLot F ON E.PickingListItemId=F.PickingListItemId AND F.IsPicking=1
		INNER JOIN (SELECT PickingListItemId,COUNT(1) AS LOTNUM FROM PickingListItemLot GROUP BY PickingListItemId) AS G ON D.PickingListItemId=G.PickingListItemId AND G.LOTNUM=1
		INNER JOIN Factory H ON C.FactoryId=H.FactoryId
		INNER JOIN Workcenter I ON C.WorkcenterId=I.WorkcenterId
		INNER JOIN Product J ON C.ProductId=J.ProductId
		INNER JOIN ProductRoot K ON K.ProductRootId=J.ProductRootId
		INNER JOIN PickingList L ON D.PickingListId=L.PickingListId
		WHERE A.PickingListId=@PickingListId AND (B.QtyRequired-B.QtyIssued)>0
	END

	IF @I_Sender='PickingCheckLot'
	BEGIN
		IF ISNULL(@PickingListName,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择领料单！' +@Enter
			RETURN -1
		END

		SELECT @PickingListId=PickingListId,@PickingListStates=PickingListStates FROM PickingList WHERE PickingListName=@PickingListName

		IF ISNULL(@PickingListId,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:领料单信息错误！' +@Enter
			RETURN -1
		END

		IF @PickingListStates='10'
		BEGIN
			SET @I_ReturnMessage='ServerMessage:领料单未审核！' +@Enter
			RETURN -1
		END

		IF @PickingListStates='30'
		BEGIN
			SET @I_ReturnMessage='ServerMessage:领料单已完成过账！' +@Enter
			RETURN -1
		END

		IF @PickingListStates<>'20'
		BEGIN
			SET @I_ReturnMessage='ServerMessage:领料单不是[已审核]状态！' +@Enter
			RETURN -1
		END

		IF ISNULL(@ExceedId,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择要领料的物料！' +@Enter
			RETURN -1
		END
		--判定是否有无法自动发料的物料（同时包含多个批号，无法确定发料批号）

		DECLARE @NowDate DATETIME =GETDATE()
		DECLARE @PickingListDescription NVARCHAR(100)='线边仓领料【工单超发料领料】'


		SELECT 
			ROW_NUMBER() OVER (ORDER BY A.col) AS ROWKEY,
			A.col AS ExceedPickingId,
			B.ProductId,
			E.LotSN,
			AA.SurplusExceedQty,
			C.PickingListId,
			C.PickingListItemId,
			C.MOId,
			C.MOItemId,
			C.ItemQtyRequired,
			F.CellId
		INTO #TEMP
		FROM DB_Split(@ExceedId,',') A
		INNER JOIN ExceedPicking AA ON A.col=AA.ExceedPickingId
		INNER JOIN ExceedPickingItem B ON A.col=B.ExceedPickingId
		INNER JOIN (
			SELECT PickingListId,PickingListItemId,MOId,MOItemId,ProductId,(QtyRequired-QtyIssued) AS ItemQtyRequired FROM PickingListItem 
			WHERE PickingListId=@PickingListId AND QtyRequired-QtyIssued>0) C ON B.ProductId=C.ProductId
		INNER JOIN PickingListItem D ON B.PickingListItemId=D.PickingListItemId
		INNER JOIN PickingListItemLot E ON D.PickingListItemId=E.PickingListItemId AND E.IsPicking=1
		INNER JOIN WW_RMInventory F ON E.LotSN= F.LotSN
		WHERE C.ItemQtyRequired>0


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
		DECLARE @PickingListItemId CHAR(12)
		DECLARE @CellId CHAR(12)
		DECLARE @PickingListItemLotId char(12)=''


		SELECT @EXCOUNT=COUNT(1) FROM #TEMP
		--开启事务
		BEGIN TRANSACTION Exceed

		WHILE @CURREX<=@EXCOUNT
		BEGIN
			SELECT 
				@ExceedPickingId=ExceedPickingId,
				@ProductId=ProductId,
				@MOItemId=MOItemId,
				@QtyRequired=ItemQtyRequired,
				@PickingListId=PickingListId,
				@PickingListItemId=PickingListItemId,
				@SurplusExceedQty=SurplusExceedQty,
				@LotSN=LotSN,
				@CellId=CellId,
				@QtyRequired=ItemQtyRequired
			FROM #TEMP WHERE ROWKEY=@CURREX

			--IF @QtyRequired<=0 CONTINUE;

			IF @SurplusExceedQty<@QtyRequired
				SET @QtyRequired=@SurplusExceedQty


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
						@QtyRequired, -- Qty - decimal(18, 8)
						@QtyRequired,
						'R', -- PickType - char(1)
						@CellId, -- CellId - char(12)
						@I_OrBitUserId, -- CreateUserId - char(12)
						GETDATE(), -- CreateDate - datetime
						1
						)

			UPDATE ExceedPicking SET SurplusExceedQty-=@QtyRequired WHERE ExceedPickingId=@ExceedPickingId

			UPDATE dbo.MOItem SET 
				ItemQtyIssued=ISNULL(ItemQtyIssued,0)+ ISNULL(@QtyRequired,0) 
			WHERE MOItemId=@MOItemId 

			UPDATE PickingListItem SET QtyIssued+=@QtyRequired WHERE PickingListItemId=@PickingListItemId

			UPDATE #TEMP SET ItemQtyRequired-=@QtyRequired WHERE PickingListItemId=@PickingListItemId

			SET @CURREX+=1;
		END
		

		--UPDATE PickingList SET PickingListStates='30' WHERE PickingListId=@PickingListId

		IF @@ERROR<>0
		BEGIN
			ROLLBACK TRANSACTION Exceed
			set @I_ReturnMessage='ServerMessage:领料失败!'
			RETURN -1
		END
		ELSE
		BEGIN
			COMMIT TRANSACTION Exceed
			SELECT CAST(0 AS BIT) AS Sel,'' AS ExceedPickingId,'' AS ProductName,'' AS ProductDescription,'' AS LotSN,''  AS BeginExceedQty,'' AS SurplusExceedQty,'' AS ItemQtyRequired,'' AS FactoryName,'' AS WorkcenterName

			SELECT '' AS ExceedId,'' AS PickingListName
			set @I_ReturnMessage='ServerMessage:领料单['+@PickingListName+']领料完成，请查看审核!'
		END
		
	END

	RETURN @RESULT
END
go

