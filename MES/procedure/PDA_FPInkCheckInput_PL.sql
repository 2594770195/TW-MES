SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:        <OrBit Team HH0082 Sunshineding>
-- Create date:   <2021/08/13 >
-- Description:   <成品灌墨>
-- Rev: 15.03
-- Update comment: 理货维度由「SAP批次」改为「物料+工厂+仓库+SAP批次」，灌墨按四维度准入与扣数
--                 1) 扫描批次取库存行时同时取 FactoryId/WorkcenterId，准入与理货数量均按四维度匹配
--                 2) 已扫量按四维度归属到当前有效理货行（以理货行创建时间为起点），不同仓库/不同次理货互不冲抵
--                 3) 已扣数结算移至流程结束：自动完工/批次下线时先校验各维度已扫量=理货量，
--                    生成领料单后将本工单已确认理货行统一置为已扣数(IsOccupyAllocatedQty=0)
--                 4) 流程结束校验（领料单之前）：任一维度已扫量≠理货量判定为程序异常，
--                    直接阻断并提示联系IT处理，不生成领料单、不推进批次
--                 5) 废弃人工输入数量分支(MLotSNScan)，数量一律按剩余理货数量自动计算
-- Rev: 15.04
-- Update comment: 新增 MOSemiFinishedLotAllocation.SAPSyncFlag（0=未同步，1=已同步）：
--                 流程结束生成领料单后统一结算置已扣数时同步置 SAPSyncFlag='0'（未同步）；
--                 SAP 同步暂未实现，后续补充：操作完成后由统一同步逻辑循环调用存在未同步记录
--                 (ConfirmStatus='1' AND SAPSyncFlag='0')的 MO 上报 SAP，失败保持'0'等待下次循环补偿
-- Rev: 15.02
-- Update comment: 预分配批次准入、实时扣库存、完工领料与占用释放
--                 2026/11/10：容载器扫码自动取数，取 MIN(MES批次可用量, 剩余理货数量)，取消人工输入数量
--                             剩余理货数量 = 理货数量 - LoadingItemLotRecord 中同SAP批次已扫数量
--                             工单剩余需求小于本次应扣减数量时直接报错
-- Update date:  <2026/11/10>
-- =============================================
CREATE PROC [dbo].[PDA_FPInkCheckInput_PL]
@I_Sender NVARCHAR(200) = '',                    --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX) = '' OUTPUT,      --返回的信息,支持多语言	
@I_ExceptionFieldName NVARCHAR(100) = '' OUTPUT, --向客户端报告引起冲突的字段
@I_LanguageId CHAR(1) = '1',                     --客户端传入的语言ID
@I_PlugInCommand VARCHAR(5) = '',                --插件命令
@I_OrBitUserId CHAR(12) = '',                    --用户ID
@I_OrBitUserName NVARCHAR(100) = '',             --用户名
@I_ResourceId CHAR(12) = '',                     --资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100) = '',              --资源名
@I_PKid CHAR(12) = '',                           --主键
@I_ParentPKId CHAR(12) = '',                     --父级主键
@I_Parameter NVARCHAR(100) = '',                 --插件参数
                                                  --以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.

@EmployeeNo NVARCHAR(50) = '',                   -- 上料员
@ProductionLine VARCHAR(50) = '',                -- 产线
@SpecificationCode VARCHAR(50) = '',             -- 规程代码
@MOName VARCHAR(50) = '',                        -- 
@InputScan VARCHAR(50) = '',                     --信息输入: 包括设备编码，人员编码，规程代码，批号，工艺参数编码，命令按钮条码
@InputNumber VARCHAR(50) = '0',                 --数值输入：重量，工艺参数值
@Command VARCHAR(50) = '',                        --当前执行指令
@FMOQty DECIMAL(18,4)=0,
@LoadingItemLotId CHAR(12)='',
@LoadingItemLotRecordId CHAR(12)=''

AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    --TY
    DECLARE @Enter NVARCHAR(50) = CHAR(13) + CHAR(10);
    DECLARE @RESULT INT = 0;
	DECLARE @LotId CHAR(12)
    DECLARE @LotSN NVARCHAR(50);
	DECLARE @MProductId CHAR(12)
	DECLARE @MLotId CHAR(12)
	DECLARE @MLotSN CHAR(50)
	DECLARE @MOProductName NVARCHAR(50) 
	DECLARE @MOProductDescription NVARCHAR(200) 
	DECLARE @MOProductId CHAR(12)
	DECLARE @MQtyRequired DECIMAL(18,4)
	DECLARE @TaskPlannedQty DECIMAL(18,4)
	DECLARE @BaseQty DECIMAL(18,4)
	DECLARE @MActualQty DECIMAL(18,4)=0
    DECLARE @CurrMActualQty DECIMAL(18,4)=0
	DECLARE @BeginQty DECIMAL(18,4)=0
	DECLARE @UsedQty DECIMAL(18,4)=0
	DECLARE @CurrMaterial NVARCHAR(50)
	DECLARE @CurrProductDescription NVARCHAR(200) 
	DECLARE @CurrSpecificationCode NVARCHAR(50)=''
	DECLARE @MOItemTaskName NVARCHAR(50)=''

	DECLARE @SpecificationId CHAR(12)=''
	DECLARE @TaskSpecificationId  CHAR(12)=''
	DECLARE @WorkflowId CHAR(12)
	DECLARE @WorkflowStepId CHAR(12)
	DECLARE @DataChainId CHAR(12);
    DECLARE @WorkCenterId CHAR(12);
	DECLARE @EmployeeId CHAR(12)
	DECLARE @AssyMOItemId CHAR(12)=''
	DECLARE @IssueMOItemId CHAR(12)=''
	DECLARE @FirstFlag BIT=0
	DECLARE @MOId  CHAR(12)='',
            @MOItemId  CHAR(12)='',
            @MOItemTaskId CHAR(12)=''

	DECLARE @DateCode NVARCHAR(50)
	DECLARE @BomItemQty DECIMAL(18,4)
	DECLARE @LoadingItemLotDetailId  CHAR(12);			
	DECLARE @DataChainAssyIssueId  CHAR(12);
	DECLARE @SrcLotSnList NVARCHAR(500)=''
	DECLARE @TaskSpecificationName NVARCHAR(50)
	DECLARE @TaskNextSpecificationId CHAR(12)
	DECLARE @SpecFlag BIT=0


	DECLARE @MSntemp TABLE(Id INT IDENTITY(1,1),LotSn NVARCHAR(50),Qty DECIMAL(18,4))
	DECLARE @MaxCnt INT
	DECLARE @Counter INT
	DECLARE @tempLotSn NVARCHAR(50) 
	DECLARE @tempQty DECIMAL(18,4)
	DECLARE @MaxId INT
	DECLARE @MinId INT
	DECLARE @NewSn NVARCHAR(50)
	DECLARE @NewLotId CHAR(12)
	DECLARE @NewLotQty INT
	DECLARE @Count INT
	DECLARE @Qty DECIMAL(18,4)
	DECLARE @WWId CHAR(12)='' -- 当前扫描批次的库存记录ID
	DECLARE @LotAvailableQty DECIMAL(18,4)=0 -- 当前批次可用库存数量
	DECLARE @TallyQty DECIMAL(18,4)=0 -- 当前批次对应的理货（预分配）数量
	DECLARE @TallyUsedQty DECIMAL(18,4)=0 -- 同一SAP批次已扫码扣减的理货数量
	DECLARE @TallyRemainQty DECIMAL(18,4)=0 -- 同一SAP批次剩余可用的理货数量
	DECLARE @MLotProductionLotNO VARCHAR(50)='' -- 当前扫描批次对应的SAP/生产批次号
	DECLARE @MFactoryId CHAR(12)='' -- 当前扫描批次所在工厂（理货维度）
	DECLARE @MWorkcenterId CHAR(12)='' -- 当前扫描批次所在仓库（理货维度）
	DECLARE @TallyStartDate DATETIME=NULL -- 当前维度有效理货行的最早创建时间，作为已扫量归属起点
	DECLARE @MRemainQty DECIMAL(18,4)=0 -- 当前工单物料剩余需求数量
	DECLARE @InventoryQtyBefore DECIMAL(18,4)=0 -- 扣减前批次库存数量
	DECLARE @Remark NVARCHAR(200)='' -- 批次跟踪备注

	DECLARE @LoadingItemLotMoveId CHAR(12)
	DECLARE @I_ReturnMessage1 NVARCHAR(MAX) ='',
	@I_ExceptionFieldName1 NVARCHAR(100)='';

	-- 【SAP 同步】已扣数变化明细：捕获本次由"已理货"释放为"已扣数"的理货记录，供同步调用 SAP 已扣数接口
	DECLARE @DeductedRows TABLE (
		MOSemiFinishedLotAllocationId CHAR(12)		-- 理货分配记录主键
	)
	DECLARE @SapRet INT = 0							-- SAP 接口返回值：0=成功，非0=失败(失败需回滚)
	DECLARE @SapMsg NVARCHAR(MAX) = ''				-- SAP 接口返回信息
	DECLARE @TallySyncCount INT = 0					-- 本次待同步 SAP 的已扣数记录数
    -- ============================ 2026年1月16日 15:14:25  截取箱号（防止录错）      ==============================================----
    IF NOT EXISTS( SELECT 1 FROM Equipment WHERE EquipmentNumber=@InputScan )--排除设备，设备会有+号的
    BEGIN
        SET @InputScan = LEFT(@InputScan, CHARINDEX('+', @InputScan + '+') - 1)
    END
    -- ============================ 2026年1月16日 15:14:29  截取箱号（防止录错）      ==============================================----




    --条码/指令扫描
	IF ISNULL(@LoadingItemLotId,'')<>''  
	BEGIN
		SELECT @EmployeeId=EmployeeId,
			@SpecificationId=SpecificationId,
			@MOId= MOId,
			@AssyMOItemId= MOItemId,
			@WorkCenterId= WorkCenterId,
			@MOItemTaskId= MOItemTaskId 
		FROM LoadingItemLot 
		WHERE LoadingItemLotId=@LoadingItemLotId

		SELECT TOP 1 @LotSN=LotSN FROM dbo.MOItemLot MOI
		    INNER JOIN dbo.MOItemTask MT ON MT.MOItemTaskId = MOI.MOItemTaskId  
		    WHERE MOI.MOItemId=@AssyMOItemId AND @MOItemTaskId=MOI.MOItemTaskId AND MT.TaskStatus = 0

		SELECT @LotId=LotId,@MOProductId=ProductId,@WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId FROM dbo.Lot WHERE @LotSN=LotSN

		SET @SrcLotSnList=''
		SELECT  @SrcLotSnList= @SrcLotSnList +  CASE WHEN ISNULL(PLIL.OrgLotSN,'')='' THEN PLIL.LotSN +',' ELSE   PLIL.OrgLotSN +',' END  FROM  dbo.PickingListItem PLI
			INNER JOIN dbo.Product Pd1 ON Pd1.ProductId = PLI.ProductId AND Pd1.ProductClassify=2
			INNER JOIN dbo.PickingList PL ON PL.PickingListId = PLI.PickingListId AND PL.PickingListClass='01'
			INNER JOIN dbo.PickingListItemLot PLIL ON PLIL.PickingListItemId = PLI.PickingListItemId
		WHERE PLI.MOId =@MOId
		ORDER BY PLI.ProductId DESC

		IF ISNULL(@SrcLotSnList,'')<>''
		BEGIN  
		    SET @SrcLotSnList= SUBSTRING(@SrcLotSnList,1,CHARINDEX(',',@SrcLotSnList,LEN(@SrcLotSnList))-1) 
		END 

		IF ISNULL(@LotId,'')=''
		BEGIN
            insert into mwjtestlog(src,log1,log2) VALUES('灌墨',@AssyMOItemId,@MOItemTaskId)
			SELECT '' InputScan 
			SET @I_ExceptionFieldName = 'InputScan' 
			SET @I_ReturnMessage = 'ServerMessage:工单【'+@MOName+'】不在当前【成品灌墨】工序节点，请检查是否进行了产线排单或已经工单完工！' + @Enter;
			RETURN -1
		END

	END

    IF @I_Sender = 'InputScanDefocus'
    BEGIN
        SET @InputScan = LTRIM(RTRIM(ISNULL(@InputScan, '')));

        IF ISNULL(@InputScan, '') = ''
        BEGIN
			SELECT '' InputScan ,'0' InputNumber,'' Command
			SET @I_ExceptionFieldName = 'InputScan';
			SET @I_ReturnMessage = 'ServerMessage:输入错误，请继续扫描墨水批次或下线命令' + @Enter;
			RETURN -1
        END;

        --进行判断，输入参数是否是执行命令
        IF LEFT(@InputScan, 3) = 'CMD'
        BEGIN
            IF @InputScan = 'CMDRESET' --重置命令：只重载在在本界面扫描的，其他参数是从查询界面带过来的
            BEGIN
				SELECT  '' AS EmployeeNo,
						'' AS ProductionLine,
						'' AS SpecificationCode,
						'' AS MOName , 
						'' AS InputScan,
						'0' AS InputNumber,
                       @InputScan AS Command,
						0 AS FMOQty,
						'' AS LoadingItemLotId,
						'' AS LoadingItemLotRecordId,
						'' AS SrcLotSnList

                SET @I_ReturnMessage = 'ServerMessage:已重置!' + @Enter;
                SET @I_ExceptionFieldName = 'InputScan';

                RETURN 0;
            END;
            IF @InputScan = 'CMDLOTMOVE' --批次下线
            BEGIN
                --修改当前执行指令为批次过站，接下来是录入重量
                --SET @I_ExceptionFieldName = 'InputNumber';

				--IF EXISTS(SELECT 1 FROM LoadingItemLotDetail WHERE LoadingItemLotId=@LoadingItemLotId AND ItemQtyRequired>ActualQty)
				--BEGIN
				--	SELECT '' AS InputScan

				--	SELECT @Qty=ItemQtyRequired,@MActualQty=ActualQty FROM LoadingItemLotDetail WHERE LoadingItemLotId=@LoadingItemLotId AND ItemQtyRequired>ActualQty
				--	SET @Qty=ISNULL(@Qty,0)
				--	SET @MActualQty=ISNULL(@MActualQty,0)

				--	SET @I_ReturnMessage = 'ServerMessage:工单任务【'+@MOItemTaskName+'】已灌墨数量【'+CAST(@MActualQty AS NVARCHAR(19))+'】还未达需求数量【'+CAST(@Qty AS NVARCHAR(19))+'】！' + @Enter;
				--	RETURN -1;
				--END

				SELECT @InputNumber=CAST(CAST(TaskPlannedQty AS DECIMAL(18,3)) AS VARCHAR(50)),
				       @MOItemTaskName=MOItemTaskName 
			    FROM dbo.MOItemTask WHERE 	@MOItemTaskId= MOItemTaskId 

                SELECT '' AS InputScan,
                       CAST(@InputNumber AS NVARCHAR(50)) AS InputNumber,
                       @InputScan AS Command;
                SET @I_ReturnMessage = 'ServerMessage:请输入工单任务【'+@MOItemTaskName+'】默认数量=【'+CAST(@InputNumber AS NVARCHAR(50)) + '】' + @Enter;
                RETURN 0;
            END;
            IF @InputScan = 'CMDSWITCHE' --切换工单
            BEGIN
                SET @I_ExceptionFieldName = 'InputScan';
				SELECT '' InputScan ,'0' InputNumber,'CMDSWITCHE' Command
				SET @I_ReturnMessage = 'ServerMessage:输入工单号或产线代码，进行工单灌墨切换操作!' + @Enter;
                RETURN 0;
            END;


			-- 2026-03-09 活性成品扫描该命令码直接跳过负压过滤节点进行成品灌墨
		    IF @InputScan='CMDINJECT'
			BEGIN
			    IF ISNULL(@MOName,'')='' OR ISNULL(@SpecificationCode,'')=''
			    BEGIN
                    SET @I_ReturnMessage='ServerMessage:请先扫描员工工号、产线代码、工单号等基础信息' +@Enter
			        RETURN 0
                END

                SELECT @MOId = MOId,
                @MOProductId = ProductId
                FROM dbo.MO
                WHERE MOName = @MOName;

                SELECT @MOProductName=ProductName,@MOProductDescription=ProductDescription FROM dbo.Product
                INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
                WHERE ProductId=@MOProductId

                SELECT @AssyMOItemId = MOItemId,@FMOQty=ItemQtyRequired
                FROM dbo.MOItem
                WHERE @MOId = MOId
                AND @MOProductId = MOItem.ProductId;

                SELECT TOP 1
                @MOItemTaskId = MOItemTaskId
                FROM dbo.MOItemTask
                WHERE MOItemId = @AssyMOItemId
                AND TaskStatus = 0;
                SELECT TOP 1 @LotSN=LotSN FROM dbo.MOItemLot MOI
                INNER JOIN dbo.MOItemTask MT ON MT.MOItemTaskId = MOI.MOItemTaskId
                WHERE @MOItemTaskId=MOI.MOItemTaskId AND MT.TaskStatus = 0

			    select @WorkflowId = WorkflowId,@LotId = LotId from Lot where LotSN = @LotSN

			    -- 如果当前不是批次启动节点，不允许节点移动
			    DECLARE @SpecificationRootName char(100)
			    select @SpecificationRootName=SpecificationRoot.SpecificationName from Lot
		        left join Specification on Specification.SpecificationId = Lot.SpecificationId
                left join SpecificationRoot on SpecificationRoot.SpecificationRootId = Specification.SpecificationRootId
                where LotSN = @LotSN	
                IF @SpecificationRootName <> '批号启动'
                BEGIN 
                    set @I_ReturnMessage = 'ServerMessage:当前工单【'+@MOName+'】不是【批号启动】节点，无法进行跳过负压过滤！当前节点为【' + @SpecificationRootName + '】' + @Enter;
                    RETURN -1
                END
			    
			    IF ISNULL(@WorkflowId,'') = 'WKF1000000ZD'
			    BEGIN
                    -- 记录数据链
                    EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
														@I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
														@I_OrBitUserId = @I_OrBitUserId,                -- char(12)
														@I_ResourceId = @I_ResourceId,                 -- char(12)
														@LotId = @LotId,                        -- char(12)
														@MOId = @MOId,                         -- char(12)
														@MOItemId ='',                     -- char(12)
														@ProductId = @MOProductId,                    -- char(12)
														@WorkcenterId = '',                 -- char(12)
														@SpecificationId ='',              -- char(12)
														@WorkflowStepId = '',               -- char(12)
                                                        @TxnCode = '活性跳过负压'
			         -- 进行节点移动（需要跳过两次节点 批号启动->负压->灌墨）---------------------------------------------------------------------------------------------------------------
                    DECLARE @nowDate DATETIME=GETDATE()
                    EXEC dbo.TxnBase_LotMove @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
                                                @I_PlugInCommand = @I_PlugInCommand  ,                    -- varchar(5)
                                                @I_OrBitUserId = @I_OrBitUserId,                        -- char(12)
                                                @I_ResourceId = @I_ResourceId,                         -- char(12)
                                                @LotSN = @LotSN,                                -- varchar(40)
                                                @LotInDate = @nowDate,         -- datetime
                                                @ShiftId = '',                              -- char(12)
                                                @UserComment = N''                          -- nvarchar(1000)
			         EXEC dbo.TxnBase_LotMove @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
                                                @I_PlugInCommand = @I_PlugInCommand  ,                    -- varchar(5)
                                                @I_OrBitUserId = @I_OrBitUserId,                        -- char(12)
                                                @I_ResourceId = @I_ResourceId,                         -- char(12)
                                                @LotSN = @LotSN,                                -- varchar(40)
                                                @LotInDate = @nowDate,         -- datetime
                                                @ShiftId = '',                              -- char(12)
                                                @UserComment = N''                          -- nvarchar(1000)
                END
			    set @I_ReturnMessage='ServerMessage:已跳过负压过滤节点，请扫描墨水领料批次' +@Enter
			    return 1
			END

        END;
		IF @Command='CMDSWITCHE'
        BEGIN
		    DECLARE @SwitcheFlag INT=0

            IF  EXISTS (SELECT 1  FROM dbo.LoadingItemLot 
		    INNER JOIN dbo.MO ON MO.MOId = LoadingItemLot.MOId
			INNER JOIN dbo.MOItemTask ON MOItemTask.MOItemId = LoadingItemLot.MOItemId  AND MOItemTask.TaskStatus = 0
			INNER JOIN dbo.MOItemLot ON MOItemLot.MOItemId = LoadingItemLot.MOItemId
            INNER JOIN Lot ON Lot.LotSN =MOItemLot.LotSN  AND Lot.SpecificationId IN ('SPE1000001B6','SPE10000028J','SPE10000028S')
			LEFT JOIN dbo.Product Pd ON Pd.ProductId = MO.ProductId
			WHERE LoadingItemLot.IsComplete=0  
			AND LoadingItemLot.SpecificationId IN ( 'SPE10000028S','SPE10000028J','SPE1000001B6')
		    AND ( MO.WorkflowId IN('WKF1000000Z0','WKF1000000YZ') OR Pd.ProductClassify='1')
			AND MO.MOStates='20' AND MO.MOName = @InputScan)
            BEGIN
                 SET @SwitcheFlag=1
				 SELECT TOP 1 @LoadingItemLotId= LoadingItemLotId FROM dbo.LoadingItemLot 
						INNER JOIN dbo.MO ON MO.MOId = LoadingItemLot.MOId
						INNER JOIN dbo.MOItemTask ON MOItemTask.MOItemId = LoadingItemLot.MOItemId  AND MOItemTask.TaskStatus = 0
						INNER JOIN dbo.MOItemLot ON MOItemLot.MOItemId = LoadingItemLot.MOItemId
						INNER JOIN Lot ON Lot.LotSN =MOItemLot.LotSN  AND Lot.SpecificationId IN ('SPE1000001B6','SPE10000028J','SPE10000028S')
						LEFT JOIN dbo.Product Pd ON Pd.ProductId = MO.ProductId
						WHERE LoadingItemLot.IsComplete=0  
						AND LoadingItemLot.SpecificationId IN ( 'SPE10000028S','SPE10000028J','SPE1000001B6')
						AND ( MO.WorkflowId IN('WKF1000000Z0','WKF1000000YZ') OR Pd.ProductClassify='1')
						AND MO.MOStates='20' AND MO.MOName = @InputScan
            END
			ELSE IF EXISTS (SELECT 1 FROM dbo.LoadingItemLot 
								INNER JOIN dbo.MO ON MO.MOId = LoadingItemLot.MOId
								INNER JOIN dbo.MOItemTask ON MOItemTask.MOItemId = LoadingItemLot.MOItemId  AND MOItemTask.TaskStatus = 0
								INNER JOIN dbo.MOItemLot ON MOItemLot.MOItemId = LoadingItemLot.MOItemId
								INNER JOIN Lot ON Lot.LotSN =MOItemLot.LotSN  AND Lot.SpecificationId IN ('SPE1000001B6','SPE10000028J','SPE10000028S')
								LEFT JOIN dbo.Workcenter ON Workcenter.WorkcenterId = LoadingItemLot.WorkCenterId
								LEFT JOIN dbo.Product Pd ON Pd.ProductId = MO.ProductId
								WHERE LoadingItemLot.IsComplete=0  
									  AND LoadingItemLot.SpecificationId  IN ('SPE1000001B6', 'SPE10000028S','SPE10000028J')
									  AND ( MO.WorkflowId IN('WKF1000000Z0','WKF1000000YZ') OR Pd.ProductClassify='1')
									  AND MO.MOStates='20' AND WorkcenterName = @InputScan)
			BEGIN
                 SET @SwitcheFlag=2
				 SELECT TOP 1 @LoadingItemLotId= LoadingItemLotId FROM dbo.LoadingItemLot 
								INNER JOIN dbo.MO ON MO.MOId = LoadingItemLot.MOId
								INNER JOIN dbo.MOItemTask ON MOItemTask.MOItemId = LoadingItemLot.MOItemId  AND MOItemTask.TaskStatus = 0
								INNER JOIN dbo.MOItemLot ON MOItemLot.MOItemId = LoadingItemLot.MOItemId
								INNER JOIN Lot ON Lot.LotSN =MOItemLot.LotSN  AND Lot.SpecificationId IN ('SPE1000001B6','SPE10000028J','SPE10000028S')
								LEFT JOIN dbo.Workcenter ON Workcenter.WorkcenterId = LoadingItemLot.WorkCenterId
								LEFT JOIN dbo.Product Pd ON Pd.ProductId = MO.ProductId
								WHERE LoadingItemLot.IsComplete=0  
									  AND LoadingItemLot.SpecificationId  IN ('SPE1000001B6', 'SPE10000028S','SPE10000028J')
									  AND ( MO.WorkflowId IN('WKF1000000Z0','WKF1000000YZ') OR Pd.ProductClassify='1')
									  AND MO.MOStates='20' AND WorkcenterName = @InputScan
			END

			IF @SwitcheFlag<>0 AND ISNULL(@LoadingItemLotId,'')<>''  
			BEGIN
				SELECT @EmployeeId=EmployeeId,
					@SpecificationId=SpecificationId,
					@MOId= MOId,
					@AssyMOItemId= MOItemId,
					@WorkCenterId= WorkCenterId,
					@MOItemTaskId= MOItemTaskId 
				FROM LoadingItemLot 
				WHERE LoadingItemLotId=@LoadingItemLotId

				SELECT @EmployeeNo=UserName FROM dbo.SysUser WHERE UserId=@EmployeeId
				SELECT @MOName=MOName,@MProductId=ProductId FROM MO WHERE MOId=@MOId
				SELECT @FMOQty=ItemQtyRequired	FROM dbo.MOItem	WHERE @MOItemId=@AssyMOItemId
				SELECT @ProductionLine=WorkcenterName FROM dbo.Workcenter WHERE WorkcenterId=@WorkCenterId

				SELECT @SpecificationCode=SpecificationCode 
				FROM dbo.Specification 
				INNER JOIN dbo.SpecificationRoot ON SpecificationRoot.SpecificationRootId = Specification.SpecificationRootId 
				WHERE Specification.SpecificationId=@SpecificationId

				SELECT @MOProductName=ProductName FROM dbo.Product 
					INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
					WHERE ProductId=@MProductId

				SELECT @AssyMOItemId = MOItemId,@FMOQty=ItemQtyRequired
					FROM dbo.MOItem
					WHERE @MOId = MOId
							AND @MProductId = MOItem.ProductId;

				SELECT TOP 1
						@MOItemTaskId = MOItemTaskId
					FROM dbo.MOItemTask
					WHERE MOItemId = @AssyMOItemId
							AND TaskStatus = 0;

				SELECT @MOItemTaskName=MOItemTaskName FROM dbo.MOItemTask WHERE MOItemTaskId=@MOItemTaskId
				SET @SrcLotSnList=''
		        SELECT  @SrcLotSnList= @SrcLotSnList +  CASE WHEN ISNULL(PLIL.OrgLotSN,'')='' THEN PLIL.LotSN +',' ELSE   PLIL.OrgLotSN +',' END  FROM  dbo.PickingListItem PLI
					INNER JOIN dbo.Product Pd1 ON Pd1.ProductId = PLI.ProductId AND Pd1.ProductClassify=2
					INNER JOIN dbo.PickingList PL ON PL.PickingListId = PLI.PickingListId AND PL.PickingListClass='01'
					INNER JOIN dbo.PickingListItemLot PLIL ON PLIL.PickingListItemId = PLI.PickingListItemId
				WHERE PLI.MOId =@MOId
				ORDER BY PLI.ProductId DESC

				IF ISNULL(@SrcLotSnList,'')<>''
				BEGIN  
					SET @SrcLotSnList= SUBSTRING(@SrcLotSnList,1,CHARINDEX(',',@SrcLotSnList,LEN(@SrcLotSnList))-1) 
				END 

				SELECT  @LoadingItemLotId AS  LoadingItemLotId,
						@EmployeeNo AS EmployeeNo,
						@ProductionLine AS ProductionLine,
						@SpecificationCode AS SpecificationCode,
						@MOName AS MOName , 
						'' AS InputScan,
						'' AS InputNumber,
						'MLotSNScan' AS Command, 
						@FMOQty AS FMOQty,
						@FMOQty AS FMOQty,
						@MOProductName AS MOProduct,			
						@MOItemTaskName AS MOItemTaskName,
						'' AS LoadingItemLotRecordId,
						@SrcLotSnList AS SrcLotSnList
                
				SET @I_ExceptionFieldName = 'InputScan';
				SET @I_ReturnMessage = 'ServerMessage:工单MO或产线切换成功，请继续上料扫描操作' + @Enter;
				RETURN 0
			END


			SELECT '' InputScan ,'0' InputNumber,'' Command
			SET @I_ExceptionFieldName = 'InputScan';
			SET @I_ReturnMessage = 'ServerMessage:工单MO或产线错误，无法切换，请继续扫描墨水批次或下线命令' + @Enter;
			RETURN -1

        END;

        --判断是否是扫描基本信息
        IF ISNULL(@EmployeeNo, '') = ''
        BEGIN	
			IF NOT EXISTS (SELECT 1 FROM SysUser WHERE  UserName = @InputScan)
            BEGIN
                SELECT '' AS InputScan;
                SET @I_ReturnMessage = 'ServerMessage:[员工工号]未维护，请重新扫描' + @Enter;
                
				SET @I_ExceptionFieldName = 'InputScan';			    
				RETURN -1
            END;
            SELECT '' AS InputScan,
                   @InputScan AS EmployeeNo
            SET @I_ReturnMessage = 'ServerMessage:[员工工号]已扫描，请继续扫描[产线代码]' + @Enter;
			
			SET @I_ExceptionFieldName = 'InputScan';			                
			RETURN @RESULT;
        END;

        IF ISNULL(@ProductionLine, '') = ''
        BEGIN
            SELECT @WorkCenterId=WorkcenterId FROM dbo.Workcenter  WHERE WorkcenterName = @InputScan;
            IF ISNULL(@WorkCenterId, '') = ''
            BEGIN
                SELECT '' AS InputScan;
                SET @I_ReturnMessage = 'ServerMessage:[产线代码]未维护，请重新扫描' + @Enter;
			    SET @I_ExceptionFieldName = 'InputScan';	
			    RETURN -1
            END;
            SELECT '' AS InputScan,
                   @InputScan AS ProductionLine;
            SET @I_ReturnMessage = 'ServerMessage:[产线代码]已扫描，请继续扫描[排产工单]' + @Enter;
			SET @I_ExceptionFieldName = 'InputScan';	
            RETURN @RESULT;
        END;

        IF ISNULL(@MOName, '') = ''
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM MO WHERE MOName = @InputScan)
            BEGIN
                SELECT '' AS InputScan;
                SET @I_ReturnMessage = 'ServerMessage:工单【' + @InputScan + '】不正确，请重新扫描' + @Enter;
			    SET @I_ExceptionFieldName = 'InputScan';	
			    RETURN -1
            END;

            IF NOT EXISTS (SELECT 1 FROM MO 
			               INNER JOIN dbo.MOItem ON MOItem.MOId = MO.MOId
						   INNER JOIN dbo.MOItemTask ON MOItemTask.MOItemId = MOItem.MOItemId
			               WHERE MOName = @InputScan AND MOItemTask.TaskStatus<>'1')
            BEGIN
                SELECT '' AS InputScan;
                SET @I_ReturnMessage = 'ServerMessage:工单【' + @InputScan + '】任务不存在，请先任务排程' + @Enter;
			    SET @I_ExceptionFieldName = 'InputScan';	
			    RETURN -1
            END;

			SET @MOName=@InputScan

			DECLARE @returnvalue NVARCHAR(200)
			EXEC @returnvalue= PMZ_SysCheckMOStatus
				@I_ReturnMessage=@I_ReturnMessage output,	
				@I_PlugInCommand=@I_PlugInCommand,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_OrBitUserName=@I_OrBitUserName,
				@I_ResourceId=@I_ResourceId,
				@I_ResourceName=@I_ResourceName,
				@MOName=@MOName

			if @returnvalue=-1
			BEGIN

   				SET @I_ExceptionFieldName='InputScan' 
				set @I_ReturnMessage=@I_ReturnMessage

				return -1
			END

            SELECT @MOId = MOId,
                   @MOProductId = ProductId
            FROM dbo.MO
            WHERE MOName = @MOName;


            -- 【校验】输入工单号时检查是否全部分配完成（分配数量等于需求数量，参考 GetMOProduct）
			-- 除允许分批的工单外，存在任何半成品物料行未分配完（需求 > 已分配）则拦截
			IF NOT EXISTS(select 1 from MOSemiFinishedLotAllocation 
                        where DeleteFlag = '0'
	                    AND IsOccupyAllocatedQty = 1
                        AND ConfirmStatus = '1' 
                        AND Allow_batch=1 
                        AND moid=@MOId)
            AND EXISTS (SELECT 1 
	            FROM dbo.MOItem mi
	            INNER JOIN dbo.MO mo ON mo.MOId = mi.MOId
	            INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
	            LEFT JOIN (
	                SELECT
	                    MOId,
	                    MOItemId,
	                    ProductId,
	                    SUM(ISNULL(Qty, 0)) AS AllocatedQty
	                FROM dbo.MOSemiFinishedLotAllocation
	                WHERE DeleteFlag = '0'
	                    AND IsOccupyAllocatedQty = 1
                        AND ConfirmStatus = '1'
	                GROUP BY MOId, MOItemId, ProductId
	            ) alloc ON alloc.MOId = mi.MOId
	                AND alloc.MOItemId = mi.MOItemId
	                AND alloc.ProductId = mi.ProductId
	            WHERE mi.MOId = @MOId  
	                AND ISNULL(mi.DeleteFlag, '') = '0'
	                AND mi.LineSequence <> '000'
	                AND p.ProductClassify = '2'
	                AND CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0)) > CONVERT(decimal(18, 8), ISNULL(alloc.AllocatedQty, 0))) 
			BEGIN
				SELECT '' AS InputScan
				SET @I_ExceptionFieldName = 'InputScan'
				SET @I_ReturnMessage = 'ServerMessage:工单【' + @MOName + '】半成品批次预分配未完成，存在未分配完的物料，请先在仓库完成批次分配！' + @Enter
				RETURN -1
			END
            -- 【校验】理货批次的剩余在库数量 + 本物料行已扫数量 必须覆盖需求数量
			-- 说明：理货记录不指向单一 MES 批次(LotSN 为空)，库存按 物料+工厂+仓库+SAP批次 四维度关联；
			--       同时灌墨是实时扣库存，已消耗部分不再体现在在库数量中，故需加上已扫数量一起比较
			IF EXISTS (SELECT 1
				FROM dbo.MOItem mi
				INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
				WHERE mi.MOId = @MOId
					AND ISNULL(mi.DeleteFlag, '') = '0'
					AND mi.LineSequence <> '000'
					AND p.ProductClassify = '2'
					AND CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0)) >
						ISNULL((
							-- 【在库】该物料行有效理货维度上的剩余在库数量
							SELECT SUM(ISNULL(wri.Qty, 0))
							FROM dbo.MOSemiFinishedLotAllocation a
							INNER JOIN dbo.WW_RMInventory wri
								ON wri.ProductId = a.ProductId
							   AND wri.FactoryId = a.FactoryId
							   AND wri.WorkcenterId = a.WorkcenterId
							   AND wri.ProductionLotNO = a.ProductionLotNO
							WHERE a.MOId = mi.MOId
								AND a.MOItemId = mi.MOItemId
								AND a.DeleteFlag = '0'
								AND a.IsOccupyAllocatedQty = 1
                                AND a.ConfirmStatus = '1'
								AND ISNULL(a.ProductionLotNO, '') <> ''
								AND wri.LotStatus = '1'
								AND wri.IsStorage = 1
						), 0)
						-- 【已扫】该物料行已经灌墨扣减的数量
						+ ISNULL((
							SELECT SUM(ISNULL(LIR.Qty, 0))
							FROM dbo.LoadingItemLotRecord LIR
							INNER JOIN dbo.LoadingItemLotDetail LID ON LID.LoadingItemLotDetailId = LIR.LoadingItemLotDetailId
							WHERE LID.MOItemId = mi.MOItemId
						), 0))
			BEGIN
				SELECT '' AS InputScan
				SET @I_ExceptionFieldName = 'InputScan'
				SET @I_ReturnMessage = 'ServerMessage:工单【' + @MOName + '】半成品预分配批次的库存不足，请确认库存是否充足！' + @Enter
				RETURN -1
			END

			

			SELECT @MOProductName=ProductName,@MOProductDescription=ProductDescription FROM dbo.Product 
			INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
			WHERE ProductId=@MOProductId

            SELECT @AssyMOItemId = MOItemId,@FMOQty=ItemQtyRequired
            FROM dbo.MOItem
            WHERE @MOId = MOId
                  AND @MOProductId = MOItem.ProductId;

            SELECT TOP 1
                   @MOItemTaskId = MOItemTaskId
            FROM dbo.MOItemTask
            WHERE MOItemId = @AssyMOItemId
                  AND TaskStatus = 0;

			SELECT @MOItemTaskName=MOItemTaskName FROM dbo.MOItemTask WHERE MOItemTaskId=@MOItemTaskId


		    SET @SrcLotSnList=''
		    SELECT  @SrcLotSnList= @SrcLotSnList +  CASE WHEN ISNULL(PLIL.OrgLotSN,'')='' THEN PLIL.LotSN +',' ELSE   PLIL.OrgLotSN +',' END  FROM  dbo.PickingListItem PLI
				INNER JOIN dbo.Product Pd1 ON Pd1.ProductId = PLI.ProductId AND Pd1.ProductClassify=2
				INNER JOIN dbo.PickingList PL ON PL.PickingListId = PLI.PickingListId AND PL.PickingListClass='01'
				INNER JOIN dbo.PickingListItemLot PLIL ON PLIL.PickingListItemId = PLI.PickingListItemId
			WHERE PLI.MOId =@MOId
			ORDER BY PLI.ProductId DESC

			SET @SrcLotSnList=','
			SET @SrcLotSnList= SUBSTRING(@SrcLotSnList,1,CHARINDEX(',',@SrcLotSnList,LEN(@SrcLotSnList))-1) 


			--------------------------------------------------自动扫描规程---------------------------------------------------------
			--SET @SpecificationCode=@InputScan
			

			SELECT @EmployeeId=UserId FROM dbo.SysUser WHERE UserName=@EmployeeNo
			SELECT @WorkCenterId=WorkcenterId FROM dbo.Workcenter WHERE WorkcenterName=@ProductionLine


			--SELECT TOP 1 @LotSN=LotSN FROM dbo.MOItemLot MOI
			--    INNER JOIN dbo.MOItem ON MOItem.MOItemId = MOI.MOItemId
			--	INNER JOIN dbo.MO ON MO.MOId = MOItem.MOId AND MO.ProductId = MOItem.ProductId
			--	INNER JOIN dbo.MOItemTask MT ON MT.MOItemTaskId = MOI.MOItemTaskId  
			--	WHERE MO.MOId=@MOId AND MT.TaskStatus = 0
			SELECT TOP 1 @LotSN=LotSN FROM dbo.MOItemLot MOI
				INNER JOIN dbo.MOItemTask MT ON MT.MOItemTaskId = MOI.MOItemTaskId  
				WHERE @MOItemTaskId=MOI.MOItemTaskId AND MT.TaskStatus = 0

			SELECT @LotId=LotId,@MOProductId=ProductId,@WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@SpecificationId=SpecificationId FROM dbo.Lot WHERE @LotSN=LotSN

			IF ISNULL(@LotId,'')=''
			BEGIN
                        insert into mwjtestlog(src,log1,log2) VALUES('灌墨',643,'')

				SET @I_ReturnMessage = 'ServerMessage:工单【'+@MOName+'】不在当前【成品灌墨】工序节点，请检查是否进行了产线排单或已经工单完工！' + @Enter;
			    SET @I_ExceptionFieldName = 'InputScan';					
				RETURN -1
			END

			--获取当前批号所在工序
			SELECT @SpecificationCode=SpecificationCode FROM dbo.Specification 
					INNER JOIN dbo.SpecificationRoot ON SpecificationRoot.SpecificationRootId = Specification.SpecificationRootId
					WHERE SpecificationId=@SpecificationId

			IF @SpecificationCode NOT IN('UVGM','FSGM','P00','HXGM','SXGM')--20260113新增活性、水性灌墨
			BEGIN
                        insert into mwjtestlog(src,log1,log2) VALUES('灌墨',657,'')

				SET @I_ReturnMessage = 'ServerMessage:工单【'+@MOName+'】不在当前【成品灌墨】工序节点，请检查是否进行了产线排单或已经工单完工！' + @Enter;
			    SET @I_ExceptionFieldName = 'InputScan';					
				RETURN -1
			END

			SELECT @TaskNextSpecificationId= Specification.SpecificationId
					FROM dbo.Lot 
					 INNER JOIN dbo.WorkflowStep ON WorkflowStep.WorkflowStepId = Lot.NextWorkflowStepId
					 INNER JOIN dbo.Specification ON Specification.SpecificationId = WorkflowStep.SpecificationId
					 INNER JOIN dbo.SpecificationRoot ON SpecificationRoot.SpecificationRootId = Specification.SpecificationRootId
					 WHERE LotSN=@LotSN

			SELECT @TaskSpecificationId= Specification.SpecificationId ,@TaskSpecificationName=SpecificationName
					FROM dbo.Lot 
					 INNER JOIN dbo.WorkflowStep ON WorkflowStep.WorkflowStepId = Lot.WorkflowStepId
					 INNER JOIN dbo.Specification ON Specification.SpecificationId = WorkflowStep.SpecificationId
					 INNER JOIN dbo.SpecificationRoot ON SpecificationRoot.SpecificationRootId = Specification.SpecificationRootId
					 WHERE LotSN=@LotSN

			--IF (ISNULL(@SpecificationId,'A') <> ISNULL(@TaskNextSpecificationId,'B')) AND ISNULL(@SpecificationId,'A') <> ISNULL(@TaskSpecificationId,'B')
			--BEGIN
			--	SELECT '' AS InputScan
			--	SET @I_ReturnMessage = 'ServerMessage:规程代码【'+ISNULL(@SpecificationCode,'')+'】错误，与工单任务规程【'+ISNULL(@TaskSpecificationName,'')+'】不匹配，请重新扫描规程代码！' + @Enter;                
			--SET @I_ExceptionFieldName = 'InputScan';
			
			--	RETURN -1;
			--END

			
			IF (ISNULL(@TaskSpecificationId,'B') = 'SPE1000001B6' AND ISNULL(@SpecificationId,'A')= ISNULL(@TaskNextSpecificationId,'B')) --批次启动和灌墨规程
			   OR (ISNULL(@SpecificationId,'A') = ISNULL(@TaskSpecificationId,'B'))   --返修或非标传送
			BEGIN
			    SET @SpecFlag =1
			END
			ELSE
			BEGIN
			    SET @SpecFlag =0
			END

			IF @SpecFlag=0
			BEGIN
				SELECT '' AS InputScan
				SET @I_ReturnMessage = 'ServerMessage:规程代码【'+ISNULL(@SpecificationCode,'')+'】错误，与工单任务规程【'+ISNULL(@TaskSpecificationName,'')+'】不匹配，请重新扫描规程代码！' + @Enter;
			    SET @I_ExceptionFieldName = 'InputScan';					
				RETURN -1;
			END
