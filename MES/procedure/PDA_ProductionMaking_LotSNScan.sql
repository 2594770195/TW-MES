SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:        <OrBit Team Owen HK0313 >
-- Create date:   <2021/07/02 11:01:37:9179>
-- Description:   <PDA  工单生产-上料>
-- Rev: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROC [dbo].[PDA_ProductionMaking_LotSNScan]
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
@LoadingItemLotId IDType='',     --本次制作编号
@BoxOrLotSN  NVARCHAR(100)='',      --SN条码
@EmployeeNo VARCHAR(32)='',
@UsedQty SysNumberType=0 OUTPUT,           --本次上料数量
@Command VARCHAR(50)=''

AS
BEGIN
	-- set NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--TY
	DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10)

	DECLARE @MOId IDType
	DECLARE @MOStates VARCHAR(20)
	DECLARE @LotType CHAR(1)='R'
	DECLARE @LotSN nvarchar(100)=''
	DECLARE @IsStorage bit=0
	DECLARE @LotStatus CHAR(2)
	DECLARE @Qty SysNumberType
	DECLARE @ProductId IDType
	DECLARE @WWId IDType
	DECLARE @IsLock bit
	DECLARE @IsComplete BIT
	DECLARE @ProductionLotNO VARCHAR(50)
	DECLARE @WProductionLotNO VARCHAR(50)
	DECLARE @WorkcenterId IDType
	DECLARE @WorkflowStepId IDType
	DECLARE @MOItemId IDType=''
	DECLARE @EquipmentId IDType=''
	DECLARE @FactoryId IDType=''
	DECLARE @WWFactoryId IDType=''
	DECLARE @WWWorkcenterId IDType=''
	DECLARE @WaterProductId IDType=''
	DECLARE @DiluentProductId IDType=''
	DECLARE @MOQtyRequired SysNumberType=0
	DECLARE @SpecificationId IDType
	DECLARE @EmployeeId IDType

	DECLARE @WorkflowId IDType

	DECLARE @AssyDataChainId IDType
	DECLARE @DataChainAssyIssueId IDType=''
	DECLARE @TxnCode varchar(10)='START'
	DECLARE @LotId IDType

	DECLARE @LoadingItemLotRecordId IDType=''
	DECLARE @LoadingItemLotPSId IDType

	DECLARE @MOName VARCHAR(32)=''
	DECLARE @Remark NVARCHAR(100)=''

	DECLARE @ProductAllotStates VARCHAR(20)

    -- ============================ 2026年1月16日 15:14:25  截取箱号（防止录错）      ==============================================----
    IF ISNULL(@BoxOrLotSN,'') !=''
    BEGIN
        SET @BoxOrLotSN = LEFT(@BoxOrLotSN, CHARINDEX('+', @BoxOrLotSN + '+') - 1)
        SELECT @BoxOrLotSN AS BoxOrLotSN
    END
    -- ============================ 2026年1月16日 15:14:29  截取箱号（防止录错）      ==============================================----


	SELECT @ProductAllotStates=ProductAllotStates FROM ProductAllot 
	INNER JOIN ProductAllotItem ON ProductAllot.ProductAllotId=ProductAllotItem.ProductAllotId 
	INNER JOIN ProductAllotItemLot ON ProductAllotItem.ProductAllotItemId=ProductAllotItemLot.ProductAllotItemId
	WHERE LotSN=@BoxOrLotSN

	--为空判定
	IF ISNULL(@LoadingItemLotId,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:缺少必要参数,[员工工号][设备编号][规程号][工单]为必需项!'+@Enter
		RETURN -1
	END
	IF ISNULL(@BoxOrLotSN,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:SN物料条码不能为空!'+@Enter
		RETURN -1
	END
	SELECT @MOId=MOId,@IsComplete=IsComplete,@MOItemId=MOItemId,@EquipmentId=EquipmentId,@SpecificationId=SpecificationId FROM LoadingItemLot WHERE LoadingItemLotId=@LoadingItemLotId

	--当最后的去离子水用完时，该字段为空，代表已经上料完成
	IF ISNULL(@MOItemId,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:本次上料已经完成，无法继续上料!'+@Enter
		RETURN -1
	END
	--检查是否已经全部上料完成
	IF @IsComplete=1
	BEGIN
		SET @I_ReturnMessage='ServerMessage:本次加工已经完成，无法继续上料!'+@Enter
		RETURN -1
	END
	
	IF (@ProductAllotStates)=20
	BEGIN
		SET @I_ReturnMessage='ServerMessage:该物料未完成调拨接收，请接收后在进行投料'+@Enter
		RETURN -1
	END

	--数据准确性判定
	SELECT top 1 @MOId=MOId,@MOStates=MOStates,@IsLock=IsLock,@MOQtyRequired=MOQtyRequired,@WorkflowId=WorkflowId,@MOName=MOName FROM MO WHERE MOId=@MOId
	--检查工单
	IF ISNULL(@MOId,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:工单信息错误，工单号不存在!'+@Enter
		RETURN -1
	END
	IF @IsLock<>0
	BEGIN
		SET @I_ReturnMessage='ServerMessage:工单处于锁定状态，请联系组长解锁!'+@Enter
		RETURN -1
	END
	IF @MOStates<>'20'
	BEGIN
		SET @I_ReturnMessage='ServerMessage:工单未下达或已加工结束!'+@Enter
		RETURN -1
	END


	SELECT @FactoryId=FactoryId,@WorkcenterId=WorkcenterId FROM Equipment WHERE EquipmentId=@EquipmentId
	--获取资源对应的工作中心
	--select 
	--	@WorkcenterId=WorkcenterId
	--from dbo.Resource 
	--where Resource.ResourceId=@I_ResourceId

	--if isnull(@WorkcenterId,'')=''
	--BEGIN
	--	set @I_ReturnMessage='ServerMessage:资源【'+@I_ResourceName+'】未维护工作中心，请检查!'
	--	return -1
	--end

	--IF NOT EXISTS(SELECT TOP 1 1 FROM MOItem MOI INNER JOIN MOItemLot MOIL ON MOI.MOItemId=MOIL.MOItemId WHERE MOI.MOId=@MOId AND MOIL.LotSN=@BoxOrLotSN)
	--BEGIN
	--	SET @I_ReturnMessage='ServerMessage:物料条码错误：所扫物料不属于当前工单!'+@Enter
	--	RETURN -1
	--END

	--半成品调拨模式不须检查是否完成发料  
	--IF EXISTS(SELECT TOP 1 1 FROM MOItem WHERE MOId=@MOId AND ItemQtyRequired>ItemQtyIssued)
	--BEGIN
	--	SET @I_ReturnMessage='ServerMessage:工单还未完成发料，无法继续上料!'+@Enter
	--	RETURN -1
	--END

	--检查库存
	IF ISNULL(@BoxOrLotSN,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请扫描物料批次!'+@Enter
		RETURN -1
	END
	--检查是否小包或者外箱
	IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@BoxOrLotSN)
		SET @LotType='R'

	IF EXISTS(SELECT 1 FROM dbo.WW_RMInventory WHERE BoxSN=@BoxOrLotSN)
	BEGIN
		SET @LotType='B'
		SET @I_ReturnMessage='ServerMessage:请扫描小包条码!'+@Enter
		RETURN -1
	END


	IF @LotType <>'R'
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请扫描有效的小包条码!'+@Enter
		RETURN -1
	END

	IF @LotType='R'
	BEGIN
		--按小包扫描
		SELECT 
			@LotSN=LotSN,
			@IsStorage=IsStorage,
			@LotStatus=LotStatus,
			@Qty=Qty,
			@ProductId=ProductId,
			@WWId=WWId,
			@WWFactoryId=FactoryId,
			@WWWorkcenterId=WorkcenterId,
			@WProductionLotNO=ProductionLotNO
		FROM WW_RMInventory WHERE LotSN=@BoxOrLotSN

		IF @IsStorage=0
		BEGIN
			SET @I_ReturnMessage='ServerMessage:当前扫描的物料['+@BoxOrLotSN+']不在库!'+@Enter
			RETURN -1
		END
		--只能使用设备所在仓库的物料/当前仓库
		--IF ISNULL(@WWFactoryId,'')<>ISNULL(@FactoryId,'') OR ISNULL(@WWWorkcenterId,'')<>ISNULL(@WorkcenterId,'')
		--BEGIN
		--	SET @I_ReturnMessage='ServerMessage:当前扫描的物料不在当前仓库!'+@Enter
		--	RETURN -1
		--END
		IF @LotStatus<>'1'
		BEGIN
			SET @I_ReturnMessage='ServerMessage:当前扫描的物料['+@BoxOrLotSN+']不是正常可用的状态!'+@Enter
			RETURN -1
		END
		IF @Qty<=0
		BEGIN
			SET @I_ReturnMessage='ServerMessage:当前扫描的物料['+@BoxOrLotSN+']已经没有库存，是否需要补料？'+@Enter
			RETURN -1
		END

		IF @WorkflowId IN('WKF1000000YQ','WKF1000000YR','WKF1000000YS','WKF1000000YT','WKF1000000YV')  AND @LotSN NOT IN ('9999999999-001') AND
		@WWWorkcenterId not in (SELECT WorkcenterId FROM Workcenter WHERE WorkcenterName='FSXB' or WorkcenterName='LFS1' or WorkcenterName='LFS2' or WorkcenterName='LYM1' or WorkcenterName='LYM2' )
		BEGIN
			SET @I_ReturnMessage='ServerMessage:当前扫描物料条码['+@BoxOrLotSN+']不在分散线边仓!'+@Enter
			RETURN -1
		END
-- 		ELSE IF @WorkflowId IN('WKF1000000YQ','WKF1000000YR','WKF1000000YS','WKF1000000YT','WKF1000000YV')  AND @LotSN NOT IN ('9999999999-001') AND
-- 		@WWWorkcenterId not in (SELECT WorkcenterId FROM Workcenter WHERE WorkcenterName='LFS1')
-- 		BEGIN
-- 			SET @I_ReturnMessage='ServerMessage:当前扫描物料条码['+@BoxOrLotSN+']不在分散投料线边仓1!'+@Enter
-- 			RETURN -1
-- 		END
-- 		ELSE IF @WorkflowId IN('WKF1000000YQ','WKF1000000YR','WKF1000000YS','WKF1000000YT','WKF1000000YV')  AND @LotSN NOT IN ('9999999999-001') AND
-- 		@WWWorkcenterId not in (SELECT WorkcenterId FROM Workcenter WHERE WorkcenterName='LFS2')
-- 		BEGIN
-- 			SET @I_ReturnMessage='ServerMessage:当前扫描物料条码['+@BoxOrLotSN+']不在分散投料线边仓2!'+@Enter
-- 			RETURN -1
-- 		END
-- 		ELSE IF @WorkflowId IN('WKF1000000YQ','WKF1000000YR','WKF1000000YS','WKF1000000YT','WKF1000000YV')  AND @LotSN NOT IN ('9999999999-001') AND
-- 		@WWWorkcenterId not in (SELECT WorkcenterId FROM Workcenter WHERE WorkcenterName='LYM1')
-- 		BEGIN
-- 			SET @I_ReturnMessage='ServerMessage:当前扫描物料条码['+@BoxOrLotSN+']不在研磨线边仓1!'+@Enter
-- 			RETURN -1
-- 		END
-- 		ELSE IF @WorkflowId IN('WKF1000000YQ','WKF1000000YR','WKF1000000YS','WKF1000000YT','WKF1000000YV')  AND @LotSN NOT IN ('9999999999-001') AND
-- 		@WWWorkcenterId not in (SELECT WorkcenterId FROM Workcenter WHERE WorkcenterName='LYM2')
-- 		BEGIN
-- 			SET @I_ReturnMessage='ServerMessage:当前扫描物料条码['+@BoxOrLotSN+']不在研磨线边仓2!'+@Enter
-- 			RETURN -1
-- 		END
-- 
-- 		IF @WorkflowId IN('WKF1000000YW','WKF1000000YX','WKF1000000YY')  AND @LotSN NOT IN ('9999999999-001') AND
-- 		@WWWorkcenterId <>(SELECT TOP 1 WorkcenterId FROM Workcenter WHERE WorkcenterName='UVXB')
-- 		BEGIN
-- 			SET @I_ReturnMessage='ServerMessage:当前扫描物料条码['+@BoxOrLotSN+']不在UV线边仓!'+@Enter
-- 			RETURN -1
-- 		END
	END
	--ELSE
	--BEGIN
	--	--按箱号扫描/按箱扫描时，一般箱内只有一包
	--	SELECT TOP 1 @LotSN=LotSN,@Qty=Qty,@ProductId=ProductId,@WWId=WWId FROM WW_RMInventory WHERE BoxSN=@BoxOrLotSN AND Qty>0 AND IsStorage=1 AND LotStatus='1' AND FactoryId=@FactoryId AND WorkcenterId=@WorkcenterId ORDER BY ProductionDate
	--	IF ISNULL(@LotSN,'')=''
	--	BEGIN
	--		SET @I_ReturnMessage='ServerMessage:所扫箱号已经没有可用的物料，是否需要补料？'+@Enter
	--		RETURN -1
	--	END
	--END
	--获取去离子水产品ID
	SELECT @WaterProductId=P.ProductId FROM ProductRoot PR INNER JOIN Product P ON PR.ProductRootId=P.ProductRootId WHERE PR.ProductName='9999999999'
	SELECT @DiluentProductId=P.ProductId FROM ProductRoot PR INNER JOIN Product P ON PR.ProductRootId=P.ProductRootId WHERE PR.ProductName='1023450105'
	

	--如果是检验后再上料，判断是否有指定优先使用物料
	DECLARE @QC_ProcessInsId IDType
	DECLARE @QC_ProcessIns_UseLotId IDType
	SELECT TOP 1 @QC_ProcessInsId=QC_ProcessInsId FROM QC_ProcessIns WHERE MOId=@MOId AND InsStates='20' ORDER BY SubmissDate DESC
	IF ISNULL(@QC_ProcessInsId,'')<>''
	BEGIN
		--如果有指定这款物料才做判断
		IF EXISTS(SELECT 1 FROM QC_ProcessIns_UseLot QC INNER JOIN WW_RMInventory L ON QC.LotSN=L.LotSN
		 WHERE QC.QC_ProcessInsId=@QC_ProcessInsId AND QC.UseState=0 AND L.ProductId=@ProductId)
		BEGIN
			SELECT @QC_ProcessIns_UseLotId=QC_ProcessIns_UseLotId FROM QC_ProcessIns_UseLot WHERE QC_ProcessInsId=@QC_ProcessInsId AND UseState=0 AND LotSN=@LotSN
			IF ISNULL(@QC_ProcessIns_UseLotId,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:工单检验时有指定优先使用物料批次['+@LotSN+']，请扫描优先使用物料!'+@Enter
				RETURN -1
			END
		END
	END

	DECLARE @MOProductId IDType='',
	@LoadingItemLotDetailId IDType='',
	@ItemQtyRequired SysNumberType=0,
	@BOMQtyRequired SysNumberType=0,
	@ActualQty SysNumberType=0,
	@LineSequence VARCHAR(12)=''

	--IF (SELECT PR.ProductName FROM Product P LEFT JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId)='99999'
	--BEGIN
	--	--如果是去离子水，需要判断是否是刚开始上料或上料结束
	--	IF EXISTS(SELECT TOP 1 1 FROM LoadingItemLotDetail WHERE LoadingItemLotId=@LoadingItemLotId AND ActualQty>0)
	--	BEGIN
	--		SET @I_ReturnMessage='ServerMessage:已经开始上料，无法使用去离子水!'+@Enter
	--		RETURN -1
	--	END
	--	IF EXISTS(SELECT TOP 1 1 FROM LoadingItemLotDetail DPMD 
	--	INNER JOIN MOItem MOI ON DPMD.MOItemId=MOI.MOItemId
	--	WHERE DPMD.LoadingItemLotId=@LoadingItemLotId AND MOI.BOMQtyRequired>DPMD.ActualQty
	--	AND MOI.ProductId=@ProductId)
	--	BEGIN
	--		SET @I_ReturnMessage='ServerMessage:工单还未上料结束，无法使用去离子水!'+@Enter
	--		RETURN -1
	--	END
	--END

	--判断当前所上物料是否是按顺序所上物料
	--获取当前要上的料
	SELECT @LineSequence=MOI.LineSequence,@MOItemId=LIL.MOItemId,@MOProductId=MOI.ProductId,@LoadingItemLotDetailId=LILD.LoadingItemLotDetailId,@ItemQtyRequired=MOI.ItemQtyRequired,@BOMQtyRequired=MOI.BOMQtyRequired,@ActualQty=LILD.ActualQty FROM LoadingItemLotDetail LILD 
	INNER JOIN LoadingItemLot LIL ON LILD.LoadingItemLotId=LIL.LoadingItemLotId AND LILD.MOItemId=LIL.MOItemId
	INNER JOIN MOItem MOI ON LILD.MOItemId=MOI.MOItemId 
	WHERE LIL.LoadingItemLotId=@LoadingItemLotId
	--当前上的物料不等于上料表要上的物料
	IF @MOProductId<>@ProductId and @MOName <> '6600014648'
	BEGIN
		--如果是当前上料顺序之前的物料也允许继续上料
		IF NOT EXISTS(SELECT 1 FROM MOItem WHERE MOId=@MOId AND LineSequence<@LineSequence AND ProductId=@ProductId AND ProductId<>@WaterProductId AND LineSequence<>'000') OR @MOProductId=@WaterProductId
		BEGIN
			DECLARE @ProductDescription NVARCHAR(100)
			DECLARE @MOProductDescription NVARCHAR(100)
			SELECT @ProductDescription=ProductDescription FROM Product WHERE ProductId=@ProductId
			SELECT @MOProductDescription=ProductDescription FROM Product WHERE ProductId=@MOProductId
			SET @I_ReturnMessage='ServerMessage:物料上料['+@LotSN+']['+ISNULL(@ProductDescription,'')+']顺序错误，请投['+ISNULL(@MOProductDescription,'')+']或之前的物料!'+@Enter
			RETURN -1
		END
		SELECT TOP 1 @MOItemId=MOI.MOItemId,@MOProductId=MOI.ProductId,@LoadingItemLotDetailId=LILD.LoadingItemLotDetailId,@ItemQtyRequired=MOI.ItemQtyRequired,@ActualQty=LILD.ActualQty FROM LoadingItemLotDetail LILD 
		INNER JOIN MOItem MOI ON LILD.MOItemId=MOI.MOItemId
		WHERE LILD.LoadingItemLotId=@LoadingItemLotId
		AND MOI.ProductId=@ProductId AND MOI.LineSequence<@LineSequence AND ProductId<>@WaterProductId AND LineSequence<>'000'
	END

	--检查：如果工单指定了物料批次，则只能使用指定的物料，其他物料指定的批次当前工单无法使用/[0713]
	SELECT @ProductionLotNO=ProductionLotNO FROM MOItem WHERE MOId=@MOId AND MOItemId=@MOItemId AND DeleteFlag IN(NULL,'','0')

	--IF ISNULL(@ProductionLotNO,'')<>''
	--BEGIN
	--	IF NOT EXISTS(SELECT TOP 1 1 FROM MOProductionLot WHERE MOItemId=@MOItemId AND LotSN=@LotSN)
	--	BEGIN
	--		SET @I_ReturnMessage='ServerMessage:当前工单有指定的生产物料，请使用指定物料进行上料!'+@Enter
	--		RETURN -1
	--	END
	--END
	--ELSE IF EXISTS(SELECT TOP 1 1 FROM MOProductionLot MPL INNER JOIN LoadingItemLot LIL ON MPL.MOId=LIL.MOId WHERE MPL.LotSN=@LotSN AND MPL.MOId<>@MOId AND LIL.IsComplete=0)
	--BEGIN
	--	--判断当前批次是否已经被其他工单指定且指定工单未完成上料
	--	SET @I_ReturnMessage='ServerMessage:当前扫描物料为其他工单指定用料，上料失败!'+@Enter
	--	RETURN -1
	--END

	IF ISNULL(@ProductionLotNO,'')<>'' AND @WProductionLotNO NOT IN(SELECT col FROM DB_Split(@ProductionLotNO,','))
	BEGIN
		SET @I_ReturnMessage='ServerMessage:当前工单有指定的生产物料，请使用指定物料进行上料，当前工单指定物料['+@ProductionLotNO+']!'+@Enter
		RETURN -1
	END

	IF ISNULL(@LoadingItemLotDetailId,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:没找到工单对应的上料计划!'+@Enter
		RETURN -1
	END

	--如果已经上足了超出工单用量的料，再次上料只能通过补料进行上料
	--IF @ActualQty>=@ItemQtyRequired AND @Command<>'CMDPSUPPLY'
	--BEGIN
	--	SET @I_ReturnMessage='ServerMessage:当前上料数量已达工单需求用量，需要继续上料请扫描补料指令!'+@Enter
	--	RETURN -1
	--END

	--获取当前操作员
	SELECT TOP 1 @EmployeeId=UserId FROM SysUser WHERE EmployeeNo=@EmployeeNo

	IF NOT EXISTS(SELECT 1 FROM [Operator] WHERE RefId=@LoadingItemLotId AND EmployeeId=@EmployeeId)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:您不属于当前工单绑定生产人员，无法进行上料!'+@Enter
		RETURN -1
	END


	DECLARE @SpecificationCode VARCHAR(50)
	SELECT @SpecificationCode=SpecificationCode FROM Specification S INNER JOIN SpecificationRoot SR ON S.SpecificationRootId=SR.SpecificationRootId
	WHERE S.SpecificationId=@SpecificationId

	IF @I_Sender='LotSNScan'
	BEGIN
		SET @UsedQty=@ItemQtyRequired
		--去离子水特殊处理
		IF @ProductId=@WaterProductId
		BEGIN
			--查询当前是不是第一次上料
			IF @ActualQty=0
			BEGIN
				IF @SpecificationCode='INKLOAD'--配置墨水
				BEGIN
					DECLARE @INKMOQtyLess SysNumberType=1000
					DECLARE @INKWaterQtyLess SysNumberType=10
					DECLARE @INKMOQtyGreater SysNumberType=1000
					DECLARE @INKWaterQtyGreater SysNumberType=100

					SELECT TOP 1 
						@INKMOQtyLess=CONVERT(decimal(18,3),ISNULL(ParameterValue,'0')),
						@INKWaterQtyLess=CONVERT(decimal(18,3),ISNULL(ParameterValueEx,'0'))
					FROM SysParameter WHERE ParameterName='[Configure Ink Deionized Water Settings Less]'

					SELECT TOP 1 
						@INKMOQtyGreater=CONVERT(decimal(18,3),ISNULL(ParameterValue,'0')),
						@INKWaterQtyGreater=CONVERT(decimal(18,3),ISNULL(ParameterValueEx,'0'))
					FROM SysParameter WHERE ParameterName='[Configure Ink Deionized Water Settings Greater]'

					IF @MOQtyRequired<@INKMOQtyLess AND @ItemQtyRequired>@INKWaterQtyLess
					BEGIN
						SET @UsedQty=@ItemQtyRequired-@INKWaterQtyLess
					END
					ELSE IF @MOQtyRequired>=@INKMOQtyGreater AND @ItemQtyRequired>@INKMOQtyGreater
					BEGIN
						SET @UsedQty=@ItemQtyRequired-@INKWaterQtyGreater
					END
				END
				ELSE
				BEGIN
					DECLARE @DMOQtyLess SysNumberType=300
					DECLARE @DWaterQtyLess SysNumberType=5
					DECLARE @DMOQtyGreater SysNumberType=300
					DECLARE @DWaterQtyGreater SysNumberType=10

					SELECT TOP 1 
						@DMOQtyLess=CONVERT(decimal(18,3),ISNULL(ParameterValue,'0')),
						@DWaterQtyLess=CONVERT(decimal(18,3),ISNULL(ParameterValueEx,'0'))
					FROM SysParameter WHERE ParameterName='[Configure Plup Deionized Water Settings Less]'

					SELECT TOP 1 
						@DMOQtyGreater=CONVERT(decimal(18,3),ISNULL(ParameterValue,'0')),
						@DWaterQtyGreater=CONVERT(decimal(18,3),ISNULL(ParameterValueEx,'0'))
					FROM SysParameter WHERE ParameterName='[Configure Plup Deionized Water Settings Greater]'

					IF @MOQtyRequired<@DMOQtyLess AND @ItemQtyRequired>@DWaterQtyLess
					BEGIN
						SET @UsedQty=@ItemQtyRequired-@DWaterQtyLess
					END
					ELSE IF @MOQtyRequired>=@DMOQtyGreater AND @ItemQtyRequired>@DMOQtyGreater
					BEGIN
						SET @UsedQty=@ItemQtyRequired-@DWaterQtyGreater
					END
				END
			END
		END

		IF @SpecificationCode='XS' AND @ProductId=@DiluentProductId
		BEGIN
			--当前上料是第一次上，还是第二次上
			IF @ActualQty<=0
			BEGIN
				--获取稀释液上料参数
				DECLARE @DiluentFQty SysNumberType
				SELECT TOP 1 
					@DiluentFQty=CONVERT(decimal(18,3),ISNULL(ParameterValue,'0'))
				FROM SysParameter WHERE ParameterName='[Diluent First Loading Setting]'

				SET @UsedQty=@DiluentFQty
			END
			ELSE
			BEGIN
				--稀释液第二次上料数量=(称重重量-稀释液50kg)-以上料稀释液重量
				DECLARE @WeighQty SysNumberType
				SELECT @WeighQty=SUM(Qty) FROM Lot WHERE MOId=@MOId AND LotStatus='1'
				SET @UsedQty=@WeighQty-@ActualQty
			END
		END
		SET @UsedQty=@UsedQty-@ActualQty

		--如果物料需求用量大于当前批次数量，则使用批次用量
		IF @UsedQty>@Qty
			SET @UsedQty=@Qty

		--使用数量等于物料需求数量减去已投料数量
		--SET @UsedQty=@ItemQtyRequired

		IF @Command<>'CMDPSUPPLY'
		BEGIN
			/******************************************************  投料确认操作  *********************************************************/
			--减去已投料数量
			--SET @UsedQty-=@ActualQty
			--print @UsedQty
			--IF @UsedQty<=0
			--BEGIN
			--	SET @I_ReturnMessage='ServerMessage:本次上料数量必须大于0!'+@Enter
			--	RETURN -1
			--END
			--上料扫描数量与实际数量不符时处理逻辑
			--当MES数量小于实物数量时，生产人员输入实物数量，提示MES数量不足，同时锁定工单，需要由管理人员进行审核解锁
			--当MES数量大于实物数量，且MES数量小于工单用量时，生产人员输入的数量小于MES数量，触发锁定（物料未上完，就去扫其他物料，这种情况通常是不允许的），MES剩余数量通过空桶回收处理
			--当MES数量大于工单用量，且工单用量大于实物数量时，MES数量足够，生产人员却输入实物数量，不足工单用量，触发锁定
            
            --数量为0会导致后续生成领料单的时候报错，会直接进入下一数据链节点
            IF @UsedQty<=0
			BEGIN
				SET @I_ReturnMessage='ServerMessage:本次上料数量必须大于0!'+@Enter
				RETURN -1
			END
            
			IF @Qty<@UsedQty
			BEGIN
				UPDATE MO SET IsLock=1 WHERE MOId=@MOId
				SET @I_ReturnMessage='ServerMessage:当前系统批次库存剩余'+CAST(@Qty AS VARCHAR(19))+',已不足上料数量,工单已自动锁定，请联系组长核实解锁!'+@Enter
				RETURN -1
			END
			IF @Qty>@UsedQty AND @ItemQtyRequired*0.99>@UsedQty+@ActualQty
			BEGIN
				IF (@ActualQty>0 AND @ProductId IN (@WaterProductId,@DiluentProductId)) OR @ProductId NOT IN (@WaterProductId,@DiluentProductId)
				BEGIN
					UPDATE MO SET IsLock=1 WHERE MOId=@MOId
					SET @I_ReturnMessage='ServerMessage:当前系统批次库存剩余'+CAST(@Qty AS VARCHAR(19))+',超出所上料数量且未达到工单需求数量,工单已自动锁定，请联系组长核实解锁!'+@Enter
					RETURN -1
				END
			END

			--获取批次ID
			SELECT @LotId=LotId,@WorkflowStepId=WorkflowStepId FROM Lot WHERE LotSN=@LotSN

			BEGIN TRANSACTION LOADING
			--更新已上料数量
			UPDATE LoadingItemLotDetail SET ActualQty+=@UsedQty,LastMakingDate=getdate() WHERE LoadingItemLotDetailId=@LoadingItemLotDetailId

			--扣除物料库存,去离子水不扣库存
			IF EXISTS(SELECT 1 FROM WW_RMInventory WHERE WWId=@WWId) AND @ProductId<>@WaterProductId
				UPDATE WW_RMInventory SET Qty-=@UsedQty WHERE WWId=@WWId

			--更新批次数量
			IF EXISTS(SELECT 1 FROM Lot WHERE LotSN=@LotSN) AND @ProductId<>@WaterProductId
				UPDATE Lot SET Qty=Qty-@UsedQty WHERE LotSN=@LotSN

			IF ISNULL(@QC_ProcessIns_UseLotId,'')<>''
				UPDATE QC_ProcessIns_UseLot SET UseState=1 WHERE QC_ProcessIns_UseLotId=@QC_ProcessIns_UseLotId

			SET @Remark='当前批次数量['+CAST(@Qty AS NVARCHAR(19))+']，工单['+@MOName+']投料使用数量['+CAST(@UsedQty AS NVARCHAR(19))+'],剩余数量['+CAST((@Qty-@UsedQty) AS NVARCHAR(19))+']';
			--记录批次跟踪
			--插入物料批号追踪表
			EXEC dbo.TxnBase_MLotTrack
				@I_OrBitUserId =@I_OrBitUserId, -- char(12)
				@I_PlugInCommand=@I_PlugInCommand,
				@I_ResourceId =@I_ResourceId, -- char(12)
				@LotSN = @LotSN, -- nvarchar(50) --物料批号
				@LotQty = @UsedQty, -- decimal(18, 6)--数量
				@TxnCode = 'M-生产上料', -- nvarchar(50) --事务码
				@OrderName =@MOName , -- nvarchar(50) --单据号
				@Remark = @Remark -- nvarchar(200) --备注

			--记录批次扫描记录
			EXEC SysGetObjectPKId '','LoadingItemLotRecord',@LoadingItemLotRecordId OUTPUT
			INSERT INTO [dbo].[LoadingItemLotRecord]
					([LoadingItemLotRecordId]
					,[LoadingItemLotDetailId]
					,[LotSN]
					,[Qty]
					,[EmployeeId]
					,[CreateUserId])
				VALUES
					(@LoadingItemLotRecordId
					,@LoadingItemLotDetailId
					,@LotSN
					,@UsedQty
					,@EmployeeId
					,@I_OrBitUserId)

			--插入数据链上料记录表，方便追溯查询dbo.DataChainAssyIssue[0713]
			EXEC [dbo].[TxnBase_DataChainMainLine]
					   @DataChainId = @AssyDataChainId OUTPUT,
					   @TxnCode =@TxnCode,
					   @I_PlugInCommand = @I_PlugInCommand,
					   @I_OrBitUserId = @I_OrBitUserId,
					   @I_ResourceId = @I_ResourceId,
					   @LotId = @LotId,
					   @MOId= @MOId,
					   @ProductId = @ProductId,
					   @WorkcenterId = @WorkcenterId,
					   @SpecificationId = @SpecificationId,
					   @WorkflowStepId = @WorkflowStepId

			SELECT @AssyDataChainId=DataChainId FROM DataChain WHERE MOId=@MOId AND MOItemId=''
			EXEC SysGetObjectPKId '','DataChainAssyIssue',@DataChainAssyIssueId OUTPUT
			INSERT INTO [dbo].[DataChainAssyIssue]
					   ([DataChainAssyIssueId]
					   ,[AssyDataChainId]
					   ,[AssyIssueType]
					   ,[AssyProductId]
					   ,[AssyLotSN]
					   ,[AssyLotId]
					   ,[AssyMOId]
					   ,[AssyMOItemId]
					   ,[IssueQty]
					   ,[BaseQty]
					   ,[DateCode]
					   ,[LotBatch]
					   ,[ItemLocation]
					   ,[VendorId]
					   ,[ResourceId]
					   ,[ShiftId]
					   ,[UserId]
					   ,[Operator]
					   ,[Side]
					   ,[SpecificationId]
					   ,[WorkflowStepId]
					   ,[IsReplaceProduct]
					   ,[IsReplacePart]
					   ,[CreateUserId])
				 VALUES
					   (@DataChainAssyIssueId
					   ,@AssyDataChainId
					   ,0
					   ,@ProductId
					   ,@LotSN
					   ,@LotId
					   ,@MOId
					   ,@MOItemId
					   ,@UsedQty
					   ,@BOMQtyRequired
					   ,NULL
					   ,NULL
					   ,NULL
					   ,NULL
					   ,@I_ResourceId
					   ,NULL
					   ,@I_OrBitUserId
					   ,@EmployeeId
					   ,''
					   ,@SpecificationId
					   ,@WorkflowStepId
					   ,0
					   ,0
					   ,@I_OrBitUserId)

			--如果是补料，插入补料记录
			IF @Command='CMDPSUPPLY'
			BEGIN
				EXEC SysGetObjectPKId '','LoadingItemLotPS',@LoadingItemLotPSId OUTPUT
				INSERT INTO [dbo].[LoadingItemLotPS]
							([LoadingItemLotPSId]
							,[LoadingItemLotDetailId]
							,[LotSN]
							,[ProductId]
							,[SupplyQty]
							,[SupplyWareHouseId]
							,[IsRequest]
							,[IsApporved]
							,[CreateUserId])
						VALUES
							(@LoadingItemLotPSId
							,@LoadingItemLotDetailId
							,@LotSN
							,@ProductId
							,@UsedQty
							,@WorkcenterId
							,0
							,0
							,@I_OrBitUserId)
				--锁定工单
				UPDATE MO SET IsLock=1 WHERE MOId=@MOId
			END

			--工单上料完成，更新主表当前上料物料到下一物料，当前上料为去离子水，无论上多少，都跳到下一物料
			--全部上料完成后还可以在上一次去离子水[0713]
			--判断去离子水是否用完，用完表示已全部上料完成
			IF NOT EXISTS(SELECT 1 FROM LoadingItemLotDetail L INNER JOIN MOItem M ON L.MOItemId=M.MOItemId WHERE L.LoadingItemLotId=@LoadingItemLotId AND L.ActualQty<M.ItemQtyRequired)
			BEGIN
				UPDATE LoadingItemLot SET MOItemId='',LastMakingDate=getdate(),StirTime=0,StirState=0,StirCurrDate=GETDATE() WHERE LoadingItemLotId=@LoadingItemLotId
			END
			ELSE IF @ItemQtyRequired<=@ActualQty+@UsedQty OR @ProductId=@WaterProductId
			BEGIN
				SET @MOItemId=''

				--下一物料
				SELECT TOP 1 @MOItemId=A.MOItemId FROM LoadingItemLotDetail L
				INNER JOIN MOItem A ON L.MOItemId=A.MOItemId
				INNER JOIN MO B ON A.MOId=B.MOId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				WHERE L.LoadingItemLotId=@LoadingItemLotId AND B.MOId=@MOId 
				AND ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>L.ActualQty
				AND A.ProductId NOT IN (@WaterProductId,@DiluentProductId) 
				AND ((A.LineSequence>@LineSequence AND @ProductId NOT IN (@WaterProductId,@DiluentProductId)) OR @ProductId IN (@WaterProductId,@DiluentProductId))
				ORDER BY A.LineSequence

				IF ISNULL(@MOItemId,'')=''
				BEGIN
					SELECT TOP 1 @MOItemId=MOI.MOItemId FROM LoadingItemLotDetail LILD 
					INNER JOIN MOItem MOI ON LILD.MOItemId=MOI.MOItemId
					INNER JOIN Product P ON MOI.ProductId=P.ProductId
					WHERE LILD.LoadingItemLotId=@LoadingItemLotId AND ISNULL(MOI.DeleteFlag,'') IN('','0')
					AND MOI.ProductId IN (@WaterProductId,@DiluentProductId) AND LILD.ActualQty<MOI.ItemQtyRequired 
					AND ((MOI.ProductId =@WaterProductId AND LILD.ActualQty>0 AND MOI.ProductId<>@ProductId)
					OR (MOI.ProductId =@DiluentProductId AND LILD.ActualQty=0))
					ORDER BY LineSequence
				END

				UPDATE LoadingItemLot SET MOItemId=ISNULL(@MOItemId,''),LastMakingDate=getdate(),StirTime=0,StirState=1,StirCurrDate=GETDATE() WHERE LoadingItemLotId=@LoadingItemLotId
			END

			--配方用量正负BOM用量1%时，锁定工单，需要组长解锁工单，继续生产（去离子水和稀释液第二次上料时做判定）
			IF ABS(@ItemQtyRequired-@ActualQty-@UsedQty)>@ItemQtyRequired*0.01 AND @Qty>@UsedQty
			BEGIN
				IF (@ActualQty>0 AND @ProductId IN (@WaterProductId,@DiluentProductId)) OR @ProductId NOT IN (@WaterProductId,@DiluentProductId)
				BEGIN
					UPDATE MO SET IsLock=1 WHERE MOId=@MOId
					SET @I_ReturnMessage='ServerMessage:物料条码 ['+@BoxOrLotSN+'] 上料完成，物料用量超出标准用量1%，工单已被锁定停止生产，请联系组长解锁!'+@Enter
				END
			END
			ELSE
			BEGIN
				SET @I_ReturnMessage='ServerMessage:物料条码 ['+@BoxOrLotSN+'] 上料完成!'+@Enter
			END

			IF @@ERROR<>0
				ROLLBACK TRANSACTION LOADING
			ELSE
				COMMIT TRANSACTION LOADING

			/******************************************************  投料确认操作.END  *********************************************************/
		END
		
		RETURN 0
	END

	IF @I_Sender='UsedQtyScan'
	BEGIN

		--减去已投料数量
		--SET @UsedQty-=@ActualQty
		--IF @UsedQty<=0
		--BEGIN
		--	SET @I_ReturnMessage='ServerMessage:本次上料数量必须大于0!'+@Enter
		--	RETURN -1
		--END
	    --上料扫描数量与实际数量不符时处理逻辑
		--当MES数量小于实物数量时，生产人员输入实物数量，提示MES数量不足，同时锁定工单，需要由管理人员进行审核解锁
		--当MES数量大于实物数量，且MES数量小于工单用量时，生产人员输入的数量小于MES数量，触发锁定（物料未上完，就去扫其他物料，这种情况通常是不允许的），MES剩余数量通过空桶回收处理
		--当MES数量大于工单用量，且工单用量大于实物数量时，MES数量足够，生产人员却输入实物数量，不足工单用量，触发锁定
		IF @Qty<@UsedQty
		BEGIN
		    UPDATE MO SET IsLock=1 WHERE MOId=@MOId
			SET @I_ReturnMessage='ServerMessage:当前系统批次库存剩余'+CAST(@Qty AS VARCHAR(19))+',已不足上料数量,工单已自动锁定，请联系组长核实解锁!'+@Enter
			RETURN -1
		END
		IF @Qty>@UsedQty AND @ItemQtyRequired*0.99>@UsedQty+@ActualQty
		BEGIN
			IF (@ActualQty>0 AND @ProductId IN (@WaterProductId,@DiluentProductId)) OR @ProductId NOT IN (@WaterProductId,@DiluentProductId)
			BEGIN
				UPDATE MO SET IsLock=1 WHERE MOId=@MOId
				SET @I_ReturnMessage='ServerMessage:当前系统批次库存剩余'+CAST(@Qty AS VARCHAR(19))+',超出所上料数量且未达到工单需求数量,工单已自动锁定，请联系组长核实解锁!'+@Enter
				RETURN -1
			END
		END




		--获取批次ID
		SELECT @LotId=LotId,@WorkflowStepId=WorkflowStepId FROM Lot WHERE LotSN=@LotSN

		BEGIN TRANSACTION LOADING
		--更新已上料数量
		UPDATE LoadingItemLotDetail SET ActualQty+=@UsedQty,LastMakingDate=getdate() WHERE LoadingItemLotDetailId=@LoadingItemLotDetailId

		--扣除物料库存,去离子水不扣库存
		IF EXISTS(SELECT 1 FROM WW_RMInventory WHERE WWId=@WWId) AND @ProductId<>@WaterProductId
			UPDATE WW_RMInventory SET Qty-=@UsedQty WHERE WWId=@WWId

		--更新批次数量
		--IF EXISTS(SELECT 1 FROM Lot WHERE LotSN=@LotSN) AND @ProductId<>@WaterProductId
		--	UPDATE Lot SET Qty=Qty-@UsedQty WHERE LotSN=@LotSN

		IF ISNULL(@QC_ProcessIns_UseLotId,'')<>''
			UPDATE QC_ProcessIns_UseLot SET UseState=1 WHERE QC_ProcessIns_UseLotId=@QC_ProcessIns_UseLotId

		SET @Remark='当前批次数量['+CAST(@Qty AS NVARCHAR(19))+']，工单['+@MOName+']投料使用数量['+CAST(@UsedQty AS NVARCHAR(19))+'],剩余数量['+CAST((@Qty-@UsedQty) AS NVARCHAR(19))+']';
		--记录批次跟踪
		--插入物料批号追踪表
		EXEC dbo.TxnBase_MLotTrack
			@I_OrBitUserId =@I_OrBitUserId, -- char(12)
			@I_PlugInCommand=@I_PlugInCommand,
			@I_ResourceId =@I_ResourceId, -- char(12)
			@LotSN = @LotSN, -- nvarchar(50) --物料批号
			@LotQty = @UsedQty, -- decimal(18, 6)--数量
			@TxnCode = 'M-生产上料', -- nvarchar(50) --事务码
			@OrderName =@MOName , -- nvarchar(50) --单据号
			@Remark = @Remark -- nvarchar(200) --备注

		--记录批次扫描记录

		EXEC SysGetObjectPKId '','LoadingItemLotRecord',@LoadingItemLotRecordId OUTPUT
		INSERT INTO [dbo].[LoadingItemLotRecord]
				([LoadingItemLotRecordId]
				,[LoadingItemLotDetailId]
				,[LotSN]
				,[Qty]
				,[EmployeeId]
				,[CreateUserId])
			VALUES
				(@LoadingItemLotRecordId
				,@LoadingItemLotDetailId
				,@LotSN
				,@UsedQty
				,@EmployeeId
				,@I_OrBitUserId)

		--插入数据链上料记录表，方便追溯查询dbo.DataChainAssyIssue[0713]
		EXEC [dbo].[TxnBase_DataChainMainLine]
				   @DataChainId = @AssyDataChainId OUTPUT,
				   @TxnCode =@TxnCode,
				   @I_PlugInCommand = @I_PlugInCommand,
				   @I_OrBitUserId = @I_OrBitUserId,
				   @I_ResourceId = @I_ResourceId,
				   @LotId = @LotId,
				   @MOId= @MOId,
				   @ProductId = @ProductId,
				   @WorkcenterId = @WorkcenterId,
				   @SpecificationId = @SpecificationId,
				   @WorkflowStepId = @WorkflowStepId

		SELECT @AssyDataChainId=DataChainId FROM DataChain WHERE MOId=@MOId AND MOItemId=''
		EXEC SysGetObjectPKId '','DataChainAssyIssue',@DataChainAssyIssueId OUTPUT
		INSERT INTO [dbo].[DataChainAssyIssue]
				   ([DataChainAssyIssueId]
				   ,[AssyDataChainId]
				   ,[AssyIssueType]
				   ,[AssyProductId]
				   ,[AssyLotSN]
				   ,[AssyLotId]
				   ,[AssyMOId]
				   ,[AssyMOItemId]
				   ,[IssueQty]
				   ,[BaseQty]
				   ,[DateCode]
				   ,[LotBatch]
				   ,[ItemLocation]
				   ,[VendorId]
				   ,[ResourceId]
				   ,[ShiftId]
				   ,[UserId]
				   ,[Operator]
				   ,[Side]
				   ,[SpecificationId]
				   ,[WorkflowStepId]
				   ,[IsReplaceProduct]
				   ,[IsReplacePart]
				   ,[CreateUserId])
			 VALUES
				   (@DataChainAssyIssueId
				   ,@AssyDataChainId
				   ,0
				   ,@ProductId
				   ,@LotSN
				   ,@LotId
				   ,@MOId
				   ,@MOItemId
				   ,@UsedQty
				   ,@BOMQtyRequired
				   ,NULL
				   ,NULL
				   ,NULL
				   ,NULL
				   ,@I_ResourceId
				   ,NULL
				   ,@I_OrBitUserId
				   ,@EmployeeId
				   ,''
				   ,@SpecificationId
				   ,@WorkflowStepId
				   ,0
				   ,0
				   ,@I_OrBitUserId)

		--如果是补料，插入补料记录
		IF @Command='CMDPSUPPLY'
		BEGIN
			EXEC SysGetObjectPKId '','LoadingItemLotPS',@LoadingItemLotPSId OUTPUT
			INSERT INTO [dbo].[LoadingItemLotPS]
						([LoadingItemLotPSId]
						,[LoadingItemLotDetailId]
						,[LotSN]
						,[ProductId]
						,[SupplyQty]
						,[SupplyWareHouseId]
						,[IsRequest]
						,[IsApporved]
						,[CreateUserId])
					VALUES
						(@LoadingItemLotPSId
						,@LoadingItemLotDetailId
						,@LotSN
						,@ProductId
						,@UsedQty
						,@WorkcenterId
						,0
						,0
						,@I_OrBitUserId)
			--锁定工单
			UPDATE MO SET IsLock=1 WHERE MOId=@MOId
		END

		--工单上料完成，更新主表当前上料物料到下一物料，当前上料为去离子水，无论上多少，都跳到下一物料
		--全部上料完成后还可以在上一次去离子水[0713]
		--判断去离子水是否用完，用完表示已全部上料完成
		IF NOT EXISTS(SELECT 1 FROM LoadingItemLotDetail L INNER JOIN MOItem M ON L.MOItemId=M.MOItemId WHERE L.LoadingItemLotId=@LoadingItemLotId AND L.ActualQty<M.ItemQtyRequired)
		BEGIN
			UPDATE LoadingItemLot SET MOItemId='',LastMakingDate=getdate(),StirTime=0,StirState=0,StirCurrDate=GETDATE() WHERE LoadingItemLotId=@LoadingItemLotId
		END
		ELSE IF @ItemQtyRequired<=@ActualQty+@UsedQty OR @ProductId=@WaterProductId
		BEGIN
			SET @MOItemId=''

			--下一物料
			SELECT TOP 1 @MOItemId=A.MOItemId FROM LoadingItemLotDetail L
			INNER JOIN MOItem A ON L.MOItemId=A.MOItemId
			INNER JOIN MO B ON A.MOId=B.MOId
			INNER JOIN Product C ON A.ProductId=C.ProductId
			WHERE L.LoadingItemLotId=@LoadingItemLotId AND B.MOId=@MOId 
			AND ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>L.ActualQty
			AND A.ProductId NOT IN (@WaterProductId,@DiluentProductId) 
			AND ((A.LineSequence>@LineSequence AND @ProductId NOT IN (@WaterProductId,@DiluentProductId)) OR @ProductId IN (@WaterProductId,@DiluentProductId))
			ORDER BY A.LineSequence

			IF ISNULL(@MOItemId,'')=''
			BEGIN
				SELECT TOP 1 @MOItemId=MOI.MOItemId FROM LoadingItemLotDetail LILD 
				INNER JOIN MOItem MOI ON LILD.MOItemId=MOI.MOItemId
				INNER JOIN Product P ON MOI.ProductId=P.ProductId
				WHERE LILD.LoadingItemLotId=@LoadingItemLotId AND ISNULL(MOI.DeleteFlag,'') IN('','0')
				AND MOI.ProductId IN (@WaterProductId,@DiluentProductId) AND LILD.ActualQty<MOI.ItemQtyRequired 
				AND ((MOI.ProductId =@WaterProductId AND LILD.ActualQty>0 AND MOI.ProductId<>@ProductId)
				OR (MOI.ProductId =@DiluentProductId AND LILD.ActualQty=0))
				ORDER BY LineSequence
			END



			UPDATE LoadingItemLot SET MOItemId=ISNULL(@MOItemId,''),LastMakingDate=getdate(),StirTime=0,StirState=1,StirCurrDate=GETDATE() WHERE LoadingItemLotId=@LoadingItemLotId
		END

		--配方用量正负BOM用量1%时，锁定工单，需要组长解锁工单，继续生产（去离子水和稀释液第二次上料时做判定）
		IF ABS(@ItemQtyRequired-@ActualQty-@UsedQty)>@ItemQtyRequired*0.01 AND @Qty>@UsedQty
		BEGIN
			IF (@ActualQty>0 AND @ProductId IN (@WaterProductId,@DiluentProductId)) OR @ProductId NOT IN (@WaterProductId,@DiluentProductId)
			BEGIN
				UPDATE MO SET IsLock=1 WHERE MOId=@MOId
				SET @I_ReturnMessage='ServerMessage:物料条码 ['+@BoxOrLotSN+'] 上料完成，物料用量超出标准用量1%，工单已被锁定停止生产，请联系组长解锁!'+@Enter
			END
		END
		ELSE
		BEGIN
			SET @I_ReturnMessage='ServerMessage:物料条码 ['+@BoxOrLotSN+'] 上料完成!'+@Enter
		END

		IF @@ERROR<>0
			ROLLBACK TRANSACTION LOADING
		ELSE
			COMMIT TRANSACTION LOADING

	END
	RETURN 0
END
GO
