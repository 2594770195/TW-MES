SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:        <OrBit Team HF0029>
-- Create date:   <2024/11/18 >
-- Description:   <工单生产-正压过滤>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROC [dbo].[PDA_PZYGLGrindCheckInput]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT, --向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',		    --客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKid CHAR(12) ='',				--主键
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(100)='',		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.

@EmployeeNo NVARCHAR(50)='',		   -- 上料员
@EquipmentNo VARCHAR(50)='',		   -- 机台
@SpecificationCode VARCHAR(50)='',     -- 规程代码
@LotSN VARCHAR(50)='',				   -- 批号条码
@ProductionGrindId IDType='',         --本次生产研磨唯一标识
@InputScan VARCHAR(50)='',             --信息输入: 包括设备编码，人员编码，规程代码，批号，工艺参数编码，命令按钮条码
@InputNumber VARCHAR(50) ='',         --数值输入：重量，工艺参数值
@Command VARCHAR(50)='',                --当前执行指令

--以下为工艺参数表单录入提供参数
@TEMPER SysNumberType=0,
@PRESSE SysNumberType=0,
@PSPEED SysNumberType=0,
@SPEED SysNumberType=0,
@SSCALE SysNumberType=0,
@CURREN SysNumberType=0,
@MWATER SysNumberType=0,

@JudgingDepartment NVARCHAR(10)=''    --判定部门：品保/研发

AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	--TY
	DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10)
	DECLARE @RESULT INT=0

	--PATINDEX('%[^0-9|.|-|+]%','2.2')--返回0--数字判断
	IF ISNULL(@InputNumber,'')<>'' AND PATINDEX('%[^0-9|.|-|+]%',@InputNumber)<>0
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请输入数值类型'--+@Enter
		SET @I_ExceptionFieldName='InputNumber'
		SELECT '' AS InputNumber
		RETURN 0
	END

	IF ISNULL(@InputNumber,'')='' SET @InputNumber='0'

	DECLARE @EmployeeId IDType
	--基本信息
	DECLARE @DataChainId IDType
	DECLARE @TxnCode VARCHAR(10)='MOVE'
	DECLARE @LotId IDType
	DECLARE @MOId IDType
	DECLARE @MOProductId IDType
	DECLARE @WorkcenterId IDType
	DECLARE @SpecificationId IDType
	DECLARE @WorkflowStepId IDType
	DECLARE @CurDate DATETIME=GETDATE()
	DECLARE @QualityMark VARCHAR(16)
	DECLARE @Tips NVARCHAR(256)
	DECLARE @WorkflowId CHAR(12)

	DECLARE @ProductDescription NVARCHAR(1000)
	DECLARE @LotQty SysNumberType
	DECLARE @ProcessCategory VARCHAR(16)

	DECLARE @EquipmentId CHAR(12)
	DECLARE @PGUsePartsId IDType
	DECLARE @PGFilterId IDType
	DECLARE @CurrentCount INT

	DECLARE @FilterType NVARCHAR(16)
	DECLARE @PartsCategory NVARCHAR(16)

	DECLARE @MixingTime DECIMAL(18,3)
	DECLARE @StartQty DECIMAL(18,3)
	DECLARE @StartTime DATETIME
	DECLARE @FilterTime SysNumberType

	DECLARE @FilterQty DECIMAL(18,3)

	DECLARE @WeighQty SysNumberType=CAST(@InputNumber AS DECIMAL(18,3))

	DECLARE @FilterE1 INT=0
	DECLARE @FilterE2 INT=0
	DECLARE @FilterE3 INT=0
	DECLARE @FilterRemark NVARCHAR(100)
	DECLARE @FilterMQty INT=0

	DECLARE @GZUsedTime INT=0
	DECLARE @GZLoadingDate DATETIME
	DECLARE @GZUnloadingTime INT
	
	DECLARE @SampingQty SysNumberType=0
    DECLARE @LossQty SysNumberType=0
	--检验单参数
	DECLARE @QC_ProcessIns_SubLotId IDType
	DECLARE @QC_ProcessInsId IDType,
			@InsName nvarchar(50)='',
			@InsStates  varchar(20)='10',
			@SubmissQty  SysNumberType=0,	 
			@SubmissCategory  char(5)='TE',
			@SubmissDate  datetime=GETDATE(),
			@FactoryId  IDType='',
			@RealInQty  SysNumberType=0,	 
			@TotalDefectQty  SysNumberType=0,	 
			@InsResult  IDType='',
			@InsDate  datetime=null,
			@Inspector  nvarchar(50)='',
			@ConfirmResult  varchar(20)='',
			@ConfirmUser  IDType='',
			@ConfirmDate  datetime=null,
			@ConfirmComment  nvarchar(100)='',
			@WorkcenterName NVARCHAR(50) = '' ,
			@UserName nvarchar(50)='',
			@Sequence int=0

    DECLARE @NEED_REFINE CHAR(1)=''

	--条码/指令扫描
	IF @I_Sender='InputScanDefocus'
	BEGIN
		SET @InputScan = LTRIM(RTRIM(ISNULL(@InputScan,'')))

		SET @I_ExceptionFieldName='InputScan'
		IF ISNULL(@InputScan,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请扫描'--+@Enter
			RETURN 0
		END

		--进行判断，输入参数是否是执行命令
		IF LEFT(@InputScan,3)='CMD'
		BEGIN
			IF @InputScan ='CMDRESET'--重置命令：只重载在在本界面扫描的，其他参数是从查询界面带过来的
			BEGIN
				SELECT '' AS EmployeeNo,'' AS EquipmentNo,'' AS SpecificationCode,
				'' AS InputScan,0 AS InputNumber,'' AS LotSN,
				'' AS ProductionGrindId,@InputScan AS Command,'请扫描[员工工号]!' AS Tips,
				'' AS ProductDescription,'' AS LotQty,'' AS QualityMark,'' AS ProcessCategory,'' AS FilterRemark
				SET @I_ReturnMessage='ServerMessage:已重置!'+@Enter
				RETURN 0
			END

			IF @InputScan ='CMDSWITCHE'--切换设备
			BEGIN
				--提示扫描设备
				SET @I_ExceptionFieldName='InputScan'
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请扫描设备条码' AS Tips
				RETURN 0
			END

			IF @InputScan ='CMDLOADGZ'--更换锆珠
			BEGIN
				--提示扫描设备
				IF ISNULL(@EquipmentNo,'')=''
				BEGIN
					SET @I_ReturnMessage='ServerMessage:请先扫描设备号后再试' +@Enter
					RETURN 0
				END

				IF NOT EXISTS(SELECT 1 FROM Equipment WHERE EquipmentNumber=@EquipmentNo)
				BEGIN
					SELECT '' AS InputScan
					SET @I_ExceptionFieldName='InputScan'
					SET @I_ReturnMessage='ServerMessage:设备编号['+@EquipmentNo+']未维护，请重新扫描' +@Enter
					RETURN 0
				END

				UPDATE Equipment SET GZLoadingDate=GETDATE() WHERE EquipmentNumber=@EquipmentNo

				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:已完成锆珠更换操作，重新开始记录锆珠使用时间' +@Enter
				SELECT '' AS InputScan,0 AS InputNumber
				RETURN 0
			END

			IF @InputScan ='CMDCFILTER'--更换滤芯
			BEGIN
				--重置滤芯次数
				IF ISNULL(@EquipmentNo,'')=''
				BEGIN
					SET @I_ReturnMessage='ServerMessage:请先扫描设备号后再试' +@Enter
					RETURN 0
				END

				--IF ISNULL(@ProductionGrindId,'')<>''
				--BEGIN
				--	SET @I_ReturnMessage='ServerMessage:请在设备未使用情况下更换' +@Enter
				--	RETURN 0
				--END

				--IF EXISTS(SELECT TOP 1 1 FROM ProductionGrind A
				--INNER JOIN Equipment B ON A.EquipmentId=B.EquipmentId
				--INNER JOIN Equipment C ON A.Equipment2Id=C.EquipmentId
				--WHERE A.IsComplete=0 AND @EquipmentNo IN(B.EquipmentNumber,C.EquipmentNumber))
				--BEGIN
				--	SET @I_ReturnMessage='ServerMessage:系统检测到当前设备正在使用，请在设备未使用情况下更换' +@Enter
				--	RETURN 0
				--END

				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请扫描滤芯条码' AS Tips
				--,N'滤芯0.5[0]次;滤芯1.0[0]次;滤芯3.0[0]次' AS FilterRemark
				RETURN 0
			END

			IF @InputScan='CMDREFRESH'--刷新命令
			BEGIN
				--获取研磨标识，如果是首次进行研磨，需要记录上机前重量
				EXEC @RESULT=[dbo].[PDA_PGrindGetID]
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@EmployeeNo=@EmployeeNo,
				@EquipmentNo=@EquipmentNo,
				@SpecificationCode=@SpecificationCode,
				@LotSN=@LotSN,
				@LotQty=0,
				@ProductionGrindId=@ProductionGrindId OUTPUT

				IF @RESULT=1
				BEGIN
					SELECT 0 AS InputNumber,'' AS InputScan,@ProductionGrindId AS ProductionGrindId,@I_ReturnMessage AS Tips
					SET @I_ReturnMessage=''
					RETURN 0
				END

				IF @RESULT=-2
				BEGIN
					SELECT @InputNumber=CAST(Qty AS VARCHAR(19)) FROM MOItemLot WHERE LotSN=@InputScan
					SET @I_ExceptionFieldName='InputNumber'
					SELECT @InputNumber AS InputNumber,'CMDWEIGH' AS Command,'首次下料请记录吨桶重量!' AS Tips
					RETURN 0
				END

				IF @RESULT=-1
				BEGIN
					SELECT 0 AS InputNumber,'' AS InputScan
					RETURN @RESULT
				END

				SELECT 0 AS InputNumber,'' AS InputScan,@ProductionGrindId AS ProductionGrindId,'请扫描指令进行操作' AS Tips
				SET @I_ReturnMessage='ServerMessage:[批次条码]已扫描，请根据工艺提示进行操作' +@Enter
				RETURN @RESULT
			END

			IF @InputScan ='CMDADDEMPLOYEE'--添加上料人员
			BEGIN
				--提示扫描员工工号
				SET @I_ExceptionFieldName='InputScan'
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请扫描员工工号' AS Tips
				RETURN 0
			END

			IF @SpecificationCode IN('GL','GL-','GL+')
			BEGIN
				IF @InputScan ='CMDFILTERM'--使用滤膜
				BEGIN
					IF ISNULL(@ProductionGrindId,'')=''
					BEGIN
						SET @I_ReturnMessage='ServerMessage:请扫描批号开始过滤工艺' +@Enter
						RETURN 0
					END

					SET @I_ExceptionFieldName='InputNumber'
					SELECT '' AS InputScan,1 AS InputNumber,@InputScan AS Command,'请输入使用滤膜数量' AS Tips
					RETURN 0
				END

				--IF @InputScan ='CMDNEWFM'--使用新滤膜
				--BEGIN
				--	SET @I_ExceptionFieldName='InputScan'

				--	EXEC SysGetObjectPKId '','PGUseParts',@PGUsePartsId OUTPUT
				--	INSERT INTO [dbo].[PGUseParts]
				--				([PGUsePartsId]
				--				,[ProductionGrindId]
				--				,[PartsType])
				--			VALUES
				--				(@PGUsePartsId
				--				,@ProductionGrindId
				--				,'NEW')

				--	SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'请扫描操作指令' AS Tips
				--	SET @I_ReturnMessage='ServerMessage:滤膜使用成功' +@Enter
				--	RETURN 0
				--END

				--IF @InputScan ='CMDOLDFM'--使用旧滤膜
				--BEGIN
				--	SET @I_ExceptionFieldName='InputScan'
				--	IF ISNULL(@ProductionGrindId,'')=''
				--	BEGIN
				--		SET @I_ReturnMessage='ServerMessage:请扫描批号开始过滤工艺' +@Enter
				--		RETURN 0
				--	END

				--	EXEC SysGetObjectPKId '','PGUseParts',@PGUsePartsId OUTPUT
				--	INSERT INTO [dbo].[PGUseParts]
				--				([PGUsePartsId]
				--				,[ProductionGrindId]
				--				,[PartsType])
				--			VALUES
				--				(@PGUsePartsId
				--				,@ProductionGrindId
				--				,'OLD')

				--	SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'请扫描操作指令' AS Tips
				--	SET @I_ReturnMessage='ServerMessage:滤膜使用成功' +@Enter
				--	RETURN 0
				--END

				IF @InputScan IN ('CMDSTARTGL+','CMDSTARTGL-')--开始正压过滤
				BEGIN
					SET @I_ExceptionFieldName='InputScan'

					IF ISNULL(@ProductionGrindId,'')=''
					BEGIN
						SET @I_ReturnMessage='ServerMessage:请扫描批号开始过滤工艺' +@Enter
						RETURN 0
					END
					
					SET @FilterType=(CASE @InputScan WHEN 'CMDSTARTGL+' THEN '正压' ELSE '负压' END);

					SELECT @StartQty=StartQty FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId
					SELECT @FilterQty=SUM(FilterQty) FROM PGFilter WHERE ProductionGrindId=@ProductionGrindId AND FilterType=@FilterType

					SET @FilterQty=ISNULL(@FilterQty,0)

					IF @FilterQty>=@StartQty
					BEGIN
						SET @I_ReturnMessage='ServerMessage:当前'+@FilterType+'已过滤数量['+CAST(@FilterQty AS VARCHAR(19))+']已达批号总数量['+CAST(@StartQty AS VARCHAR(19))+']，过滤已全部完成'--+@Enter
						SELECT '' AS InputScan,0 AS InputNumber
						RETURN 0
					END

					--判断当前是否正在过滤中
					IF EXISTS(SELECT 1 FROM PGFilter WHERE ProductionGrindId=@ProductionGrindId AND FilterType=@FilterType AND StopTime IS NULL)
					BEGIN
						SET @I_ReturnMessage='ServerMessage:上次'+@FilterType+'过滤还未停止，无法进行新的过滤'--+@Enter
						SELECT '' AS InputScan,0 AS InputNumber
						RETURN 0
					END

					EXEC SysGetObjectPKId '','PGFilter',@PGFilterId OUTPUT

					INSERT INTO [dbo].[PGFilter]
								([PGFilterId]
								,[ProductionGrindId]
								,[StartTime]
								,[FilterTime]
								,[FilterType]
								,[FilterQty])
							VALUES
								(@PGFilterId
								,@ProductionGrindId
								,GETDATE()
								,0
								,@FilterType
								,0)

					SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'请扫描操作指令' AS Tips
					SET @I_ReturnMessage='ServerMessage:已开始'+@FilterType+'过滤，将累计过滤时间' +@Enter
					RETURN 0

				END

				IF @InputScan IN('CMDSTOPGL+','CMDSTOPGL-')--停止过滤
				BEGIN
					SET @I_ExceptionFieldName='InputNumber'

					IF ISNULL(@ProductionGrindId,'')=''
					BEGIN
						SET @I_ReturnMessage='ServerMessage:请扫描批号开始过滤工艺' +@Enter
						RETURN 0
					END

					SET @FilterType=(CASE @InputScan WHEN 'CMDSTOPGL+' THEN '正压' ELSE '负压' END);

					--判断是否有未停止的过滤
					SELECT TOP 1 @StartTime=StartTime,@PGFilterId=PGFilterId FROM PGFilter WHERE ProductionGrindId=@ProductionGrindId AND FilterType=@FilterType AND StopTime IS NULL
					IF ISNULL(@PGFilterId,'')=''
					BEGIN
						SET @I_ReturnMessage='ServerMessage:当前还未开始'+@FilterType+'过滤，请扫描开始过滤指令后进行过滤'--+@Enter
						SELECT '' AS InputScan,0 AS InputNumber
						RETURN 0
					END

					SELECT @StartQty=StartQty FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId
					SELECT @FilterQty=SUM(FilterQty) FROM PGFilter WHERE ProductionGrindId=@ProductionGrindId AND FilterType=@FilterType

					SET @FilterQty=ISNULL(@FilterQty,0)

					SET @FilterQty=@StartQty-@FilterQty

					SELECT '' AS InputScan,@FilterQty AS InputNumber,@InputScan AS Command,'请输入过滤数量' AS Tips
					RETURN 0
				END
			END
            IF @InputScan IN('CMDREFINE','CMDNOTREFINE')--是否需要提纯
            BEGIN
                IF @InputScan  ='CMDREFINE'
                BEGIN
                    SET @NEED_REFINE='1' 
                    SELECT '' AS InputScan,0 AS InputNumber,'已选择【提纯】流程，请扫描指令进行操作' AS Tips
                END
                ELSE IF @InputScan  ='CMDNOTREFINE'
                BEGIN
                    SET @NEED_REFINE='0' 
                    SELECT '' AS InputScan,0 AS InputNumber,'已选择【不提纯】流程，请扫描指令进行操作' AS Tips
                END
                IF EXISTS(SELECT 1 FROM ZYGL_NEEDFEFINE WHERE LOTSN=@LotSN)
                BEGIN
                    UPDATE ZYGL_NEEDFEFINE SET NEEDREFINE=@NEED_REFINE WHERE LOTSN=@LotSN
                    RETURN 0
                END
                ELSE 
                BEGIN
                    INSERT INTO ZYGL_NEEDFEFINE(NEEDREFINE,LOTSN) VALUES(@NEED_REFINE,@LotSN) 
                END
            END
			IF @InputScan IN('CMDLOTMOVEG','CMDLOTMOVER','CMDLOTMOVEY','CMDLOTMOVE')--批次下线,绿标/红标/黄标/未判定
			BEGIN
				--负压过滤：判定是否有过滤记录
				--IF @SpecificationCode='GL-'
				--BEGIN
				--	IF NOT EXISTS(SELECT 1 FROM PGFilter WHERE ProductionGrindId=@ProductionGrindId)
				--	BEGIN
				--		SELECT '' AS InputScan 
				--		SET @I_ReturnMessage='ServerMessage:请进行开始或结束过滤后再试！'--+@Enter
				--		RETURN 0
				--	END
				--END
			    --活性水浆流程需要选择是否提纯，提纯与不提纯公用一个工作流
                SELECT @WorkflowId=WorkflowId FROM Lot WHERE LotSN=@LotSN
                IF @WorkflowId in ('WKF1000000ZC')
                BEGIN
                    IF NOT EXISTS(SELECT 1 FROM ZYGL_NEEDFEFINE WHERE LOTSN = @LotSN)
                    BEGIN
                        SELECT '' AS InputScan
                        SET @I_ReturnMessage='ServerMessage:请先选择是否提纯！'--+@Enter
                        RETURN 0
                    END
                END

				IF ISNULL(@ProductionGrindId,'')=''
				BEGIN
					SELECT '' AS InputScan 
					SET @I_ReturnMessage='ServerMessage:请先扫描批号开始操作！'--+@Enter
					RETURN 0
				END

				SELECT @StartQty=StartQty,@StartTime=StartTime FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId

				/************************************************* 生产中拆批提前下线处理 ********************************************************/
				--生产过程中是否有拆批动作，如有，请扫描拆分的批次下线
				--SELECT @LotId=LotId,@WorkflowId=WorkflowId FROM Lot WHERE LotSN=@LotSN
				--IF EXISTS(SELECT 1 FROM Lot WHERE ParentLotId=@LotId AND CreateDate>@StartTime)
				--BEGIN
				--	SET @I_ExceptionFieldName='InputNumber'
				--	SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'系统检测到生产过程中有拆批，请扫描生产批次!' AS Tips
				--	RETURN 0
				--END
				/************************************************* 生产中拆批提前下线处理 ********************************************************/


				--是否有未完成的检验单
				IF @SpecificationCode IN('GL+')
				BEGIN
					IF NOT EXISTS(SELECT 1 FROM PGSamping WHERE ProductionGrindId=@ProductionGrindId)
					BEGIN
						SELECT '' AS InputScan 
						SET @I_ReturnMessage='ServerMessage:请先进行取样！'--+@Enter
						RETURN 0
					END

					IF  EXISTS(SELECT 1 FROM QC_ProcessIns_SubLot A
                        INNER JOIN QC_ProcessIns B ON A.QC_ProcessInsId=B.QC_ProcessInsId
                        WHERE A.LotSN=@LotSN AND B.InsStates<>'20' AND B.SubmissCategory='TE') 
                    BEGIN
                            SELECT '' AS InputScan
                            SET @I_ExceptionFieldName='InputScan'
                            SET @I_ReturnMessage='ServerMessage:检测到还有未完成的检验单，请先完成检验！' +@Enter
                            RETURN 0
                    END

				END

				--IF @SpecificationCode ='LX' AND @WorkflowId IN('WKF1000000YQ','WKF1000000YR')
				--BEGIN

				--	SET @MixingTime=[dbo].[MixingTime]('XS',@StartQty,@StartTime)

				--	IF @MixingTime>0
				--	BEGIN
				--		SELECT '' AS InputScan,0 AS InputNumber
				--		SET @I_ExceptionFieldName='InputScan'
				--		SET @I_ReturnMessage='ServerMessage:当前未到搅拌时间点，不能执行此动作,搅拌时间剩余['+CAST(@MixingTime AS NVARCHAR(19))+']秒!'+@Enter
				--		RETURN 0
				--	END
				--END

				SELECT @LotQty=Qty FROM Lot WHERE LotSN=@LotSN
				SELECT @SampingQty=SUM(SampingQty) FROM PGSamping WHERE ProductionGrindId=@ProductionGrindId
                SELECT @LossQty=SUM(LossQty) FROM PGLoss WHERE ProductionGrindId=@ProductionGrindId--20260116新增损耗功能（可选）

				SET @LotQty-=ISNULL(@SampingQty,0)
                SET @LotQty-=ISNULL(@LossQty,0)
				--修改当前执行指令为批次过站，接下来是录入重量
				SET @I_ExceptionFieldName='InputNumber'
				SELECT '' AS InputScan,@LotQty AS InputNumber,@InputScan AS Command,'请录入重量!' AS Tips
				RETURN 0
			END
			IF @InputScan ='CMDTEMPER'--工艺参数录入：温度
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请输入[温度]!' AS Tips
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END
			IF @InputScan ='CMDPRESSE'--工艺参数录入：压力
			BEGIN
			    SELECT @WorkflowId=WorkflowId FROM Lot WHERE LotSN=@LotSN
			    IF @WorkflowId IN ('WKF1000000ZB','WKF1000000ZC','WKF1000000ZD') --活性正压过滤压力值默认0.1
			    BEGIN
			        SELECT '' AS InputScan,0.1 AS InputNumber,@InputScan AS Command,'请输入[压力]!' AS Tips
			        SET @I_ExceptionFieldName='InputNumber'
			        RETURN 0
			    END
			    ELSE
			    BEGIN
			       	SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请输入[压力]!' AS Tips
				    SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			    END

			END
			IF @InputScan ='CMDPSPEED'--工艺参数录入：泵速
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请输入[泵速]!' AS Tips
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END
			IF @InputScan ='CMDSPEED'--工艺参数录入：投料转速、C点转速
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请输入[转速]!' AS Tips
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END
			IF @InputScan ='CMDSSCALE'--工艺参数录入：机封刻度
			BEGIN
				SELECT '' AS InputScan,'' AS InputNumber,@InputScan AS Command,'请输入[机封刻度]!' AS Tips
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END
			IF @InputScan ='CMDCURREN'--工艺参数录入：电流
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请输入[电流]!' AS Tips
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END
			IF @InputScan ='CMDMWATER'--工艺参数录入：过滤性能
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请输入[过滤性能]!' AS Tips
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END
			IF @InputScan ='CMDSAMPLING'--取样命令
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请输入取样数量!' AS Tips
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END
            IF @InputScan ='CMDLOSS'--损耗命令
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请输入损耗数量!' AS Tips
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END
			IF @InputScan ='CMDTOTE' AND @SpecificationCode IN('GL+')--D点送检（打印测试）
			BEGIN
				--判定是否提前取样
				IF NOT EXISTS(SELECT 1 FROM PGSamping WHERE ProductionGrindId=@ProductionGrindId AND IsInspection=0)
				BEGIN
					SELECT '' AS InputScan,0 AS InputNumber
					SET @I_ExceptionFieldName='InputScan'
					SET @I_ReturnMessage='ServerMessage:请提前取样！' +@Enter
					RETURN -1
				END

				--判定是否还有未完成的检验单
				IF EXISTS(SELECT 1 FROM QC_ProcessIns_SubLot A
				INNER JOIN QC_ProcessIns B ON A.QC_ProcessInsId=B.QC_ProcessInsId
				WHERE A.LotSN=@LotSN AND B.InsStates<>'20' AND B.SubmissCategory='TE')
				BEGIN
					SELECT '' AS InputScan,0 AS InputNumber
					SET @I_ExceptionFieldName='InputScan'
					SET @I_ReturnMessage='ServerMessage:检测到还有未完成的检验单，请先完成检验！' +@Enter
					RETURN -1
				END

				SET @SubmissCategory='TE'

				SELECT @Sequence=COUNT(1) FROM QC_ProcessIns WHERE DATEDIFF(DAY,CreateDate,GETDATE())=0

				SELECT @UserName=UserName FROM SysUser WHERE EmployeeNo=@EmployeeNo

				SELECT @LotId=LotId,@MOId=MOId FROM Lot WHERE LotSN=@LotSN

				SELECT @SubmissQty=SUM(SampingQty) FROM PGSamping WHERE ProductionGrindId=@ProductionGrindId AND IsInspection=0

				EXEC SysGetObjectPKId '','QC_ProcessIns',@QC_ProcessInsId OUTPUT
				SET @InsName='1000'+RIGHT(convert(varchar(8),getdate(),112),6)+SUBSTRING('000',0,4-LEN(CAST(@Sequence AS CHAR(3))))+CAST(@Sequence AS CHAR(3))
				--添加过程检验单
				Insert into QC_ProcessIns(
							QC_ProcessInsId,
							InsName,
							InsStates,
							SubmissQty,
							SubmissCategory,
							SubmissDate,
							SubmissUser,
							MOId,
							FactoryId,
							RealInQty,
							TotalDefectQty,
							InsResult,
							InsDate,
							Inspector,
							ConfirmResult,
							ConfirmUser,
							ConfirmDate,
							ConfirmComment,
							WorkcenterId,
							ResourceId ,
							CreateUser ,
							ShiftId,
							ProductionGrindId
				)Values(
							@QC_ProcessInsId,
							@InsName,
							@InsStates,
							@SubmissQty,
							@SubmissCategory,
							@SubmissDate,
							@UserName,
							@MOId,
							@FactoryId,
							@RealInQty,
							@TotalDefectQty,
							@InsResult,
							@InsDate,
							@Inspector,
							@ConfirmResult,
							@ConfirmUser,
							@ConfirmDate,
							@ConfirmComment,
							@WorkcenterId,
							@I_ResourceId ,
							@UserName,
							'',
							@ProductionGrindId
							)

				--创建过程送检批号
				EXEC SysGetObjectPKId '','QC_ProcessIns_SubLot',@QC_ProcessIns_SubLotId OUTPUT
				Insert into QC_ProcessIns_SubLot(
							 QC_ProcessIns_SubLotId,
							 QC_ProcessInsId,
							 LotId,
							 LotSN ,
							 LotQty ,
							 ResourceId
				  )Values(
							 @QC_ProcessIns_SubLotId,
							 @QC_ProcessInsId,
							 @LotId,
							 @LotSN ,
							 @SubmissQty ,
							 @I_ResourceId
							 )

				UPDATE PGSamping SET IsInspection=1 WHERE ProductionGrindId=@ProductionGrindId AND IsInspection=0

				SELECT '' AS InputScan,0 AS InputNumber
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:已完成送检！' +@Enter
				RETURN 0
			END

			IF @InputScan ='CMDFAULT'--故障命令
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'请输入或扫描故障代码!' AS Tips
				RETURN 0
			END
		END

		IF @Command ='CMDSWITCHE'--切换设备
		BEGIN
			--验证设备号正确性，以及是否正在投料
			IF NOT EXISTS(SELECT 1 FROM Equipment WHERE EquipmentNumber=@InputScan)
			BEGIN
				SELECT '' AS InputScan
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:设备编号['+@InputScan+']未维护，请重新扫描' +@Enter
				RETURN 0
			END

			SELECT 
				@ProductionGrindId=A.ProductionGrindId,
				@SpecificationCode=D.SpecificationCode,
				@LotSN=A.LotSN,
				@WorkflowId=E.WorkflowId
			FROM ProductionGrind A
			INNER JOIN Equipment B ON A.EquipmentId=B.EquipmentId
			INNER JOIN Specification C ON A.SpecificationId=C.SpecificationId
			INNER JOIN SpecificationRoot D ON C.SpecificationRootId=D.SpecificationRootId
			INNER JOIN Lot E ON A.LotSN=E.LotSN
			LEFT JOIN Equipment F ON A.Equipment2Id=F.EquipmentId
			WHERE @InputScan IN(B.EquipmentNumber,ISNULL(F.EquipmentNumber,'')) AND IsComplete=0

			IF ISNULL(@ProductionGrindId,'')=''
			BEGIN
				SELECT '' AS InputScan
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:所扫设备['+@InputScan+']不在生产中，请重新扫描' +@Enter
				RETURN 0
			END

			SET @EquipmentNo=@InputScan

			SELECT TOP 1 @EmployeeNo=B.EmployeeNo FROM Operator A
			INNER JOIN SysUser B ON A.EmployeeId=B.UserId WHERE A.RefId=@ProductionGrindId
			ORDER BY A.CreateDate DESC

			EXEC @RESULT=[dbo].[PDA_PGrindGetID]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@EmployeeNo=@EmployeeNo,
			@EquipmentNo=@EquipmentNo,
			@SpecificationCode=@SpecificationCode,
			@LotSN=@LotSN,
			@LotQty=@WeighQty,
			@ProductionGrindId=@ProductionGrindId OUTPUT

			IF @RESULT=-1 RETURN @RESULT 

			--获取批号信息
			IF @SpecificationCode IN('GL','GL+','GL-')
			BEGIN
				SELECT 
					@ProductDescription=P.ProductDescription, 
					@LotQty=L.Qty, 
					@MOId=L.MOId, 
					@ProcessCategory='['+P.FiltrationProcess+']['+P.FiltrationProcess1+']'
				FROM Lot L 
				INNER JOIN Product P ON L.ProductId=P.ProductId 
				WHERE L.LotSN=@LotSN
			END

			--获取投料批次的状态
			SELECT TOP 1 @QualityMark=[dbo].[FormatQualityMark](QualityMark)
			FROM (SELECT (CASE D.QualityMark 
					WHEN 'G' THEN 1
					WHEN 'Y' THEN 1
					WHEN 'YG' THEN 2
					WHEN 'YB' THEN 3
					WHEN 'R' THEN 1
					WHEN 'RG' THEN 2
					WHEN 'RB' THEN 3
					WHEN 'Q' THEN 1
					WHEN 'NQ' THEN 2 END) AS QualityLevel,D.QualityMark FROM LoadingItemLotRecord A
			INNER JOIN LoadingItemLotDetail B ON A.LoadingItemLotDetailId=B.LoadingItemLotDetailId
			INNER JOIN LoadingItemLot C ON B.LoadingItemLotId=C.LoadingItemLotId
			INNER JOIN Lot D ON A.LotSN=D.LotSN
			WHERE C.MOId=@MOId AND ISNULL(D.QualityMark,'')<>'') T ORDER BY QualityLevel DESC

			IF @RESULT=1
			BEGIN
				SELECT 0 AS InputNumber,@LotSN AS LotSN,@EmployeeNo AS EmployeeNo,@EquipmentNo AS EquipmentNo,@SpecificationCode AS SpecificationCode,
				'' AS InputScan,@ProductionGrindId AS ProductionGrindId,@I_ReturnMessage AS Tips,
				@ProductDescription AS ProductDescription,@WeighQty AS LotQty,@QualityMark AS QualityMark,@ProcessCategory AS ProcessCategory

				SET @I_ReturnMessage=''
				RETURN 0
			END

			SET @Tips='请扫描指令进行操作'

			SELECT @StartQty=StartQty,@StartTime=StartTime,@FilterE1=FilterE1,@FilterE2=FilterE2,@FilterE3=FilterE3 FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId

			IF @SpecificationCode ='LX' AND @WorkflowId IN('WKF1000000YQ','WKF1000000YR')
			BEGIN
				SET @MixingTime=[dbo].[MixingTime]('XS',@StartQty,@StartTime)

				IF @MixingTime>0
				BEGIN
					SET @Tips='离心工艺搅拌时间剩余['+CAST(@MixingTime AS NVARCHAR(19))+']秒!'
				END
			END

			IF @SpecificationCode='GL+'
			BEGIN
				SET @FilterRemark=N'滤芯0.5['+CAST(@FilterE1 AS NVARCHAR(5))+N']次;滤芯1.0['+CAST(@FilterE2  AS NVARCHAR(5))+']次;滤芯3.0['+CAST(@FilterE3  AS NVARCHAR(5))+']次';
			END
			IF @SpecificationCode='GL-'
			BEGIN
				SELECT @FilterMQty=SUM(PartsQty) FROM PGUseParts WHERE ProductionGrindId=@ProductionGrindId AND PartsCategory='滤膜'
				SET @FilterRemark=N'已使用滤膜['+CAST(@FilterMQty AS NVARCHAR(10))+']张'
			END

			SELECT 0 AS InputNumber,@LotSN AS LotSN,@EmployeeNo AS EmployeeNo,@EquipmentNo AS EquipmentNo,@SpecificationCode AS SpecificationCode,
			'' AS InputScan,@ProductionGrindId AS ProductionGrindId,@Tips AS Tips,
			@ProductDescription AS ProductDescription,@WeighQty AS LotQty,@QualityMark AS QualityMark,@ProcessCategory AS ProcessCategory,@FilterRemark AS FilterRemark

			SET @I_ReturnMessage='ServerMessage:[设备]已切换，请根据工艺提示进行操作' +@Enter
			RETURN @RESULT
		END
		
		IF @Command ='CMDCFILTER'--更换滤芯
		BEGIN
			IF @InputScan IN('CMDFILTERE1','CMDFILTERE2','CMDFILTERE3')--使用滤芯
			BEGIN
				SET @I_ExceptionFieldName='InputScan'

				IF ISNULL(@EquipmentNo,'')=''
				BEGIN
					SET @I_ReturnMessage='ServerMessage:请先扫描设备号后再试' +@Enter
					RETURN 0
				END

				--IF ISNULL(@ProductionGrindId,'')<>''
				--BEGIN
				--	SET @I_ReturnMessage='ServerMessage:请在设备未使用情况下更换' +@Enter
				--	RETURN 0
				--END

				SET @PartsCategory=(CASE @InputScan WHEN 'CMDFILTERE1' THEN '滤芯0.5' WHEN 'CMDFILTERE2' THEN '滤芯1.0' ELSE '滤芯3.0' END)
				
				SELECT TOP 1 @ProductionGrindId=A.ProductionGrindId FROM ProductionGrind A
				INNER JOIN Equipment B ON A.EquipmentId=B.EquipmentId
				INNER JOIN Equipment C ON A.Equipment2Id=C.EquipmentId
				WHERE A.IsComplete=0 AND @EquipmentNo IN(B.EquipmentNumber,C.EquipmentNumber)
				IF ISNULL(@ProductionGrindId,'')<>''
				BEGIN
					--SET @I_ReturnMessage='ServerMessage:系统检测到当前设备正在使用，请在设备未使用情况下更换' +@Enter
					--RETURN 0
					IF @InputScan='CMDFILTERE1'
					BEGIN
						UPDATE Equipment SET FilterE1=1 WHERE EquipmentNumber=@EquipmentNo
						UPDATE ProductionGrind SET FilterE1=1 WHERE ProductionGrindId=@ProductionGrindId
					END
					IF @InputScan='CMDFILTERE2'
					BEGIN
						UPDATE Equipment SET FilterE2=1 WHERE EquipmentNumber=@EquipmentNo
						UPDATE ProductionGrind SET FilterE2=1 WHERE ProductionGrindId=@ProductionGrindId
					END
					IF @InputScan='CMDFILTERE3'
					BEGIN
						UPDATE Equipment SET FilterE3=1 WHERE EquipmentNumber=@EquipmentNo
						UPDATE ProductionGrind SET FilterE3=1 WHERE ProductionGrindId=@ProductionGrindId
					END

					EXEC SysGetObjectPKId '','PGUseParts',@PGUsePartsId OUTPUT
					INSERT INTO [dbo].[PGUseParts]
								([PGUsePartsId]
								,[ProductionGrindId]
								,[PartsType]
								,[PartsQty]
								,[PartsCategory])
							VALUES
								(@PGUsePartsId
								,@ProductionGrindId
								,'New'
								,1
								,@PartsCategory)
				END
				ELSE
				BEGIN
					IF @InputScan='CMDFILTERE1'
					BEGIN
						UPDATE Equipment SET FilterType='',FilterE1=0 WHERE EquipmentNumber=@EquipmentNo
					END
					IF @InputScan='CMDFILTERE2'
					BEGIN
						UPDATE Equipment SET FilterType='',FilterE2=0 WHERE EquipmentNumber=@EquipmentNo
					END
					IF @InputScan='CMDFILTERE3'
					BEGIN
						UPDATE Equipment SET FilterType='',FilterE3=0 WHERE EquipmentNumber=@EquipmentNo
					END
				END
				
				SELECT @FilterE1=ISNULL(FilterE1,0),@FilterE2=ISNULL(FilterE2,0),@FilterE3=ISNULL(FilterE3,0),@FilterType=ISNULL(FilterType,'') FROM Equipment WHERE IsAvalid=1 AND EquipmentNumber=@EquipmentNo
				
				IF @SpecificationCode='GL+'
				BEGIN
					SET @FilterRemark=N'滤芯0.5['+CAST(@FilterE1 AS NVARCHAR(5))+N']次;滤芯1.0['+CAST(@FilterE2  AS NVARCHAR(5))+']次;滤芯3.0['+CAST(@FilterE3  AS NVARCHAR(5))+']次;['+@FilterType+']';
				END
				IF @SpecificationCode='GL-'
				BEGIN
					SELECT @FilterMQty=SUM(PartsQty) FROM PGUseParts WHERE ProductionGrindId=@ProductionGrindId AND PartsCategory='滤膜'
					SET @FilterRemark=N'已使用滤膜['+CAST(@FilterMQty AS NVARCHAR(10))+']张'
				END

				IF ISNULL(@LotSN,'')='' SET @Tips='请扫描[批次条码]!'
				
				IF ISNULL(@SpecificationCode,'')='' SET @Tips='请扫描[规程代码]!'

				IF ISNULL(@Tips,'')='' SET @Tips='请扫描操作指令'

				SET @I_ReturnMessage='ServerMessage:设备['+@EquipmentNo+']已更换['+@PartsCategory+']，重置滤芯使用次数和过滤墨水类别!'+@Enter

				SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,@Tips AS Tips,@FilterRemark AS FilterRemark
				RETURN 0
			END
			SET @I_ReturnMessage='ServerMessage:扫描滤芯条码错误!'+@Enter
			RETURN 0
		END

		--判断是否是扫描基本信息
		IF ISNULL(@EmployeeNo,'')=''
		BEGIN
			SELECT @EmployeeNo=EmployeeNo FROM SysUser WHERE EmployeeNo=@InputScan
		    IF ISNULL(@EmployeeNo,'')=''
			BEGIN
				SELECT '' AS InputScan
				SET @I_ReturnMessage='ServerMessage:[员工工号]未维护，请重新扫描' +@Enter
				RETURN 0
			END
			SELECT '' AS InputScan,@EmployeeNo AS EmployeeNo,'请扫描[设备编号]!' AS Tips
			SET @I_ReturnMessage='ServerMessage:[员工工号]已扫描' +@Enter
			RETURN @RESULT
		END

		IF ISNULL(@EquipmentNo,'')=''
		BEGIN
		    SELECT @EquipmentNo=EquipmentNumber,@GZUnloadingTime=GZUnloadingTime,@GZLoadingDate=GZLoadingDate FROM Equipment WHERE IsAvalid=1 AND EquipmentNumber=@InputScan
			IF ISNULL(@EquipmentNo,'')=''
			BEGIN
				SELECT '' AS InputScan
				SET @I_ReturnMessage='ServerMessage:[设备编号]未维护，请重新扫描' +@Enter
				RETURN 0
			END
			
			--SELECT '' AS InputScan,@EquipmentNo AS EquipmentNo,'请扫描[规程代码]!' AS Tips
			SET @I_ReturnMessage='ServerMessage:[设备编号]已扫描' +@Enter

			--锆珠使用时间是否已达标
			IF @GZLoadingDate IS NOT NULL AND ISNULL(@GZUnloadingTime,0)>0
			BEGIN
				SET @GZUsedTime = DATEDIFF(MINUTE,@GZLoadingDate,GETDATE())
				IF @GZUsedTime>ISNULL(@GZUnloadingTime,0)
				BEGIN
					SET @I_ReturnMessage='ServerMessage:[设备编号]已扫描，设备['+@InputScan+']锆珠当前使用时间['+CAST(@GZUsedTime AS VARCHAR(20))+']分钟，已超出标准时间['+CAST(ISNULL(@GZUnloadingTime,0) AS VARCHAR(20))+']分钟，请及时扫描更换锆珠指令并更换锆珠' +@Enter
				END
			END
			----------------------------------------20260130 mwj扫描设备号回显批号等数据START------------------------------------------------------------
            SELECT @EquipmentId=EquipmentId FROM Equipment WHERE EquipmentNumber=@EquipmentNo

            SELECT top 1 @LotSN=LOTSN,@SpecificationId=SpecificationId ,@ProductionGrindId=ProductionGrindId FROM ProductionGrind 
            WHERE (EquipmentId=@EquipmentId OR ISNULL(Equipment2Id,'')=@EquipmentId) 
            AND IsComplete=0
            order by CreateDate desc
            --当前设备有在制工单则回显
            IF  ISNULL(@LotSN,'') <>''
            BEGIN
                --获取规程代码
                select @SpecificationCode=SpecificationCode 
                FROM SpecificationRoot 
                LEFT JOIN  Specification ON Specification.SpecificationRootId = SpecificationRoot.SpecificationRootId
                WHERE Specification.SpecificationID=@SpecificationId

                --获取批号信息
                IF @SpecificationCode IN('GL','GL+','GL-')
                BEGIN
                    SELECT 
                        @ProductDescription=P.ProductDescription, 
                        @LotQty=L.Qty, 
                        @MOId=L.MOId, 
                        @ProcessCategory='['+P.FiltrationProcess+']['+P.FiltrationProcess1+']'
                    FROM Lot L 
                    INNER JOIN Product P ON L.ProductId=P.ProductId 
                    WHERE L.LotSN=@LotSN
                END

                --获取投料批次的状态
                SELECT TOP 1 @QualityMark=[dbo].[FormatQualityMark](QualityMark)
                FROM (SELECT (CASE D.QualityMark 
                        WHEN 'G' THEN 1
                        WHEN 'Y' THEN 1
                        WHEN 'YG' THEN 2
                        WHEN 'YB' THEN 3
                        WHEN 'R' THEN 1
                        WHEN 'RG' THEN 2
                        WHEN 'RB' THEN 3
                        WHEN 'Q' THEN 1
                        WHEN 'NQ' THEN 2 END) AS QualityLevel,D.QualityMark FROM LoadingItemLotRecord A
                INNER JOIN LoadingItemLotDetail B ON A.LoadingItemLotDetailId=B.LoadingItemLotDetailId
                INNER JOIN LoadingItemLot C ON B.LoadingItemLotId=C.LoadingItemLotId
                INNER JOIN Lot D ON A.LotSN=D.LotSN
                WHERE C.MOId=@MOId AND ISNULL(D.QualityMark,'')<>'') T ORDER BY QualityLevel DESC

                SET @Tips='请扫描指令进行操作'

                SELECT @WorkflowId=WorkflowId FROM Lot WHERE LotSN=@LotSN

                SELECT @StartQty=StartQty,@StartTime=StartTime,@FilterE1=FilterE1,@FilterE2=FilterE2,@FilterE3=FilterE3 FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId

                SELECT @SpecificationCode AS SpecificationCode,@EquipmentNo AS EquipmentNo,
                        0 AS InputNumber,@LotSN AS Lotsn,'' AS InputScan,@ProductionGrindId AS ProductionGrindId,@Tips AS Tips,
                        @ProductDescription AS ProductDescription,@LotQty AS LotQty,@QualityMark AS QualityMark,@ProcessCategory AS ProcessCategory,@FilterRemark AS FilterRemark

                SET @I_ReturnMessage='ServerMessage:[批次条码]已扫描，请根据工艺提示进行操作' +@Enter
            END
            ELSE
            BEGIN
                SELECT '' AS InputScan,@EquipmentNo AS EquipmentNo,'请扫描[规程代码]!' AS Tips
            END
            ----------------------------------------扫描设备号回显批号等数据END------------------------------------------------------------
            
			
			RETURN @RESULT
		END

		IF ISNULL(@SpecificationCode,'')=''
		BEGIN
			DECLARE @IsGrind BIT
			SELECT @IsGrind=B.IsGrind,@SpecificationCode=A.SpecificationCode FROM SpecificationRoot A INNER JOIN Specification B ON A.SpecificationRootId=B.SpecificationRootId WHERE A.SpecificationCode=@InputScan

			IF ISNULL(@SpecificationCode,'')=''
			BEGIN
				SELECT '' AS InputScan
				SET @I_ReturnMessage='ServerMessage:[规程代码]不存在，请重新扫描' +@Enter
				RETURN 0
			END

			IF @IsGrind <> 1
			BEGIN
				SELECT '' AS InputScan
				SET @I_ReturnMessage='ServerMessage:[规程代码]不是研磨工艺，请重新扫描' +@Enter
				RETURN 0
			END

			SELECT @FilterE1=ISNULL(FilterE1,0),@FilterE2=ISNULL(FilterE2,0),@FilterE3=ISNULL(FilterE3,0),@FilterType=ISNULL(FilterType,'') FROM Equipment WHERE IsAvalid=1 AND EquipmentNumber=@EquipmentNo

			IF @SpecificationCode='GL+'
			BEGIN
				SET @FilterRemark=N'滤芯0.5['+CAST(@FilterE1 AS NVARCHAR(5))+N']次;滤芯1.0['+CAST(@FilterE2  AS NVARCHAR(5))+']次;滤芯3.0['+CAST(@FilterE3  AS NVARCHAR(5))+']次;['+@FilterType+']';
			END
			IF @SpecificationCode='GL-'
			BEGIN
				SELECT @FilterMQty=SUM(PartsQty) FROM PGUseParts WHERE ProductionGrindId=@ProductionGrindId AND PartsCategory='滤膜'
				SET @FilterRemark=N'已使用滤膜['+CAST(@FilterMQty AS NVARCHAR(10))+']张'
			END

			SELECT '' AS InputScan,@SpecificationCode AS SpecificationCode,'请扫描[批次条码]!' AS Tips,@FilterRemark AS FilterRemark
			SET @I_ReturnMessage='ServerMessage:[规程代码]已扫描' +@Enter
			RETURN @RESULT
		END

		IF ISNULL(@LotSN,'')=''
		BEGIN
			IF NOT EXISTS(SELECT 1 FROM MOItemLot WHERE LotSN=@InputScan)
			BEGIN
				SELECT '' AS InputScan
				SET @I_ReturnMessage='ServerMessage:[批次条码]不正确，请重新扫描' +@Enter
				RETURN 0
			END

			--获取研磨标识，如果是首次进行研磨，需要记录上机前重量
			EXEC @RESULT=[dbo].[PDA_PGrindGetID]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@EmployeeNo=@EmployeeNo,
			@EquipmentNo=@EquipmentNo,
			@SpecificationCode=@SpecificationCode,
			@LotSN=@InputScan,
			@LotQty=@WeighQty,
			@ProductionGrindId=@ProductionGrindId OUTPUT

			IF @RESULT=-2
			BEGIN
				SELECT @InputNumber=CAST(Qty AS VARCHAR(19)) FROM MOItemLot WHERE LotSN=@InputScan
				SET @I_ExceptionFieldName='InputNumber'
				SELECT @InputNumber AS InputNumber,'CMDWEIGH' AS Command,'首次下料请记录吨桶重量!' AS Tips
				RETURN 0
			END

			IF @RESULT=-1
			BEGIN
				SELECT 0 AS InputNumber,'' AS InputScan
				RETURN @RESULT
			END

			--获取批号信息
			IF @SpecificationCode IN('GL','GL+','GL-')
			BEGIN
				SELECT 
					@ProductDescription=P.ProductDescription, 
					@LotQty=L.Qty, 
					@MOId=L.MOId, 
					@ProcessCategory='['+P.FiltrationProcess+']['+P.FiltrationProcess1+']'
				FROM Lot L 
				INNER JOIN Product P ON L.ProductId=P.ProductId 
				WHERE L.LotSN=@InputScan
			END

			--获取投料批次的状态
			SELECT TOP 1 @QualityMark=[dbo].[FormatQualityMark](QualityMark)
			FROM (SELECT (CASE D.QualityMark 
					WHEN 'G' THEN 1
					WHEN 'Y' THEN 1
					WHEN 'YG' THEN 2
					WHEN 'YB' THEN 3
					WHEN 'R' THEN 1
					WHEN 'RG' THEN 2
					WHEN 'RB' THEN 3
					WHEN 'Q' THEN 1
					WHEN 'NQ' THEN 2 END) AS QualityLevel,D.QualityMark FROM LoadingItemLotRecord A
			INNER JOIN LoadingItemLotDetail B ON A.LoadingItemLotDetailId=B.LoadingItemLotDetailId
			INNER JOIN LoadingItemLot C ON B.LoadingItemLotId=C.LoadingItemLotId
			INNER JOIN Lot D ON A.LotSN=D.LotSN
			WHERE C.MOId=@MOId AND ISNULL(D.QualityMark,'')<>'') T ORDER BY QualityLevel DESC

			IF @RESULT=1
			BEGIN
				SELECT 0 AS InputNumber,@InputScan AS LotSN,'' AS InputScan,@ProductionGrindId AS ProductionGrindId,@I_ReturnMessage AS Tips,
					@ProductDescription AS ProductDescription,@WeighQty AS LotQty,@QualityMark AS QualityMark,@ProcessCategory AS ProcessCategory
				SET @I_ReturnMessage=''
				RETURN 0
			END

			SET @Tips='请扫描指令进行操作'

			SELECT @WorkflowId=WorkflowId FROM Lot WHERE LotSN=@LotSN

			SELECT @StartQty=StartQty,@StartTime=StartTime,@FilterE1=FilterE1,@FilterE2=FilterE2,@FilterE3=FilterE3 FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId

			IF @SpecificationCode ='LX' AND @WorkflowId IN('WKF1000000YQ','WKF1000000YR')
			BEGIN
				SET @MixingTime=[dbo].[MixingTime]('XS',@StartQty,@StartTime)

				IF @MixingTime>0
				BEGIN
					SET @Tips='离心工艺搅拌时间剩余['+CAST(@MixingTime AS NVARCHAR(19))+']秒!'
				END
			END

			IF @SpecificationCode='GL+'
			BEGIN
				SET @FilterRemark=N'滤芯0.5['+CAST(@FilterE1 AS NVARCHAR(5))+N']次;滤芯1.0['+CAST(@FilterE2  AS NVARCHAR(5))+']次;滤芯3.0['+CAST(@FilterE3  AS NVARCHAR(5))+']次';
			END
			IF @SpecificationCode='GL-'
			BEGIN
				SELECT @FilterMQty=SUM(PartsQty) FROM PGUseParts WHERE ProductionGrindId=@ProductionGrindId AND PartsCategory='滤膜'
				SET @FilterRemark=N'已使用滤膜['+CAST(@FilterMQty AS NVARCHAR(10))+']张'
			END

			SELECT 0 AS InputNumber,@InputScan AS LotSN,'' AS InputScan,@ProductionGrindId AS ProductionGrindId,@Tips AS Tips,
					@ProductDescription AS ProductDescription,@WeighQty AS LotQty,@QualityMark AS QualityMark,@ProcessCategory AS ProcessCategory,@FilterRemark AS FilterRemark

			SET @I_ReturnMessage='ServerMessage:[批次条码]已扫描，请根据工艺提示进行操作' +@Enter
			RETURN @RESULT
		END

		IF @Command='CMDADDEMPLOYEE'--当前指令为添加人员
		BEGIN
			--判定员工工号
			IF ISNULL(@InputScan,'')='' RETURN

			SELECT TOP 1 @EmployeeId=UserId FROM SysUser WHERE EmployeeNo=@InputScan
			IF ISNULL(@EmployeeId,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:员工工号【'+@InputScan+'】不存在，请维护!'+@Enter
				RETURN -1
			END

			IF EXISTS(SELECT 1 FROM [dbo].[Operator] WHERE RefId=@ProductionGrindId AND EmployeeId=@EmployeeId)
			BEGIN
				SET @I_ReturnMessage='ServerMessage:员工工号【'+@InputScan+'】已添加，请不要重复添加!'+@Enter
				RETURN -1
			END

			DECLARE @OperatorId IDType
			EXEC SysGetObjectPKId '','Operator',@OperatorId OUTPUT
			--添加上料员工
			INSERT INTO [dbo].[Operator]
					   ([OperatorId]
					   ,[RefId]
					   ,[EmployeeId])
				 VALUES
					   (@OperatorId
					   ,@ProductionGrindId
					   ,@EmployeeId)

			SET @I_ReturnMessage='ServerMessage:员工工号['+@InputScan+']已添加为当前工序生产员工！' +@Enter
			SELECT '' AS Command,0 as InputNumber,'请扫描操作指令' AS Tips
			RETURN 0
		END

		IF @Command ='CMDFAULT'--当前指令为发生故障
		BEGIN
			--判断故障代码是否存在
			IF ISNULL(@InputScan,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:故障代码不能为空' +@Enter
				RETURN 0
			END
			DECLARE @PGFaultId IDType=''
			DECLARE @FaultCodeId IDType=''

			SELECT TOP 1 @FaultCodeId=FaultCodeId FROM FaultCode WHERE FaultCode=@InputScan AND IsActivation=1
			IF ISNULL(@FaultCodeId,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:故障代码['+@InputScan+']不存在，请重新输入' +@Enter
				RETURN 0
			END

			EXEC SysGetObjectPKId '','PGFault',@PGFaultId OUTPUT
			INSERT INTO [dbo].[PGFault]
					   ([PGFaultId]
					   ,[ProductionGrindId]
					   ,[FaultCodeId])
				 VALUES
					   (@PGFaultId
					   ,@ProductionGrindId
					   ,@FaultCodeId)
			SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'请扫描操作指令' AS Tips
			SET @I_ReturnMessage='ServerMessage:已记入故障记录' +@Enter
			RETURN 0
		END

		IF @Command ='CMDFILTERELEMENT'--使用过滤器
		BEGIN
			--判断过滤器是否维护设备
			DECLARE @FilterElementId IDType
			SELECT @FilterElementId=FilterElementId FROM FilterElement WHERE FilterElementNo=@InputScan
			IF ISNULL(@FilterElementId,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:过滤器['+@InputScan+']不存在，请扫描有效的条码' +@Enter
				RETURN 0
			END

			IF ISNULL(@ProductionGrindId,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:请扫描批号开始过滤工艺' +@Enter
				RETURN 0
			END

			DECLARE @PartsType VARCHAR(16)
			IF EXISTS(SELECT 1 FROM PGUseParts WHERE PartsId=@FilterElementId) SET @PartsType='OLD'
			ELSE SET @PartsType='NEW'

			EXEC SysGetObjectPKId '','PGUseParts',@PGUsePartsId OUTPUT
			INSERT INTO [dbo].[PGUseParts]
					   ([PGUsePartsId]
					   ,[ProductionGrindId]
					   ,[PartsId]
					   ,[PartsType])
				 VALUES
					   (@PGUsePartsId
					   ,@ProductionGrindId
					   ,@FilterElementId
					   ,@PartsType)
			--修改使用次数
			UPDATE FilterElement SET UsageCounter+=1,LastUsedDate=GETDATE() WHERE FilterElementId=@FilterElementId

			SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'请扫描操作指令' AS Tips
			SET @I_ReturnMessage='ServerMessage:过滤器使用成功' +@Enter
			RETURN 0
		END

		/************************************************* 生产中拆批提前下线处理 ********************************************************/
		--IF @Command IN('CMDLOTMOVEG','CMDLOTMOVER','CMDLOTMOVEY','CMDLOTMOVE')--批次下线,绿标/红标/黄标/未判定
		--BEGIN
		--	IF ISNULL(@InputScan,'')=''
		--	BEGIN
		--		SET @I_ReturnMessage='ServerMessage:请扫描批号条码' +@Enter
		--		RETURN 0
		--	END

		--	IF ISNULL(@ProductionGrindId,'')=''
		--	BEGIN
		--		SET @I_ReturnMessage='ServerMessage:请先扫描批号开始生产' +@Enter
		--		RETURN 0
		--	END

		--	IF NOT EXISTS(SELECT 1 FROM MOItemLot WHERE LotSN=@InputScan)
		--	BEGIN
		--	    SET @I_ReturnMessage='ServerMessage:批号条码错误' +@Enter
		--		SELECT '' AS InputScan
		--		RETURN 0
		--	END
		--	SELECT @StartQty=Qty FROM Lot WHERE LotSN=@InputScan

		--	SET @I_ExceptionFieldName='InputNumber'
		--	SELECT @StartQty AS InputNumber,'请录入重量!' AS Tips
		--	RETURN 0
		--END
		/************************************************* 生产中拆批提前下线处理 ********************************************************/

		SET @I_ReturnMessage='ServerMessage:不可识别的操作指令' +@Enter
		RETURN 0
	END

	IF @I_Sender='InputNumberDefocus'
	BEGIN
		SET @I_ExceptionFieldName='InputScan'

		--工艺参数录入
		IF @Command IN ('CMDTEMPER','CMDPRESSE','CMDPSPEED','CMDSPEED','CMDSSCALE','CMDCURREN','CMDMWATER')
		BEGIN
			EXEC @RESULT=[dbo].[PDA_AddPGrindParams]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@ProductionGrindId=@ProductionGrindId,
			@SpecificationCode=@SpecificationCode,
			@ParamsType=@Command,
			@ParamsValue=@WeighQty

			SELECT '' AS Command,0 as InputNumber,'请扫描操作指令' AS Tips
			RETURN @RESULT
		END

		IF @Command='CMDWEIGH'--上机称重
		BEGIN
			EXEC @RESULT=[dbo].[PDA_PGrindGetID]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@EmployeeNo=@EmployeeNo,
			@EquipmentNo=@EquipmentNo,
			@SpecificationCode=@SpecificationCode,
			@LotSN=@InputScan,
			@LotQty=@WeighQty,
			@ProductionGrindId=@ProductionGrindId OUTPUT

			--获取批号信息
			IF @SpecificationCode IN('GL','GL+','GL-')
			BEGIN
				SELECT 
					@ProductDescription=P.ProductDescription, 
					@LotQty=L.Qty, 
					@MOId=L.MOId, 
					@ProcessCategory='['+P.FiltrationProcess+']['+P.FiltrationProcess1+']'
				FROM Lot L 
				INNER JOIN Product P ON L.ProductId=P.ProductId 
				WHERE L.LotSN=@InputScan
			END

			--获取投料批次的状态
			SELECT TOP 1 @QualityMark=[dbo].[FormatQualityMark](QualityMark)
			FROM (SELECT (CASE D.QualityMark 
					WHEN 'G' THEN 1
					WHEN 'Y' THEN 1
					WHEN 'YG' THEN 2
					WHEN 'YB' THEN 3
					WHEN 'R' THEN 1
					WHEN 'RG' THEN 2
					WHEN 'RB' THEN 3
					WHEN 'Q' THEN 1
					WHEN 'NQ' THEN 2
					ELSE 0 END) AS QualityLevel,D.QualityMark FROM LoadingItemLotRecord A
			INNER JOIN LoadingItemLotDetail B ON A.LoadingItemLotDetailId=B.LoadingItemLotDetailId
			INNER JOIN LoadingItemLot C ON B.LoadingItemLotId=C.LoadingItemLotId
			INNER JOIN Lot D ON A.LotSN=D.LotSN
			WHERE C.MOId=@MOId AND ISNULL(D.QualityMark,'')<>'') T ORDER BY QualityLevel DESC

			IF @RESULT=1
			BEGIN
				SELECT 0 AS InputNumber,@InputScan AS LotSN,'' AS InputScan,@ProductionGrindId AS ProductionGrindId,@I_ReturnMessage AS Tips,
				@ProductDescription AS ProductDescription,@WeighQty AS LotQty,@QualityMark AS QualityMark,@ProcessCategory AS ProcessCategory
				SET @I_ReturnMessage=''
				RETURN 0
			END

			IF @RESULT<>0 RETURN @RESULT

			SET @Tips='请扫描指令进行操作'

			SELECT @WorkflowId=WorkflowId FROM Lot WHERE LotSN=@LotSN

			SELECT @StartQty=StartQty,@StartTime=StartTime,@FilterE1=FilterE1,@FilterE2=FilterE2,@FilterE3=FilterE3 FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId

			IF @SpecificationCode ='LX' AND @WorkflowId IN('WKF1000000YQ','WKF1000000YR')
			BEGIN
				SET @MixingTime=[dbo].[MixingTime]('XS',@StartQty,@StartTime)

				IF @MixingTime>0
				BEGIN
					SET @Tips='离心工艺搅拌时间剩余['+CAST(@MixingTime AS NVARCHAR(19))+']秒!'
				END
			END
			
			IF @SpecificationCode='GL+'
			BEGIN
				SET @FilterRemark=N'滤芯0.5['+CAST(@FilterE1 AS NVARCHAR(5))+N']次;滤芯1.0['+CAST(@FilterE2  AS NVARCHAR(5))+']次;滤芯3.0['+CAST(@FilterE3  AS NVARCHAR(5))+']次';
			END
			IF @SpecificationCode='GL-'
			BEGIN
				SELECT @FilterMQty=SUM(PartsQty) FROM PGUseParts WHERE ProductionGrindId=@ProductionGrindId AND PartsCategory='滤膜'
				SET @FilterRemark=N'已使用滤膜['+CAST(@FilterMQty AS NVARCHAR(10))+']张'
			END
			
			SELECT 0 AS InputNumber,@InputScan AS LotSN,'' AS InputScan,@ProductionGrindId AS ProductionGrindId,'' AS Command,@Tips AS Tips,
			@ProductDescription AS ProductDescription,@WeighQty AS LotQty,@QualityMark AS QualityMark,@ProcessCategory AS ProcessCategory,@FilterRemark AS FilterRemark
			SET @I_ReturnMessage='ServerMessage:上机称重完成，请根据工艺提示进行操作' +@Enter
			RETURN @RESULT
		END

		--批次过站
		IF @Command IN('CMDLOTMOVEG','CMDLOTMOVER','CMDLOTMOVEY','CMDLOTMOVE')
		BEGIN

			IF ISNULL(@ProductionGrindId,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:请先扫描批号开始生产' +@Enter
				RETURN 0
			END

			IF @WeighQty<=0
			BEGIN
				SET @I_ReturnMessage='ServerMessage:重量必须大于0' +@Enter
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END

			IF ISNULL(@LotSN,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:请扫描批号条码' +@Enter
				RETURN 0
			END

			IF NOT EXISTS(SELECT 1 FROM MOItemLot WHERE LotSN=@LotSN)
			BEGIN
			    SET @I_ReturnMessage='ServerMessage:批号条码['+@LotSN+']错误' +@Enter
				SELECT 0 AS InputNumber
				RETURN 0
			END

			DECLARE @IsComplete BIT = 0
			DECLARE @SampFlag BIT = 0
			DECLARE @MaxSampFlag BIT = 0
			DECLARE @PGSpecificationId IDType
			DECLARE @FilteFunction SysNumberType
			DECLARE @PGFilteFunction SysNumberType
			DECLARE @FilterTechnologyId IDType
			DECLARE @IsPressN BIT
			DECLARE @MaxPressN INT
			

			SELECT TOP 1 
				@IsComplete=IsComplete,
				@SampFlag=SampFlag,
				@MaxSampFlag=MaxSampFlag,
				@CurrentCount=CurrentCount,
				@PGSpecificationId=SpecificationId,
				@FilterTechnologyId=FilterTechnologyId,
				@StartTime=StartTime,
				@StartQty=StartQty,
				@EquipmentId=EquipmentId 
			FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId

			IF @IsComplete<>0
			BEGIN
				SET @I_ReturnMessage='ServerMessage:本次研磨已完成，无需重复执行' +@Enter
				SELECT 0 AS InputNumber,'' AS Command
				RETURN 0
			END

			/************************************************* 生产中拆批提前下线处理 ********************************************************/
			--IF ISNULL(@InputScan,'')<>'' AND @LotSN<>@InputScan
			--BEGIN
			--	IF NOT EXISTS(SELECT 1 FROM Lot WHERE LotSN=@InputScan)
			--	BEGIN
			--		SET @I_ReturnMessage='ServerMessage:批号条码['+@InputScan+']错误' +@Enter
			--		SET @I_ExceptionFieldName='InputScan'
			--		SELECT '' AS InputScan
			--		RETURN 0
			--	END

			--	SELECT @LotId=LotId FROM Lot WHERE LotSN=@LotSN
			--	IF NOT EXISTS(SELECT 1 FROM Lot WHERE ParentLotId=@LotId AND LotSN=@InputScan AND CreateDate>@StartTime)
			--	BEGIN
			--		SET @I_ReturnMessage='ServerMessage:批号条码['+@InputScan+']不是在当前生产过程中拆分，无法通过此方法移送' +@Enter
			--		SET @I_ExceptionFieldName='InputScan'
			--		SELECT '' AS InputScan,0 AS InputNumber,'请扫描生产批次!' AS Tips
			--		RETURN 0
			--	END

			--	SET @LotSN=@InputScan;
			--END
			/************************************************* 生产中拆批提前下线处理 ********************************************************/


			SELECT @SampingQty=SUM(SampingQty) FROM PGSamping WHERE ProductionGrindId=@ProductionGrindId
            SELECT @LossQty=SUM(LossQty) FROM PGLoss WHERE ProductionGrindId=@ProductionGrindId

			SELECT @LotQty=Qty FROM Lot WHERE LotSN=@LotSN

			SET @LotQty=@LotQty-ISNULL(@SampingQty,0)-ISNULL(@LossQty,0)
			IF ABS(@LotQty-@WeighQty)>@LotQty*0.1
			BEGIN
				SET @I_ReturnMessage='ServerMessage:输入重量不能大于或小于总重量的10%，总重量为['+CAST(@StartQty AS VARCHAR(19))+']' +@Enter
				SELECT 0 AS InputNumber
				RETURN 0
			END

			IF NOT EXISTS(SELECT 1 FROM Lot A
			INNER JOIN Specification B ON A.SpecificationId=B.SpecificationId
			INNER JOIN SpecificationRoot C ON B.SpecificationRootId=C.SpecificationRootId
			WHERE ((@SpecificationCode NOT IN('GL+') AND C.SpecificationCode=@SpecificationCode)
			OR (@SpecificationCode IN('GL+') AND C.SpecificationCode='GL+')) AND A.LotSN=@LotSN)
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'批号['+@LotSN+']不在当前工序节点，请检查!' AS Tips
				SET @I_ExceptionFieldName='InputScan'
				SET @I_ReturnMessage='ServerMessage:批号['+@LotSN+']不在当前工序节点，请检查！' +@Enter
				RETURN -1
			END

			--是否有未完成的检验单
			--IF @SpecificationCode ='GL'
			--BEGIN
			--	IF EXISTS(SELECT 1 FROM QC_ProcessIns_SubLot A
			--	INNER JOIN QC_ProcessIns B ON A.QC_ProcessInsId=B.QC_ProcessInsId
			--	WHERE A.LotSN=@LotSN AND B.InsStates<>'20' AND B.SubmissCategory='TE')
			--	BEGIN
			--		SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'请等待品保完成检验!' AS Tips
			--		SET @I_ExceptionFieldName='InputScan'
			--		SET @I_ReturnMessage='ServerMessage:检测到还有未完成的检验单，请先完成检验！' +@Enter
			--		RETURN -1
			--	END
			--END

			IF EXISTS(SELECT 1 FROM PGFilter WHERE ProductionGrindId=@ProductionGrindId AND FilterType='正压' AND StopTime IS NULL)
			BEGIN
				SET @I_ReturnMessage='ServerMessage:正压过滤未结束，请先结束正压过滤' +@Enter
				SELECT 0 AS InputNumber
				RETURN 0
			END

			IF EXISTS(SELECT 1 FROM PGFilter WHERE ProductionGrindId=@ProductionGrindId AND FilterType='负压' AND StopTime IS NULL)
			BEGIN
				SET @I_ReturnMessage='ServerMessage:负压过滤未结束，请先结束负压过滤' +@Enter
				SELECT 0 AS InputNumber
				RETURN 0
			END

			IF @SpecificationCode ='GL-'
			BEGIN
				IF EXISTS(SELECT 1 FROM ProductionGrind A INNER JOIN Specification B ON A.SpecificationId=B.SpecificationId
				INNER JOIN SpecificationRoot C ON B.SpecificationRootId=C.SpecificationRootId WHERE C.SpecificationCode ='GL+' AND LotSN=@LotSN AND IsComplete=0)
				BEGIN
					SET @I_ReturnMessage='ServerMessage:正压过滤未执行完工操作，请先结束正压过滤' +@Enter
					SELECT 0 AS InputNumber
					RETURN 0
				END
			END

			--计算锆珠使用时间
			SELECT @GZLoadingDate=GZLoadingDate FROM Equipment WHERE EquipmentId=@EquipmentId
			IF @GZLoadingDate IS NOT NULL
			BEGIN
				SET @GZUsedTime=DATEDIFF(SECOND,@GZLoadingDate,GETDATE())
			END

			--标准过滤性能值
			SELECT @FilteFunction=ISNULL(FilteFunction,0),@IsPressN=IsPressN,@MaxPressN=MaxPressN FROM FilterTechnology WHERE FilterTechnologyId=@FilterTechnologyId

			--当前最后一次录入过滤性能值
			SELECT TOP 1 @PGFilteFunction=ISNULL(ParamsValue,0) FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId AND ParamsType='CMDMWATER' ORDER BY CurrentCount DESC

			SET @PGFilteFunction=ISNULL(@PGFilteFunction,0)
			--只有精磨有此判断
			IF @SpecificationCode IN ('Grind-JM','BYM') AND ISNULL(@IsPressN,0)=0
			BEGIN
				--未出现异常不可以提前结束
				IF NOT EXISTS(SELECT 1 FROM PGFault WHERE ProductionGrindId=@ProductionGrindId)
				BEGIN
					IF @SampFlag<>1 AND @Command ='CMDLOTMOVEG'
					BEGIN
						SET @I_ReturnMessage='ServerMessage:本次研磨未达合格点，不能绿标结束工序' +@Enter
						SELECT 0 AS InputNumber
						RETURN 0
					END

			--		--判定是否是绿标
			--		--IF @SampFlag=1 AND @MaxSampFlag<>1 AND @Command <>'CMDLOTMOVEG'
			--		--BEGIN
			--		--	SET @I_ReturnMessage='ServerMessage:未达最大取样点之前，只能是绿标结束' +@Enter
			--		--	SELECT 0 AS InputNumber
			--		--	RETURN 0
			--		--END
				END
			END

			IF @SpecificationCode IN ('BYM','UVPULPYM') AND ISNULL(@IsPressN,0)=1
			BEGIN
				--判定过滤性能是否达标
				IF @PGFilteFunction<@FilteFunction AND @CurrentCount<@MaxPressN
				BEGIN
					SET @I_ReturnMessage='ServerMessage:未达研磨上限之前，必须等待过滤性能达标后才能结束' +@Enter
					SELECT 0 AS InputNumber
					RETURN 0
				END
			END

			IF ISNULL(@SpecificationCode,'') ='Grind-JM' AND @Command NOT IN('CMDLOTMOVEG','CMDLOTMOVER','CMDLOTMOVEY')
			BEGIN
				SET @I_ReturnMessage='ServerMessage:当前工序为精磨，请扫描绿标、黄标或红标!'
				RETURN -1
			END

			--获取资源对应的工作中心
			--select 
			--	@WorkcenterId=WorkcenterId
			--from dbo.Resource 
			--where Resource.ResourceId=@I_ResourceId

			SELECT TOP 1 @WorkcenterId=WorkcenterId FROM Equipment WHERE EquipmentNumber=@EquipmentNo

			--if isnull(@WorkcenterId,'')=''
			--BEGIN
			--	set @I_ReturnMessage='ServerMessage:设备['+@EquipmentNo+']未维护工作中心，请检查!'
			--	SELECT 0 AS InputNumber
			--	return -1
			--end

			IF ISNULL(@JudgingDepartment,'')='' AND ((@Command <>'CMDLOTMOVEG' AND ISNULL(@SpecificationCode,'') ='Grind-JM') 
			OR (ISNULL(@SpecificationCode,'') = 'UVPULPYM' AND @PGFilteFunction<@FilteFunction))
			BEGIN
				SET @I_ReturnMessage='ServerMessage:请选择判定部门!'
				RETURN -1
			END

			--批次品质标志
			SET @QualityMark=(CASE @Command 
			WHEN 'CMDLOTMOVEG' THEN 'G' 
			WHEN 'CMDLOTMOVER' THEN 'R' 
			WHEN 'CMDLOTMOVEY' THEN 'Y'
			ELSE '' END)

			IF @SpecificationCode IN ('BYM','UVPULPYM') AND @Command='CMDLOTMOVE'
			BEGIN
				SET @QualityMark=(CASE WHEN @PGFilteFunction>=@FilteFunction THEN 'Q' ELSE 'NQ' END)
			END

			SELECT @LotId=LotId,@MOId=MOId,@MOProductId=ProductId,@SpecificationId=@SpecificationId,@WorkflowStepId=WorkflowStepId FROM Lot WHERE LotId=@LotId

			DECLARE @ToSpecificationId IDType=''

			IF ISNULL(@SpecificationCode,'')='Grind-JM'
			BEGIN
				SELECT @ToSpecificationId=S.SpecificationId FROM Specification S INNER JOIN SpecificationRoot SR ON S.SpecificationRootId=SR.SpecificationRootId
				WHERE SR.SpecificationCode=(CASE ISNULL(@JudgingDepartment,'') WHEN '品保判定' THEN 'LJDMP' WHEN '研发判定' THEN 'LJDMY' ELSE '' END)
			END

			IF ISNULL(@SpecificationCode,'')='UVPULPYM'
			BEGIN
				SELECT @ToSpecificationId=S.SpecificationId FROM Specification S INNER JOIN SpecificationRoot SR ON S.SpecificationRootId=SR.SpecificationRootId
				WHERE SR.SpecificationCode=(CASE ISNULL(@JudgingDepartment,'') WHEN '品保判定' THEN 'UVPULPJP' WHEN '研发判定' THEN 'UVPULPJY' ELSE '' END)
			END

			BEGIN TRANSACTION GRINDMOVE

			--修改物料批号数量
			UPDATE MOItemLot SET Qty=@WeighQty WHERE LotSN=@LotSN
			--修改批次数量
			UPDATE Lot SET Qty=@WeighQty,QualityMark=ISNULL(@QualityMark,QualityMark) WHERE LotSN=@LotSN

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

			--记录批次损耗/修改完成状态
			IF EXISTS(SELECT 1 FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId AND IsComplete=0 AND LotSN=@LotSN)
			BEGIN
				UPDATE ProductionGrind SET MoveFlag=@QualityMark,IsComplete=1,EndQty=@WeighQty,DataChainId=@DataChainId ,
				ToSpecificationId=ISNULL(@ToSpecificationId,''),EndTime=GETDATE(),GZUsedTime=@GZUsedTime
				WHERE ProductionGrindId=@ProductionGrindId AND IsComplete=0
			END

			IF @SpecificationCode <>'GL'
			BEGIN
				----传送 LotSN 到工作流下一节点
				EXEC @RESULT= [dbo].[TxnBase_LotMove] 
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@LotSN=@LotSN,
				@LotInDate=@CurDate	
			END
			
			IF @@ERROR<>0
				ROLLBACK TRANSACTION GRINDMOVE
			ELSE 
				COMMIT TRANSACTION GRINDMOVE


			--作业报工
			IF @SpecificationCode  IN('GL+') AND NOT EXISTS(SELECT 1 FROM dbo.UploadIng WHERE UploadDateId=@MOId AND Line='20')
			AND EXISTS(SELECT 1 FROM MoCraftPath WHERE MoId=@MOId AND WorkstageNO='20')
			BEGIN
				EXEC [dbo].[MOProductionOrder]
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@MOID=@MOId,
				@Line='20',
				@Qty=@WeighQty
			END


			IF NOT EXISTS(SELECT 1 FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId AND IsComplete=0 AND LotSN=@LotSN)
			BEGIN
				SET @I_ReturnMessage='ServerMessage:批号条码['+@LotSN+']已完成当前工序，已自动重置' +@Enter
				SELECT '' AS EmployeeNo,'' AS EquipmentNo,'' AS SpecificationCode,
					'' AS InputScan,0 AS InputNumber,'' AS LotSN,
					'' AS ProductionGrindId,'' AS Command,'请扫描[员工工号]!' AS Tips,
					'' AS ProductDescription,'' AS LotQty,'' AS QualityMark,'' AS ProcessCategory,'' AS FilterRemark
				RETURN @RESULT
			END

			ELSE
			BEGIN
				SET @I_ReturnMessage='ServerMessage:批号条码['+@LotSN+']已完成当前工序' +@Enter
				SELECT 
					'' AS InputScan,0 AS InputNumber,
					'' AS Command,'请扫描操作指令!' AS Tips
				RETURN @RESULT
			END
		END

		IF @Command ='CMDSAMPLING'--取样
		BEGIN
			--取样数量判断
			IF @WeighQty<=0
			BEGIN
				SET @I_ReturnMessage='ServerMessage:本次取样数量必须大于0!'+@Enter
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END

			DECLARE @PGSampingId IDType=''
			
			SELECT TOP 1 @StartQty=ISNULL(StartQty,0),@CurrentCount=ISNULL(CurrentCount,0) FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId
			SELECT @SampingQty=ISNULL(SUM(SampingQty),0) FROM PGSamping WHERE ProductionGrindId=@ProductionGrindId

			IF @StartQty<@WeighQty+@SampingQty
			BEGIN
				SET @I_ReturnMessage='ServerMessage:本次取样数量['+@InputNumber+']与累计取样数量['+CAST(@SampingQty AS VARCHAR(19))+']不能大于正在加工产品数量!'+@Enter
				SET @I_ExceptionFieldName='InputNumber'
				RETURN -1
			END

			EXEC SysGetObjectPKId '','PGSamping',@PGSampingId OUTPUT
			INSERT INTO [dbo].[PGSamping]
					   ([PGSampingId]
					   ,[ProductionGrindId]
					   ,[CurrentCount]
					   ,[SampingQty])
				 VALUES
					   (@PGSampingId
					   ,@ProductionGrindId
					   ,@CurrentCount
					   ,@WeighQty)
			SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'请扫描操作指令' AS Tips
			SET @I_ReturnMessage='ServerMessage:已记入采样记录' +@Enter
			RETURN 0
		END

        IF @Command ='CMDLOSS'--损耗
		BEGIN
		    SELECT @WorkflowId=WorkflowId FROM Lot WHERE LotSN=@LotSN
			--损耗数量判断
			IF @WeighQty<=0 and @WorkflowId not in ('WKF1000000ZB','WKF1000000ZC','WKF1000000ZD')
			BEGIN
				SET @I_ReturnMessage='ServerMessage:本次损耗数量必须大于0!'+@Enter
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END
			IF @WeighQty<0 and @WorkflowId in ('WKF1000000ZB','WKF1000000ZC','WKF1000000ZD')
			BEGIN
				SET @I_ReturnMessage='ServerMessage:本次损耗数量必须大于0!'+@Enter
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END

			DECLARE @PGLossId IDType=''
			
			SELECT TOP 1 @StartQty=ISNULL(StartQty,0),@CurrentCount=ISNULL(CurrentCount,0) FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId
			SELECT @LossQty=ISNULL(SUM(LossQty),0) FROM PGLoss WHERE ProductionGrindId=@ProductionGrindId

			IF @StartQty<@WeighQty+@LossQty
			BEGIN
				SET @I_ReturnMessage='ServerMessage:本次损耗数量['+@InputNumber+']与累计损耗数量['+CAST(@LossQty AS VARCHAR(19))+']不能大于正在加工产品数量!'+@Enter
				SET @I_ExceptionFieldName='InputNumber'
				RETURN -1
			END

			EXEC SysGetObjectPKId '','PGLoss',@PGLossId OUTPUT
			INSERT INTO [dbo].[PGLoss]
					   ([PGLossId]
					   ,[ProductionGrindId]
					   ,[CurrentCount]
					   ,[LossQty])
				 VALUES
					   (@PGLossId
					   ,@ProductionGrindId
					   ,@CurrentCount
					   ,@WeighQty)
			SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'请扫描操作指令' AS Tips
			SET @I_ReturnMessage='ServerMessage:已记入损耗记录' +@Enter
			RETURN 0
		END

		IF @Command IN('CMDSTOPGL+','CMDSTOPGL-')
		BEGIN
			IF @WeighQty<=0
			BEGIN
				SET @I_ReturnMessage='ServerMessage:过滤数量必须大于0'--+@Enter
				SELECT '' AS InputScan,0 AS InputNumber
				RETURN 0
			END
			SET @FilterType=(CASE @Command WHEN 'CMDSTOPGL+' THEN '正压' ELSE '负压' END);

			--判断当前是否正在过滤中
			SELECT TOP 1 @StartTime=StartTime,@PGFilterId=PGFilterId FROM PGFilter WHERE ProductionGrindId=@ProductionGrindId AND FilterType=@FilterType AND StopTime IS NULL
			IF ISNULL(@PGFilterId,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:当前还未开始'+@FilterType+'过滤，请扫描开始过滤指令后进行过滤'--+@Enter
				RETURN 0
			END

			SELECT @StartQty=StartQty FROM ProductionGrind WHERE ProductionGrindId=@ProductionGrindId
			SELECT @FilterQty=SUM(FilterQty) FROM PGFilter WHERE ProductionGrindId=@ProductionGrindId AND FilterType=@FilterType

			SET @FilterQty=ISNULL(@FilterQty,0)

			IF @FilterQty+@WeighQty>@StartQty
			BEGIN
				SET @I_ReturnMessage='ServerMessage:当前'+@FilterType+'已过滤数量['+CAST(@FilterQty AS VARCHAR(19))+']加上本次过滤数量['+CAST(@WeighQty AS VARCHAR(19))+']不能超过批号总数量['+CAST(@StartQty AS VARCHAR(19))+']'--+@Enter
				SELECT '' AS InputScan,0 AS InputNumber
				SET @I_ExceptionFieldName='InputNumber'
				RETURN 0
			END

			SET @FilterTime=DATEDIFF(SECOND,@StartTime,GETDATE())

			--计算过滤时间
			UPDATE PGFilter SET StopTime=GETDATE(),FilterTime=@FilterTime,FilterQty=@WeighQty WHERE PGFilterId=@PGFilterId

			SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'请扫描操作指令' AS Tips
			SET @I_ReturnMessage='ServerMessage:本次'+@FilterType+'过滤已停止，累计过滤时间['+ CAST(@FilterTime AS VARCHAR(19)) +']秒，过滤数量'+CAST(@WeighQty AS VARCHAR(19))+'' +@Enter
			RETURN 0
		END

		IF @Command ='CMDFILTERM'--使用过滤器
		BEGIN
			IF ISNULL(@ProductionGrindId,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:请扫描批号开始过滤工艺' +@Enter
				RETURN 0
			END

			IF @WeighQty<=0
			BEGIN
				SET @I_ReturnMessage='ServerMessage:使用滤膜数量必须大于0'--+@Enter
				SELECT '' AS InputScan,0 AS InputNumber
				RETURN 0
			END

			EXEC SysGetObjectPKId '','PGUseParts',@PGUsePartsId OUTPUT
			INSERT INTO [dbo].[PGUseParts]
						([PGUsePartsId]
						,[ProductionGrindId]
						,[PartsType]
						,[PartsQty]
						,[PartsCategory])
					VALUES
						(@PGUsePartsId
						,@ProductionGrindId
						,'New'
						,@WeighQty
						,'滤膜')

			SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'请扫描操作指令' AS Tips
			SET @I_ReturnMessage='ServerMessage:滤膜使用成功' +@Enter
			RETURN 0
		END

		SET @I_ReturnMessage='ServerMessage:请先扫描操作指令' +@Enter
		RETURN 0
	END

	--*********************   工艺参数表单录入   ********************--
	IF @I_Sender='Params Submit'
	BEGIN
		IF @ProductionGrindId=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请先扫描研磨批号' +@Enter
			RETURN -1
		END

		SET @TEMPER=ISNULL(@TEMPER,0)
		SET @PRESSE=ISNULL(@PRESSE,0)
		SET @PSPEED=ISNULL(@PSPEED,0)
		SET @SPEED=ISNULL(@SPEED,0)
		SET @SSCALE=ISNULL(@SSCALE,0)
		SET @CURREN=ISNULL(@CURREN,0)
		SET @MWATER=ISNULL(@MWATER,0)

		EXEC @RESULT=[dbo].[PDA_AddPGrindParams]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@ProductionGrindId=@ProductionGrindId,
			@SpecificationCode=@SpecificationCode,
			@ParamsType='CMDTEMPER',
			@ParamsValue=@TEMPER

		EXEC @RESULT=[dbo].[PDA_AddPGrindParams]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@ProductionGrindId=@ProductionGrindId,
			@SpecificationCode=@SpecificationCode,
			@ParamsType='CMDPRESSE',
			@ParamsValue=@PRESSE

		EXEC @RESULT=[dbo].[PDA_AddPGrindParams]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@ProductionGrindId=@ProductionGrindId,
			@SpecificationCode=@SpecificationCode,
			@ParamsType='CMDPSPEED',
			@ParamsValue=@PSPEED

		EXEC @RESULT=[dbo].[PDA_AddPGrindParams]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@ProductionGrindId=@ProductionGrindId,
			@SpecificationCode=@SpecificationCode,
			@ParamsType='CMDSPEED',
			@ParamsValue=@SPEED

		EXEC @RESULT=[dbo].[PDA_AddPGrindParams]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@ProductionGrindId=@ProductionGrindId,
			@SpecificationCode=@SpecificationCode,
			@ParamsType='CMDSSCALE',
			@ParamsValue=@SSCALE

		EXEC @RESULT=[dbo].[PDA_AddPGrindParams]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@ProductionGrindId=@ProductionGrindId,
			@SpecificationCode=@SpecificationCode,
			@ParamsType='CMDCURREN',
			@ParamsValue=@CURREN

		--只有精磨录入过滤参数
		IF @SpecificationCode IN('Grind-JM','BYM','UVPULPYM')
		BEGIN
			EXEC @RESULT=[dbo].[PDA_AddPGrindParams]
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@ProductionGrindId=@ProductionGrindId,
				@SpecificationCode=@SpecificationCode,
				@ParamsType='CMDMWATER',
				@ParamsValue=@MWATER
		END

		SELECT '' AS TEMPER, '' AS PRESSE, '' AS PSPEED, '' AS SPEED, '' AS SSCALE, '' AS CURREN, '' AS MWATER

		RETURN @RESULT
	END
	--*********************   工艺参数表单录入   ********************--
	SET @I_ReturnMessage='ServerMessage:请扫描' +@Enter


	RETURN 0
END
GO