-------------------------------------------------------------------------------------------------------------------------------------

			IF EXISTS (SELECT 1 FROM dbo.LoadingItemLot 
						WHERE MOId=@MOId AND MOItemTaskId=@MOItemTaskId AND WorkCenterId=@WorkCenterId
								AND MOItemId=@AssyMOItemId AND SpecificationId=@SpecificationId AND IsComplete=0)
			BEGIN
				SELECT @LoadingItemLotId=LoadingItemLotId
				FROM LoadingItemLot 
				WHERE MOId=@MOId 
				      AND MOItemTaskId=@MOItemTaskId 
					  AND WorkCenterId=@WorkCenterId
					  AND MOItemId=@AssyMOItemId 
					  AND SpecificationId=@SpecificationId 
					  AND IsComplete=0 
			END
			ELSE
			BEGIN
				EXEC dbo.SysGetObjectPKId @ObjectId = '@LoadingItemLotId',      -- char(12)
											@ObjectName = N'@LoadingItemLot',   -- nvarchar(100)
											@PKID = @LoadingItemLotId OUTPUT -- char(12)
				INSERT dbo.LoadingItemLot
				(
					LoadingItemLotId,
					IsComplete,
					EquipmentId,
					EmployeeId,
					SpecificationId,
					MOId,
					MOItemId,
					WorkCenterId,
					MOItemTaskId,
					LastMakingDate,
					CreateUserId,
					CreateDate,
					CompleteDate,
					PickingListId
				)
				VALUES
				(  @LoadingItemLotId,        -- LoadingItemLotId - char(12)
					0,      -- IsComplete - bit
					'',        -- EquipmentId - char(12)
					@EmployeeId,        -- EmployeeId - char(12)
					@SpecificationId,       -- SpecificationId - nvarchar(50)
					@MOId,        -- MOId - char(12)
					@AssyMOItemId,        -- MOItemId - char(12)
					@WorkCenterId,        -- WorkCenterId - char(12)
					@MOItemTaskId,        -- MOItemTaskId - char(12)
					GETDATE(), -- LastMakingDate - datetime
					@I_OrBitUserId,        -- CreateUserId - char(12)
					GETDATE(), -- CreateDate - datetime
					GETDATE(), -- CompleteDate - datetime
					''         -- PickingListId - char(10)
					)
			END
            SELECT '0' AS InputNumber,
                   @MOName AS MOName,@FMOQty AS FMOQty,@MOProductName+' '+@MOProductDescription AS MOProduct,
				   '' AS InputScan,@MOItemTaskName AS MOItemTaskName,
					@SrcLotSnList AS SrcLotSnList,@LoadingItemLotId AS LoadingItemLotId,
                   @SpecificationCode AS SpecificationCode;
            SET @I_ReturnMessage = 'ServerMessage:工单'+@InputScan+'已扫描，请继续墨水扫描操作' + @Enter;
			SET @I_ExceptionFieldName = 'InputScan';	
            RETURN @RESULT;
			--------------------------------------------------自动扫描规程---------------------------------------------------------
        END;

        IF ISNULL(@SpecificationCode, '') = ''
        BEGIN
		    SET @SpecificationCode=@InputScan
			SELECT @EmployeeId=UserId FROM dbo.SysUser WHERE UserName=@EmployeeNo
			SELECT @MOId=MOId FROM dbo.MO WHERE MOName=@MOName
			SELECT @WorkCenterId=WorkcenterId FROM dbo.Workcenter WHERE WorkcenterName=@ProductionLine

			SELECT @AssyMOItemId=MOItem.MOItemId FROM dbo.MOItem 
					INNER JOIN dbo.MO ON MO.MOId = MOItem.MOId AND MO.ProductId = MOItem.ProductId
					WHERE MO.MOId=@MOId
			SELECT TOP 1 @MOItemTaskId=MOItemTaskId FROM dbo.MOItemTask WHERE MOItemId=@AssyMOItemId AND TaskStatus=0

			--SELECT TOP 1 @LotSN=LotSN FROM dbo.MOItemLot MOI
			--    INNER JOIN dbo.MOItem ON MOItem.MOItemId = MOI.MOItemId
			--	INNER JOIN dbo.MO ON MO.MOId = MOItem.MOId AND MO.ProductId = MOItem.ProductId
			--	INNER JOIN dbo.MOItemTask MT ON MT.MOItemTaskId = MOI.MOItemTaskId  
			--	WHERE MO.MOId=@MOId AND MT.TaskStatus = 0
			SELECT TOP 1 @LotSN=LotSN FROM dbo.MOItemLot MOI
				INNER JOIN dbo.MOItemTask MT ON MT.MOItemTaskId = MOI.MOItemTaskId  
				WHERE @MOItemTaskId=MOI.MOItemTaskId AND MT.TaskStatus = 0

			SELECT @LotId=LotId,@MOProductId=ProductId,@WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId FROM dbo.Lot WHERE @LotSN=LotSN

			IF ISNULL(@LotId,'')=''
			BEGIN
                        insert into mwjtestlog(src,log1,log2) VALUES('灌墨',795,'')

				SET @I_ReturnMessage = 'ServerMessage:工单【'+@MOName+'】不在当前【成品灌墨】工序节点，请检查是否进行了产线排单或已经工单完工！' + @Enter;
			    SET @I_ExceptionFieldName = 'InputScan';					
				RETURN -1
			END

			SELECT @SpecificationId=SpecificationId FROM dbo.Specification 
					INNER JOIN dbo.SpecificationRoot ON SpecificationRoot.SpecificationRootId = Specification.SpecificationRootId
					WHERE SpecificationCode=@SpecificationCode

			
			SELECT @TaskNextSpecificationId= Specification.SpecificationId
					FROM dbo.Lot 
					 INNER JOIN dbo.WorkflowStep ON WorkflowStep.WorkflowStepId = Lot.NextWorkflowStepId
					 INNER JOIN dbo.Specification ON Specification.SpecificationId = WorkflowStep.SpecificationId
					 INNER JOIN dbo.SpecificationRoot ON SpecificationRoot.SpecificationRootId = Specification.SpecificationRootId
					 WHERE LotSN=@LotSN

			SELECT @TaskSpecificationId= Specification.SpecificationId ,@TaskSpecificationName=SpecificationName
					FROM dbo.Lot 
					 INNER JOIN dbo.WorkflowStep ON WorkflowStep.WorkflowStepId = Lot.WorkflowStepId
					 INNER JOIN dbo.Specification ON Specification.SpecificationId = WorkflowStep.SpecificationId
					 INNER JOIN dbo.SpecificationRoot ON SpecificationRoot.SpecificationRootId = Specification.SpecificationRootId
					 WHERE LotSN=@LotSN

			--IF (ISNULL(@SpecificationId,'A') <> ISNULL(@TaskNextSpecificationId,'B')) AND ISNULL(@SpecificationId,'A') <> ISNULL(@TaskSpecificationId,'B')
			--BEGIN
			--	SELECT '' AS InputScan
			--	SET @I_ReturnMessage = 'ServerMessage:规程代码【'+ISNULL(@SpecificationCode,'')+'】错误，与工单任务规程【'+ISNULL(@TaskSpecificationName,'')+'】不匹配，请重新扫描规程代码！' + @Enter;                
			--SET @I_ExceptionFieldName = 'InputScan';
			
			--	RETURN -1;
			--END

			
			
			IF (ISNULL(@TaskSpecificationId,'B') = 'SPE1000001B6' AND ISNULL(@SpecificationId,'A')= ISNULL(@TaskNextSpecificationId,'B')) --批次启动和灌墨规程
			   OR (ISNULL(@SpecificationId,'A') = ISNULL(@TaskSpecificationId,'B'))   --返修或非标传送
			BEGIN
			    SET @SpecFlag =1
			END
			ELSE
			BEGIN
			    SET @SpecFlag =0
			END

			IF @SpecFlag=0
			BEGIN
				SELECT '' AS InputScan
				SET @I_ReturnMessage = 'ServerMessage:规程代码【'+ISNULL(@SpecificationCode,'')+'】错误，与工单任务规程【'+ISNULL(@TaskSpecificationName,'')+'】不匹配，请重新扫描规程代码！' + @Enter;
			    SET @I_ExceptionFieldName = 'InputScan';					
				RETURN -1;
			END
