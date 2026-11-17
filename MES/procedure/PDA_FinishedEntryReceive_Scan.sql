SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/05/29 16:28:06:9107>
-- Description:   <入库接收。扫描>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
alter PROCEDURE  [dbo].[PDA_FinishedEntryReceive_Scan]
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
@WareHouseId CHAR(12)='',                       --	仓库ID
@WareHouseName NVARCHAR(50)='',                 -- 仓库
@CellName NVARCHAR(50)='',
@ScanSN NVARCHAR(100)=''

AS
BEGIN
	-- set NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	/*
		Content1:方案说明：
		1.本方案由产线先“入库申请”扫描，入库申请时，生成单据的状态是10（待审核），扫描完之后点击“提交”，状态更新为20（已审核）
		2.仓库 接收扫描 。当全部接收完成时，会自动更新单据状态为30（已确认），紧接着调用ERP接口
	*/
	

	--公共信息变量
	DECLARE @return_value INT=-1
	DECLARE @Enter VARCHAR(2)=CHAR(13)+CHAR(10)
	DECLARE @CurDate DATETIME=GETDATE()
	DECLARE @RowCount INT=0
	DECLARE @RowId INT=0
	DECLARE @ReceiveUnit VARCHAR(20)=''
	DECLARE @ReceiveUnitDesc VARCHAR(100)=''


	--扫码信息信息
	DECLARE @PalletSN NVARCHAR(100)='' --栈板号
	DECLARE @OBoxSN NVARCHAR(100)='' --外箱号
	DECLARE @MBoxSN NVARCHAR(100)='' --中箱号
	DECLARE @BoxSN NVARCHAR(100)=''--内箱号
	DECLARE @LotSN NVARCHAR(100)=''
	DECLARE @LotQty FLOAT=0

	--入库单
	--bill
	DECLARE @FinishingEntryId CHAR(12)=''
	DECLARE @FinishingEntryName NVARCHAR(50)=''
	DECLARE @FinishingEntryStates VARCHAR(10)=''
	DECLARE @FinishingEntryStatesDesc NVARCHAR(50)=''
	--billItem
	DECLARE @FinishingEntryItemId CHAR(12)=''
	--DECLARE @WarehouseId CHAR(12)=''
	--DECLARE @WarehouseName NVARCHAR(50)=''
	--billItemLot
	DECLARE @FinishingEntryItemLotId CHAR(12)=''
	DECLARE @CellId CHAR(12)=''

	DECLARE @LotMOId CHAR(12)
	DECLARE @FactoryId CHAR(12)
	DECLARE @LotMOName VARCHAR(50)
	DECLARE @FactoryName VARCHAR(50)
	DECLARE @LotSpecificationId CHAR(12)

	DECLARE @QualityMark VARCHAR(16)
	DECLARE @WhCategoryCode VARCHAR(5)

    --容载器信息
    DECLARE @Containernum FLOAT=0


	CREATE TABLE #Table(
		RowId INT IDENTITY(1,1),
		FinishingEntryItemLotId CHAR(12),
		LotSN NVARCHAR(100)
	)

    --容载器明细临时表：保留“绑定该 SAP 批次、且尚未绑定 MES 批次”的容器最新一条明细
	--前面做数量校验时写入（按批号追加保存），入库完成后按 LotSN 逐桶拆批绑定 MES 批次
	CREATE TABLE #Container(
		RowId INT IDENTITY(1,1),
		LotSN NVARCHAR(100),
		ZR_ContainerCodeId CHAR(12),
		ContainerCode NVARCHAR(50),
		num FLOAT,
		remark NVARCHAR(MAX),
		CodeStatus NVARCHAR(50)
	)

	
	--设置
	SET @I_ExceptionFieldName ='ScanSN'
	SET @ScanSN=ISNULL(@ScanSN,'')


	--****************【 界面输入参数检查 】*****************
	IF ISNULL(@WareHouseId,'')='' OR ISNULL(@WareHouseName,'')=''
	BEGIN
		SELECT '' AS ScanSN,'NG.png' AS WarnImage
		SET @I_ReturnMessage='ServerMessage:请选择仓库！'
		SET @I_ExceptionFieldName='WareHouseName'
		RETURN -1
	END

	IF ISNULL(@CellName,'')<>''
	BEGIN
		IF NOT EXISTS(SELECT 1 FROM dbo.Cell WHERE CellName=@CellName AND IsActivity=1)
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:储位号【'+@CellName+'】不存在，或没有激活，请检查！'+@Enter
			SET @I_ExceptionFieldName='CellName'
			RETURN -1
		END
	END



	--****************【 扫描 】*****************
	IF ISNULL(@ScanSN,'')=''
	BEGIN
		SELECT '' AS ScanSN
		SET @I_ReturnMessage='ServerMessage:请扫产品条码！'+@Enter
		RETURN -1
	END

	--获取入库单位。
	IF EXISTS(SELECT 1 FROM dbo.Lot WHERE LotSN=@ScanSN)
	BEGIN
		SET @ReceiveUnit='Lot'
		SET @ReceiveUnitDesc='批号'
	END
	--ELSE IF EXISTS(SELECT 1 FROM dbo.ShipBox WHERE BoxSN=@ScanSN)
	--BEGIN
	--	SET @ReceiveUnit='Box'
	--	SET @ReceiveUnitDesc='箱号'
	--END
	--ELSE IF EXISTS(SELECT 1 FROM dbo.ShipPallet WHERE PalletSN=@ScanSN)
	--BEGIN
	--	SET @ReceiveUnit='Pallet'
	--	SET @ReceiveUnitDesc='栈板号'
	--END
	--ELSE IF EXISTS(SELECT 1 FROM dbo.ShipBox WHERE MBoxSN=@ScanSN)
	--BEGIN
	--	SET @ReceiveUnit='MBox'
	--	SET @ReceiveUnitDesc='中箱号'
	--END
	--ELSE IF EXISTS(SELECT 1 FROM dbo.ShipBox WHERE OBoxSN=@ScanSN)
	--BEGIN
	--	SET @ReceiveUnit='OBox'
	--	SET @ReceiveUnitDesc='外箱号'
	--END
	ELSE IF EXISTS(SELECT 1 FROM dbo.MO WHERE MOName=@ScanSN AND ISNULL(DeleteFlag,'')<>'X' AND MOStates='20')
	BEGIN
		SET @ReceiveUnit='MO'
		SET @ReceiveUnitDesc='工单号'
	END

	IF ISNULL(@ReceiveUnit,'') NOT IN('Lot','Box','MBox','OBox','Pallet','MO')
	BEGIN
		SELECT '' AS ScanSN
		SET @I_ReturnMessage='ServerMessage:产品条码【'+@ScanSN+'】无效，请扫描有效条码！'+@Enter
		RETURN -1
	END


   


	--************************《按Lot 接收，插入临时表》*******************************
	IF @ReceiveUnit='Lot'
	BEGIN
		SET @LotSN = @ScanSN

		IF NOT EXISTS(SELECT 1 FROM dbo.Lot WHERE LotSN=@LotSN)
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】不存在，请检查!'+@Enter
			RETURN -1
		END
		
		--只要没有接收，入库单肯定没有确认
		IF NOT EXISTS(SELECT 1 FROM dbo.FinishingEntryItemLot WHERE LotSN=@LotSN AND IsAccepted=0)
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】不存在 [入库待接收] 记录，请检查！'+@Enter
			RETURN -1
		END

		--获取 Lot 信息
		SELECT 
			@LotMOId=MOId ,
			@LotSpecificationId = SpecificationId,
			@QualityMark=QualityMark
		FROM dbo.Lot 
		WHERE LotSN=@LotSN

        --TODO 入库前校验必须先完成C点检验
		IF EXISTS (SELECT 1 FROM MO B
			INNER JOIN dbo.Workflow E ON E.WorkflowId = B.WorkflowId WHERE 1=1 AND B.MOId=@LotMOId
             AND (E.WorkflowDescription LIKE '%UV半成品墨水%' or E.WorkflowDescription LIKE '%UV组合液%'  ) AND B.ProductLine='UV')
		AND EXISTS (SELECT TOP 1 QC_ProcessInsId FROM QC_ProcessIns WHERE SubmissCategory='IPQC' AND MOId=@LotMOId AND (InsResult IS NULL OR InsResult ='' OR RealInsResult IS NULL OR RealInsResult ='') ORDER BY CreateDate desc)
	    BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】还未完成C点检测，不能进行半成品完工入库，请先完成C点检测!'
			RETURN -1
		END;


		--获取单据信息
		SELECT TOP 1
			   @FinishingEntryItemId=FinishingEntryItemId
		FROM dbo.FinishingEntryItemLot
		WHERE LotSN=@LotSN AND IsAccepted=0

		SELECT @FinishingEntryId=FinishingEntry.FinishingEntryId,
			   @FinishingEntryName=FinishingEntryName,
			   @FinishingEntryStates=FinishingEntryStates,
			   @WhCategoryCode=FinishingEntry.FinishingEntryType
		FROM dbo.FinishingEntryItem
		INNER JOIN dbo.FinishingEntry ON FinishingEntry.FinishingEntryId = FinishingEntryItem.FinishingEntryId
		WHERE FinishingEntryItemId=@FinishingEntryItemId

		IF ISNULL(@FinishingEntryStates,'')<>'20'
		BEGIN
			SELECT @FinishingEntryStatesDesc=BillStatesDescription
			FROM dbo.Bill
			INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
			WHERE BillName='FinishingEntry' AND BillStatesName=@FinishingEntryStates

			SELECT '' AS ScanSN

			IF ISNULL(@FinishingEntryStates,'')='10'
				SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，即产线还没有提交申请，不允许仓库接收！'+@Enter
			ELSE
				SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，不需要再次接收！'+@Enter
			RETURN -1
		END

		--半成品入库，如果品质不合格，只能入报废仓
		IF @WhCategoryCode='01' AND ISNULL(@QualityMark,'') IN('YB','RB') AND @WareHouseName<>'B59Z'
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】检测品质不合格，只能入报废品区域!'
			RETURN -1
		END

		INSERT INTO #Table
		     (
		         FinishingEntryItemLotId,
		         LotSN
		     )
		SELECT  FinishingEntryItemLotId,
				LotSN
		FROM dbo.FinishingEntryItemLot
		INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
		WHERE LotSN=@LotSN AND FinishingEntryId=@FinishingEntryId
		AND IsAccepted=0
	END





	--************************《按BoxSN 内箱接收，插入临时表》*******************************
	IF @ReceiveUnit='Box'
	BEGIN
		SET @BoxSN = @ScanSN

		IF NOT EXISTS(SELECT 1 FROM dbo.ShipBox WHERE BoxSN=@BoxSN)
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:箱号【'+@BoxSN+'】不存在，请检查!'+@Enter
			RETURN -1
		END

		IF NOT EXISTS(SELECT 1 FROM dbo.FinishingEntryItemLot WHERE BoxSN=@BoxSN AND IsAccepted=0)
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:箱号【'+@BoxSN+'】不存在 [入库待接收] 记录，请检查！'+@Enter
			RETURN -1
		END
	
		--获取单据信息
		SELECT TOP 1
			   @FinishingEntryId=FinishingEntryId
		FROM dbo.FinishingEntryItemLot
		INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
		WHERE BoxSN=@BoxSN AND IsAccepted=0

		SELECT
			   @FinishingEntryName=FinishingEntryName,
			   @FinishingEntryStates=FinishingEntryStates
		FROM dbo.FinishingEntry
		WHERE FinishingEntryId=@FinishingEntryId

		IF ISNULL(@FinishingEntryStates,'')<>'20'
		BEGIN
			SELECT @FinishingEntryStatesDesc=BillStatesDescription
			FROM dbo.Bill
			INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
			WHERE BillName='FinishingEntry' AND BillStatesName=@FinishingEntryStates

			SELECT '' AS ScanSN

			IF ISNULL(@FinishingEntryStates,'')='10'
				SET @I_ReturnMessage='ServerMessage:箱号【'+@BoxSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，即产线还没有提交申请，不允许仓库接收！'+@Enter
			ELSE
				SET @I_ReturnMessage='ServerMessage:箱号【'+@BoxSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，不需要再次接收！'+@Enter

			RETURN -1
		END

		INSERT INTO #Table
		     (
		         FinishingEntryItemLotId,
		         LotSN
		     )
		SELECT  FinishingEntryItemLotId,
				LotSN
		FROM dbo.FinishingEntryItemLot
		INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
		WHERE BoxSN=@BoxSN AND FinishingEntryId=@FinishingEntryId
		AND IsAccepted=0
		--E
	END





	--************************《按MBox 中箱接收，插入临时表》*******************************
	IF @ReceiveUnit='MBox'
	BEGIN
		SET @MBoxSN = @ScanSN

		IF NOT EXISTS(SELECT 1 FROM dbo.ShipBox WHERE MBoxSN=@MBoxSN)
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:箱号【'+@MBoxSN+'】不存在，请检查!'+@Enter
			RETURN -1
		END

		IF NOT EXISTS(SELECT 1 FROM dbo.FinishingEntryItemLot WHERE MBoxSN=@MBoxSN AND IsAccepted=0)
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:箱号【'+@MBoxSN+'】不存在 [入库待接收] 记录，请检查！'+@Enter
			RETURN -1
		END
	
		--获取单据信息
		SELECT TOP 1
			   @FinishingEntryId=FinishingEntryId
		FROM dbo.FinishingEntryItemLot
		INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
		WHERE MBoxSN=@MBoxSN AND IsAccepted=0

		SELECT
			   @FinishingEntryName=FinishingEntryName,
			   @FinishingEntryStates=FinishingEntryStates
		FROM dbo.FinishingEntry
		WHERE FinishingEntryId=@FinishingEntryId

		IF ISNULL(@FinishingEntryStates,'')<>'20'
		BEGIN
			SELECT @FinishingEntryStatesDesc=BillStatesDescription
			FROM dbo.Bill
			INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
			WHERE BillName='FinishingEntry' AND BillStatesName=@FinishingEntryStates

			SELECT '' AS ScanSN

			IF ISNULL(@FinishingEntryStates,'')='10'
				SET @I_ReturnMessage='ServerMessage:箱号【'+@MBoxSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，即产线还没有提交申请，不允许仓库接收！'+@Enter
			ELSE
				SET @I_ReturnMessage='ServerMessage:箱号【'+@MBoxSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，不需要再次接收！'+@Enter
			RETURN -1
		END

		INSERT INTO #Table
		     (
		         FinishingEntryItemLotId,
		         LotSN
		     )
		SELECT  FinishingEntryItemLotId,
				LotSN
		FROM dbo.FinishingEntryItemLot
		INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
		WHERE MBoxSN=@MBoxSN AND FinishingEntryId=@FinishingEntryId
		AND IsAccepted=0
		--E
	END




	--************************《按OBox 外箱接收，插入临时表》*******************************
	IF @ReceiveUnit='OBox'
	BEGIN
		SET @OBoxSN = @ScanSN

		IF NOT EXISTS(SELECT 1 FROM dbo.ShipBox WHERE OBoxSN=@OBoxSN)
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:箱号【'+@OBoxSN+'】不存在，请检查!'+@Enter
			RETURN -1
		END

		IF NOT EXISTS(SELECT 1 FROM dbo.FinishingEntryItemLot WHERE OBoxSN=@OBoxSN AND IsAccepted=0)
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:箱号【'+@OBoxSN+'】不存在 [入库待接收] 记录，请检查！'+@Enter
			RETURN -1
		END
	
		--获取单据信息
		SELECT TOP 1
			   @FinishingEntryId=FinishingEntryId
		FROM dbo.FinishingEntryItemLot
		INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
		WHERE OBoxSN=@OBoxSN AND IsAccepted=0

		SELECT
			   @FinishingEntryName=FinishingEntryName,
			   @FinishingEntryStates=FinishingEntryStates
		FROM dbo.FinishingEntry
		WHERE FinishingEntryId=@FinishingEntryId

		IF ISNULL(@FinishingEntryStates,'')<>'20'
		BEGIN
			SELECT @FinishingEntryStatesDesc=BillStatesDescription
			FROM dbo.Bill
			INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
			WHERE BillName='FinishingEntry' AND BillStatesName=@FinishingEntryStates

			SELECT '' AS ScanSN

			IF ISNULL(@FinishingEntryStates,'')='10'
				SET @I_ReturnMessage='ServerMessage:箱号【'+@OBoxSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，即产线还没有提交申请，不允许仓库接收！'+@Enter
			ELSE
				SET @I_ReturnMessage='ServerMessage:箱号【'+@OBoxSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，不需要再次接收！'+@Enter
			RETURN -1
		END


		INSERT INTO #Table
		     (
		         FinishingEntryItemLotId,
		         LotSN
		     )
		SELECT  FinishingEntryItemLotId,
				LotSN
		FROM dbo.FinishingEntryItemLot
		INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
		WHERE OBoxSN=@OBoxSN AND FinishingEntryId=@FinishingEntryId
		AND IsAccepted=0
		--E
	END




	--************************《按Pallet 栈板接收，插入临时表》*******************************
	IF @ReceiveUnit='Pallet'
	BEGIN
		SET @PalletSN = @ScanSN

		IF NOT EXISTS(SELECT 1 FROM dbo.ShipPallet WHERE PalletSN=@PalletSN)
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:栈板号【'+@PalletSN+'】不存在，请检查!'+@Enter
			RETURN -1
		END

		IF NOT EXISTS(SELECT 1 FROM dbo.FinishingEntryItemLot WHERE PalletSN=@PalletSN AND IsAccepted=0)
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:栈板号【'+@PalletSN+'】不存在 [入库待接收] 记录，请检查！'+@Enter
			RETURN -1
		END
	
		--获取单据信息
		SELECT TOP 1
			   @FinishingEntryId=FinishingEntryId
		FROM dbo.FinishingEntryItemLot
		INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
		WHERE PalletSN=@PalletSN AND IsAccepted=0

		SELECT
			   @FinishingEntryName=FinishingEntryName,
			   @FinishingEntryStates=FinishingEntryStates
		FROM dbo.FinishingEntry
		WHERE FinishingEntryId=@FinishingEntryId

		IF ISNULL(@FinishingEntryStates,'')<>'20'
		BEGIN
			SELECT @FinishingEntryStatesDesc=BillStatesDescription
			FROM dbo.Bill
			INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
			WHERE BillName='FinishingEntry' AND BillStatesName=@FinishingEntryStates

			SELECT '' AS ScanSN

			IF ISNULL(@FinishingEntryStates,'')='10'
				SET @I_ReturnMessage='ServerMessage:栈板号【'+@PalletSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，即产线还没有提交申请，不允许仓库接收！'+@Enter
			ELSE
				SET @I_ReturnMessage='ServerMessage:栈板号【'+@PalletSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，不需要再次接收！'+@Enter
			RETURN -1
		END




		INSERT INTO #Table
		     (
		         FinishingEntryItemLotId,
		         LotSN
		     )
		SELECT  FinishingEntryItemLotId,
				LotSN
		FROM dbo.FinishingEntryItemLot
		INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
		WHERE PalletSN=@PalletSN AND FinishingEntryId=@FinishingEntryId
		AND IsAccepted=0
		--E
	END



	--************************《按Lot 接收，插入临时表》*******************************
	IF @ReceiveUnit='MO'
	BEGIN
		SET @LotMOName=@ScanSN

		--工单判定
		IF NOT EXISTS(SELECT 1 FROM MO WHERE MOName=@LotMOName AND ISNULL(DeleteFlag,'')<>'X' AND MOStates='20')
		BEGIN
			SELECT '' AS ScanSN,'NG.png' AS WarnImage
			SET @I_ReturnMessage='ServerMessage:工单【'+@LotMOName+'】不存在或未下达，请检查!'
			RETURN -1
		END

		SELECT ROW_NUMBER() OVER(ORDER BY A.LotId) AS LineKey,A.LotId,A.LotSN,B.MOId,B.QualityMark,C.SpecificationId 
		INTO #TEMP FROM FinishingEntryItemLot A
		INNER JOIN dbo.FinishingEntryItem AS fei ON fei.FinishingEntryItemId = A.FinishingEntryItemId
		INNER JOIN dbo.FinishingEntry AS fe ON fe.FinishingEntryId = fei.FinishingEntryId
		INNER JOIN Lot B ON A.LotId=B.LotId 
		INNER JOIN Specification C ON B.SpecificationId=C.SpecificationId
		INNER JOIN SpecificationRoot D ON C.SpecificationRootId=D.SpecificationRootId 
		INNER JOIN MO E ON B.MOId=E.MOId
		WHERE E.MOName=@LotMOName AND C.IsEntryStep=1 AND D.SpecificationCode IN('SFGW','FSPD','OTGW') AND A.IsAccepted=0

		DECLARE @LotSq INT
		DECLARE @CurrSq INT=1

		SELECT @LotSq=COUNT(1) FROM #TEMP
		
		--只要没有接收，入库单肯定没有确认
		IF @LotSq=0
		BEGIN
			SELECT '' AS ScanSN
			SET @I_ReturnMessage='ServerMessage:工单【'+@LotMOName+'】不存在 [入库待接收] 记录，请检查！'+@Enter
			RETURN -1
		END

		WHILE @CurrSq<=@LotSq
		BEGIN
			--获取 Lot 信息
			SELECT 
				@LotSN=LotSN,
				@LotMOId=MOId ,
				@LotSpecificationId = SpecificationId,
				@QualityMark= QualityMark
			FROM #TEMP 
			WHERE LineKey=@CurrSq

			--获取单据信息
			SELECT TOP 1
				   @FinishingEntryItemId=FinishingEntryItemId
			FROM dbo.FinishingEntryItemLot
			WHERE LotSN=@LotSN AND IsAccepted=0

			SELECT @FinishingEntryId=FinishingEntry.FinishingEntryId,
				   @FinishingEntryName=FinishingEntryName,
				   @FinishingEntryStates=FinishingEntryStates,
				   @WhCategoryCode=FinishingEntry.FinishingEntryType
			FROM dbo.FinishingEntryItem
			INNER JOIN dbo.FinishingEntry ON FinishingEntry.FinishingEntryId = FinishingEntryItem.FinishingEntryId
			WHERE FinishingEntryItemId=@FinishingEntryItemId

			IF ISNULL(@FinishingEntryStates,'')<>'20'
			BEGIN
				SELECT @FinishingEntryStatesDesc=BillStatesDescription
				FROM dbo.Bill
				INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
				WHERE BillName='FinishingEntry' AND BillStatesName=@FinishingEntryStates

				SELECT '' AS ScanSN

				IF ISNULL(@FinishingEntryStates,'')='10'
					SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，即产线还没有提交申请，不允许仓库接收！'+@Enter
				ELSE
					SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】对应的入库单【'+@FinishingEntryName+'】当前状态【'+ISNULL(@FinishingEntryStatesDesc,'')+'】，不需要再次接收！'+@Enter
				RETURN -1
			END

			--半成品入库，如果品质不合格，只能入报废仓
			IF @WhCategoryCode='01' AND ISNULL(@QualityMark,'') IN('YB','RB') AND @WareHouseName<>'B59Z'
			BEGIN
				SELECT '' AS ScanSN,'NG.png' AS WarnImage
				SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】检测品质不合格，只能入报废品区域!'
				RETURN -1
			END

			INSERT INTO #Table
				 (
					 FinishingEntryItemLotId,
					 LotSN
				 )
			SELECT  FinishingEntryItemLotId,
					LotSN
			FROM dbo.FinishingEntryItemLot
			INNER JOIN dbo.FinishingEntryItem ON FinishingEntryItem.FinishingEntryItemId = FinishingEntryItemLot.FinishingEntryItemId
			WHERE LotSN=@LotSN AND FinishingEntryId=@FinishingEntryId
			AND IsAccepted=0

			SET @CurrSq+=1
		END

		
	END


	IF NOT EXISTS(SELECT 1 FROM #Table)
	BEGIN
		SELECT '' AS ScanSN
		SET @I_ReturnMessage= 'ServerMessage:系统未找到接收 的入库申请数据，请检查!'+@Enter
		RETURN -1
	END
	
	SELECT @FactoryId='FAC1000000SW'

	SELECT @FactoryName='FAC1000000SW'
	FROM dbo.Factory WHERE FactoryId=@FactoryId

--	IF NOT EXISTS(SELECT 1 FROM dbo.Workcenter
----	INNER JOIN dbo.Site ON Site.SiteId = Workcenter.SiteId
--	WHERE Workcenter.WorkcenterId=@WareHouseId AND FactoryId=@FactoryId)
--	BEGIN
--		SELECT '' AS ScanSN,'NG.png' AS WarnImage
--		SET @I_ReturnMessage='ServerMessage:工单【'+@LotMOName+'】属于工厂【'+ISNULL(@FactoryName,'')+'】，'
--			+@Enter+'仓库【'+@WareHouseName+'】不属于此工厂，请检查！'+@ReceiveUnitDesc+'【'+@ScanSN+'】'
--		RETURN -1
--	END

--	IF ISNULL(@CellName,'')<>''
--	BEGIN
--		SELECT @WareHouseName=WorkcenterName
--		FROM dbo.Workcenter
--		WHERE WorkcenterId=@WarehouseId

--		IF NOT EXISTS(SELECT 1 FROM dbo.Cell 
--		WHERE CellName=@CellName AND WorkcenterId=@WareHouseId AND IsActivity=1)
--		BEGIN
--			SELECT '' AS ScanSN
--			SET @I_ReturnMessage='ServerMessage:储位号【'+@CellName+'】不属于仓库【'+ISNULL(@WareHouseName,'')+'】，请检查！'
--				+@Enter+@ReceiveUnitDesc+'【'+@ScanSN+'】入库申请的仓库是【'++ISNULL(@WareHouseName,'')+'】'+@Enter
--			SET @I_ExceptionFieldName='CellName'
--			RETURN -1
--		END

	--	SET @CellId=''
	--	SELECT @CellId=CellId
	--	FROM dbo.Cell WHERE CellName=@CellName AND WorkcenterId=@WareHouseId AND IsActivity=1
	--END











	--循环拆批会累加每个容器的提示信息，使用MAX避免拼接长度超限
	DECLARE @I_APIReturnMessage NVARCHAR(MAX)=''


	--****************【 执行 接收 】*****************
	--删除入库单信息
	SET @RowId=0
	SET @RowCount=0
	SELECT @RowCount=COUNT(1) FROM #Table

	WHILE(@RowId<@RowCount)
	BEGIN
		--循环计数器
		SET @RowId=@RowId+1

		--设置初始值
		SET @FinishingEntryItemLotId=''
		SET @LotSN=''

		SELECT 
			   @FinishingEntryItemLotId=FinishingEntryItemLotId,
			   @LotSN=LotSN
		FROM #Table
		WHERE RowId=@RowId

		SELECT 
			   @FinishingEntryItemId=FinishingEntryItemId,
			   @LotQty=Qty
		FROM dbo.FinishingEntryItemLot
		WHERE FinishingEntryItemLotId=@FinishingEntryItemLotId

		SELECT @FinishingEntryId=FinishingEntry.FinishingEntryId,
				@FinishingEntryName=FinishingEntryName,
				@FinishingEntryStates=FinishingEntryStates,
				@WhCategoryCode=FinishingEntry.FinishingEntryType
		FROM dbo.FinishingEntryItem
		INNER JOIN dbo.FinishingEntry ON FinishingEntry.FinishingEntryId = FinishingEntryItem.FinishingEntryId
		WHERE FinishingEntryItemId=@FinishingEntryItemId

        --20261110判断容载器中数量和入库单中是否一致
        DECLARE @ProductionLotNO NVARCHAR(50) = '';
        SELECT @ProductionLotNO = ProductionLotNO FROM dbo.WW_RMInventory WHERE LotSN = @LotSN;
        -- 2、缓存“当前绑定该 SAP 批次、且尚未绑定 MES 批次”的容器最新一条明细（每个容器一条）
        -- 同一批号重复扫描时先清空，避免重复记录
        DELETE FROM #Container WHERE LotSN = @LotSN;
        INSERT INTO #Container (LotSN, ZR_ContainerCodeId, ContainerCode, num, remark, CodeStatus)
        SELECT
            @LotSN AS LotSN,
            t.ZR_ContainerCodeId,
            t.ContainerCode,
            t.num,
            t.remark,
            t.CodeStatus
        FROM (
            SELECT
                cc.ZR_ContainerCodeID AS ZR_ContainerCodeId,
                cc.ContainerCode AS ContainerCode,
                ISNULL(d.num, 0) AS num,
                ISNULL(d.remark, '') AS remark,
                ISNULL(d.CodeStatus, '') AS CodeStatus,
                ROW_NUMBER() OVER (
                    PARTITION BY cc.ZR_ContainerCodeID
                    ORDER BY d.createDate DESC, d.ZR_ContainerCodeDetailsId DESC
                ) AS rn
            FROM dbo.ZR_ContainerCode cc
            INNER JOIN dbo.ZR_ToFac_ContainerCode tc ON tc.ZR_ContainerCodeId = cc.ZR_ContainerCodeID
            INNER JOIN dbo.ZR_ContainerCodeDetails d ON d.ZR_ToFac_ContainerCodeID = tc.ZR_ToFac_ContainerCodeID
            WHERE cc.CurrentProudctionLotSN = @ProductionLotNO
            AND (tc.BoxLotSn IS NULL OR tc.BoxLotSn = '')
            AND tc.ToFacId IN (SELECT ToFacId FROM dbo.ToFac WHERE ProudctionLotSN = @ProductionLotNO)
        ) t
        WHERE t.rn = 1;
        -- 统计容器最新数量之和，用于与入库申请数量比对
        SET @Containernum = 0;
        SELECT @Containernum = ISNULL(SUM(num), 0)
        FROM #Container
        WHERE LotSN = @LotSN;
        -- 3、数量一致性校验（容差比较，避免浮点误差）
        IF ABS(ISNULL(@Containernum, 0) - @LotQty) > 0.0001
        BEGIN
            SET @I_ReturnMessage='ServerMessage:入库数量【'+CONVERT(nvarchar,@LotQty)+'】不等于容载器绑定数量【'+CONVERT(nvarchar,@Containernum)+'】，请检查！'
            RETURN -1
        END


		--更新已接收
		UPDATE dbo.FinishingEntryItemLot SET
			   IsAccepted=1,
			   AcceptUserId=@I_OrBitUserId,
			   AccepteDate=GETDATE(),
			   WorkcenterId=@WareHouseId
		WHERE FinishingEntryItemLotId=@FinishingEntryItemLotId

		--更新库存批号信息
		--IF @CellId<>''
		--BEGIN 
		--	UPDATE dbo.WW_RMInventory SET 
		--			CellId=@CellId,
		--			WorkcenterId=@WareHouseId
		--	WHERE LotSN=@LotSN
		--END
		UPDATE FinishingEntryItem SET WorkcenterId=@WareHouseId WHERE FinishingEntryItemId=@FinishingEntryItemId

		UPDATE dbo.WW_RMInventory SET 
					CellId=@CellId,
					WorkcenterId=@WareHouseId,
					IsStorage=1
			WHERE LotSN=@LotSN

       IF @WhCategoryCode='01' AND ISNULL(@QualityMark,'') IN('YB','RB','NQ')
	   BEGIN 
	   UPDATE dbo.WW_RMInventory SET 
					LotStatus=0,
					IsStorage=1
			WHERE LotSN=@LotSN

	   END 
		--插入批号追踪表：
		EXEC dbo.TxnBase_MLotTrack
			@I_OrBitUserId =@I_OrBitUserId,
			@I_PlugInCommand=@I_PlugInCommand,
			@I_ResourceId =@I_ResourceId,
			@LotSN = @LotSN, --批号：物料、半成品、成品
			@LotQty = @LotQty, --数量
			@TxnCode = 'F-入库接收', --事务码,简短描述功能
			@OrderName = @FinishingEntryName,
			@Remark = N'' --备注，
		--E

		IF EXISTS(SELECT 1 FROM dbo.FinishingEntryItem
		INNER JOIN dbo.FinishingEntryItemLot ON FinishingEntryItemLot.FinishingEntryItemId = FinishingEntryItem.FinishingEntryItemId
		WHERE FinishingEntryId=@FinishingEntryId AND IsAccepted=0)
		BEGIN
			--如果存在待接收的，则提示继续
			--SELECT @FinishingEntryName AS FinishingEntryName,'' AS ScanSN
			SET @I_APIReturnMessage='ServerMessage:'+@ReceiveUnitDesc+'【'+@ScanSN+'】接收成功，共【'+CAST(@RowCount AS VARCHAR)+'】个批号！'
				+@Enter+'请继续！'+@Enter
		END
		ELSE
		BEGIN
			--不存在待接收，则自动确认单据
			/*
				Content1:调用完工入库单 统一接口,由仓管员执行的操作
				Content2:
			*/
			EXEC @return_value=dbo.TxnBase_MBill_FinishingEntryConfirm
				@I_Sender=@I_Sender,
				@I_ReturnMessage=@I_ReturnMessage OUTPUT, -- nvarchar(max)	
				@I_PlugInCommand=@I_PlugInCommand,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_OrBitUserName=@I_OrBitUserName,
				@I_ResourceId=@I_ResourceId,
				@I_ResourceName=@I_ResourceName,
				@I_Parameter=@I_Parameter,
				@FinishingEntryName=@FinishingEntryName

			SET @I_APIReturnMessage+=REPLACE(@I_ReturnMessage,'ServerMessage:','');
            --20261110根据容载器的数量自动拆批绑定容载器（逐桶循环拆批）
            --20261111本次接收包含多个批号时，不做自动拆批，改为提示人工操作
            IF @return_value<>-1
            BEGIN
                DECLARE @ContainerRowId INT = 0                --容器循环计数器
                DECLARE @ContainerRowCount INT = 0             --待拆批容器数量
                DECLARE @ContainerCode NVARCHAR(50) = ''       --当前容器码
                DECLARE @ContainerQty FLOAT = 0                --当前容器最新数量（即拆批数量）
                DECLARE @ContainerRemark NVARCHAR(MAX) = ''    --当前容器最新备注
                DECLARE @SplitResult INT = -1                  --拆批过程返回值
                DECLARE @SplitMessage NVARCHAR(MAX) = ''       --拆批过程返回信息

                --多批号场景：本次接收包含多个批号时，不做自动拆批，提示人工拆批绑定
                IF ISNULL(@RowCount,0) > 1
                BEGIN
                    SET @I_APIReturnMessage += @Enter + '本次接收包含【'+CAST(@RowCount AS VARCHAR)+'】个批号，系统不做自动拆批，请人工拆批并绑定容载器！'
                END
                ELSE
                BEGIN
					SELECT @ContainerRowCount = COUNT(1)
					FROM #Container
					WHERE LotSN = @LotSN

					WHILE @ContainerRowId < ISNULL(@ContainerRowCount, 0)
					BEGIN
						SET @ContainerRowId += 1
						SET @ContainerCode = ''
						SET @ContainerQty = 0
						SET @ContainerRemark = ''
						SET @SplitResult = -1
						SET @SplitMessage = ''

						SELECT @ContainerCode = ContainerCode,
							@ContainerQty = num,
							@ContainerRemark = ISNULL(remark, '')
						FROM #Container
						WHERE LotSN = @LotSN AND RowId = @ContainerRowId

						--容器码非空校验：为空则跳过该条，避免拆批过程报错
						IF ISNULL(@ContainerCode, '') = ''
						BEGIN
							SET @I_APIReturnMessage += @Enter + '批号【' + @LotSN + '】存在容器码为空的记录，已跳过自动拆批！'
							CONTINUE
						END

						--拆批数量边界校验：必须大于0
						IF ISNULL(@ContainerQty, 0) <= 0
						BEGIN
							SET @I_APIReturnMessage += @Enter + '容器【' + @ContainerCode + '】数量为0，已跳过自动拆批！'
							CONTINUE
						END

						--逐桶调用拆批过程：按容器数量从当前批号拆出并绑定该容器
						EXEC @SplitResult = [dbo].[PDA_ToFac_Split]
							@I_Sender='confirm',
							@I_ReturnMessage=@SplitMessage OUTPUT, -- nvarchar(max)	
							@I_PlugInCommand=@I_PlugInCommand,
							@I_OrBitUserId=@I_OrBitUserId,
							@I_OrBitUserName=@I_OrBitUserName,
							@I_ResourceId=@I_ResourceId,
							@I_ResourceName=@I_ResourceName,
							@I_Parameter=@I_Parameter,
							@ProudctionLotSN=@LotSN,
							@ContainerCode=@ContainerCode,
							@num=@ContainerQty,
							@remark='入库接收自动拆批',
							@IsSplitLotSN=1

						--拆批失败不中断循环，记录提示信息并继续处理下一个容器
						IF ISNULL(@SplitResult, 0) <> 0
						BEGIN
							SET @I_APIReturnMessage += @Enter + '容器【' + @ContainerCode + '】拆批失败，请及时处理：'
								+ REPLACE(ISNULL(NULLIF(@SplitMessage, ''), '未知原因'), 'ServerMessage:', '')
						END
						ELSE
						BEGIN
							SET @I_APIReturnMessage += @Enter + REPLACE(ISNULL(@SplitMessage, ''), 'ServerMessage:', '')
						END
					END
                END
            END
		END
	END
	SET @I_ReturnMessage='ServerMessage:'+@ReceiveUnitDesc+'【'+@ScanSN+'】接收成功，共【'+CAST(@RowCount AS VARCHAR)+'】个批号！'
				+@Enter+REPLACE(@I_APIReturnMessage,'ServerMessage:','')+@Enter
	SELECT '' AS FinishingEntryName,'' AS ScanSN
	
	--====================================================2025.08.30 begin 9302 转到 9502 B57Z 库位=============================================================================
    -- 用库

	declare @zr_moid varchar(50)
	declare @zr_factoryId varchar(50) --9302
	declare @zr_factoryId9502 varchar(50) --9502
	declare @zr_workcenterId nvarchar(50) --9502 B57Z
	declare @zr_MOType nvarchar(50)

	select @zr_factoryId = factoryid from Factory where FactoryName = '9302'
	select @zr_factoryId9502 = factoryid from Factory where FactoryName = '9502'
    select @zr_workcenterId = workcenterid from workcenter where workcentername = 'B57Z' and factoryid = @zr_factoryId9502 --9502 B57Z
    select @zr_moid = moid from WW_RMInventory where LotSN= @LotSN

	select @zr_MOType = MOType from mo where moid = @zr_moid

	if ISNULL(@zr_MOType,'') IN('01') --成品
        begin
            -- 9302 TZ
            if exists(select 1 from mo where moid = @zr_moid and FactoryId = @zr_factoryId and ProductLine = 'TZ')
            begin
                update WW_RMInventory set WorkcenterId = @zr_workcenterId,factoryid = @zr_factoryId9502 where LotSN= @LotSN
--                 insert into zr_edlog (InputParams)values ('成品9302 TZ 转到 9502 B57Z 库位，批次号：'+@LotSN)
            end
        end
	--====================================================2025.08.30 end 9302 转到 9502 B57Z 库位=============================================================================

	update WW_RMInventory set FactoryId='FAC1000000SW' where Factoryid='FAC1000000T4' --9102受托->9502
	update WW_RMInventory set FactoryId='FAC1000000SW' where Factoryid='FAC1000000T9' --9304受托->9502



	RETURN 0

	
	


END
GO
