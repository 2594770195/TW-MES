SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/05/26 17:10:22:6269>
-- Description:   <入库申请。扫描>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[Txn_FinishedEntryApply_Scan]
@I_Sender NVARCHAR(200)='',						--	客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,		--	返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT,	--	向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',						--	客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',					--	插件命令
@I_OrBitUserId CHAR(12)='',						--	用户ID
@I_OrBitUserName NVARCHAR(100)='',				--	用户名
@I_ResourceId CHAR(12)='',						--	资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',				--	资源名
@I_PKid CHAR(12) ='',							--	主键
@I_ParentPKId CHAR(12)='',						--	父级主键
@I_Parameter NVARCHAR(MAX)='',  				--	插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@WhCategoryCode VARCHAR(5)='',                  -- 入库类别
@WhCategory NVARCHAR(50) = '' ,				    --	入库类别
@WareHouseId CHAR(12)='',                       --	仓库ID
@WareHouseName NVARCHAR(50)='',                 -- 仓库
@ScanSN NVARCHAR(50) = '' ,
@EntryQty DECIMAL(18,8) = 0,
@Barrelage NVARCHAR(200)=''
AS
BEGIN
	-- set NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	/*
		Content1:方案说明：
		1.本方案由产线先“入库申请”扫描，入库申请时，生成单据的状态是10（待审核），扫描完之后点击“提交”，状态更新为20（已审核）
		2.仓库有对应的功能“入库接收”
	*/
	

	--公共信息变量
	DECLARE @return_value INT=-1
	DECLARE @Enter VARCHAR(2)=CHAR(13)+CHAR(10)
	DECLARE @CurDate DATETIME=GETDATE()
	DECLARE @StartDate DATETIME=CAST(CONVERT(VARCHAR,GETDATE(),23)+' 00:00:00' AS DATETIME)
	DECLARE @RowCount INT=0
	DECLARE @RowId INT=0
	DECLARE @EntryUnit VARCHAR(20)=''
	DECLARE @EntryUnitDesc VARCHAR(100)=''
	DECLARE @TempStr NVARCHAR(MAX)=''


	--扫码信息信息
	DECLARE @BoxLayer CHAR(1)=''
	DECLARE @PalletSN NVARCHAR(100)='' --栈板号
	DECLARE @OBoxSN NVARCHAR(100)='' --外箱号
	DECLARE @MBoxSN NVARCHAR(100)='' --中箱号
	DECLARE @BoxSN NVARCHAR(100)=''--内箱号
	DECLARE @LotSN NVARCHAR(100)=''
	DECLARE @LotId CHAR(12)=''
	DECLARE @LotStatus CHAR(1)=''
	DECLARE @LotQty FLOAT=0
	DECLARE @LotUOMId CHAR(12)=''
	DECLARE @LotProductId CHAR(12)=''
	DECLARE @LotProductName NVARCHAR(50)=''
	DECLARE @LotMOId CHAR(12)=''
	DECLARE @LotMOName NVARCHAR(50)=''
	DECLARE @LotMOItemId CHAR(12)=''
	DECLARE @LotMOItemTaskId CHAR(12)=''
	DECLARE @LotSpecificationId CHAR(12)=''
	DECLARE @LotSpecificationName NVARCHAR(50)=''
	DECLARE @LotIsEntryStepb BIT=0
	DECLARE @QualityMark VARCHAR(16)

	DECLARE @SOName NVARCHAR(20)=''
	DECLARE @ProductDescription NVARCHAR(200)

	--入库单
	--bill
	DECLARE @FinishingEntryId CHAR(12)=''
	DECLARE @FinishingEntryName NVARCHAR(50)=''
	DECLARE @FactoryId CHAR(12)=''
	DECLARE @FactoryName NVARCHAR(50)=''
	DECLARE @DivisionId CHAR(12)=''
	--billItem
	DECLARE @FinishingEntryItemId CHAR(12)=''
	DECLARE @ItemSequence VARCHAR(20)=''
	DECLARE @ItemQtyEntry FLOAT=0
	--billItemLot
	DECLARE @FinishingEntryItemLotId CHAR(12)=''
	DECLARE @SpecificationCode VARCHAR(16)

	--库存表信息
	DECLARE @WWId CHAR(12)=''

	CREATE TABLE #Table_Scan(
		RowId INT IDENTITY(1,1),
		LotId CHAR(12) PRIMARY KEY,
		LotSN NVARCHAR(100) ,
		Qty FLOAT,
		BoxSN  NVARCHAR(100) DEFAULT '',
		MBoxSN NVARCHAR(100) DEFAULT '',
		OBoxSN NVARCHAR(100) DEFAULT '',
		PalletSN NVARCHAR(100) DEFAULT '',
		MOId CHAR(12),
		MOItemId CHAR(12),
		ProductId CHAR(12)
	)

	DECLARE @PKIdCount INT=1 --申请主键的个数
	--申请主键：批量
	DECLARE @Table_PKId TABLE(
		RowNO INT,
		PKId CHAR(12)
	)

	
	--设置
	SET @I_ExceptionFieldName ='ScanSN'
	SET @ScanSN=ISNULL(@ScanSN,'')





	--****************【 界面输入参数检查 】*****************
	IF ISNULL(@WhCategoryCode,'')='' OR ISNULL(@WhCategory,'')=''
	BEGIN
		SELECT '' AS ScanSN,'NG.png' AS WarnImage
		SET @I_ReturnMessage='ServerMessage:入库类别不能为空！'
		SET @I_ExceptionFieldName='WhCategory'
		RETURN -1
	END

	IF NOT EXISTS(SELECT 1 FROM dbo.Bill
	INNER JOIN dbo.BillType ON BillType.BillId = Bill.BillId
	WHERE BillName='FinishingEntry' AND BillTypeName=@WhCategoryCode)
	BEGIN
		SELECT '' AS ScanSN,'NG.png' AS WarnImage
		SET @I_ReturnMessage='ServerMessage:入库类别错误，请检查！'
		SET @I_ExceptionFieldName='WhCategory'
		RETURN -1
	END

	--IF ISNULL(@WareHouseId,'')='' OR ISNULL(@WareHouseName,'')=''
	--BEGIN
	--	SELECT '' AS ScanSN,'NG.png' AS WarnImage
	--	SET @I_ReturnMessage='ServerMessage:请选择仓库！'
	--	SET @I_ExceptionFieldName='WareHouseName'
	--	RETURN -1
	--END






	--****************【 扫描 】*****************
	IF ISNULL(@ScanSN,'')=''
	BEGIN
		SELECT '' AS ScanSN,'NG.png' AS WarnImage
		SET @I_ReturnMessage='ServerMessage:请扫产品条码！'
		RETURN -1
	END

	--获取入库单位。
	IF EXISTS(SELECT 1 FROM dbo.Lot WHERE LotSN=@ScanSN)
	BEGIN
		SET @EntryUnit='Lot'
		SET @EntryUnitDesc='批号'
	END
	ELSE IF EXISTS(SELECT 1 FROM dbo.MO WHERE MOName=@ScanSN AND ISNULL(DeleteFlag,'') IN('','0') AND MOStates='20')
	BEGIN
		SET @EntryUnit='MO'
		SET @EntryUnitDesc='工单号'
	END

	IF ISNULL(@EntryUnit,'') NOT IN('Lot','Box','MBox','OBox','Pallet','MO')
	BEGIN
		SELECT '' AS ScanSN,'NG.png' AS WarnImage
		SET @I_ReturnMessage='ServerMessage:产品条码【'+@ScanSN+'】无效，请扫描有效条码！'
		RETURN -1
	END






	--************************《按Lot入库，插入临时表》*******************************
	IF ISNULL(@EntryUnit,'')='Lot'
	BEGIN
		SET @LotSN = @ScanSN

		IF NOT EXISTS(SELECT 1 FROM dbo.Lot WHERE LotSN=@LotSN)
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】不存在，请检查!'
			RETURN -1
		END
		
		--获取 Lot 信息
		DECLARE @WorkflowStepId CHAR(12)
		SELECT 
			@LotId = LotId,
			@LotQty = Qty,
			@LotStatus = LotStatus,
			@LotProductId = ProductId,
			@LotMOId=MOId ,
			@LotMOItemId=MOItemId,
			@LotSpecificationId = SpecificationId,
			@WorkflowStepId=WorkflowStepId,
			@QualityMark= QualityMark
		FROM dbo.Lot 
		WHERE LotSN=@LotSN

		SELECT @LotSpecificationName = SpecificationName ,
			   @LotIsEntryStepb = IsEntryStep,
			   @SpecificationCode=SpecificationCode
		FROM dbo.Specification 
		INNER JOIN dbo.SpecificationRoot ON SpecificationRoot.SpecificationRootId = Specification.SpecificationRootId
		WHERE SpecificationId = @LotSpecificationId

		SELECT @LotMOName=MOName,@SOName=SOName
		FROM dbo.MO WHERE MOId=@LotMOId

		SELECT @LotProductName=ProductName,@ProductDescription=ProductDescription
		FROM dbo.Product
		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
		WHERE ProductId=@LotProductId

		-- 检查批号数是否足够
		IF ISNULL(@LotQty,0) <= 0
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】数量【'+CAST(@LotQty AS VARCHAR)+'】为0，请检查!'
			RETURN -1
		END

		-- 检查批号状态是否有效
		IF ISNULL(@LotStatus,'')<>'1'
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】状态无效，请检查!'
			RETURN -1
		END

		-- 检查扫描批号当前是否入库节点
		IF ISNULL(@LotIsEntryStepb,0) = 0
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】当前节点【'+@LotSpecificationName+'】非入库节点，请检查!'
			RETURN -1
		END

		-- 检查扫描批号是否入库
		IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN = @LotSN AND IsStorage = 1)
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】已入库.请检查!'
			RETURN -1
		END

		--TODO 校验必须先完成C点检验 2026年3月4日 取消，不在入库申请卡控
		--IF (SELECT ProductLine FROM dbo.MO WHERE MOId=@LotMOId)='UV' AND EXISTS (SELECT 1 FROM WorkflowStep B
		--	INNER JOIN dbo.Workflow E ON E.WorkflowId = B.WorkflowId WHERE 1=1 AND B.WorkflowStepId=@WorkflowStepId AND E.WorkflowDescription LIKE '%UV半成品墨水%')
		--AND EXISTS (SELECT TOP 1 QC_ProcessInsId FROM QC_ProcessIns WHERE SubmissCategory='IPQC' AND MOId=@LotMOId AND (InsResult IS NULL OR InsResult ='' OR RealInsResult IS NULL OR RealInsResult ='') ORDER BY CreateDate desc)
	 --   BEGIN
		--	SELECT '' AS ScanSN,'NG.png' AS WarnImage
		--	SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】还未完成C点检测，不能入库，请先完成C点检测!'
		--	RETURN -1
		--END;

		--一个批号在一个工单中只会入库一次，返工会开返工工单。如果不是这样，这检查可注释
		IF EXISTS(SELECT 1 FROM dbo.FinishingEntryItemLot
		INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
		WHERE LotSN=@LotSN AND MOId=@LotMOId AND ProductId=@LotProductId)
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			--=============================== 提示当前入库单状态 begin======================================
			declare @ZR_FinishingEntryStates nvarchar(100)
			declare @ZR_FinishingEntryName nvarchar(100)
            SELECT @ZR_FinishingEntryStates = FinishingEntryStates,
                   @ZR_FinishingEntryName = FinishingEntryName
            FROM dbo.FinishingEntryItemLot
            INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
                     join FinishingEntry on FinishingEntry.FinishingEntryId = FinishingEntryItem.FinishingEntryId
            WHERE LotSN=@LotSN AND MOId=@LotMOId AND ProductId=@LotProductId
			if isnull(@ZR_FinishingEntryStates,'') = '10'
			begin
				SET @ZR_FinishingEntryStates = ' 目前是：待提交审核状态'
			end
			--=============================== 提示当前入库单状态 end======================================