-------------------------------------------------------------------------------------------------------------------------------------

			IF EXISTS (SELECT 1 FROM dbo.LoadingItemLot 
						WHERE MOId=@MOId AND MOItemTaskId=@MOItemTaskId AND WorkCenterId=@WorkCenterId
								AND MOItemId=@AssyMOItemId AND SpecificationId=@SpecificationId AND IsComplete=0)
			BEGIN
				SELECT @LoadingItemLotId=LoadingItemLotId
				FROM LoadingItemLot 
				WHERE MOId=@MOId 
				      AND MOItemTaskId=@MOItemTaskId 
					  AND WorkCenterId=@WorkCenterId
					  AND MOItemId=@AssyMOItemId 
					  AND SpecificationId=@SpecificationId 
					  AND IsComplete=0 
			END
			ELSE
			BEGIN
				EXEC dbo.SysGetObjectPKId @ObjectId = '@LoadingItemLotId',      -- char(12)
											@ObjectName = N'@LoadingItemLot',   -- nvarchar(100)
											@PKID = @LoadingItemLotId OUTPUT -- char(12)
				INSERT dbo.LoadingItemLot
				(
					LoadingItemLotId,
					IsComplete,
					EquipmentId,
					EmployeeId,
					SpecificationId,
					MOId,
					MOItemId,
					WorkCenterId,
					MOItemTaskId,
					LastMakingDate,
					CreateUserId,
					CreateDate,
					CompleteDate,
					PickingListId
				)
				VALUES
				(  @LoadingItemLotId,        -- LoadingItemLotId - char(12)
					0,      -- IsComplete - bit
					'',        -- EquipmentId - char(12)
					@EmployeeId,        -- EmployeeId - char(12)
					@SpecificationId,       -- SpecificationId - nvarchar(50)
					@MOId,        -- MOId - char(12)
					@AssyMOItemId,        -- MOItemId - char(12)
					@WorkCenterId,        -- WorkCenterId - char(12)
					@MOItemTaskId,        -- MOItemTaskId - char(12)
					GETDATE(), -- LastMakingDate - datetime
					@I_OrBitUserId,        -- CreateUserId - char(12)
					GETDATE(), -- CreateDate - datetime
					GETDATE(), -- CompleteDate - datetime
					''         -- PickingListId - char(10)
					)
			END
            SELECT '' AS InputScan,@LoadingItemLotId AS LoadingItemLotId,
                   @InputScan AS SpecificationCode;
            SET @I_ReturnMessage = 'ServerMessage:规程代码'+@InputScan+'已扫描，请继续墨水扫描操作' + @Enter;
			SET @I_ExceptionFieldName = 'InputScan';	
            RETURN @RESULT;
        END;


        -- 【保留】以下领料批次兼容及-001补码逻辑，改由预分配批次准入与实时库存校验替代，不再执行
		/*
        --水性成品灌墨如果找不到对应的批号，则在当前输入批号的后面加上-001（初期打印）
        IF NOT EXISTS (SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@InputScan
		           UNION ALL SELECT 1 FROM dbo.PickingListItemLot
			          INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListItemId = PickingListItemLot.PickingListItemId
					  WHERE MOId =@MOId AND OrgLotSN=@InputScan)
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@InputScan + '-001'
		           UNION ALL SELECT 1 FROM dbo.PickingListItemLot
			          INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListItemId = PickingListItemLot.PickingListItemId
					  WHERE MOId =@MOId AND OrgLotSN=@InputScan + '-001')
            BEGIN
                SELECT
                @MOProductId = ProductId
                FROM dbo.MO
                WHERE MOName = @MOId;

                SELECT @MOProductName=ProductName,@MOProductDescription=ProductDescription FROM dbo.Product
                INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
                WHERE ProductId=@MOProductId

                SELECT @AssyMOItemId = MOItemId,@FMOQty=ItemQtyRequired
                FROM dbo.MOItem
                WHERE @MOId = MOId
                AND @MOProductId = MOItem.ProductId;

                SELECT TOP 1
                @MOItemTaskId = MOItemTaskId
                FROM dbo.MOItemTask
                WHERE MOItemId = @AssyMOItemId
                AND TaskStatus = 0;
                SELECT TOP 1 @LotSN=LotSN FROM dbo.MOItemLot MOI
                INNER JOIN dbo.MOItemTask MT ON MT.MOItemTaskId = MOI.MOItemTaskId
                WHERE @MOItemTaskId=MOI.MOItemTaskId AND MT.TaskStatus = 0

			    select @WorkflowId = WorkflowId,@LotId = LotId from Lot where LotSN = @LotSN

                IF @WorkflowId = 'WKF1000000ZI' --水性成品灌墨
                BEGIN
                    DECLARE @NEWINPUTSCAN varchar(50)
                    SET @NEWINPUTSCAN = @InputScan + '-001'
                    SELECT @InputScan=@NEWINPUTSCAN
                    SET @InputScan=@NEWINPUTSCAN
                END

            END
        END
		*/

        -- =============================================
		-- 【新增】容载器码校验（2026/11/09）
		-- 1、扫描值必须先按容载器码识别，不是容载器码则直接报错
		-- 2、容载器码必须已绑定箱号（ZR_ToFac_ContainerCode.BoxLotSn），否则报错
		-- 3、校验通过后，用绑定的箱号替换@InputScan，继续按批次做后续校验
		--    关联关系：ZR_ContainerCode.ContainerCode = @InputScan
		--             → ZR_ToFac_ContainerCode.ZR_ContainerCodeId
		--             → ZR_ToFac_ContainerCode.BoxLotSn
		-- =============================================
		-- 校验是否为容载器码,且未解绑
		IF NOT EXISTS (SELECT 1 FROM dbo.ZR_ContainerCode WHERE ContainerCode = @InputScan AND isnull(CurrentProudctionLotSN,'') <>'')
		BEGIN
			SELECT '' InputScan ,'0' InputNumber,'' Command
			SET @I_ExceptionFieldName = 'InputScan';
			SET @I_ReturnMessage = 'ServerMessage:【' + @InputScan + '】不是有效的容载器码，请重新扫描！' + @Enter;
			RETURN -1
		END

		-- 取该容载器码最近一次绑定的MES批次（同一容器可能多次绑批，取最新有效MES批次）
		DECLARE @ContainerBoxLotSn VARCHAR(255) = '';
		SELECT TOP 1 @ContainerBoxLotSn = ISNULL(TC.BoxLotSn, '')
		FROM dbo.ZR_ContainerCode CC
			INNER JOIN dbo.ZR_ToFac_ContainerCode TC ON TC.ZR_ContainerCodeId = CC.ZR_ContainerCodeId
		WHERE CC.ContainerCode = @InputScan
		ORDER BY TC.CreateData DESC;

		-- 容载器码未绑定MES批次则报错
		IF ISNULL(@ContainerBoxLotSn, '') = ''
		BEGIN
			SELECT '' InputScan ,'0' InputNumber,'' Command
			SET @I_ExceptionFieldName = 'InputScan';
			SET @I_ReturnMessage = 'ServerMessage:容载器码【' + @InputScan + '】未绑定箱号，请先完成绑定后再扫描！' + @Enter;
			RETURN -1
		END

		-- 将扫描值替换为MES批次，后续按MES批次进行库存与预分配校验
		SET @InputScan = @ContainerBoxLotSn;

		--取消校验是否存在领料单，改由预分配批次准入与实时库存校验替代，不再执行
		-- IF EXISTS (SELECT 1 FROM dbo.WW_RMInventory WHERE LotSN=@InputScan
		--            UNION ALL SELECT 1 FROM dbo.PickingListItemLot 
		-- 	          INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListItemId = PickingListItemLot.PickingListItemId 
		-- 			  WHERE MOId =@MOId AND OrgLotSN=@InputScan)
		IF EXISTS (SELECT 1 FROM dbo.WW_RMInventory
			WHERE LotSN=@InputScan AND LotStatus='1' AND IsStorage=1 AND Qty>0)
		BEGIN
		  
		    -- 【取数】按 MES 批次取库存行，同时取工厂/仓库/SAP批次，构成理货四维度
		    SELECT @WWId=WWId,@MLotId=LotId,@MLotSN=LotSN,@MProductId=ProductId,
				   @DateCode=ProductionLotNO,@MLotProductionLotNO=ProductionLotNO,@LotAvailableQty=Qty,
				   @MFactoryId=FactoryId,@MWorkcenterId=WorkcenterId
			FROM dbo.WW_RMInventory
			WHERE LotSN=@InputScan AND LotStatus='1' AND IsStorage=1 AND Qty>0

			-- 【校验】扫描批次的 SAP 生产批次与工厂/仓库必须完整，否则无法按四维度匹配理货记录
			IF ISNULL(@MLotProductionLotNO,'')='' OR ISNULL(@MFactoryId,'')='' OR ISNULL(@MWorkcenterId,'')=''
			BEGIN
				SELECT '' InputScan ,'0' InputNumber,'' Command
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:[墨水批次]['+@InputScan+']缺少SAP生产批次或工厂仓库信息，请联系仓库确认库存数据！'+@Enter
				RETURN -1
			END

			-- 【保留】原按领料单数量计算自动使用量，改由实时库存数量计算，不再执行
			/*
			SELECT @BeginQty=SUM(PickingListItemLot.Qty) FROM dbo.PickingListItemLot 
			    INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListItemId = PickingListItemLot.PickingListItemId 
				WHERE MOId =@MOId AND (OrgLotSN=@InputScan OR LotSN=@InputScan)
			*/

			IF NOT EXISTS (SELECT 1 FROM dbo.MOItem WHERE  MOId=@MOId AND ProductId=@MProductId)
			BEGIN
				SELECT '' InputScan ,'0' InputNumber,'' Command
				SET @I_ExceptionFieldName = 'InputScan';
				SET @I_ReturnMessage =  'ServerMessage:批次【' + @InputScan + '】不是工单【'+ @MOName +'】物料，请更换批次扫描！'+@MProductId+' 1'+@MOId ++'2 '+ @Enter;
				RETURN -1
			END

			IF NOT EXISTS (SELECT 1 FROM dbo.MOItem
				            INNER JOIN dbo.Product ON Product.ProductId = MOItem.ProductId 
							WHERE  MOId=@MOId AND MOItem.ProductId=@MProductId AND ProductClassify='2')
			BEGIN
			    SELECT
                @MOProductId = ProductId
                FROM dbo.MO
                WHERE MOName = @MOId;

                SELECT @MOProductName=ProductName,@MOProductDescription=ProductDescription FROM dbo.Product
                INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
                WHERE ProductId=@MOProductId

                SELECT @AssyMOItemId = MOItemId,@FMOQty=ItemQtyRequired
                FROM dbo.MOItem
                WHERE @MOId = MOId
                AND @MOProductId = MOItem.ProductId;

                SELECT TOP 1
                @MOItemTaskId = MOItemTaskId
                FROM dbo.MOItemTask
                WHERE MOItemId = @AssyMOItemId
                AND TaskStatus = 0;
                SELECT TOP 1 @LotSN=LotSN FROM dbo.MOItemLot MOI
                INNER JOIN dbo.MOItemTask MT ON MT.MOItemTaskId = MOI.MOItemTaskId
                WHERE @MOItemTaskId=MOI.MOItemTaskId AND MT.TaskStatus = 0

			    select @WorkflowId = WorkflowId,@LotId = LotId from Lot where LotSN = @LotSN
			     
			    IF ISNULL(@WorkflowId,'') <> 'WKF1000000ZD'
			    BEGIN
                    SELECT '' InputScan ,'0' InputNumber,'' Command
                    SET @I_ExceptionFieldName = 'InputScan';
                    SET @I_ReturnMessage =  'ServerMessage:批次【' + @InputScan + '】不是半成品墨水物料，请更换批次扫描！'+@MProductId+' 1'+@MOId + +'2 '+ @Enter;
                    RETURN -1
			    END
			END

		    SELECT @IssueMOItemId=MOItemId FROM dbo.MOItem WHERE  MOId=@MOId AND ProductId=@MProductId 

		    IF EXISTS (SELECT 1 FROM dbo.LoadingItemLotRecord 
			INNER JOIN dbo.LoadingItemLotDetail ON LoadingItemLotDetail.LoadingItemLotDetailId = LoadingItemLotRecord.LoadingItemLotDetailId 
			INNER JOIN dbo.LoadingItemLot ON LoadingItemLot.LoadingItemLotId = LoadingItemLotDetail.LoadingItemLotId
			 WHERE LoadingItemLotRecord.LotSN=@InputScan AND MOItemTaskId= @MOItemTaskId AND LoadingItemLot.LoadingItemLotId=@LoadingItemLotId)
			BEGIN
				SELECT '' InputScan ,'0' InputNumber,'' Command
				SET @I_ExceptionFieldName = 'InputScan';
				SET @I_ReturnMessage =  'ServerMessage:墨水批次【' + @InputScan + '】已经在此工单任务生产中，请更换批次扫描！' + @Enter;
				RETURN -1
			END

			-- 【保留】原已领料校验，改由有效预分配记录校验替代，不再执行
			/*
		    IF NOT EXISTS (SELECT 1 FROM dbo.PickingListItemLot 
			          INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListItemId = PickingListItemLot.PickingListItemId 
					  WHERE MOId =@MOId AND LotSN=@InputScan 
					  UNION SELECT 1 FROM dbo.PickingListItemLot 
			          INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListItemId = PickingListItemLot.PickingListItemId 
					  WHERE MOId =@MOId AND OrgLotSN=@InputScan)
			BEGIN
				SELECT '' InputScan ,'0' InputNumber,'' Command 
				SET @I_ExceptionFieldName = 'InputScan';
				SET @I_ReturnMessage =  'ServerMessage:墨水批次【' + @InputScan + '】未进行工单【'+@MOName+' '+ @MOId+ '】领料，请更换批次扫描！' + @Enter 
				RETURN -1
			END
			*/

			-- 【校验】扫描批次必须为当前工单物料有效且仍占用的理货批次
			-- 说明：理货维度为 物料+工厂+仓库+SAP批次，扫描批次须按四维度严格匹配，避免跨仓库/跨工厂误匹配
			IF NOT EXISTS
			(
				SELECT 1
				FROM dbo.MOSemiFinishedLotAllocation
				WHERE MOId=@MOId AND MOItemId=@IssueMOItemId AND ProductId=@MProductId
					AND FactoryId=@MFactoryId AND WorkcenterId=@MWorkcenterId
					AND ProductionLotNO=@MLotProductionLotNO
					AND DeleteFlag='0' AND IsOccupyAllocatedQty=1 AND ConfirmStatus = '1'
			)
			BEGIN
				SELECT '' InputScan,'0' InputNumber,'' Command
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:[墨水批次]['+@InputScan+']未指定给工单['+@MOName+']，请更换批次扫描！'+@Enter
				RETURN -1
			END

			-- 【取数】读取扫描批次对应维度的理货数量（有效占用中的预分配数量合计）
			-- 一个维度的理货数量固定，可被多个容载器（MES批次）分批扫码扣减
			SET @TallyQty=0
			SELECT @TallyQty=ISNULL(SUM(ISNULL(Qty,0)),0)
			FROM dbo.MOSemiFinishedLotAllocation
			WHERE MOId=@MOId AND MOItemId=@IssueMOItemId AND ProductId=@MProductId
				AND FactoryId=@MFactoryId AND WorkcenterId=@MWorkcenterId
				AND ProductionLotNO=@MLotProductionLotNO
				AND DeleteFlag='0' AND IsOccupyAllocatedQty=1 AND ConfirmStatus = '1'

			IF ISNULL(@TallyQty,0)<=0
			BEGIN
				SELECT '' InputScan,'0' InputNumber,'' Command
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:[墨水批次]['+@InputScan+']在工单['+@MOName+']中无有效理货数量，请先完成成品理货后再扫描！'+@Enter
				RETURN -1
			END

			-- 【已扫数量】按 物料+工厂+仓库+SAP批次 四维度，统计归属当前有效理货行的已扣减数量
			-- 归属起点取当前维度有效理货行的最早创建时间：理货取消后重新理货时，新行创建时间更晚，
			-- 之前的扫码量不会冲抵新理货数量，实现"不同次理货互不冲抵"
			SET @TallyStartDate=NULL
			SELECT @TallyStartDate=MIN(CreateDate)
			FROM dbo.MOSemiFinishedLotAllocation
			WHERE MOItemId=@IssueMOItemId AND ProductId=@MProductId
				AND FactoryId=@MFactoryId AND WorkcenterId=@MWorkcenterId
				AND ProductionLotNO=@MLotProductionLotNO
				AND DeleteFlag='0' AND IsOccupyAllocatedQty=1 AND ConfirmStatus = '1'

			SET @TallyUsedQty=0
			SELECT @TallyUsedQty=ISNULL(SUM(ISNULL(LIR.Qty,0)),0)
			FROM dbo.LoadingItemLotRecord LIR
				INNER JOIN dbo.LoadingItemLotDetail LID ON LID.LoadingItemLotDetailId=LIR.LoadingItemLotDetailId
				INNER JOIN dbo.WW_RMInventory WRI ON WRI.LotSN=LIR.LotSN
			WHERE LID.MOItemId=@IssueMOItemId
				AND WRI.ProductId=@MProductId
				AND WRI.FactoryId=@MFactoryId
				AND WRI.WorkcenterId=@MWorkcenterId
				AND WRI.ProductionLotNO=@MLotProductionLotNO
				AND (@TallyStartDate IS NULL OR LIR.CreateDate>=@TallyStartDate)

			-- 【剩余理货数量】总理货数量 - 已扫数量
			SET @TallyRemainQty=ISNULL(@TallyQty,0)-ISNULL(@TallyUsedQty,0)
			IF ISNULL(@TallyRemainQty,0)<=0
			BEGIN
				SELECT '' InputScan,'0' InputNumber,'' Command
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:[墨水批次]['+@InputScan+']所属SAP批次['+ISNULL(@MLotProductionLotNO,'')+']理货数量['+CAST(ISNULL(@TallyQty,0) AS NVARCHAR(50))+']已全部使用，请更换批次扫描！'+@Enter
				RETURN -1
			END
			
			SELECT @CurrMaterial=ProductName ,@CurrProductDescription=ProductDescription
			FROM dbo.Product INNER JOIN  dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
			WHERE ProductId =@MProductId

			SELECT  @TaskPlannedQty=TaskPlannedQty FROM dbo.MOItemTask WHERE MOItemTaskId=@MOItemTaskId

			SELECT @BaseQty=ItemQtyRequired  / ISNULL(@FMOQty,1.0),
				@BomItemQty=ItemQtyRequired,
				@MQtyRequired=ItemQtyRequired * ISNULL(@TaskPlannedQty,1.0) / ISNULL(@FMOQty,1.0)  
			FROM dbo.MOItem WHERE MOItemId=@IssueMOItemId

            SELECT @MActualQty=SUM(ISNULL(ActualQty,0)) FROM dbo.LoadingItemLotDetail WHERE  @LoadingItemLotId=LoadingItemLotId AND MOItemId =@IssueMOItemId
			
			IF ISNULL(@MActualQty,0)=0
			BEGIN
			    SET @MActualQty=0
			END
			-- 不再提前领料，取数逻辑修改
			-- IF ISNULL(@MActualQty,0) + ISNULL(@BeginQty,0) <= ISNULL(@MQtyRequired,0)
			-- BEGIN
			--     SET @UsedQty=ISNULL(@BeginQty,0)  
			-- END
			-- ELSE
			-- BEGIN
			--     SET @UsedQty=ISNULL(@MQtyRequired,0)-ISNULL(@MActualQty,0)
			-- END

			-- 【计算】库存写入时已实时扣减，当前库存余额即为批次可用量
			SET @MRemainQty=ISNULL(@MQtyRequired,0)-ISNULL(@MActualQty,0)
			IF @LotAvailableQty<=0 OR @MRemainQty<=0
			BEGIN
				SELECT '' InputScan,'0' InputNumber,'' Command
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:[墨水批次]['+@InputScan+']已无可用库存数量或工单剩余需求，请更换批次扫描！'+@Enter
				RETURN -1
			END

			-- 【自动取数】不再人工输入数量，按以下口径自动计算本次扣减数量：
			--   1、MES批次可用数量不足以覆盖剩余理货数量时，取MES批次可用数量；
			--   2、MES批次可用数量足够时，取剩余理货数量（总理货数量 - 同SAP批次已扫数量）；
			--   3、允许一个理货数量分多个容载器扫码依次扣数。
			SET @UsedQty=@TallyRemainQty
			IF @LotAvailableQty<@UsedQty
				SET @UsedQty=@LotAvailableQty

			IF ISNULL(@UsedQty,0)<=0
			BEGIN
				SELECT '' InputScan,'0' InputNumber,'' Command
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:[墨水批次]['+@InputScan+']本次可扣减数量为0，请更换批次扫描！'+@Enter
				RETURN -1
			END

			-- 【校验】工单剩余需求小于本次应扣减数量时直接报错，不允许超需求扣数
			IF ISNULL(@MRemainQty,0)<ISNULL(@UsedQty,0)
			BEGIN
				SELECT '' InputScan,'0' InputNumber,'' Command
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:[工单号]['+ISNULL(@MOName,'')+']剩余需求数量['+CAST(ISNULL(@MRemainQty,0) AS NVARCHAR(50))+']小于本次应扣减数量['+CAST(ISNULL(@UsedQty,0) AS NVARCHAR(50))+']，请联系仓库文员处理！'+@Enter
				RETURN -1
			END

			SET @InputNumber = CAST( CAST(ISNULL(@UsedQty,0) AS DECIMAL(18,3)) AS VARCHAR(50))

			-- 【保留】原超量时转人工确认数量的逻辑，改由上述自动取数替代，不再执行
			/*
			IF @LotAvailableQty>@MRemainQty
			BEGIN
				SELECT CAST(@MRemainQty AS NVARCHAR(50)) AS InputNumber,
					   @MRemainQty AS MQtyRequired,
					   @MActualQty AS MActualQty,
					   @InputScan AS InputScan,
					   'MLotSNScan' AS Command
				SET @I_ExceptionFieldName='InputNumber'
				SET @I_ReturnMessage='ServerMessage:墨水批次【'+@InputScan+'】可用数量大于剩余需求，请确认使用数量【'+CAST(@MRemainQty AS NVARCHAR(50))+'】'+@Enter
				RETURN 0
			END
			*/
            
			--/***************************************自动确认数量***************************************/
			-- 【事务】自动写入时同步完成上料明细、库存扣减、批次跟踪和数据链记录
			BEGIN TRY
				BEGIN TRANSACTION InkLoading
			SELECT @SpecificationId= WorkSpecificationId FROM dbo.MOItemTask WHERE MOItemTaskId=@MOItemTaskId

			SELECT @LoadingItemLotDetailId=LoadingItemLotDetailId FROM dbo.LoadingItemLotDetail WHERE LoadingItemLotId=@LoadingItemLotId AND MOItemId=@IssueMOItemId

			IF ISNULL(@LoadingItemLotDetailId,'')=''
			BEGIN
				EXEC dbo.SysGetObjectPKId @ObjectId = 'LoadingItemLotDetailId',      -- char(12)
											@ObjectName = N'LoadingItemLotDetail',   -- nvarchar(100)
											@PKID = @LoadingItemLotDetailId OUTPUT -- char(12)
			
				INSERT dbo.LoadingItemLotDetail
				(
					LoadingItemLotDetailId,
					LoadingItemLotId,
					MOItemId,
					ItemQtyRequired,
					ActualQty,
					LastMakingDate,
					CreateDate
				)
				VALUES
				(   @LoadingItemLotDetailId,        -- LoadingItemLotDetailId - char(12)
					@LoadingItemLotId,        -- LoadingItemLotId - char(12)
					@IssueMOItemId,        -- MOItemId - char(12)
					@MQtyRequired,      -- ItemQtyRequired - decimal(18, 8)
					@UsedQty,      -- ActualQty - decimal(18, 5)
					GETDATE(), -- LastMakingDate - datetime
					GETDATE()  -- CreateDate - datetime
					)
			END
			ELSE
			BEGIN
				UPDATE LoadingItemLotDetail SET ActualQty=ISNULL(@MActualQty,0)+ISNULL(@UsedQty,0) WHERE LoadingItemLotDetailId=@LoadingItemLotDetailId
			END
			SELECT  @CurrMActualQty= ActualQty FROM LoadingItemLotDetail WHERE LoadingItemLotDetailId=@LoadingItemLotDetailId		

			-- 【校验与扣减】按库存主键再次校验余额后扣减本次实际使用数量
			SELECT @InventoryQtyBefore=Qty
			FROM dbo.WW_RMInventory
			WHERE WWId=@WWId AND LotStatus='1' AND IsStorage=1

			IF ISNULL(@InventoryQtyBefore,0)<@UsedQty
			BEGIN
				ROLLBACK TRANSACTION InkLoading
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:墨水批次库存不足，无法完成上料'+@Enter
				RETURN -1
			END

			UPDATE dbo.WW_RMInventory
			SET Qty=Qty-@UsedQty,ModifyDate=GETDATE()
			WHERE WWId=@WWId

			IF @@ROWCOUNT<>1
			BEGIN
				ROLLBACK TRANSACTION InkLoading
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:墨水批次库存不足，无法完成上料'+@Enter
				RETURN -1
			END

			-- 【追溯】记录本次上料引起的批次库存变更
			SET @Remark='当前批次数量['+CAST(@InventoryQtyBefore AS NVARCHAR(19))+']，工单['+@MOName+']投料使用数量['+CAST(@UsedQty AS NVARCHAR(19))+']，剩余数量['+CAST((@InventoryQtyBefore-@UsedQty) AS NVARCHAR(19))+']'
			EXEC dbo.TxnBase_MLotTrack
				@I_OrBitUserId=@I_OrBitUserId,
				@I_PlugInCommand=@I_PlugInCommand,
				@I_ResourceId=@I_ResourceId,
				@LotSN=@MLotSN,
				@LotQty=@UsedQty,
				@TxnCode='M-生产上料',
				@OrderName=@MOName,
				@Remark=@Remark

			EXEC dbo.SysGetObjectPKId @ObjectId = 'LoadingItemLotRecordId',      -- char(12)
										@ObjectName = N'LoadingItemLotRecord',   -- nvarchar(100)
										@PKID = @LoadingItemLotRecordId OUTPUT -- char(12)
			INSERT dbo.LoadingItemLotRecord
			(
				LoadingItemLotRecordId,
				LoadingItemLotDetailId,
				LotSN,
				Qty,
				CreateUserId,
				CreateDate
			)
			VALUES
			(   @LoadingItemLotRecordId,       -- LoadingItemLotRecordId - char(12)
				@LoadingItemLotDetailId,       -- LoadingItemLotDetailId - char(12)
				@MLotSN,      -- LotSN - nvarchar(50)
				@UsedQty,     -- Qty - decimal(18, 8)
				@I_OrBitUserId,       -- CreateUserId - char(12)
				GETDATE() -- CreateDate - datetime
				)
	        
			SELECT  @WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@LotId=LotId FROM dbo.Lot WHERE LotSN=@LotSN
			EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
												@TxnCode = 'DC',                      -- varchar(10)
												@I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
												@I_OrBitUserId = @I_OrBitUserId,                -- char(12)
												@I_ResourceId = @I_ResourceId,                 -- char(12)
												@LotId = @LotId,                        -- char(12)
												@MOId = @MOId,                         -- char(12)
												@MOItemId =@AssyMOItemId,                     -- char(12)
												@ProductId = @MOProductId,                    -- char(12)
												@WorkcenterId = @WorkCenterId,                 -- char(12)
												@SpecificationId =@SpecificationId,              -- char(12)
												@WorkflowStepId = @WorkflowStepId               -- char(12)


			EXEC dbo.SysGetObjectPKId @ObjectId = 'DataChainAssyIssueId',      -- char(12)
										@ObjectName = N'DataChainAssyIssue',   -- nvarchar(100)
										@PKID = @DataChainAssyIssueId OUTPUT -- char(12)
			INSERT dbo.DataChainAssyIssue
			(
				DataChainAssyIssueId,
				AssyDataChainId,
				IssueDataChainId,
				AssyIssueType,
				AssyProductId,
				AssyLotSN,
				AssyLotId,
				AssyMOId,
				AssyMOItemId,
				IssueProductId,
				IssueLotSN,
				IssueLotId,
				IssueMOId,
				IssueMOItemId,
				IssueQty,
				BaseQty,
				IssueDate,
				DateCode,
				LotBatch,
				ItemLocation,
				VendorId,
				ResourceId,
				ShiftId,
				UserId,
				Operator,
				Side,
				SpecificationId,
				WorkflowStepId,
				IsReplaceProduct,
				IsReplacePart,
				CreateUserId,
				CreateDate
			)
			VALUES
			(   @DataChainAssyIssueId,        -- DataChainAssyIssueId - char(12)
				@DataChainId,        -- AssyDataChainId - char(12)
				'',        -- IssueDataChainId - char(12)
				0,        -- AssyIssueType - char(1)
				@MOProductId,        -- AssyProductId - char(12)
				@LotSN,       -- AssyLotSN - nvarchar(50)
				@LotId,        -- AssyLotId - char(12)
				@MOId,        -- AssyMOId - char(12)
				@AssyMOItemId,        -- AssyMOItemId - char(12)
				@MProductId,        -- IssueProductId - char(12)
				@MLotSN,       -- IssueLotSN - nvarchar(50)
				@MLotId,        -- IssueLotId - char(12)
				@MOId,        -- IssueMOId - char(12)
				@IssueMOItemId,        -- IssueMOItemId - char(12)
				@UsedQty,      -- IssueQty - decimal(18, 3)
				@BomItemQty,      -- BaseQty - decimal(18, 3)
				GETDATE(), -- IssueDate - datetime
				@DateCode,       -- DateCode - nvarchar(50)
				@DateCode,       -- LotBatch - nvarchar(50)
				N'',       -- ItemLocation - nvarchar(max)
				'',        -- VendorId - char(12)
				@I_ResourceId,        -- ResourceId - char(12)
				'',        -- ShiftId - char(12)
				@I_OrBitUserId,        -- UserId - char(12)
				@I_OrBitUserName ,        -- Operator - char(12)
				'',        -- Side - char(10)
				@SpecificationId,        -- SpecificationId - char(12)
				@WorkflowStepId,        -- WorkflowStepId - char(12)
				0,      -- IsReplaceProduct - bit
				0,      -- IsReplacePart - bit
				@I_OrBitUserId,        -- CreateUserId - char(12)
				GETDATE()  -- CreateDate - datetime
				)

			COMMIT TRANSACTION InkLoading
			END TRY
			BEGIN CATCH
				IF @@TRANCOUNT>0
					ROLLBACK TRANSACTION InkLoading

				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:墨水批次【'+@InputScan+'】上料写入失败：'+ERROR_MESSAGE()+@Enter
				RETURN -1
			END CATCH

			-- 【结算说明】扫满结算已移至流程结束（自动完工/批次下线）生成领料单之后统一执行：
			--   扫码时理货行保持"已理货"占用状态(ConfirmStatus='1' AND IsOccupyAllocatedQty=1)不变化，
			--   流程结束时先校验各维度已扫量=理货量，生成领料单后再统一置为"已扣数"(IsOccupyAllocatedQty=0)

			--墨水批次扫完自动完工移送（检查所有半成品物料是否都完成）
                -- IF @MQtyRequired<=ISNULL(@MActualQty,0)+ISNULL(@UsedQty,0)
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.MOItem mi
                    INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
                    WHERE mi.MOId = @MOId
                        AND ISNULL(mi.DeleteFlag, '') = '0'
                        AND mi.LineSequence <> '000'
                        AND p.ProductClassify = '2'
                        AND ISNULL(mi.ItemQtyRequired, 0) > ISNULL((
                            SELECT SUM(ISNULL(lild.ActualQty, 0))
                            FROM dbo.LoadingItemLotDetail lild
                            WHERE lild.LoadingItemLotId = @LoadingItemLotId
                                AND lild.MOItemId = mi.MOItemId
                        ), 0)
                )
			BEGIN
				-- 【校验】流程结束前校验：每个理货维度(物料+工厂+仓库+SAP批次)的已扫量必须等于理货量
				-- 说明：已扫量小于理货量说明流程未完成即结束，已扫量大于理货量说明重复扣数，
				--       均属程序/数据异常；异常时不生成领料单、不推进批次，直接阻断完工并提示联系IT处理
				IF EXISTS (
					SELECT 1
					FROM (
						-- 【准备】按四维度汇总本工单有效理货行：理货量合计 + 最早创建时间(已扫量归属起点)
						SELECT a.MOItemId,a.ProductId,a.FactoryId,a.WorkcenterId,a.ProductionLotNO,
							   MIN(a.CreateDate) AS TallyStartDate,
							   SUM(ISNULL(a.Qty,0)) AS TallyQty
						FROM dbo.MOSemiFinishedLotAllocation a
						WHERE a.MOId=@MOId AND a.DeleteFlag='0'
							AND a.IsOccupyAllocatedQty=1 AND a.ConfirmStatus='1'
						GROUP BY a.MOItemId,a.ProductId,a.FactoryId,a.WorkcenterId,a.ProductionLotNO
					) l
					OUTER APPLY (
						-- 【准备】按四维度+归属起点汇总该维度已扫(灌墨扣减)数量
						SELECT SUM(ISNULL(LIR.Qty,0)) AS UsedQty
						FROM dbo.LoadingItemLotRecord LIR
						INNER JOIN dbo.LoadingItemLotDetail LID ON LID.LoadingItemLotDetailId=LIR.LoadingItemLotDetailId
						INNER JOIN dbo.WW_RMInventory WRI ON WRI.LotSN=LIR.LotSN
						WHERE LID.MOItemId=l.MOItemId
							AND WRI.ProductId=l.ProductId
							AND WRI.FactoryId=l.FactoryId
							AND WRI.WorkcenterId=l.WorkcenterId
							AND WRI.ProductionLotNO=l.ProductionLotNO
							AND LIR.CreateDate>=l.TallyStartDate
					) u
					WHERE ISNULL(u.UsedQty,0)<>l.TallyQty
				)
				BEGIN
					SET @I_ExceptionFieldName='InputScan'
					SET @I_ReturnMessage='ServerMessage:[工单号]['+ISNULL(@MOName,'')+']理货数量与灌墨扣减数量不一致(程序异常)，系统已阻断完工，请联系IT处理！'+@Enter
					RETURN -1
				END

				INSERT @MSntemp
				(
					LotSn,
					Qty
				)
				SELECT LoadingItemLotRecord.LotSN,Qty  FROM  dbo.LoadingItemLotRecord 
				LEFT JOIN dbo.LoadingItemLotDetail ON LoadingItemLotDetail.LoadingItemLotDetailId = LoadingItemLotRecord.LoadingItemLotDetailId
				LEFT JOIN dbo.LoadingItemLot ON LoadingItemLot.LoadingItemLotId = LoadingItemLotDetail.LoadingItemLotId
				WHERE LoadingItemLot.LoadingItemLotId =@LoadingItemLotId

		
				SELECT @MaxCnt=COUNT(*),@Counter=MIN(Id) FROM @MSntemp
				WHILE @Counter <= @MaxCnt AND 0 < @MaxCnt
				BEGIN 
					SELECT @tempLotSn=LotSn,@tempQty=Qty FROM @MSntemp WHERE Id=@Counter
					--UPDATE dbo.WW_RMInventory SET Qty=  CASE WHEN  @tempQty<Qty THEN Qty-@tempQty ELSE 0 END WHERE LotSN=@tempLotSn

					SET @Counter=@Counter+1
				END
	
				-- 【领料】自动完工前为当前上料会话的未领料记录生成生产领料单
				EXEC @RESULT=dbo.PDA_ProductionMakingSubmit
					@I_Sender='MakingComplete',
					@I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
					@I_PlugInCommand=@I_PlugInCommand,
					@I_OrBitUserId=@I_OrBitUserId,
					@I_OrBitUserName=@I_OrBitUserName,
					@I_ResourceId=@I_ResourceId,
					@I_ResourceName=@I_ResourceName,
					@LoadingItemLotId=@LoadingItemLotId
				IF @RESULT<>0
					RETURN @RESULT

				-- =============================================
				-- 【结算】领料单生成后统一结算：前置校验已保证每个维度已扫量=理货量，
				--       将本工单全部已确认理货行置为"已扣数"(IsOccupyAllocatedQty=0)，释放占用
				-- 【SAP 同步标记】已扣数属于需上报 SAP 的变更，同步置为未同步
				-- =============================================
				UPDATE a
				SET a.IsOccupyAllocatedQty=0,
					a.SAPSyncFlag='0',
					a.ModifyDate=GETDATE()
				FROM dbo.MOSemiFinishedLotAllocation a
				WHERE a.MOId=@MOId AND a.DeleteFlag='0'
					AND a.IsOccupyAllocatedQty=1 AND a.ConfirmStatus='1'

				-- 【SAP 同步 - 已扣数】暂未实现，后续补充；本操作仅将本次结算的理货记录置 SAPSyncFlag='0'（未同步）；
				-- 实现方式：流程结束后，由统一同步逻辑循环调用存在未同步记录
				--          （ConfirmStatus='1' AND SAPSyncFlag='0'）的 MO，按记录状态推导动作上报 SAP；
				--          同步成功置 SAPSyncFlag='1'，失败保持 '0' 等待下次循环补偿；
				-- 接口过程：dbo.APISyncU_SemiFinishedTallyToSAP（已扣数→过账扣减/预留核销）


				---------------------------------------------------------------------------------------------
				SELECT  @WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@SpecificationId=SpecificationId,@LotId=LotId,@Qty=Qty FROM dbo.Lot WHERE LotSN=@LotSN
				IF ISNULL(@SpecificationId,'') = 'SPE1000001B6'  --批次启动
				BEGIN 
					EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
														@TxnCode = 'DC',                      -- varchar(10)
														@I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
														@I_OrBitUserId = @I_OrBitUserId,                -- char(12)
														@I_ResourceId = @I_ResourceId,                 -- char(12)
														@LotId = @LotId,                        -- char(12)
														@MOId = @MOId,                         -- char(12)
														@MOItemId =@AssyMOItemId,                     -- char(12)
														@ProductId = @MOProductId,                    -- char(12)
														@WorkcenterId = @WorkCenterId,                 -- char(12)
														@SpecificationId =@SpecificationId,              -- char(12)
														@WorkflowStepId = @WorkflowStepId               -- char(12)		
					EXEC dbo.TxnBase_LotMove @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
												@I_PlugInCommand = @I_PlugInCommand  ,                    -- varchar(5)
												@I_OrBitUserId = @I_OrBitUserId,                        -- char(12)
												@I_ResourceId = @I_ResourceId,                         -- char(12)
												@LotSN = @LotSN,                                -- varchar(40)
												@LotInDate = '2021-08-23 08:47:42',         -- datetime
												@ShiftId = '',                              -- char(12)
												@UserComment = N''                          -- nvarchar(1000)			    
				END
			
                SET @CurrSpecificationCode=''
                SELECT  @WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@SpecificationId=Lot.SpecificationId,@LotId=LotId,@Qty=Qty,@CurrSpecificationCode=sr.SpecificationCode 
                FROM dbo.Lot 
                left join Specification s on  Lot.SpecificationId=s.SpecificationId
                left join SpecificationRoot sr ON sr.SpecificationRootId=s.SpecificationRootId
                WHERE LotSN=@LotSN
                -- IF ISNULL(@SpecificationId,'') IN ('SPE10000028J','SPE10000028S'
                --     ,'SPE1000002AD','SPE1000002AE'--20260116新增活性、水性灌墨 mwj
                -- )  --灌墨规程
                IF ISNULL(@CurrSpecificationCode,'') IN ('FSGM','UVGM','HXGM','SXGM')
				BEGIN 
					EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
														@TxnCode = 'DC',                      -- varchar(10)
														@I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
														@I_OrBitUserId = @I_OrBitUserId,                -- char(12)
														@I_ResourceId = @I_ResourceId,                 -- char(12)
														@LotId = @LotId,                        -- char(12)
														@MOId = @MOId,                         -- char(12)
														@MOItemId =@AssyMOItemId,                     -- char(12)
														@ProductId = @MOProductId,                    -- char(12)
														@WorkcenterId = @WorkCenterId,                 -- char(12)
														@SpecificationId =@SpecificationId,              -- char(12)
														@WorkflowStepId = @WorkflowStepId               -- char(12)			
				---------------------------------------------------------------------------------------------------------------------------------		
					EXEC dbo.SysGetObjectPKId @ObjectId = 'LoadingItemLotMoveId',      -- char(12)
											@ObjectName = N'LoadingItemLotMove',   -- nvarchar(100)
											@PKID = @LoadingItemLotMoveId OUTPUT -- char(12)
					INSERT dbo.LoadingItemLotMove
					(
						LoadingItemLotMoveId,
						LoadingItemLotId,
						DataChainId,
						LotId,
						LotSN,
						InQty,
						OutQty,
						MOId,
						MOItemId,
						MOItemTaskId,
						ProductId,
						WorkflowId,
						WorkflowStepId,
						SpecificationId,
						Operator,
						WorkcenterId,
						EquipmentId,
						ResourceId,
						UserId,
						CreateDate
					)
					VALUES
					(   @LoadingItemLotMoveId,     -- LoadingItemLotMoveId - IDType
						@LoadingItemLotId,     -- LoadingItemLotId - IDType
						@DataChainId,     -- DataChainId - IDType
						@LotId,     -- LotId - IDType
						@LotSN,     -- LotSN - LotSN
						@Qty,     -- InQty - SysNumberType
						@InputNumber,     -- OutQty - SysNumberType
						@MOId,     -- MOId - IDType
						@AssyMOItemId,     -- MOItemId - IDType
						@MOItemTaskId,     -- MOItemTaskId - IDType
						@MOProductId,     -- ProductId - IDType
						@WorkflowId,     -- WorkflowId - IDType
						@WorkflowStepId,     -- WorkflowStepId - IDType
						@SpecificationId,     -- SpecificationId - IDType
						@I_OrBitUserName,      -- Operator - nvarchar(50)
						@WorkCenterId,     -- WorkcenterId - IDType
						NULL,     -- EquipmentId - IDType
						@I_ResourceId,     -- ResourceId - IDType
						@I_OrBitUserId,     -- UserId - IDType
						GETDATE() -- CreateDate - datetime
						)

					EXEC dbo.TxnBase_LotMove @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
												@I_PlugInCommand = @I_PlugInCommand  ,                    -- varchar(5)
												@I_OrBitUserId = @I_OrBitUserId,                        -- char(12)
												@I_ResourceId = @I_ResourceId,                         -- char(12)
												@LotSN = @LotSN,                                -- varchar(40)
												@LotInDate = '2021-08-23 08:47:42',         -- datetime
												@ShiftId = '',                              -- char(12)
												@UserComment = N''                          -- nvarchar(1000)			    
				END

				SELECT @WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@SpecificationId=SpecificationId,@LotId=LotId FROM dbo.Lot WHERE LotSN=@LotSN
				EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
													@TxnCode = 'DC',                      -- varchar(10)
													@I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
													@I_OrBitUserId = @I_OrBitUserId,                -- char(12)
													@I_ResourceId = @I_ResourceId,                 -- char(12)
													@LotId = @LotId,                        -- char(12)
													@MOId = @MOId,                         -- char(12)
													@MOItemId =@AssyMOItemId,                     -- char(12)
													@ProductId = @MOProductId,                    -- char(12)
													@WorkcenterId = @WorkCenterId,                 -- char(12)
													@SpecificationId =@SpecificationId,              -- char(12)
													@WorkflowStepId = @WorkflowStepId               -- char(12)			
		    
		
				IF EXISTS(SELECT 1 FROM dbo.MoCraftPath WHERE MoId=@MOId AND WorkstageNO='10')
				BEGIN
				EXEC dbo.MOProductionOrder 
										   @I_ReturnMessage = @I_ReturnMessage1 OUTPUT,            -- nvarchar(max)
										   @I_ExceptionFieldName = @I_ExceptionFieldName1 OUTPUT,  -- nvarchar(100)
										   @MOID = @MOId,                                           -- char(12)
										   @Line = '10',                                 -- nvarchar(30)
										   @Qty = @Qty                                            -- nvarchar(30)
				END

				-- 【释放】已扣数在流程结束（自动完工/批次下线）生成领料单后按 MOId 统一结算(@DeductedRows)，
				--       此处不再整单释放；原按 MOId/MOItemId 提前置 IsOccupyAllocatedQty=0 的写法已移除

				SELECT @MOItemTaskName=MOItemTaskName FROM dbo.MOItemTask WHERE @MOItemTaskId= MOItemTaskId 
				SELECT 
						'' AS Command,
					--	'' AS EmployeeNo,
					--	'' AS ProductionLine,
						'' AS SpecificationCode,
						'' AS MOName , 
						'' AS InputScan,
						'0' AS InputNumber,
						'' AS FMOQty,
						'' AS MOProduct,			
						'' AS MOItemTaskName,
						'' AS LoadingItemLotId,
						'' AS LoadingItemLotRecordId,
						'' AS MQtyRequired ,
						'' AS MActualQty,
						''  AS CurrMaterial,
						'' AS SrcLotSnList
				SET @I_ExceptionFieldName = 'InputScan';	
				SET @I_ReturnMessage = 'ServerMessage: 工单任务【'+ISNULL(@MOItemTaskName,'')+'】墨水已全部使用，已自动为您完成生产灌墨！' + @Enter +'报工信息：' +ISNULL(@I_ReturnMessage1,'');
				RETURN 0;
			END

			SELECT  '0' AS InputNumber,
					ISNULL(@MQtyRequired,0) AS MQtyRequired ,
					ISNULL(@CurrMActualQty,0.001) AS MActualQty,
					'' AS InputScan,
					'MLotNumberScan' AS Command,
					ISNULL(@CurrMaterial,'') + ' '+ ISNULL(@CurrProductDescription,'')  AS CurrMaterial,
					ISNULL(@LoadingItemLotRecordId,'') AS LoadingItemLotRecordId
			SET @I_ExceptionFieldName = 'InputScan';	
			SET @I_ReturnMessage = 'ServerMessage:墨水【' + @InputScan + '】已自动扣减数量【'+CAST(@InputNumber AS NVARCHAR(50))+'】' +',请继续扫描' +@Enter 
			--/************************************************自动确认数量
			--SET @I_ExceptionFieldName = 'InputNumber';
        --    SELECT  CAST(ISNULL(@InputNumber,'0') AS NVARCHAR(50)) AS InputNumber,
			     --   ISNULL(@MQtyRequired,0) AS MQtyRequired ,
				    --ISNULL(@MActualQty,0) AS MActualQty,
			     --   'MLotSNScan' AS Command,
				    --ISNULL(@CurrMaterial,'') + ' '+ ISNULL(@CurrProductDescription,'') AS CurrMaterial
        --    SET @I_ReturnMessage = 'ServerMessage:物料【' + @InputScan + '】已扫描，请输入墨水使用数量【'+CAST(@InputNumber AS NVARCHAR(50))+'】'  +@Enter 
            RETURN 0;
		END
		ELSE
		BEGIN
			SELECT '' InputScan ,'0' InputNumber,'' Command
			SET @I_ExceptionFieldName = 'InputScan';
			SET @I_ReturnMessage =  'ServerMessage:墨水物料批次【' + @InputScan + '】不存在，请重新扫描！' + @Enter;
			RETURN -1
		END
    END;


    IF @I_Sender = 'InputNumberDefocus'
    BEGIN
        SET @I_ExceptionFieldName = 'InputScan';

		-- 【废弃】人工输入数量分支已停用：数量统一在扫码时按剩余理货数量自动计算
		-- 仅拦截人工确认数量的指令，批次下线(CMDLOTMOVE)等其它指令保持原逻辑
		IF @Command IN ('MLotSNScan','MLotNumberScan')
		BEGIN
			SET @I_ReturnMessage = 'ServerMessage:已取消人工输入数量，请重新扫描墨水批次，系统将自动按剩余理货数量扣减！' + @Enter;
			RETURN -1
		END

		IF @Command ='MLotSNScan'
		BEGIN
			IF EXISTS (SELECT 1 FROM dbo.WW_RMInventory
				WHERE LotSN=@InputScan AND LotStatus='1' AND IsStorage=1 AND Qty>0)
			BEGIN
				 SELECT @WWId=WWId,@MLotId=LotId,@MLotSN=LotSN,@MProductId=ProductId,
						@DateCode=ProductionLotNO,@LotAvailableQty=Qty
				 FROM dbo.WW_RMInventory
				 WHERE LotSN=@InputScan AND LotStatus='1' AND IsStorage=1 AND Qty>0

				-- 【保留】原按领料单查询数量逻辑，改由实时库存数量计算，不再执行
				/*
				SELECT @BeginQty=SUM(PickingListItemLot.Qty) FROM dbo.PickingListItemLot 
			    INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListItemId = PickingListItemLot.PickingListItemId 
				WHERE MOId =@MOId AND (OrgLotSN=@InputScan OR LotSN=@InputScan)
				*/

				IF NOT EXISTS (SELECT 1 FROM dbo.MOItem WHERE  MOId=@MOId AND ProductId=@MProductId)
				BEGIN
					SELECT '' InputScan ,'0' InputNumber,'' Command
					SET @I_ExceptionFieldName = 'InputScan';
					SET @I_ReturnMessage =  'ServerMessage:批次【' + @InputScan + '】不是工单【'+ @MOName +'】物料，请更换批次扫描！'+@MProductId+' 1'+@MOId ++'2 '+ @Enter;
					RETURN -1
				END

				IF NOT EXISTS (SELECT 1 FROM dbo.MOItem
				              INNER JOIN dbo.Product ON Product.ProductId = MOItem.ProductId 
							   WHERE  MOId=@MOId AND MOItem.ProductId=@MProductId AND ProductClassify='2')
				BEGIN
				    SELECT
                    @MOProductId = ProductId
                    FROM dbo.MO
                    WHERE MOName = @MOId;
    
                    SELECT @MOProductName=ProductName,@MOProductDescription=ProductDescription FROM dbo.Product
                    INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
                    WHERE ProductId=@MOProductId
    
                    SELECT @AssyMOItemId = MOItemId,@FMOQty=ItemQtyRequired
                    FROM dbo.MOItem
                    WHERE @MOId = MOId
                    AND @MOProductId = MOItem.ProductId;
    
                    SELECT TOP 1
                    @MOItemTaskId = MOItemTaskId
                    FROM dbo.MOItemTask
                    WHERE MOItemId = @AssyMOItemId
                    AND TaskStatus = 0;
                    SELECT TOP 1 @LotSN=LotSN FROM dbo.MOItemLot MOI
                    INNER JOIN dbo.MOItemTask MT ON MT.MOItemTaskId = MOI.MOItemTaskId
                    WHERE @MOItemTaskId=MOI.MOItemTaskId AND MT.TaskStatus = 0
    
                    select @WorkflowId = WorkflowId,@LotId = LotId from Lot where LotSN = @LotSN
                     
                    IF ISNULL(@WorkflowId,'') <> 'WKF1000000ZD'
                    BEGIN
                        SELECT '' InputScan ,'0' InputNumber,'' Command
                        SET @I_ExceptionFieldName = 'InputScan';
                        SET @I_ReturnMessage =  'ServerMessage:批次【' + @InputScan + '】不是半成品墨水物料，请更换批次扫描！'+@MProductId+' 1'+@MOId ++'2 '+ @Enter;
                        RETURN -1
                    END
				END

				SELECT @IssueMOItemId=MOItemId FROM dbo.MOItem WHERE  MOId=@MOId AND ProductId=@MProductId 

				IF EXISTS (SELECT 1 FROM dbo.LoadingItemLotRecord 
				INNER JOIN dbo.LoadingItemLotDetail ON LoadingItemLotDetail.LoadingItemLotDetailId = LoadingItemLotRecord.LoadingItemLotDetailId 
				INNER JOIN dbo.LoadingItemLot ON LoadingItemLot.LoadingItemLotId = LoadingItemLotDetail.LoadingItemLotId
				 WHERE LoadingItemLotRecord.LotSN=@InputScan AND MOItemTaskId= @MOItemTaskId AND LoadingItemLot.LoadingItemLotId=@LoadingItemLotId)
				BEGIN
					SELECT '' InputScan ,'0' InputNumber,'' Command
					SET @I_ExceptionFieldName = 'InputScan';
					SET @I_ReturnMessage =  'ServerMessage:墨水批次【' + @InputScan + '】已经在工单任务生产中，请更换批次扫描！' + @Enter;
					RETURN -1
				END

				-- 【保留】原已领料校验，改由有效预分配记录校验替代，不再执行
				/*
				IF NOT EXISTS (SELECT 1 FROM dbo.PickingListItemLot 
						  INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListItemId = PickingListItemLot.PickingListItemId 
						  WHERE MOId =@MOId AND LotSN=@InputScan 
						  UNION SELECT 1 FROM dbo.PickingListItemLot 
			              INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListItemId = PickingListItemLot.PickingListItemId 
					      WHERE MOId =@MOId AND OrgLotSN=@InputScan)
				BEGIN
					SELECT '' InputScan ,'0' InputNumber,'' Command 
					SET @I_ExceptionFieldName = 'InputScan';
					SET @I_ReturnMessage =  'ServerMessage:墨水批次【' + @InputScan + '】未进行工单【'+@MOName+ '】领料，请更换批次扫描！' + @Enter;
					RETURN -1
				END
				*/

				-- 【校验】数量确认时重新校验扫描批次仍属于当前工单有效预分配
				IF NOT EXISTS
				(
					SELECT 1
					FROM dbo.MOSemiFinishedLotAllocation
					WHERE MOId=@MOId AND MOItemId=@IssueMOItemId AND ProductId=@MProductId
						AND LotSN=@InputScan AND DeleteFlag='0' AND IsOccupyAllocatedQty=1 AND ConfirmStatus = '1'
				)
				BEGIN
					SELECT '' InputScan,'0' InputNumber,'' Command
					SET @I_ExceptionFieldName='InputScan'
					SET @I_ReturnMessage='ServerMessage:[墨水批次]['+@InputScan+']未指定给工单['+@MOName+']，请更换批次扫描！'+@Enter
					RETURN -1
				END
		
				SELECT @CurrMaterial=ProductName ,@CurrProductDescription=ProductDescription
				FROM dbo.Product INNER JOIN  dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
				WHERE ProductId =@MProductId

				SELECT  @TaskPlannedQty=TaskPlannedQty FROM dbo.MOItemTask WHERE MOItemTaskId=@MOItemTaskId


				SELECT @BaseQty=ItemQtyRequired  / ISNULL(@FMOQty,1.0),
					@BomItemQty=ItemQtyRequired,
					@MQtyRequired=ItemQtyRequired * ISNULL(@TaskPlannedQty,1.0) / ISNULL(@FMOQty,1.0)  
				FROM dbo.MOItem WHERE MOItemId=@IssueMOItemId

				SELECT @MActualQty=SUM(ISNULL(ActualQty,0)) FROM dbo.LoadingItemLotDetail WHERE  @LoadingItemLotId=LoadingItemLotId AND MOItemId =@IssueMOItemId
			
				IF ISNULL(@MActualQty,0)=0
				BEGIN
					SET @MActualQty=0
				END

				IF ISNUMERIC(@InputNumber)=1 
				BEGIN
				    SET @UsedQty=CAST(@InputNumber AS DECIMAL(18,4)) 
				END
				ELSE
				BEGIN
					SET @I_ReturnMessage = 'ServerMessage:输入数字【'+CAST(@InputNumber AS NVARCHAR(50))+'】有非法字符' +',请重新输入' +@Enter 
                    SET @I_ExceptionFieldName = 'InputNumber';					
					RETURN -1;
				END

				-- 【校验】确认数量不得超过当前库存余额或工单物料剩余需求
				SET @MRemainQty=ISNULL(@MQtyRequired,0)-ISNULL(@MActualQty,0)
				IF @UsedQty<=0 OR @UsedQty>@LotAvailableQty OR @UsedQty>@MRemainQty
				BEGIN
					SET @I_ReturnMessage='ServerMessage:[输入数量]['+CAST(@InputNumber AS NVARCHAR(50))+']超过墨水批次['+@InputScan+']可用库存数量或工单剩余需求，请重新输入'+@Enter
					SET @I_ExceptionFieldName='InputNumber'
					RETURN -1
				END

				-- 【事务】数量确认时同步完成上料明细、库存扣减、批次跟踪和数据链记录
				BEGIN TRY
					BEGIN TRANSACTION InkLoading
				SELECT @SpecificationId= WorkSpecificationId FROM dbo.MOItemTask WHERE MOItemTaskId=@MOItemTaskId

				SELECT @LoadingItemLotDetailId=LoadingItemLotDetailId FROM dbo.LoadingItemLotDetail WHERE LoadingItemLotId=@LoadingItemLotId AND MOItemId=@IssueMOItemId

				IF ISNULL(@LoadingItemLotDetailId,'')=''
				BEGIN
					EXEC dbo.SysGetObjectPKId @ObjectId = 'LoadingItemLotDetailId',      -- char(12)
											  @ObjectName = N'LoadingItemLotDetail',   -- nvarchar(100)
											  @PKID = @LoadingItemLotDetailId OUTPUT -- char(12)
			
					INSERT dbo.LoadingItemLotDetail
					(
						LoadingItemLotDetailId,
						LoadingItemLotId,
						MOItemId,
						ItemQtyRequired,
						ActualQty,
						LastMakingDate,
						CreateDate
					)
					VALUES
					(   @LoadingItemLotDetailId,        -- LoadingItemLotDetailId - char(12)
						@LoadingItemLotId,        -- LoadingItemLotId - char(12)
						@IssueMOItemId,        -- MOItemId - char(12)
						@MQtyRequired,      -- ItemQtyRequired - decimal(18, 8)
						@UsedQty,      -- ActualQty - decimal(18, 5)
						GETDATE(), -- LastMakingDate - datetime
						GETDATE()  -- CreateDate - datetime
						)
				END
				ELSE
				BEGIN
					UPDATE LoadingItemLotDetail SET ActualQty=ISNULL(@MActualQty,0)+ISNULL(@UsedQty,0) WHERE LoadingItemLotDetailId=@LoadingItemLotDetailId
				END
				SELECT  @CurrMActualQty= ActualQty FROM LoadingItemLotDetail WHERE LoadingItemLotDetailId=@LoadingItemLotDetailId		

				-- 【校验与扣减】按库存主键再次校验余额后扣减本次实际使用数量
				SELECT @InventoryQtyBefore=Qty
				FROM dbo.WW_RMInventory
				WHERE WWId=@WWId AND LotStatus='1' AND IsStorage=1

				IF ISNULL(@InventoryQtyBefore,0)<@UsedQty
				BEGIN
					ROLLBACK TRANSACTION InkLoading
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:墨水批次库存不足，无法完成上料'+@Enter
				RETURN -1
				END

				UPDATE dbo.WW_RMInventory
				SET Qty=Qty-@UsedQty,ModifyDate=GETDATE()
				WHERE WWId=@WWId AND LotStatus='1' AND IsStorage=1 AND Qty>=@UsedQty

				IF @@ROWCOUNT<>1
				BEGIN
					ROLLBACK TRANSACTION InkLoading
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:墨水批次库存不足，无法完成上料'+@Enter
				RETURN -1
				END

				-- 【追溯】记录本次上料引起的批次库存变更
				SET @Remark='当前批次数量['+CAST(@InventoryQtyBefore AS NVARCHAR(19))+']，工单['+@MOName+']投料使用数量['+CAST(@UsedQty AS NVARCHAR(19))+']，剩余数量['+CAST((@InventoryQtyBefore-@UsedQty) AS NVARCHAR(19))+']'
				EXEC dbo.TxnBase_MLotTrack
					@I_OrBitUserId=@I_OrBitUserId,
					@I_PlugInCommand=@I_PlugInCommand,
					@I_ResourceId=@I_ResourceId,
					@LotSN=@MLotSN,
					@LotQty=@UsedQty,
					@TxnCode='M-生产上料',
					@OrderName=@MOName,
					@Remark=@Remark

				EXEC dbo.SysGetObjectPKId @ObjectId = 'LoadingItemLotRecordId',      -- char(12)
										  @ObjectName = N'LoadingItemLotRecord',   -- nvarchar(100)
										  @PKID = @LoadingItemLotRecordId OUTPUT -- char(12)
				INSERT dbo.LoadingItemLotRecord
				(
					LoadingItemLotRecordId,
					LoadingItemLotDetailId,
					LotSN,
					Qty,
					CreateUserId,
					CreateDate
				)
				VALUES
				(   @LoadingItemLotRecordId,       -- LoadingItemLotRecordId - char(12)
					@LoadingItemLotDetailId,       -- LoadingItemLotDetailId - char(12)
					@MLotSN,      -- LotSN - nvarchar(50)
					@UsedQty,     -- Qty - decimal(18, 8)
					@I_OrBitUserId,       -- CreateUserId - char(12)
					GETDATE() -- CreateDate - datetime
					)
	        
				SELECT  @WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@LotId=LotId FROM dbo.Lot WHERE LotSN=@LotSN
				EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
												   @TxnCode = 'DC',                      -- varchar(10)
												   @I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
												   @I_OrBitUserId = @I_OrBitUserId,                -- char(12)
												   @I_ResourceId = @I_ResourceId,                 -- char(12)
												   @LotId = @LotId,                        -- char(12)
												   @MOId = @MOId,                         -- char(12)
												   @MOItemId =@AssyMOItemId,                     -- char(12)
												   @ProductId = @MOProductId,                    -- char(12)
												   @WorkcenterId = @WorkCenterId,                 -- char(12)
												   @SpecificationId =@SpecificationId,              -- char(12)
												   @WorkflowStepId = @WorkflowStepId               -- char(12)


				EXEC dbo.SysGetObjectPKId @ObjectId = 'DataChainAssyIssueId',      -- char(12)
										  @ObjectName = N'DataChainAssyIssue',   -- nvarchar(100)
										  @PKID = @DataChainAssyIssueId OUTPUT -- char(12)
				INSERT dbo.DataChainAssyIssue
				(
					DataChainAssyIssueId,
					AssyDataChainId,
					IssueDataChainId,
					AssyIssueType,
					AssyProductId,
					AssyLotSN,
					AssyLotId,
					AssyMOId,
					AssyMOItemId,
					IssueProductId,
					IssueLotSN,
					IssueLotId,
					IssueMOId,
					IssueMOItemId,
					IssueQty,
					BaseQty,
					IssueDate,
					DateCode,
					LotBatch,
					ItemLocation,
					VendorId,
					ResourceId,
					ShiftId,
					UserId,
					Operator,
					Side,
					SpecificationId,
					WorkflowStepId,
					IsReplaceProduct,
					IsReplacePart,
					CreateUserId,
					CreateDate
				)
				VALUES
				(   @DataChainAssyIssueId,        -- DataChainAssyIssueId - char(12)
					@DataChainId,        -- AssyDataChainId - char(12)
					'',        -- IssueDataChainId - char(12)
					0,        -- AssyIssueType - char(1)
					@MOProductId,        -- AssyProductId - char(12)
					@LotSN,       -- AssyLotSN - nvarchar(50)
					@LotId,        -- AssyLotId - char(12)
					@MOId,        -- AssyMOId - char(12)
					@AssyMOItemId,        -- AssyMOItemId - char(12)
					@MProductId,        -- IssueProductId - char(12)
					@MLotSN,       -- IssueLotSN - nvarchar(50)
					@MLotId,        -- IssueLotId - char(12)
					@MOId,        -- IssueMOId - char(12)
					@IssueMOItemId,        -- IssueMOItemId - char(12)
					@UsedQty,      -- IssueQty - decimal(18, 3)
					@BomItemQty,      -- BaseQty - decimal(18, 3)
					GETDATE(), -- IssueDate - datetime
					@DateCode,       -- DateCode - nvarchar(50)
					@DateCode,       -- LotBatch - nvarchar(50)
					N'',       -- ItemLocation - nvarchar(max)
					'',        -- VendorId - char(12)
					@I_ResourceId,        -- ResourceId - char(12)
					'',        -- ShiftId - char(12)
					@I_OrBitUserId,        -- UserId - char(12)
					@I_OrBitUserName ,        -- Operator - char(12)
					'',        -- Side - char(10)
					@SpecificationId,        -- SpecificationId - char(12)
					@WorkflowStepId,        -- WorkflowStepId - char(12)
					0,      -- IsReplaceProduct - bit
					0,      -- IsReplacePart - bit
					@I_OrBitUserId,        -- CreateUserId - char(12)
					GETDATE()  -- CreateDate - datetime
					)

				COMMIT TRANSACTION InkLoading
				END TRY
				BEGIN CATCH
					IF @@TRANCOUNT>0
						ROLLBACK TRANSACTION InkLoading

					SET @I_ExceptionFieldName='InputNumber'
					SET @I_ReturnMessage='ServerMessage:墨水批次【'+@InputScan+'】上料写入失败：'+ERROR_MESSAGE()+@Enter
					RETURN -1
				END CATCH

                --墨水批次扫完自动完工移送（检查所有半成品物料是否都已完成）
                -- IF @MQtyRequired<=ISNULL(@MActualQty,0)+ISNULL(@UsedQty,0)
                IF NOT EXISTS (
                    SELECT 1
                    FROM dbo.MOItem mi
                    INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
                    WHERE mi.MOId = @MOId
                        AND ISNULL(mi.DeleteFlag, '') = '0'
                        AND mi.LineSequence <> '000'
                        AND p.ProductClassify = '2'
                        AND ISNULL(mi.ItemQtyRequired, 0) > ISNULL((
                            SELECT SUM(ISNULL(lild.ActualQty, 0))
                            FROM dbo.LoadingItemLotDetail lild
                            WHERE lild.LoadingItemLotId = @LoadingItemLotId
                                AND lild.MOItemId = mi.MOItemId
                        ), 0)
                )
                BEGIN
                    INSERT @MSntemp
                    (
                        LotSn,
                        Qty
                    )
                    SELECT LoadingItemLotRecord.LotSN,Qty  FROM  dbo.LoadingItemLotRecord 
                    LEFT JOIN dbo.LoadingItemLotDetail ON LoadingItemLotDetail.LoadingItemLotDetailId = LoadingItemLotRecord.LoadingItemLotDetailId
                    LEFT JOIN dbo.LoadingItemLot ON LoadingItemLot.LoadingItemLotId = LoadingItemLotDetail.LoadingItemLotId
                    WHERE LoadingItemLot.LoadingItemLotId =@LoadingItemLotId

            
                    SELECT @MaxCnt=COUNT(*),@Counter=MIN(Id) FROM @MSntemp
                    WHILE @Counter <= @MaxCnt AND 0 < @MaxCnt
                    BEGIN 
                        SELECT @tempLotSn=LotSn,@tempQty=Qty FROM @MSntemp WHERE Id=@Counter
                        --UPDATE dbo.WW_RMInventory SET Qty=  CASE WHEN  @tempQty<Qty THEN Qty-@tempQty ELSE 0 END WHERE LotSN=@tempLotSn

                        SET @Counter=@Counter+1
                    END
        
                    -- 【领料】自动完工前为当前上料会话的未领料记录生成生产领料单
                    EXEC @RESULT=dbo.PDA_ProductionMakingSubmit
                        @I_Sender='MakingComplete',
                        @I_ReturnMessage=@I_ReturnMessage OUTPUT,
                        @I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
                        @I_PlugInCommand=@I_PlugInCommand,
                        @I_OrBitUserId=@I_OrBitUserId,
                        @I_OrBitUserName=@I_OrBitUserName,
                        @I_ResourceId=@I_ResourceId,
                        @I_ResourceName=@I_ResourceName,
                        @LoadingItemLotId=@LoadingItemLotId
                    IF @RESULT<>0
                        RETURN @RESULT


                    ---------------------------------------------------------------------------------------------
                    SELECT  @WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@SpecificationId=SpecificationId,@LotId=LotId,@Qty=Qty FROM dbo.Lot WHERE LotSN=@LotSN
                    IF ISNULL(@SpecificationId,'') = 'SPE1000001B6'  --批次启动
                    BEGIN 
                        EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
                                                            @TxnCode = 'DC',                      -- varchar(10)
                                                            @I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
                                                            @I_OrBitUserId = @I_OrBitUserId,                -- char(12)
                                                            @I_ResourceId = @I_ResourceId,                 -- char(12)
                                                            @LotId = @LotId,                        -- char(12)
                                                            @MOId = @MOId,                         -- char(12)
                                                            @MOItemId =@AssyMOItemId,                     -- char(12)
                                                            @ProductId = @MOProductId,                    -- char(12)
                                                            @WorkcenterId = @WorkCenterId,                 -- char(12)
                                                            @SpecificationId =@SpecificationId,              -- char(12)
                                                            @WorkflowStepId = @WorkflowStepId               -- char(12)		
                        EXEC dbo.TxnBase_LotMove @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
                                                    @I_PlugInCommand = @I_PlugInCommand  ,                    -- varchar(5)
                                                    @I_OrBitUserId = @I_OrBitUserId,                        -- char(12)
                                                    @I_ResourceId = @I_ResourceId,                         -- char(12)
                                                    @LotSN = @LotSN,                                -- varchar(40)
                                                    @LotInDate = '2021-08-23 08:47:42',         -- datetime
                                                    @ShiftId = '',                              -- char(12)
                                                    @UserComment = N''                          -- nvarchar(1000)			    
                    END
                
                    SET @CurrSpecificationCode=''
                    SELECT  @WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@SpecificationId=Lot.SpecificationId,@LotId=LotId,@Qty=Qty,@CurrSpecificationCode=sr.SpecificationCode 
                    FROM dbo.Lot 
                    left join Specification s on  Lot.SpecificationId=s.SpecificationId
                    left join SpecificationRoot sr ON sr.SpecificationRootId=s.SpecificationRootId
                    WHERE LotSN=@LotSN
                    -- IF ISNULL(@SpecificationId,'') IN ('SPE10000028J','SPE10000028S'
                    --     ,'SPE1000002AD','SPE1000002AE'--20260116新增活性、水性灌墨 mwj
                    -- )  --灌墨规程
                    IF ISNULL(@CurrSpecificationCode,'') IN ('FSGM','UVGM','HXGM','SXGM')
                    BEGIN 
                        EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
                                                            @TxnCode = 'DC',                      -- varchar(10)
                                                            @I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
                                                            @I_OrBitUserId = @I_OrBitUserId,                -- char(12)
                                                            @I_ResourceId = @I_ResourceId,                 -- char(12)
                                                            @LotId = @LotId,                        -- char(12)
                                                            @MOId = @MOId,                         -- char(12)
                                                            @MOItemId =@AssyMOItemId,                     -- char(12)
                                                            @ProductId = @MOProductId,                    -- char(12)
                                                            @WorkcenterId = @WorkCenterId,                 -- char(12)
                                                            @SpecificationId =@SpecificationId,              -- char(12)
                                                            @WorkflowStepId = @WorkflowStepId               -- char(12)			
                    ---------------------------------------------------------------------------------------------------------------------------------		
                        EXEC dbo.SysGetObjectPKId @ObjectId = 'LoadingItemLotMoveId',      -- char(12)
                                                @ObjectName = N'LoadingItemLotMove',   -- nvarchar(100)
                                                @PKID = @LoadingItemLotMoveId OUTPUT -- char(12)
                        INSERT dbo.LoadingItemLotMove
                        (
                            LoadingItemLotMoveId,
                            LoadingItemLotId,
                            DataChainId,
                            LotId,
                            LotSN,
                            InQty,
                            OutQty,
                            MOId,
                            MOItemId,
                            MOItemTaskId,
                            ProductId,
                            WorkflowId,
                            WorkflowStepId,
                            SpecificationId,
                            Operator,
                            WorkcenterId,
                            EquipmentId,
                            ResourceId,
                            UserId,
                            CreateDate
                        )
                        VALUES
                        (   @LoadingItemLotMoveId,     -- LoadingItemLotMoveId - IDType
                            @LoadingItemLotId,     -- LoadingItemLotId - IDType
                            @DataChainId,     -- DataChainId - IDType
                            @LotId,     -- LotId - IDType
                            @LotSN,     -- LotSN - LotSN
                            @Qty,     -- InQty - SysNumberType
                            @InputNumber,     -- OutQty - SysNumberType
                            @MOId,     -- MOId - IDType
                            @AssyMOItemId,     -- MOItemId - IDType
                            @MOItemTaskId,     -- MOItemTaskId - IDType
                            @MOProductId,     -- ProductId - IDType
                            @WorkflowId,     -- WorkflowId - IDType
                            @WorkflowStepId,     -- WorkflowStepId - IDType
                            @SpecificationId,     -- SpecificationId - IDType
                            @I_OrBitUserName,      -- Operator - nvarchar(50)
                            @WorkCenterId,     -- WorkcenterId - IDType
                            NULL,     -- EquipmentId - IDType
                            @I_ResourceId,     -- ResourceId - IDType
                            @I_OrBitUserId,     -- UserId - IDType
                            GETDATE() -- CreateDate - datetime
                            )

                        EXEC dbo.TxnBase_LotMove @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
                                                    @I_PlugInCommand = @I_PlugInCommand  ,                    -- varchar(5)
                                                    @I_OrBitUserId = @I_OrBitUserId,                        -- char(12)
                                                    @I_ResourceId = @I_ResourceId,                         -- char(12)
                                                    @LotSN = @LotSN,                                -- varchar(40)
                                                    @LotInDate = '2021-08-23 08:47:42',         -- datetime
                                                    @ShiftId = '',                              -- char(12)
                                                    @UserComment = N''                          -- nvarchar(1000)			    
                    END

                    SELECT @WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@SpecificationId=SpecificationId,@LotId=LotId FROM dbo.Lot WHERE LotSN=@LotSN
                    EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
                                                        @TxnCode = 'DC',                      -- varchar(10)
                                                        @I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
                                                        @I_OrBitUserId = @I_OrBitUserId,                -- char(12)
                                                        @I_ResourceId = @I_ResourceId,                 -- char(12)
                                                        @LotId = @LotId,                        -- char(12)
                                                        @MOId = @MOId,                         -- char(12)
                                                        @MOItemId =@AssyMOItemId,                     -- char(12)
                                                        @ProductId = @MOProductId,                    -- char(12)
                                                        @WorkcenterId = @WorkCenterId,                 -- char(12)
                                                        @SpecificationId =@SpecificationId,              -- char(12)
                                                        @WorkflowStepId = @WorkflowStepId               -- char(12)			
                
            
                    IF EXISTS(SELECT 1 FROM dbo.MoCraftPath WHERE MoId=@MOId AND WorkstageNO='10')
                    BEGIN
                    EXEC dbo.MOProductionOrder 
                                            @I_ReturnMessage = @I_ReturnMessage1 OUTPUT,            -- nvarchar(max)
                                            @I_ExceptionFieldName = @I_ExceptionFieldName1 OUTPUT,  -- nvarchar(100)
                                            @MOID = @MOId,                                           -- char(12)
                                            @Line = '10',                                 -- nvarchar(30)
                                            @Qty = @Qty                                            -- nvarchar(30)
                    END

                    -- 【释放】已扣数在流程结束生成领料单后统一结算，此处不再整单释放（本分支已废弃，不参与执行）

                    SELECT @MOItemTaskName=MOItemTaskName FROM dbo.MOItemTask WHERE @MOItemTaskId= MOItemTaskId 
                    SELECT 
                            '' AS Command,
                        --	'' AS EmployeeNo,
                        --	'' AS ProductionLine,
                            '' AS SpecificationCode,
                            '' AS MOName , 
                            '' AS InputScan,
                            '0' AS InputNumber,
                            '' AS FMOQty,
                            '' AS MOProduct,			
                            '' AS MOItemTaskName,
                            '' AS LoadingItemLotId,
                            '' AS LoadingItemLotRecordId,
                            '' AS MQtyRequired ,
                            '' AS MActualQty,
                            ''  AS CurrMaterial,
                            '' AS SrcLotSnList
                    SET @I_ExceptionFieldName = 'InputScan';	
                    SET @I_ReturnMessage = 'ServerMessage: 工单任务【'+ISNULL(@MOItemTaskName,'')+'】墨水已全部使用，已自动为您完成生产灌墨！' + @Enter +'报工信息：' +ISNULL(@I_ReturnMessage1,'');
                    RETURN 0;
                END

				SELECT  '0' AS InputNumber,
						ISNULL(@MQtyRequired,0) AS MQtyRequired ,
						ISNULL(@CurrMActualQty,0.001) AS MActualQty,
						'' AS InputScan,
						'MLotNumberScan' AS Command,
						ISNULL(@CurrMaterial,'') + ' '+ ISNULL(@CurrProductDescription,'')  AS CurrMaterial,
						ISNULL(@LoadingItemLotRecordId,'') AS LoadingItemLotRecordId
			    SET @I_ExceptionFieldName = 'InputScan';	
				SET @I_ReturnMessage = 'ServerMessage:墨水【' + @InputScan + '】使用数量已更改为【'+CAST(@InputNumber AS NVARCHAR(50))+'】' +',请继续扫描' +@Enter 
				RETURN 0;
			END

			SELECT '0' AS InputNumber,'' AS InputScan,'MLotNumberScan' AS Command
		    SET @I_ReturnMessage = 'ServerMessage: 批次【'+@MLotSN+'】不存在,请继续扫描' + @Enter;
			SET @I_ExceptionFieldName = 'InputScan';	
			RETURN 0;
		END 
		ELSE IF @Command = 'CMDLOTMOVE' --批次下线
        BEGIN
			-- 【校验】批次下线（流程结束）前校验：每个理货维度(物料+工厂+仓库+SAP批次)的已扫量必须等于理货量
			-- 说明：已扫量小于理货量说明流程未完成即结束，已扫量大于理货量说明重复扣数，
			--       均属程序/数据异常；异常时不生成领料单、不推进批次节点，直接阻断下线并提示联系IT处理；
			--       校验放在最前面，避免未通过校验时仍生成领料单或推进批次节点
			IF EXISTS (
				SELECT 1
				FROM (
					-- 【准备】按四维度汇总本工单有效理货行：理货量合计 + 最早创建时间(已扫量归属起点)
					SELECT a.MOItemId,a.ProductId,a.FactoryId,a.WorkcenterId,a.ProductionLotNO,
						   MIN(a.CreateDate) AS TallyStartDate,
						   SUM(ISNULL(a.Qty,0)) AS TallyQty
					FROM dbo.MOSemiFinishedLotAllocation a
					WHERE a.MOId=@MOId AND a.DeleteFlag='0'
						AND a.IsOccupyAllocatedQty=1 AND a.ConfirmStatus='1'
					GROUP BY a.MOItemId,a.ProductId,a.FactoryId,a.WorkcenterId,a.ProductionLotNO
				) l
				OUTER APPLY (
					-- 【准备】按四维度+归属起点汇总该维度已扫(灌墨扣减)数量
					SELECT SUM(ISNULL(LIR.Qty,0)) AS UsedQty
					FROM dbo.LoadingItemLotRecord LIR
					INNER JOIN dbo.LoadingItemLotDetail LID ON LID.LoadingItemLotDetailId=LIR.LoadingItemLotDetailId
					INNER JOIN dbo.WW_RMInventory WRI ON WRI.LotSN=LIR.LotSN
					WHERE LID.MOItemId=l.MOItemId
						AND WRI.ProductId=l.ProductId
						AND WRI.FactoryId=l.FactoryId
						AND WRI.WorkcenterId=l.WorkcenterId
						AND WRI.ProductionLotNO=l.ProductionLotNO
						AND LIR.CreateDate>=l.TallyStartDate
				) u
				WHERE ISNULL(u.UsedQty,0)<>l.TallyQty
			)
			BEGIN
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:[工单号]['+ISNULL(@MOName,'')+']理货数量与灌墨扣减数量不一致(程序异常)，系统已阻断下线，请联系IT处理！'+@Enter
				RETURN -1
			END

			INSERT @MSntemp
			(
			    LotSn,
				Qty
			)
			SELECT LoadingItemLotRecord.LotSN,Qty  FROM  dbo.LoadingItemLotRecord 
			LEFT JOIN dbo.LoadingItemLotDetail ON LoadingItemLotDetail.LoadingItemLotDetailId = LoadingItemLotRecord.LoadingItemLotDetailId
			LEFT JOIN dbo.LoadingItemLot ON LoadingItemLot.LoadingItemLotId = LoadingItemLotDetail.LoadingItemLotId
			WHERE LoadingItemLot.LoadingItemLotId =@LoadingItemLotId

			-- 【领料】手工批次下线前为当前上料会话的未领料记录生成生产领料单
			EXEC @RESULT=dbo.PDA_ProductionMakingSubmit
				@I_Sender='MakingComplete',
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
				@I_PlugInCommand=@I_PlugInCommand,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_OrBitUserName=@I_OrBitUserName,
				@I_ResourceId=@I_ResourceId,
				@I_ResourceName=@I_ResourceName,
				@LoadingItemLotId=@LoadingItemLotId
			IF @RESULT<>0
				RETURN @RESULT

			-- =============================================
			-- 【结算】领料单生成后统一结算：前置校验已保证每个维度已扫量=理货量，
			--       将本工单全部已确认理货行置为"已扣数"(IsOccupyAllocatedQty=0)，释放占用
			-- 【SAP 同步标记】已扣数属于需上报 SAP 的变更，同步置为未同步
			-- =============================================
			UPDATE a
			SET a.IsOccupyAllocatedQty=0,
				a.SAPSyncFlag='0',
				a.ModifyDate=GETDATE()
			OUTPUT inserted.MOSemiFinishedLotAllocationId INTO @DeductedRows (MOSemiFinishedLotAllocationId)
			FROM dbo.MOSemiFinishedLotAllocation a
			WHERE a.MOId=@MOId AND a.DeleteFlag='0'
				AND a.IsOccupyAllocatedQty=1 AND a.ConfirmStatus='1'

			-- 【SAP 同步 - 已扣数】暂未实现，后续补充；本操作仅将本次结算的理货记录置 SAPSyncFlag='0'（未同步）；
			-- 实现方式：流程结束后，由统一同步逻辑循环调用存在未同步记录
			--          （ConfirmStatus='1' AND SAPSyncFlag='0'）的 MO，按记录状态推导动作上报 SAP；
			--          同步成功置 SAPSyncFlag='1'，失败保持 '0' 等待下次循环补偿；
			--          @DeductedRows 为本次结算的理货记录，暂未使用，预留给同步实现后使用
			-- 接口过程：dbo.APISyncU_SemiFinishedTallyToSAP（已扣数→过账扣减/预留核销）

		
			--SELECT @MaxCnt=COUNT(*),@Counter=MIN(Id) FROM @MSntemp
			--WHILE @Counter <= @MaxCnt AND 0 < @MaxCnt
			--BEGIN 
			--    SELECT @tempLotSn=LotSn,@tempQty=Qty FROM @MSntemp WHERE Id=@Counter
			--	--UPDATE dbo.WW_RMInventory SET Qty=  CASE WHEN  @tempQty<Qty THEN Qty-@tempQty ELSE 0 END WHERE LotSN=@tempLotSn

			--	SET @Counter=@Counter+1
			--END
	

			---------------------------------------------------------------------------------------------
			SELECT  @WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@SpecificationId=SpecificationId,@LotId=LotId,@Qty=Qty FROM dbo.Lot WHERE LotSN=@LotSN
			IF ISNULL(@SpecificationId,'') = 'SPE1000001B6'  --批次启动
			BEGIN 
				EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
													@TxnCode = 'DC',                      -- varchar(10)
													@I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
													@I_OrBitUserId = @I_OrBitUserId,                -- char(12)
													@I_ResourceId = @I_ResourceId,                 -- char(12)
													@LotId = @LotId,                        -- char(12)
													@MOId = @MOId,                         -- char(12)
													@MOItemId =@AssyMOItemId,                     -- char(12)
													@ProductId = @MOProductId,                    -- char(12)
													@WorkcenterId = @WorkCenterId,                 -- char(12)
													@SpecificationId =@SpecificationId,              -- char(12)
													@WorkflowStepId = @WorkflowStepId               -- char(12)		
				EXEC dbo.TxnBase_LotMove @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
											@I_PlugInCommand = @I_PlugInCommand  ,                    -- varchar(5)
											@I_OrBitUserId = @I_OrBitUserId,                        -- char(12)
											@I_ResourceId = @I_ResourceId,                         -- char(12)
											@LotSN = @LotSN,                                -- varchar(40)
											@LotInDate = '2021-08-23 08:47:42',         -- datetime
											@ShiftId = '',                              -- char(12)
											@UserComment = N''                          -- nvarchar(1000)			    
			END
			SET @CurrSpecificationCode=''
			SELECT  @WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@SpecificationId=Lot.SpecificationId,@LotId=LotId,@Qty=Qty,@CurrSpecificationCode=sr.SpecificationCode 
            FROM dbo.Lot 
            left join Specification s on  Lot.SpecificationId=s.SpecificationId
            left join SpecificationRoot sr ON sr.SpecificationRootId=s.SpecificationRootId
            WHERE LotSN=@LotSN
			-- IF ISNULL(@SpecificationId,'') IN ('SPE10000028J','SPE10000028S'
            --     ,'SPE1000002AD','SPE1000002AE'--20260116新增活性、水性灌墨 mwj
            -- )  --灌墨规程
            IF ISNULL(@CurrSpecificationCode,'') IN ('FSGM','UVGM','HXGM','SXGM')
			BEGIN 
				EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
													@TxnCode = 'DC',                      -- varchar(10)
													@I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
													@I_OrBitUserId = @I_OrBitUserId,                -- char(12)
													@I_ResourceId = @I_ResourceId,                 -- char(12)
													@LotId = @LotId,                        -- char(12)
													@MOId = @MOId,                         -- char(12)
													@MOItemId =@AssyMOItemId,                     -- char(12)
													@ProductId = @MOProductId,                    -- char(12)
													@WorkcenterId = @WorkCenterId,                 -- char(12)
													@SpecificationId =@SpecificationId,              -- char(12)
													@WorkflowStepId = @WorkflowStepId               -- char(12)			
			---------------------------------------------------------------------------------------------------------------------------------		
				
				EXEC dbo.SysGetObjectPKId @ObjectId = 'LoadingItemLotMoveId',      -- char(12)
										@ObjectName = N'LoadingItemLotMove',   -- nvarchar(100)
										@PKID = @LoadingItemLotMoveId OUTPUT -- char(12)
				INSERT dbo.LoadingItemLotMove
				(
					LoadingItemLotMoveId,
					LoadingItemLotId,
					DataChainId,
					LotId,
					LotSN,
					InQty,
					OutQty,
					MOId,
					MOItemId,
					MOItemTaskId,
					ProductId,
					WorkflowId,
					WorkflowStepId,
					SpecificationId,
					Operator,
					WorkcenterId,
					EquipmentId,
					ResourceId,
					UserId,
					CreateDate
				)
				VALUES
				(   @LoadingItemLotMoveId,     -- LoadingItemLotMoveId - IDType
					@LoadingItemLotId,     -- LoadingItemLotId - IDType
					@DataChainId,     -- DataChainId - IDType
					@LotId,     -- LotId - IDType
					@LotSN,     -- LotSN - LotSN
					@Qty,     -- InQty - SysNumberType
					@InputNumber,     -- OutQty - SysNumberType
					@MOId,     -- MOId - IDType
					@AssyMOItemId,     -- MOItemId - IDType
					@MOItemTaskId,     -- MOItemTaskId - IDType
					@MOProductId,     -- ProductId - IDType
					@WorkflowId,     -- WorkflowId - IDType
					@WorkflowStepId,     -- WorkflowStepId - IDType
					@SpecificationId,     -- SpecificationId - IDType
					@I_OrBitUserName,      -- Operator - nvarchar(50)
					@WorkCenterId,     -- WorkcenterId - IDType
					NULL,     -- EquipmentId - IDType
					@I_ResourceId,     -- ResourceId - IDType
					@I_OrBitUserId,     -- UserId - IDType
					GETDATE() -- CreateDate - datetime
					)

				EXEC dbo.TxnBase_LotMove @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
											@I_PlugInCommand = @I_PlugInCommand  ,                    -- varchar(5)
											@I_OrBitUserId = @I_OrBitUserId,                        -- char(12)
											@I_ResourceId = @I_ResourceId,                         -- char(12)
											@LotSN = @LotSN,                                -- varchar(40)
											@LotInDate = '2021-08-23 08:47:42',         -- datetime
											@ShiftId = '',                              -- char(12)
											@UserComment = N''                          -- nvarchar(1000)			    
	        END

			SELECT @WorkflowId=WorkflowId,@WorkflowStepId = WorkflowStepId,@SpecificationId=SpecificationId,@LotId=LotId FROM dbo.Lot WHERE LotSN=@LotSN
			EXEC dbo.TxnBase_DataChainMainLine @DataChainId = @DataChainId OUTPUT, -- char(12)
												@TxnCode = 'DC',                      -- varchar(10)
												@I_PlugInCommand = @I_PlugInCommand,              -- varchar(5)
												@I_OrBitUserId = @I_OrBitUserId,                -- char(12)
												@I_ResourceId = @I_ResourceId,                 -- char(12)
												@LotId = @LotId,                        -- char(12)
												@MOId = @MOId,                         -- char(12)
												@MOItemId =@AssyMOItemId,                     -- char(12)
												@ProductId = @MOProductId,                    -- char(12)
												@WorkcenterId = @WorkCenterId,                 -- char(12)
												@SpecificationId =@SpecificationId,              -- char(12)
												@WorkflowStepId = @WorkflowStepId               -- char(12)			
		    

						
			-- 【报工】理货已全部扫满（已在分支入口校验），执行工单报工
			IF EXISTS(SELECT 1 FROM dbo.MoCraftPath WHERE MoId=@MOId AND WorkstageNO='10')
			BEGIN
		    EXEC dbo.MOProductionOrder 
                               @I_ReturnMessage = @I_ReturnMessage1 OUTPUT,            -- nvarchar(max)
                               @I_ExceptionFieldName = @I_ExceptionFieldName1 OUTPUT,  -- nvarchar(100)
                               @MOID = @MOId,                                           -- char(12)
                               @Line = '10',                                 -- nvarchar(30)
                               @Qty = @Qty                                            -- nvarchar(30)
		    END

			-- 【释放】已扣数在扫码扫满时按四维度即时结算，此处不再按 MOId 整单释放
			-- 原按 MOId 全量置 IsOccupyAllocatedQty=0 会误释放未扫满的理货行，已移除

			SELECT @MOItemTaskName=MOItemTaskName FROM dbo.MOItemTask WHERE @MOItemTaskId= MOItemTaskId 
            SELECT 
                    '' AS Command,
                 --   '' AS EmployeeNo,
				--	'' AS ProductionLine,
					'' AS SpecificationCode,
					'' AS MOName , 
					'' AS InputScan,
					'0' AS InputNumber,
					'' AS FMOQty,
					'' AS MOProduct,			
					'' AS MOItemTaskName,
					'' AS LoadingItemLotId,
					'' AS LoadingItemLotRecordId,
					'' AS MQtyRequired ,
					'' AS MActualQty,
					''  AS CurrMaterial,
					'' AS SrcLotSnList
			SET @I_ExceptionFieldName = 'InputScan';	
			SET @I_ReturnMessage = 'ServerMessage: 工单任务【'+ISNULL(@MOItemTaskName,'')+'】灌墨生产完成！' + @Enter +'报工信息：' +ISNULL(@I_ReturnMessage1,'');
            RETURN 0;
        END;
		SELECT '0' AS InputNumber,'' AS InputScan,'MLotNumberScan' AS Command
		SET @I_ReturnMessage = 'ServerMessage: 请继续扫描墨水批次或下线命令' + @Enter;
		RETURN 0;

    END;

	SELECT '' InputScan ,'0' InputNumber,'' Command
    SET @I_ExceptionFieldName = 'InputScan';
	SET @I_ExceptionFieldName = 'InputScan';	
    SET @I_ReturnMessage = 'ServerMessage:请继续扫描墨水批次或下线命令' + @Enter;
    RETURN 0;
END;
GO
