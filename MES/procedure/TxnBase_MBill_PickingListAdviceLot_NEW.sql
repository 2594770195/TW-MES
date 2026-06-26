
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/03/18 09:38:35:3194>
-- Description:   <领料单:获取建议储位号>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[TxnBase_MBill_PickingListAdviceLot_NEW]
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId CHAR(12)='',			--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PlugInCommand VARCHAR(5)='',		--插件命令
------------------------------
@PickingListName NVARCHAR(50)='',
@ProductId CHAR(12)='',					--（可选）指定要找具体物料的建议批次，如果没有指定，则找出领料单明细所有物料的建议批次。
@CurWareHouseId CHAR(12)='',			--（可选）当前扫描的仓库Id。为了排序显示，适用于一个领料单明细存在不同仓库的情况
@CurCellId CHAR(12)='',					--（可选）当前扫描的储位号Id。为了显示当前位置
@MaxQty INT=0,							--最大批号个数。0不限制，大于0限制
@AdviceCell NVARCHAR(MAX)='' OUTPUT		--输出建议储位，如果是多个，则按“,”分隔

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
	DECLARE @RowCount INT=0
	DECLARE @RowId INT=0
  
	--bill
	DECLARE @PickingListId CHAR(12)=''
	DECLARE @FactoryId CHAR(12)=''
	--billItem
	DECLARE @ProductName NVARCHAR(50)=''
	DECLARE @WarehouseId CHAR(12)=''
	DECLARE @WarehouseName NVARCHAR(50)=''
	DECLARE @QtyRequired DECIMAL(18,6)=0
	DECLARE @QtyIssued DECIMAL(18,6)=0
	DECLARE @OweQty DECIMAL(18,6)=0 --欠料数
	DECLARE @ProductDescription NVARCHAR(100)

	--输入
	DECLARE @IsCurWorkcenter BIT=0

    DECLARE @Moitemid CHAR(12)=''

	--保存需要建议的物料信息
	DECLARE @Temp1 TABLE(
		RowId INT IDENTITY(1,1),
		ProductId CHAR(12),
		WorkcenterId CHAR(12),
		QtyRequired DECIMAL(18,6),
		QtyIssued DECIMAL(18,6),
		IsCurWorkcenter BIT,
        MoItemId  CHAR(12)  
	)

	DECLARE @Temp_AdviceLot TABLE(
		RowLogo NVARCHAR(50),
		ProductName NVARCHAR(50),
		LotSN NVARCHAR(50),
		Qty FLOAT,
		UOMName NVARCHAR(50),
		ProductionDate NVARCHAR(50),
		WarehouseName NVARCHAR(50),
		ProductDescription NVARCHAR(100),
		CellName NVARCHAR(50),
		Cell_RouteOrder NVARCHAR(50), --储位的路线顺序
		IsCurWorkcenter BIT --是否是当前仓库
	)

    --根据不同情况筛选不同数据
    DECLARE @Temp2 TABLE(
		
		LotSN NVARCHAR(50),
		Qty DECIMAL(18,6),
		UOMName NVARCHAR(50),
		ProductionDate NVARCHAR(50),
		CellId NVARCHAR(50),
		CellName NVARCHAR(50),
		WorkcenterName NVARCHAR(50),
		RouteOrder NVARCHAR(50),
		RowId INT
	)

	IF ISNULL(@PickingListName,'')=''
	BEGIN
		SELECT 
				RowLogo,
				CellName,
				ProductName,
				ProductDescription,
				LotSN,
				Qty,
				UOMName,
				ProductionDate,
				WarehouseName,
				Cell_RouteOrder
		FROM @Temp_AdviceLot
		RETURN 0
	END

	--获取单据明细
	SELECT @PickingListId=PickingListId,@FactoryId=FactoryId
	FROM dbo.PickingList 
	WHERE PickingListName=@PickingListName

	IF ISNULL(@PickingListId,'')=''
	BEGIN
		SELECT 
				RowLogo,
				CellName,
				ProductName,
				ProductDescription,
				LotSN,
				Qty,
				UOMName,
				ProductionDate,
				WarehouseName,
				Cell_RouteOrder
		FROM @Temp_AdviceLot
		RETURN 0
	END

	IF NOT EXISTS(SELECT 1 FROM dbo.PickingList WHERE PickingListId=@PickingListId AND PickingListStates IN('10','20','21'))
	BEGIN
		SELECT 
				RowLogo,
				CellName,
				ProductName,
				ProductDescription,
				LotSN,
				Qty,
				UOMName,
				ProductionDate,
				WarehouseName,
				Cell_RouteOrder
		FROM @Temp_AdviceLot
		RETURN 0
	END

    --20260319按全部仓库先进先出
    SET @CurWareHouseId=''
	SET @CurWareHouseId=ISNULL(@CurWareHouseId,'')
	SET @CurCellId=ISNULL(@CurCellId,'')

	--获取要查找的物料
	IF ISNULL(@ProductId,'')=''
	BEGIN 
		INSERT INTO @Temp1
				(
					ProductId,
					WorkcenterId,
					QtyRequired,
					QtyIssued,
					IsCurWorkcenter,
                    moitemid
				)
		SELECT ProductId,
				WorkcenterId,
				SUM(ISNULL(QtyRequired,0)),
				SUM(ISNULL(QtyIssued,0) ),
				CASE WHEN WorkcenterId=@CurWareHouseId THEN 1
					ELSE 0 END
                ,moitemid
		FROM dbo.PickingListItem 
		WHERE PickingListId=@PickingListId
		AND QtyRequired>QtyIssued 
		AND DeleteFlag=''
		GROUP BY ProductId,WorkcenterId,moitemid
	END
	ELSE
	BEGIN 
		INSERT INTO @Temp1
				(
					ProductId,
					WorkcenterId,
					QtyRequired,
					QtyIssued,
					IsCurWorkcenter,
                    moitemid
				)
		SELECT ProductId,
				WorkcenterId,
				SUM(ISNULL(QtyRequired,0)),
				SUM(ISNULL(QtyIssued,0) ),
				CASE WHEN WorkcenterId=@CurWareHouseId THEN 1
					ELSE 0 END
                ,moitemid
		FROM dbo.PickingListItem 
		WHERE PickingListId=@PickingListId
		AND ProductId=@ProductId
		AND QtyRequired>QtyIssued 
		AND DeleteFlag=''
		GROUP BY ProductId,WorkcenterId,moitemid
	END


	--游标1循环处理：先处理当前仓库的建议批次，再处理不是当前仓库的建议批次
	SET @RowId=1
	SELECT @RowCount=COUNT(1) FROM @Temp1
	WHILE(@RowId<=@RowCount)
	BEGIN
		--获取要查找的物料
		SELECT
			   @ProductId=ProductId,
			   @WarehouseId=WorkcenterId,
			   @QtyRequired=QtyRequired,
			   @QtyIssued=QtyIssued,
			   @IsCurWorkcenter=IsCurWorkcenter,
               @Moitemid=MoItemId
		FROM @Temp1
		WHERE RowId=@RowId
	
		--更新计数器，一定要注意
		SET @RowId=@RowId+1

		SET @OweQty=0
		SET @OweQty=ISNULL(@QtyRequired,0)-ISNULL(@QtyIssued,0)

		IF ISNULL(@OweQty,0)<=0
		BEGIN
			CONTINUE
		END

		SELECT @ProductName=ProductName,@ProductDescription=ProductDescription
		FROM dbo.Product
		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
		WHERE ProductId=@ProductId

		SELECT @WarehouseName=WorkcenterName
		FROM dbo.Workcenter 
		WHERE WorkcenterId=@WarehouseId


		--领料单建议批次匹配规则修改，仓管员按建议批次进行领料下架。
        --规则：有效日期内、先进先出。
        --特殊规则：指定批次、海外分散单的指定扣备注绿标的墨水、ITS的单指定扣备注ITS的墨水、XFY订单也是指定扣绿标的墨水。
        --三种单依据头注释中的备注匹配包含“海外”、“ITS”、“XFY”
        DECLARE @ProductionLotNOS NVARCHAR(1000)=''
        DECLARE @Moid NVARCHAR(20)=''
        DECLARE @NoteMessage  NVARCHAR(200)=''

        select @ProductionLotNOS=mi.ProductionLotNO,@Moid=m.moid,@NoteMessage=m.NoteMessage from  PickingList p 
            left join PickingListItem pi on p.PickingListId=pi.PickingListId
            left join moitem mi on mi.MOItemId=pi.MOItemId
            left join mo m on m.moid=mi.moid
            where  p.PickingListId=@PickingListId and pi.ProductId=@ProductId and mi.MOItemid=@Moitemid
        --指定批次
        IF ISNULL(@ProductionLotNOS,'')<>''
        BEGIN
            INSERT INTO @Temp2
            (   LotSN ,
                Qty ,
                UOMName,
                ProductionDate,
                CellId ,
                CellName,
                WorkcenterName ,
                RouteOrder,
                RowId
            )
            SELECT 
						WW.LotSN,
						WW.Qty,
						UOMName,
						WW.ProductionDate,
						--WW.CellId,
                        '' AS CellId,
						--Cell.CellName,
                        '' AS CellName,
						W.WorkcenterName,
						RouteOrder,
						ROW_NUMBER()OVER(ORDER BY WW.ProductionDate,Cell.RouteOrder,Cell.CellName) AS RowId
					FROM dbo.WW_RMInventory WW
					LEFT JOIN dbo.Cell ON Cell.CellId = WW.CellId
					LEFT JOIN dbo.UOM ON UOM.UOMId = WW.UOMId
                    LEFT JOIN dbo.Lot on Lot.LotId = ww.LotId
					INNER JOIN Workcenter W ON WW.WorkcenterId=W.WorkcenterId
					WHERE WW.ProductId=@ProductId AND WW.IsStorage=1 
                    AND WW.LotStatus='1' AND (ISNULL(@FactoryId,'')='' OR WW.FactoryId=@FactoryId)
                    AND ww.ProductionLotNO in( SELECT value FROM STRING_SPLIT(@ProductionLotNOS, ','))
					AND WW.Qty>0 AND (WW.ValidityEndDate>=@CurDate OR WW.ValidityEndDate IS NULL)
        END
        --ITS的单指定扣备注ITS的墨水
        ELSE IF EXISTS (select 1 from mo where moid=@Moid AND UPPER(HeadComment) like '%ITS%' )
        BEGIN
            INSERT INTO @Temp2
            (   LotSN ,
                Qty ,
                UOMName,
                ProductionDate,
                CellId ,
                CellName,
                WorkcenterName ,
                RouteOrder,
                RowId
            )
            SELECT 
						WW.LotSN,
						WW.Qty,
						UOMName,
						WW.ProductionDate,
						--WW.CellId,
                        '' AS CellId,
						--Cell.CellName,
                        '' AS CellName,
						W.WorkcenterName,
						RouteOrder,
						ROW_NUMBER()OVER(ORDER BY WW.ProductionDate,Cell.RouteOrder,Cell.CellName) AS RowId
					FROM dbo.WW_RMInventory WW
					LEFT JOIN dbo.Cell ON Cell.CellId = WW.CellId
					LEFT JOIN dbo.UOM ON UOM.UOMId = WW.UOMId
                    LEFT JOIN dbo.Lot on Lot.LotId = ww.LotId
					INNER JOIN Workcenter W ON WW.WorkcenterId=W.WorkcenterId
                    LEFT join mo on mo.moid=ww.moid
					WHERE WW.ProductId=@ProductId AND WW.IsStorage=1 
                    AND  UPPER(mo.NoteMessage) like '%ITS%'
                    AND WW.LotStatus='1' AND (ISNULL(@FactoryId,'')='' OR WW.FactoryId=@FactoryId)
                    AND ww.QCStatus !=1 AND (ISNULL(lot.QualityMark,'')='' OR LOt.QualityMark in ('G','Y','YG','YB','Q'))
					AND WW.Qty>0 AND (WW.ValidityEndDate>=@CurDate OR WW.ValidityEndDate IS NULL)
        END
        --海外、XFY订单指定扣绿标的墨水。
        ELSE IF EXISTS (select 1 from mo where moid=@Moid AND  ( HeadComment like '%海外%' OR UPPER(HeadComment) like '%XFY%' ))
        BEGIN
            INSERT INTO @Temp2
                (   LotSN ,
                    Qty ,
                    UOMName,
                    ProductionDate,
                    CellId ,
                    CellName,
                    WorkcenterName ,
                    RouteOrder,
                    RowId
                )
                SELECT 
                            WW.LotSN,
                            WW.Qty,
                            UOMName,
                            WW.ProductionDate,
                            --WW.CellId,
                            '' AS CellId,
                            --Cell.CellName,
                            '' AS CellName,
                            W.WorkcenterName,
                            RouteOrder,
                            ROW_NUMBER()OVER(ORDER BY WW.ProductionDate,Cell.RouteOrder,Cell.CellName) AS RowId
                        FROM dbo.WW_RMInventory WW
                        LEFT JOIN dbo.Cell ON Cell.CellId = WW.CellId
                        LEFT JOIN dbo.UOM ON UOM.UOMId = WW.UOMId
                        LEFT JOIN dbo.Lot on Lot.LotId = ww.LotId
                        INNER JOIN Workcenter W ON WW.WorkcenterId=W.WorkcenterId
                        LEFT join mo on mo.moid=ww.moid
                        WHERE WW.ProductId=@ProductId AND WW.IsStorage=1 
                        AND WW.LotStatus='1' AND (ISNULL(@FactoryId,'')='' OR WW.FactoryId=@FactoryId)
                        AND ww.QCStatus !=1 AND UPPER(mo.NoteMessage) like '%绿标%'
                        AND WW.Qty>0 AND (WW.ValidityEndDate>=@CurDate OR WW.ValidityEndDate IS NULL)
        END
        ELSE 
        BEGIN
            --有效日期内、先进先出。
            INSERT INTO @Temp2
            (   LotSN ,
                Qty ,
                UOMName,
                ProductionDate,
                CellId ,
                CellName,
                WorkcenterName ,
                RouteOrder,
                RowId
            )
            SELECT 
						WW.LotSN,
						WW.Qty,
						UOMName,
						WW.ProductionDate,
						--WW.CellId,
                        '' AS CellId,
						--Cell.CellName,
                        '' AS CellName,
						W.WorkcenterName,
						RouteOrder,
						ROW_NUMBER()OVER(ORDER BY WW.ProductionDate,Cell.RouteOrder,Cell.CellName) AS RowId
					FROM dbo.WW_RMInventory WW
					LEFT JOIN dbo.Cell ON Cell.CellId = WW.CellId
					LEFT JOIN dbo.UOM ON UOM.UOMId = WW.UOMId
                    LEFT JOIN dbo.Lot on Lot.LotId = ww.LotId
					INNER JOIN Workcenter W ON WW.WorkcenterId=W.WorkcenterId
					WHERE WW.ProductId=@ProductId AND WW.IsStorage=1 
					--AND (ISNULL(@WarehouseId,'')='' OR WW.WorkcenterId=@WarehouseId) 
                    AND WW.LotStatus='1' AND (ISNULL(@FactoryId,'')='' OR WW.FactoryId=@FactoryId)
                    AND ww.QCStatus !=1 AND (ISNULL(lot.QualityMark,'')='' OR LOt.QualityMark in ('G','Y','YG','YB','Q'))
					AND WW.Qty>0 AND (WW.ValidityEndDate>=@CurDate OR WW.ValidityEndDate IS NULL)
        END


		INSERT INTO @Temp_AdviceLot
				(
					
					RowLogo,
					ProductName,
					ProductDescription,
					LotSN,
					Qty,
					UOMName,
					ProductionDate,
					WarehouseName,
					CellName,
					Cell_RouteOrder,
					IsCurWorkcenter
				)
		SELECT 
				CASE T3.CellId WHEN @CurCellId THEN '★' ELSE '' END, --当前储位的位置
				@ProductName,
				@ProductDescription,
				T3.LotSN,
				T3.Qty,
				T3.UOMName,
				T3.ProductionDate,
				T3.WorkcenterName,
				T3.CellName,
				T3.RouteOrder,
				@IsCurWorkcenter
		FROM
		(
			--T2:“每列的累加汇总”往下推移一列
			SELECT *,LAG(SQty) OVER( ORDER BY(RowId)) AS SQty_LAG FROM 
			(
				--T1:列出“每列的累加汇总”
				SELECT *,SUM(Qty)OVER(ORDER BY RowId) SQty  FROM @Temp2 T1
			)T2
		)T3 WHERE ISNULL(T3.SQty_LAG,0)<@OweQty

        delete @Temp2
		--E
	END
	

	--获取建议储位
	SELECT @AdviceCell=IIF(ISNULL(@AdviceCell,'')='',A.CellName,@AdviceCell+','+A.CellName)
	FROM
	(
		SELECT DISTINCT CellName
		FROM @Temp_AdviceLot
	)A


	--输出建议批次:按当前仓库，储位顺序
	IF ISNULL(@MaxQty,0)>0
	begin
		SELECT 
				RowLogo,
				CellName,
				ProductName,
				ProductDescription,
				LotSN,
				Qty,
				UOMName,
				ProductionDate,
				WarehouseName,
				Cell_RouteOrder
		FROM @Temp_AdviceLot
		ORDER BY IsCurWorkcenter DESC,RowLogo DESC,Cell_RouteOrder,CellName
		OFFSET 0 ROW FETCH NEXT @MaxQty ROWS ONLY
	END
	ELSE
	BEGIN
		SELECT 
				RowLogo,
				CellName,
				ProductName,
				ProductDescription,
				LotSN,
				Qty,
				UOMName,
				ProductionDate,
				WarehouseName,
				Cell_RouteOrder
		FROM @Temp_AdviceLot
		ORDER BY IsCurWorkcenter DESC,RowLogo DESC,Cell_RouteOrder,CellName
	END

	RETURN 0
END
 


go