-- 			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】所属工单【'+@LotMOName+'】产品【'+@LotProductName+'】已有入库记录，禁止重复入库'
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】' +@ZR_FinishingEntryStates
			+'请到 申请撤销 页签，撤销批号，然后再入库申请。'+ '所属工单【'+@LotMOName+'】产品【'+@LotProductName+'】有入库单：'+ @ZR_FinishingEntryName 
			RETURN -1
		END

		--检查是否已装箱
		IF EXISTS(SELECT 1 FROM dbo.ShipBox WHERE LotSN=@LotSN AND IsAutoBoxing=0)
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】已装箱，不允许按 批号 入库!'
			RETURN -1
		END

		--检查是否已装栈(批号装栈时，会直接往ShipBox表插入一批记录)
		IF EXISTS(SELECT 1 FROM dbo.ShipBox WHERE LotSN=@LotSN AND IsAutoBoxing=1)
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】已装栈，不允许按 批号 入库!'
			RETURN -1
		END

		IF @SpecificationCode NOT IN('FBXR','FCXR','UBXR','UCXR','OTXR','HXXR','SXXR')--20260202新增活性、水性申请节点
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】不在入库申请工序!'
			RETURN -1
		END

		--扫批号录入重量
		IF @I_Sender='LotScan'
		BEGIN
			SELECT @LotQty AS EntryQty,@ProductDescription AS ProductDescription,dbo.FormatQualityMark(@QualityMark) AS QualityMark
			SET @I_ExceptionFieldName='EntryQty'
			RETURN 0
		END

		IF @EntryQty<=0
		BEGIN
			SET @I_ExceptionFieldName='EntryQty'
			SET @I_ReturnMessage='ServerMessage:入库数量必须大于0!'
			RETURN -1
		END
        IF @EntryQty>isnull((select MOQtyRequired from mo where moid=@LotMOId),0)*10
		BEGIN
			SET @I_ExceptionFieldName='EntryQty'
			SET @I_ReturnMessage='ServerMessage:入库数量异常，请检查!'
			RETURN -1
		END
		SET @LotQty=@EntryQty

		--批号写入表
		INSERT INTO #Table_Scan
			 (
				 LotId,
				 LotSN,
				 Qty,
				 MOId,
				 MOItemId,
				 ProductId
			 )
		VALUES
			 (
				 @LotId,
				 @LotSN,
				 @LotQty,
				 @LotMOId,
				 ISNULL(@LotMOItemId,''),
				 @LotProductId
			 )
	END


	--************************《按MO 工单入库，插入临时表》*******************************
	IF ISNULL(@EntryUnit,'')='MO'
	BEGIN
		SET @LotMOName=@ScanSN

		--工单判定
		IF NOT EXISTS(SELECT 1 FROM MO WHERE MOName=@LotMOName AND ISNULL(DeleteFlag,'')<>'X' AND MOStates='20')
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:工单【'+@LotMOName+'】不存在或未下达，请检查!'
			RETURN -1
		END

		SELECT ROW_NUMBER() OVER(ORDER BY C.LotId) AS LineKey,D.LotId,D.LotSN,A.MOId,
		D.Qty,D.LotStatus,D.ProductId,B.MOItemId,D.SpecificationId,D.QualityMark,G.ProductDescription 
		INTO #TEMP FROM MO A INNER JOIN MOItem B ON A.MOId=B.MOId
		INNER JOIN MOItemLot C ON B.MOItemId=C.MOItemId
		INNER JOIN Lot D ON C.LotId=D.LotId 
		INNER JOIN Specification E ON D.SpecificationId=E.SpecificationId
		INNER JOIN SpecificationRoot F ON E.SpecificationRootId=F.SpecificationRootId 
		INNER JOIN Product G ON D.ProductId=G.ProductId
		WHERE A.MOName=@LotMOName AND E.IsEntryStep=1 AND F.SpecificationCode IN('FBXR','FCXR','UBXR','UCXR','OTXR','HXXR','SXXR')--20260202新增活性、水性申请节点

		DECLARE @LotSq INT
		DECLARE @CurrSq INT=1

		SELECT @LotSq=COUNT(1) FROM #TEMP
		--判定是否有待入库的批次
		IF @LotSq<=0
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:工单【'+@LotMOName+'】没找到待入库的批次，请检查!'
			RETURN -1
		END

		WHILE @CurrSq<=@LotSq
		BEGIN
			--获取 Lot 信息
			SELECT 
				@LotId = LotId,
				@LotSN=LotSN,
				@LotQty = Qty,
				@LotStatus = LotStatus,
				@LotProductId = ProductId,
				@LotMOId=MOId ,
				@LotMOItemId=MOItemId,
				@LotSpecificationId = SpecificationId,
				@QualityMark= QualityMark,
				@ProductDescription=ProductDescription
			FROM #TEMP 
			WHERE LineKey=@CurrSq

			
			SELECT @LotSpecificationName = SpecificationName ,
				   @LotIsEntryStepb = IsEntryStep
			FROM dbo.Specification 
			INNER JOIN dbo.SpecificationRoot ON SpecificationRoot.SpecificationRootId = Specification.SpecificationRootId
			WHERE SpecificationId = @LotSpecificationId

			SELECT @LotMOName=MOName,@SOName=SOName
			FROM dbo.MO WHERE MOId=@LotMOId

			SELECT @LotProductName=ProductName
			FROM dbo.Product
			INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
			WHERE ProductId=@LotProductId

			-- 检查批号数是否足够
			IF ISNULL(@LotQty,0) <= 0
			BEGIN
				SELECT '' AS ScanSN,'NG.png' AS WarnImage
				SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】数量【'+CAST(@LotQty AS VARCHAR)+'】为0，请检查!'
				RETURN -1
			END

			-- 检查批号状态是否有效
			IF ISNULL(@LotStatus,'')<>'1'
			BEGIN
				SELECT '' AS ScanSN,'NG.png' AS WarnImage
				SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】状态无效，请检查!'
				RETURN -1
			END

			-- 检查扫描批号当前是否入库节点
			IF ISNULL(@LotIsEntryStepb,0) = 0
			BEGIN
				SELECT '' AS ScanSN,'NG.png' AS WarnImage
				SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】当前节点【'+@LotSpecificationName+'】非入库节点，请检查!'
				RETURN -1
			END

			-- 检查扫描批号是否入库
			IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN = @LotSN AND IsStorage = 1)
			BEGIN
				SELECT '' AS ScanSN,'NG.png' AS WarnImage
				SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】已入库.请检查!'
				RETURN -1
			END

			--一个批号在一个工单中只会入库一次，返工会开返工工单。如果不是这样，这检查可注释
			IF EXISTS(SELECT 1 FROM dbo.FinishingEntryItemLot
			INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
			WHERE LotSN=@LotSN AND MOId=@LotMOId AND ProductId=@LotProductId)
			BEGIN
				SELECT '' AS ScanSN,'NG.png' AS WarnImage
				SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】所属工单【'+@LotMOName+'】产品【'+@LotProductName+'】已有入库记录，禁止重复入库'
				RETURN -1
			END

			--检查是否已装箱
			IF EXISTS(SELECT 1 FROM dbo.ShipBox WHERE LotSN=@LotSN AND IsAutoBoxing=0)
			BEGIN
				SELECT '' AS ScanSN,'NG.png' AS WarnImage
				SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】已装箱，不允许按 批号 入库!'
				RETURN -1
			END

			--检查是否已装栈(批号装栈时，会直接往ShipBox表插入一批记录)
			IF EXISTS(SELECT 1 FROM dbo.ShipBox WHERE LotSN=@LotSN AND IsAutoBoxing=1)
			BEGIN
				SELECT '' AS ScanSN,'NG.png' AS WarnImage
				SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】已装栈，不允许按 批号 入库!'
				RETURN -1
			END

			select @Barrelage=Barrelage from tofac where ProudctionLotSN=LEFT(@LotSN, 10)
			IF @LotSq=1
			BEGIN
				--扫批号录入重量
				IF @I_Sender='LotScan'
				BEGIN
					
					SELECT @LotQty AS EntryQty,@ProductDescription AS ProductDescription,dbo.FormatQualityMark(@QualityMark) AS QualityMark,@Barrelage as Barrelage
					
					SET @I_ExceptionFieldName='EntryQty'
					RETURN 0
				END
				IF @EntryQty<=0
				BEGIN
					SET @I_ExceptionFieldName='EntryQty'
					SET @I_ReturnMessage='ServerMessage:入库数量必须大于0!'
					RETURN -1
				END
                IF @EntryQty>isnull((select MOQtyRequired from mo where moid=@LotMOId),0)*10
                BEGIN
                    SET @I_ExceptionFieldName='EntryQty'
                    SET @I_ReturnMessage='ServerMessage:入库数量异常，请检查!'
                    RETURN -1
                END
				SET @LotQty=@EntryQty
			END

			IF @I_Sender='LotScan' AND @Barrelage!= NULL AND  @Barrelage!= 0
			BEGIN
				update tofac set Barrelage=@Barrelage where  ProudctionLotSN=LEFT(@LotSN, 10)
			END

			--批号写入表
			INSERT INTO #Table_Scan
				 (
					 LotId,
					 LotSN,
					 Qty,
					 MOId,
					 MOItemId,
					 ProductId
				 )
			VALUES
				 (
					 @LotId,
					 @LotSN,
					 @LotQty,
					 @LotMOId,
					 ISNULL(@LotMOItemId,''),
					 @LotProductId
				 )

			SET @CurrSq+=1
		END
	END


	IF NOT EXISTS(SELECT 1 FROM #Table_Scan)
	BEGIN
		SELECT '' AS ScanSN,'NG.png' AS WarnImage
		SET @I_ReturnMessage='ServerMessage:系统未找到可入库的数据，请扫描有效产品条码!'
		RETURN -1
	END

	SET @LotMOId=''
	SELECT TOP 1 @LotMOId=MOId
	FROM #Table_Scan

	SELECT @DivisionId=DivisionId,
		   @FactoryId=FactoryId,
		   @LotMOName=MOName
	FROM dbo.MO
	WHERE MOId=@LotMOId

	SELECT @FactoryName=FactoryName
	FROM dbo.Factory WHERE FactoryId=@FactoryId

	IF ISNULL(@FactoryId,'')=''
	BEGIN
		SELECT '' AS ScanSN,'NG.png' AS WarnImage
		SET @I_ReturnMessage='ServerMessage:工单【'+@LotMOName+'】没有维护工厂，请检查！'
			+@Enter+@EntryUnitDesc+'【'+@ScanSN+'】'
		RETURN -1
	END

	--IF ISNULL(@DivisionId,'')=''
	--BEGIN
	--	SELECT '' AS ScanSN,'NG.png' AS WarnImage
	--	SET @I_ReturnMessage='ServerMessage:工单【'+@LotMOName+'】没有维护部门，请检查！'
	--		+@Enter+@EntryUnitDesc+'【'+@ScanSN+'】'
	--	RETURN -1
	--END

	--IF NOT EXISTS(SELECT 1 FROM dbo.Workcenter
	--INNER JOIN dbo.Site ON Site.SiteId = Workcenter.SiteId
	--WHERE WorkcenterId=@WareHouseId AND FactoryId=@FactoryId)
	--BEGIN
	--	SELECT '' AS ScanSN,'NG.png' AS WarnImage
	--	SET @I_ReturnMessage='ServerMessage:工单【'+@LotMOName+'】属于工厂【'+ISNULL(@FactoryName,'')+'】，'
	--		+@Enter+'仓库【'+@WareHouseName+'】不属于此工厂，请检查！'+@EntryUnitDesc+'【'+@ScanSN+'】'
	--	RETURN -1
	--END



	--************************《数据保存》*******************************

	--1.创建单据
	--IF EXISTS(SELECT 1 FROM dbo.FinishingEntry 
	--WHERE CreateDate>=@StartDate AND FinishingEntryStates='10'
	--AND CreateUserId=@I_OrBitUserId AND FinishingEntryWay='2' AND FinishingEntryType='01'
	--AND FactoryId=@FactoryId AND DivisionId=@DivisionId)
	--BEGIN
	--	SELECT @FinishingEntryId=FinishingEntryId,
	--		   @FinishingEntryName=FinishingEntryName
	--	FROM dbo.FinishingEntry
	--	WHERE CreateDate>=@StartDate AND FinishingEntryStates='10'
	--	AND CreateUserId=@I_OrBitUserId AND FinishingEntryWay='2' AND FinishingEntryType=@WhCategoryCode
	--	AND FactoryId=@FactoryId AND DivisionId=@DivisionId
	--END
	
	--IF ISNULL(@WhCategoryCode,'')='02'
	--BEGIN 
	--	IF EXISTS(SELECT 1 FROM dbo.FinishingEntry t1
	--	INNER JOIN   dbo.FinishingEntryItem AS fei ON fei.FinishingEntryId = t1.FinishingEntryId
	--	WHERE t1.CreateDate>=@StartDate AND t1.FinishingEntryStates='10'
	--	AND t1.CreateUserId=@I_OrBitUserId AND t1.FinishingEntryWay='2' AND t1.FinishingEntryType=@WhCategoryCode
	--	AND t1.FactoryId=@FactoryId AND t1.DivisionId=@DivisionId 
	--	AND (SELECT TOP 1 m.SOName FROM dbo.MO AS m WHERE m.moid=fei.MOId)=@SOName)
	--	BEGIN
	--		SELECT @FinishingEntryId=t1.FinishingEntryId,
	--			   @FinishingEntryName=FinishingEntryName
	--		FROM dbo.FinishingEntry t1
	--		INNER JOIN   dbo.FinishingEntryItem AS fei ON fei.FinishingEntryId = t1.FinishingEntryId
	--		WHERE t1.CreateDate>=@StartDate AND t1.FinishingEntryStates='10'
	--		AND t1.CreateUserId=@I_OrBitUserId AND t1.FinishingEntryWay='2' AND t1.FinishingEntryType=@WhCategoryCode
	--		AND t1.FactoryId=@FactoryId AND t1.DivisionId=@DivisionId 
	--		AND (SELECT TOP 1 m.SOName FROM dbo.MO AS m WHERE m.moid=fei.MOId)=@SOName
	--	END
	--	ELSE 
	--	BEGIN 
	--			  SET  @FinishingEntryId=''
	--			  SET  @FinishingEntryName=''
	--	END 
	
	--END 

	IF ISNULL(@FinishingEntryId,'')=''
	BEGIN 
		--申请单据
		EXEC [dbo].[Txn_BillNewSN]
			@BillName = N'FinishingEntry', --Bill表
			@NewSN = @FinishingEntryName OUTPUT

		IF ISNULL(@FinishingEntryName,'')=''
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:入库单创建失败！'
			RETURN -1
		END

		IF EXISTS(SELECT 1 FROM dbo.FinishingEntry WHERE FinishingEntryName=@FinishingEntryName)
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:入库单创建失败！单据【'+@FinishingEntryName+'】重复！'
			RETURN -1
		END

		--申请主键
		EXEC dbo.SysGetObjectPKId '','FinishingEntry',@FinishingEntryId OUTPUT
		INSERT INTO dbo.FinishingEntry
			 (
				 FinishingEntryId,
				 FinishingEntryName,
				 FinishingEntryDescription,
				 FinishingEntryStates,
				 FinishingEntryType,
				 FinishingEntryWay,
				 FactoryId,
				 DivisionId,
				 CreateUserId,
				 CreateDate
			 )
		VALUES
			 (
				@FinishingEntryId,
				@FinishingEntryName,
				@WhCategory,
				'10',
				@WhCategoryCode,
				'2',
				@FactoryId,
				@DivisionId,
				@I_OrBitUserId,
				GETDATE()
			 )

		--E
	END


	--2.创建单据明细,批量创建（可能存在不同工单）
	--游标1循环处理：
	DECLARE cursor_1 CURSOR LOCAL FAST_FORWARD FOR
	SELECT DISTINCT MOId,MOItemId,ProductId FROM #Table_Scan
	OPEN cursor_1
	FETCH NEXT FROM cursor_1
	INTO @LotMOId,@LotMOItemId,@LotProductId
	WHILE @@FETCH_STATUS = 0
	BEGIN
		--获取明细行
		IF EXISTS(SELECT 1 FROM dbo.FinishingEntryItem
		WHERE FinishingEntryId=@FinishingEntryId AND MOId=@LotMOId AND MOItemId=@LotMOItemId 
		AND ProductId=@LotProductId)
		BEGIN
			SELECT @FinishingEntryItemId=FinishingEntryItemId
			FROM dbo.FinishingEntryItem
			WHERE FinishingEntryId=@FinishingEntryId AND MOId=@LotMOId AND MOItemId=@LotMOItemId
			AND ProductId=@LotProductId
		END
		ELSE
		BEGIN
			--获取行号
			IF EXISTS(SELECT 1 FROM dbo.FinishingEntryItem WHERE FinishingEntryId=@FinishingEntryId)
			BEGIN
				SELECT @ItemSequence=RIGHT('000'+CAST(MAX(CAST(ItemSequence AS INT))+1 AS VARCHAR),4)
				FROM dbo.FinishingEntryItem
				WHERE FinishingEntryId=@FinishingEntryId
			END
			ELSE
			BEGIN
				SET @ItemSequence='0001'
			END

			SELECT @LotUOMId=UOMId
			FROM dbo.MOItem
			WHERE MOItemId=@LotMOItemId

			--申请主键
			EXEC dbo.SysGetObjectPKId '','FinishingEntryItem',@FinishingEntryItemId OUTPUT
			INSERT INTO dbo.FinishingEntryItem
				 (
					 FinishingEntryItemId,
					 FinishingEntryId,
					 ItemSequence,
					 MOId,
					 MOItemId,
					 ProductId,
					 ItemQtyEntry,
					 ItemUOMId,
					 WorkcenterId,
					 ModifyDate,
					 CreateDate
				 )
			VALUES
				 (
					 @FinishingEntryItemId,
					 @FinishingEntryId,
					 @ItemSequence, 
					 @LotMOId,
					 @LotMOItemId,
					 @LotProductId,
					 0,
					 @LotUOMId,
					 '',
					 GETDATE(),
					 GETDATE()
				 )

			--E
		END
	


		--创建单据明细批号
		SET @PKIdCount=0
		SELECT @PKIdCount=COUNT(1) FROM #Table_Scan WHERE MOId=@LotMOId AND MOItemId=@LotMOItemId AND ProductId=@LotProductId
		--申请主键：批量
		DELETE FROM @Table_PKId
		INSERT INTO @Table_PKId
			 (
				RowNO,
				PKId
			 )
		EXEC [dbo].[SysGetObjectPKIdBatch]
			@ObjectId = '',
			@ObjectName = N'FinishingEntryItemLot',
			@RowCount = @PKIdCount

		INSERT INTO dbo.FinishingEntryItemLot
		     (
		         FinishingEntryItemLotId,
		         FinishingEntryItemId,
		         LotId,
		         LotSN,
		         Qty,
		         BoxSN,
		         MBoxSN,
		         OBoxSN,
		         PalletSN,
		         EntryUnit,
		         CreateDate
		     )
		SELECT   B.PKId,
				 @FinishingEntryItemId,
                 A.LotId,
                 A.LotSN,
                 A.Qty,
                 A.BoxSN,
                 A.MBoxSN,
                 A.OBoxSN,
                 A.PalletSN,
				 @EntryUnit,
				 GETDATE()
		FROM
		(
			SELECT ROW_NUMBER() OVER(ORDER BY a.LotId) AS RowNO,
				  *
			FROM #Table_Scan a
			WHERE a.MOId=@LotMOId AND a.MOItemId=@LotMOItemId AND a.ProductId=@LotProductId
		)A
		INNER JOIN @Table_PKId B ON B.RowNO = A.RowNO


		--计算入库数量，并更新
		SET @ItemQtyEntry=0
		SELECT @ItemQtyEntry=SUM(Qty)
		FROM dbo.FinishingEntryItemLot
		WHERE FinishingEntryItemId=@FinishingEntryItemId

		UPDATE dbo.FinishingEntryItem SET 
			  ItemQtyEntry=ISNULL(@ItemQtyEntry,0),
			  ModifyDate=GETDATE()
		WHERE FinishingEntryItemId=@FinishingEntryItemId

		FETCH NEXT FROM cursor_1
		INTO  @LotMOId,@LotMOItemId,@LotProductId
	END
	CLOSE cursor_1
	DEALLOCATE cursor_1
	


	--3.插入库存表，没有就插入，有就更新。
	--循环保存数据：
	SELECT @RowCount=COUNT(1) FROM #Table_Scan
	SET @RowId=0
	--Start
	WHILE (@RowId<@RowCount)
	BEGIN
		--循环计数器
		SET @RowId=@RowId+1

		SET @LotId=''

		SELECT 
			   @LotId=LotId,
			   @LotSN=LotSN,
			   @LotQty=Qty,
			   @BoxSN=BoxSN,
			   @MBoxSN=MBoxSN,
			   @OBoxSN=OBoxSN,
			   @PalletSN=PalletSN,
			   @LotMOId=MOId,
			   @LotMOItemId=MOItemId,
			   @LotProductId=ProductId
		FROM #Table_Scan
		WHERE RowId=@RowId

		IF ISNULL(@LotId,'')=''
			CONTINUE;

		--获取条码信息
		SELECT 
			   @LotUOMId=UOMId,
			   @LotMOItemTaskId=MOItemTaskId
		FROM dbo.Lot
		WHERE LotId=@LotId

		IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@LotSN)
		BEGIN
			UPDATE dbo.WW_RMInventory SET 
				   LotId=@LotId,
				   LotStatus='9', --只要单据没有确认就是9，单据确认后才变为1
				   QCStatus='0',
				   IsolateStatus='0',
				   Qty=@LotQty,
				   OrgQty=@LotQty,
				   UOMId=@LotUOMId,
				   OrgLotSN=LotSN,
				   BoxSN=@BoxSN,
				   MBoxSN=@MBoxSN,
				   OBoxSN=@OBoxSN,
				   PalletSN=@PalletSN,
				   ProductId=@LotProductId,
				   MOId=@LotMOId,
				   MOItemId=@LotMOItemId,
				   MOItemTaskId=@LotMOItemTaskId,
				   EntryDate=GETDATE(),
				   FactoryId=@FactoryId,
				   WorkcenterId='',
				   IsStorage=0,
				   Operator=@I_OrBitUserName,
				   LotSType='30',
				   IsInternalLot=1,
				   ProductionLotNO=@LotMOName
			WHERE LotSN=@LotSN
		END
		ELSE
		BEGIN
			--申请主键
			EXEC dbo.SysGetObjectPKId '','WW_RMInventory',@WWId OUTPUT
			-- 写入库存表
			INSERT INTO WW_RMInventory
			(
				WWId,
				LotId,
				LotSN,
				LotStatus,
				Qty,
				OrgQty,
				UOMId ,
				OrgLotSN ,
				BoxSN,
				MBoxSN,
				OBoxSN,
				PalletSN,
				ProductId,
				MOId,
				MOItemId,
				MOItemTaskId,
				EntryDate ,
				FactoryId ,
				WorkcenterId ,
				IsStorage ,
				Operator,
				LotSType,
				IsInternalLot,
				ProductionLotNO
			)
			VALUES
			(
				@WWId,
				@LotId,
				@LotSN,
				'9', --只要单据没有确认就是9，单据确认后才变为1
				@LotQty,
				@LotQty,
				@LotUOMId,
				@LotSN,
				@BoxSN,
				@MBoxSN,
				@OBoxSN,
				@PalletSN,
				@LotProductId,
				@LotMOId,
				@LotMOItemId,
				@LotMOItemTaskId,
				GETDATE(),
				@FactoryId,
				'',
				0,
				@I_OrBitUserName,
				'30',
				1,
				@LotMOName
			)
		END

		--插入批号追踪表：
		EXEC dbo.TxnBase_MLotTrack
			@I_OrBitUserId =@I_OrBitUserId,
			@I_PlugInCommand=@I_PlugInCommand,
			@I_ResourceId =@I_ResourceId,
			@LotSN = @LotSN, --批号：物料、半成品、成品
			@LotQty = @LotQty, --数量
			@TxnCode = 'F-入库申请', --事务码,简短描述功能
			@OrderName =@FinishingEntryName , --单据号
			@Remark = N'' --备注，
		--E
	END



	DROP TABLE #Table_Scan

	SELECT '' AS ScanSN,'OK.png' AS WarnImage,@FinishingEntryName AS FinishingEntryName,'' AS EntryQty
	SET @I_ReturnMessage= 'ServerMessage:'+@EntryUnitDesc+'【'+@ScanSN+'】，总批号数【'+CAST(@RowCount AS VARCHAR)+'】入库申请成功，请继续！'
		+@Enter+'入库单【'+@FinishingEntryName+'】'
	RETURN 0
END
GO
