SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:<OrBit Team HK0313>
-- Create date:   <2021/07/12 >
-- Description:<工单生产上料>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROC [dbo].[PDA_LILPMakeCheckInput]
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
@MOName VARCHAR(50)='',				   -- 工单
@LoadingItemLotId CHAR(12)='',            --本次生产上料唯一标识
@InputScan VARCHAR(50)='',             --信息输入: 包括设备编码，人员编码，规程代码，上料批次，下线批次，工艺参数编码，命令按钮条码
@InputNumber VARCHAR(50) ='',          --数值输入：重量，工艺参数值
@Command VARCHAR(50)='',                 --当前执行指令
@AdjustmentMO VARCHAR(50)=''                 --当前执行指令

AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	--TY
	DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10)
	DECLARE @RESULT INT=0
	DECLARE @Tips NVARCHAR(256)=''
	--继续扫描下一下：作为提示使用
	--重复提示信息
	--PATINDEX('%[^0-9|.|-|+]%','2.2')--返回0--数字判断
	IF ISNULL(@InputNumber,'')<>'' AND PATINDEX('%[^0-9|.|-|+]%',@InputNumber)<>0
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请输入数值类型'--+@Enter
		SELECT '' AS InputNumber,'InputNumber' AS ExceptionFieldName
		RETURN 0
	END


	IF ISNULL(@InputNumber,'')='' SET @InputNumber='0'

	--工单信息
	DECLARE @MOId IDType =''
	DECLARE @ProductId IDType=''
	DECLARE @MOItemId IDType=''
	DECLARE @WaterProductId IDType
	DECLARE @DiluentProductId IDType
	DECLARE @MOQtyRequired SysNumberType=0
	DECLARE @SpecificationId IDType
	DECLARE @EmployeeId IDType
	DECLARE @MinStirringTime SysNumberType
	DECLARE @MinStirringSpeed SysNumberType
	DECLARE @MaxStirringSpeed SysNumberType

	DECLARE @CurrMaterial nvarchar(50)=N''
	DECLARE @CurrMaterialId CHAR(12)
	DECLARE @ItemQtyRequired SysNumberType
	DECLARE @ActualQty SysNumberType
	DECLARE @NextMaterial NVARCHAR(50)=''
	DECLARE @LineSequence VARCHAR(8)=''

	DECLARE @LastMakingDate DATETIME
	DECLARE @MixingTime SysNumberType=0
	DECLARE @UsedQty SysNumberType=0

	DECLARE @MOStates VARCHAR(8)

    DECLARE @LotSN NVARCHAR(50)=''

    DECLARE @WorkflowId CHAR(12)=''


	--为了计算上料数、预警数
	IF @I_Sender='LILPMakeCheckInput'
	BEGIN
		SET @InputScan = LTRIM(RTRIM(ISNULL(@InputScan,'')))

		IF ISNULL(@InputScan,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请扫描'--+@Enter
			RETURN 0
		END

        -- ============================ 2026年1月16日 15:14:25  截取箱号（防止录错）      ==============================================----
        IF NOT EXISTS( SELECT 1 FROM Equipment WHERE EquipmentNumber=@InputScan )--排除设备，设备会有+号的
        BEGIN
            SET @InputScan = LEFT(@InputScan, CHARINDEX('+', @InputScan + '+') - 1)
        END
        -- ============================ 2026年1月16日 15:14:29  截取箱号（防止录错）      ==============================================----

		--进行判断，输入参数是否是执行命令
		IF LEFT(@InputScan,3)='CMD'
		BEGIN
			IF @InputScan ='CMDRESET'--重置命令：只重载在在本界面扫描的，其他参数是从查询界面带过来的
			BEGIN
				SELECT '' AS EmployeeNo,'' AS EquipmentNo,0 AS SeqNum,'' AS SpecificationCode,
				'' AS MOName,'' AS InputScan,0 AS InputNumber,'' AS CurrMaterial,'' AS MOProduct,'' AS ItemQtyRequired,'' AS ActualQty,
				'' AS LoadingItemLotId,@InputScan AS Command,'InputScan' AS ExceptionFieldName,'请扫描[员工工号]' AS Tips
				SET @I_ReturnMessage='ServerMessage:已重置!'+@Enter
				RETURN 0
			END
			IF @InputScan ='CMDSUBMIT'--提交命令
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'InputScan' AS ExceptionFieldName
				SET @I_ReturnMessage='ServerMessage:已提交!'+@Enter
				RETURN 0
			END
			IF @InputScan ='CMDCOA'--Complete order adjustment  完成调单
			BEGIN
				IF ISNULL(@AdjustmentMO,'')=''
				BEGIN
					SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
					SET @I_ReturnMessage='ServerMessage:请先选择工单!'+@Enter
					RETURN -1
				END

				IF NOT EXISTS(SELECT 1 FROM MO WHERE MOName=@AdjustmentMO)
				BEGIN
					SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
					SET @I_ReturnMessage='ServerMessage:工单['+@AdjustmentMO+']不存在!'+@Enter
					RETURN -1
				END
				
				UPDATE MO SET IsAdjustment=0 WHERE MOName=@AdjustmentMO

				SELECT '' AS InputScan,0 AS InputNumber,'' AS Command,'InputScan' AS ExceptionFieldName
				SET @I_ReturnMessage='ServerMessage:已自动完成调单!'+@Enter
				RETURN 0
			END

			IF @InputScan='CMDREFRESH'--刷新命令
			BEGIN
				EXEC @RESULT=[dbo].[PDA_ProductionMOItemQuery]
				@I_Sender='GetParams',
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@EquipmentNo=@EquipmentNo,
				@EmployeeNo=@EmployeeNo,
				@SpecificationCode=@SpecificationCode,
				@MOName=@MOName,
				@LoadingItemLotId=@LoadingItemLotId,
				@IsFirstBack=0,
				@Command=''
			
				RETURN @RESULT
			END

			IF @InputScan ='CMDWEIGH'--称重
			BEGIN
				--修改当前执行指令为称重，接下来是扫描批次条码
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputScan' AS ExceptionFieldName,'请扫描工单批次条码' AS Tips
				RETURN 0
			END

			IF @InputScan ='CMDADDEMPLOYEE'--添加上料人员
			BEGIN
				--提示扫描员工工号
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputScan' AS ExceptionFieldName,'请扫描员工工号' AS Tips
				RETURN 0
			END

			IF @InputScan ='CMDFINISH'--制作完成
			BEGIN
				--调用制作完成事件
				EXEC @RESULT=[dbo].[PDA_ProductionMakingSubmit]
				@I_Sender='MakingComplete',
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_PlugInCommand=@I_PlugInCommand,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@I_ResourceName=@I_ResourceName,
				@LoadingItemLotId=@LoadingItemLotId
				IF @RESULT<>0
				BEGIN
					SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
					RETURN @RESULT
				END

				SELECT '' AS EmployeeNo,'' AS EquipmentNo,0 AS SeqNum,'' AS SpecificationCode,
				'' AS MOName,'' AS Command,'' AS InputScan,0 AS InputNumber,'' AS CurrMaterial,'' AS MOProduct,'' AS LoadingItemLotId,'InputScan' AS ExceptionFieldName
				SET @I_ReturnMessage='ServerMessage:当前工单制作完成，请重新选择工单!'+@Enter
				RETURN 0
			END
			IF @InputScan ='CMDLOTMOVE'--批次下线
			BEGIN
				IF ISNULL(@LoadingItemLotId,'')=''
				BEGIN
					SELECT '' AS InputScan,0 AS InputNumber
					SET @I_ReturnMessage='ServerMessage:请先进行上料!'+@Enter
					RETURN -1
				END

				--=================================Irving 2025.03.28 begin fix 工单未投料完成，就移送到下一道工序 =============================================================================
                -- 定义提示信息：检查是否还有未投完料的工单明细
                DECLARE @UnfinishedInfo NVARCHAR(MAX) = '';

				-- 检查投料明细表的数量 与 工单明细表需求数
                SELECT
                    @UnfinishedInfo = @UnfinishedInfo +
                        '物料: ' + P.ProductDescription + ', 还需投料数量: ' + CAST(MOI.ItemQtyRequired - LILD.ActualQty AS NVARCHAR(19)) + @Enter
                FROM
                    MOItem MOI
                    INNER JOIN LoadingItemLotDetail LILD ON MOI.MOItemId = LILD.MOItemId
                    INNER JOIN Product P ON MOI.ProductId = P.ProductId
                WHERE
                    LILD.LoadingItemLotId = @LoadingItemLotId
                    AND MOI.ItemQtyRequired > LILD.ActualQty and MOI.DeleteFlag != 1;

				-- return -1 如果有未完成上料的提示信息，则返回错误信息
                IF @UnfinishedInfo LIKE '%物料%'
                    begin
                        SELECT '' AS InputScan,0 AS InputNumber
                        SET @I_ReturnMessage='ServerMessage:-请核实-未投完' + @UnfinishedInfo + +@Enter --物料: C561SLG, 还需投料数量: 200.000
                        select @I_ReturnMessage
                        RETURN -1
                    end
                --=================================Irving 2025.03.28 end fix 工单未投料完成，就移送到下一道工序 =============================================================================

				SELECT TOP 1 
					@MOItemId=MOItemId,
					@MOId=MOId,
					@LastMakingDate=ISNULL(LastMakingDate,CreateDate) 
				FROM LoadingItemLot WHERE LoadingItemLotId=@LoadingItemLotId

				--当前上料是否完成
				IF ISNULL(@MOItemId,'')<>''
				BEGIN
					SELECT '' AS InputScan,0 AS InputNumber
					SET @I_ReturnMessage='ServerMessage:当前未完成上料，不能执行此动作!'+@Enter
					RETURN -1
				END



				--SELECT @MOQtyRequired=MOQtyRequired FROM MO WHERE MOId=@MOId

				--SET @MixingTime=[dbo].[MixingTime](@SpecificationCode,@MOQtyRequired,@LastMakingDate)

				--IF @MixingTime>0
				--BEGIN
				--	SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
				--	SET @I_ReturnMessage='ServerMessage:当前未到搅拌时间点，不能执行此动作,搅拌时间剩余['+CAST(@MixingTime AS NVARCHAR(19))+']秒!'+@Enter
				--	RETURN -1
				--END

				--判断是否录入转速
				IF NOT EXISTS(SELECT 1 FROM LoadingItemLotParams WHERE LoadingItemLotId=@LoadingItemLotId AND ParamsType='CMDSPEED')
				BEGIN
					--获取转速区间
					EXEC @RESULT = [dbo].[PDA_VerifyFeedingProcess]
					@I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
					@LoadingItemLotId=@LoadingItemLotId,
					@I_OrBitUserId=@I_OrBitUserId,
					@I_ResourceId=@I_ResourceId,
					@IsFeeding=1,
					@MinStirringTime=@MinStirringTime OUTPUT,
					@MinStirringSpeed=@MinStirringSpeed OUTPUT,
					@MaxStirringSpeed=@MaxStirringSpeed OUTPUT,
					@Tips=@Tips OUTPUT
					IF @RESULT=-1 RETURN @RESULT

					IF @MinStirringSpeed>0 OR @MaxStirringSpeed>0
						SET @Tips='结束投料前请先录入[转速]!转速区间['+CAST(@MinStirringSpeed AS VARCHAR(19))+'-'+CAST(@MaxStirringSpeed AS VARCHAR(19))+']!'
					ELSE
						SET @Tips='结束投料前请先录入[转速]!'

					SELECT '' AS InputScan,0 AS InputNumber,'CMDSPEED' AS Command,'InputNumber' AS ExceptionFieldName
					,@Tips AS Tips
					RETURN 0
				END
				
				--修改当前执行指令为下线，接下来是扫描批次条码
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputScan' AS ExceptionFieldName,'请扫描工单批次条码' AS Tips
				RETURN 0
			END
			IF @InputScan ='CMDTEMPER'--工艺参数录入：温度
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputNumber' AS ExceptionFieldName
				,'请输入[温度]!' AS Tips
				RETURN 0
			END
			IF @InputScan ='CMDPRESSE'--工艺参数录入：压力
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputNumber' AS ExceptionFieldName
				,'请输入[压力]!' AS Tips
				RETURN 0
			END
			IF @InputScan ='CMDPSPEED'--工艺参数录入：泵速
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputNumber' AS ExceptionFieldName
				,'请输入[泵速]!' AS Tips
				RETURN 0
			END
			IF @InputScan ='CMDSPEED'--工艺参数录入：投料转速、C点转速
			BEGIN
				--获取转速区间
				EXEC @RESULT = [dbo].[PDA_VerifyFeedingProcess]
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
				@LoadingItemLotId=@LoadingItemLotId,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@IsFeeding=1,
				@MinStirringTime=@MinStirringTime OUTPUT,
				@MinStirringSpeed=@MinStirringSpeed OUTPUT,
				@MaxStirringSpeed=@MaxStirringSpeed OUTPUT,
				@Tips=@Tips OUTPUT
				IF @RESULT=-1 RETURN @RESULT

				IF @MinStirringSpeed>0 OR @MaxStirringSpeed>0
					SET @Tips='请输入[转速],转速区间['+CAST(@MinStirringSpeed AS VARCHAR(19))+'-'+CAST(@MaxStirringSpeed AS VARCHAR(19))+']!'
				ELSE
					SET @Tips='请输入[转速]!'

				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputNumber' AS ExceptionFieldName
				,@Tips AS Tips
				RETURN 0
			END
			IF @InputScan ='CMDSSCALE'--工艺参数录入：机封刻度
			BEGIN
				SELECT '' AS InputScan,'' AS InputNumber,@InputScan AS Command,'InputNumber' AS ExceptionFieldName
				,'请输入[机封刻度]!' AS Tips
				RETURN 0
			END
			IF @InputScan ='CMDCURREN'--工艺参数录入：电流
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputNumber' AS ExceptionFieldName
				,'请输入[电流]!' AS Tips
				RETURN 0
			END
			--IF @InputScan ='CMDPERSON'--工艺参数录入：人员
			--BEGIN
			--	SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputNumber' AS ExceptionFieldName
			--	,'请输入[人员]!' AS Tips
			--	RETURN 0
			--END
			IF @InputScan ='CMDMWATER'--工艺参数录入：补水
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputNumber' AS ExceptionFieldName
				,'请输入[过滤参数]!' AS Tips
				RETURN 0
			END
			IF @InputScan ='CMDPSUPPLY'--补料指令
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputScan' AS ExceptionFieldName
				,'开始补料，请扫描物料条码!' AS Tips
				RETURN 0
			END

			IF @InputScan ='CMDSTARTSTIR'--开始搅拌指令
			BEGIN
				IF ISNULL(@LoadingItemLotId,'')=''
				BEGIN
					SET @I_ReturnMessage='ServerMessage:参数错误，请先选择工单开始投料工艺!'+@Enter
					SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
					RETURN -1
				END
				
				IF EXISTS(SELECT 1 FROM LoadingItemLot WHERE LoadingItemLotId=@LoadingItemLotId AND StirState=1)
				BEGIN
					SET @I_ReturnMessage='ServerMessage:当前已在搅拌中!'+@Enter
					SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
					RETURN 0
				END

				UPDATE LoadingItemLot SET StirState=1,StirTime=0,StirCurrDate=GETDATE() WHERE LoadingItemLotId=@LoadingItemLotId

				SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
				,'已开始搅拌，正在累计搅拌时间!' AS Tips
				RETURN 0
			END

			IF @InputScan ='CMDSTOPSTIR'--停止搅拌指令
			BEGIN
				IF ISNULL(@LoadingItemLotId,'')=''
				BEGIN
					SET @I_ReturnMessage='ServerMessage:参数错误，请先选择工单开始投料工艺!'+@Enter
					SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
					RETURN -1
				END

				IF EXISTS(SELECT 1 FROM LoadingItemLot WHERE LoadingItemLotId=@LoadingItemLotId AND StirState=0)
				BEGIN
					SET @I_ReturnMessage='ServerMessage:当前未在搅拌中!'+@Enter
					SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
					RETURN 0
				END

				UPDATE LoadingItemLot SET StirState=0,StirTime=DATEDIFF(SECOND,StirCurrDate,GETDATE()),StirCurrDate=GETDATE() WHERE LoadingItemLotId=@LoadingItemLotId

				SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
				,'已停止搅拌，累计时间停止!' AS Tips
				RETURN 0
			END
            IF @InputScan ='CMDSTARTCB'--开始拆包装
			BEGIN
				IF ISNULL(@LoadingItemLotId,'')=''
				BEGIN
					SET @I_ReturnMessage='ServerMessage:参数错误，请先选择工单开始投料工艺!'+@Enter
					SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
					RETURN -1
				END
				select @MOId=moid,@Lotsn=lotsn from LoadingItemLot where LoadingItemLotId=@LoadingItemLotId
				IF EXISTS ( SELECT 1 FROM PUnpackRecord WHERE moid=@MOId AND EndTime IS NULL )
				BEGIN
					SET @I_ReturnMessage='ServerMessage:当前已在拆包装中!'+@Enter
					SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
					RETURN 0
				END
                INSERT INTO PUnpackRecord
                (
                    EmployeeNo,
                    MOId,
                    LotSN,
                    StartTime,
                    CreateUserId,
                    ModifyDate
                )
                VALUES
                (
                    @EmployeeNo,
                    @MOId,
                    @LotSN,
                    GETDATE(),
                    @I_OrBitUserId,
                    GETDATE()
                );


				SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
				,'已开始拆包装，正在累计时间!' AS Tips
				RETURN 0
			END

            IF @InputScan ='CMDENDCB'--停止拆包装指令
			BEGIN
				IF ISNULL(@LoadingItemLotId,'')=''
				BEGIN
					SET @I_ReturnMessage='ServerMessage:参数错误，请先选择工单开始投料工艺!'+@Enter
					SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
					RETURN -1
				END
                -- 【结束校验】先定位最近一条未结束记录，不存在时禁止结束
                select @MOId=moid,@Lotsn=lotsn from LoadingItemLot where LoadingItemLotId=@LoadingItemLotId
                DECLARE @OpenRecordId NVARCHAR(20)=''
                SELECT TOP 1 @OpenRecordId=UnpackRecordId
                FROM PUnpackRecord
                WHERE moid=@MOId
                AND EndTime IS NULL
                ORDER BY StartTime DESC, CreateDate DESC;

                IF ISNULL(@OpenRecordId,'')=''
                BEGIN
                    SET @I_ReturnMessage='ServerMessage:当前未在拆包装中' + @Enter;
                    SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
                    RETURN -1;
                END;

                UPDATE PUnpackRecord  SET EndTime=GETDATE(), ModifyDate=GETDATE() WHERE UnpackRecordId=@OpenRecordId AND EndTime IS NULL;
				SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
				,'已停止拆包装，累计时间停止!' AS Tips
				RETURN 0
			END

			IF @InputScan ='CMDSWITCHE'--切换设备
			BEGIN
				--提示扫描设备
				SELECT '' AS InputScan,0 AS InputNumber,@InputScan AS Command,'InputScan' AS ExceptionFieldName,'请扫描设备条码' AS Tips
				RETURN 0
			END
		END


		IF @Command ='CMDSWITCHE'--切换设备
		BEGIN
			--验证设备号正确性，以及是否正在投料
			IF NOT EXISTS(SELECT 1 FROM Equipment WHERE EquipmentNumber=@InputScan)
			BEGIN
				SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
				SET @I_ReturnMessage='ServerMessage:设备编号['+@InputScan+']未维护，请重新扫描' +@Enter
				RETURN 0
			END

			SELECT 
				@LoadingItemLotId=LoadingItemLotId,
				@EquipmentNo=C.EquipmentNumber,
				@SpecificationCode=E.SpecificationCode,
				@MOName=B.MOName
			FROM LoadingItemLot A
			INNER JOIN MO B ON A.MOId=B.MOId
			INNER JOIN Equipment C ON A.EquipmentId=C.EquipmentId
			INNER JOIN Specification D ON A.SpecificationId=D.SpecificationId
			INNER JOIN SpecificationRoot E ON D.SpecificationRootId=E.SpecificationRootId
			WHERE A.IsComplete=0 AND C.EquipmentNumber=@InputScan

			IF ISNULL(@LoadingItemLotId,'')=''
			BEGIN
				SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
				SET @I_ReturnMessage='ServerMessage:所扫设备['+@InputScan+']不在生产中，请重新扫描' +@Enter
				RETURN 0
			END

			SELECT TOP 1 @EmployeeNo=B.EmployeeNo FROM Operator A
			INNER JOIN SysUser B ON A.EmployeeId=B.UserId WHERE A.RefId=@LoadingItemLotId
			ORDER BY A.CreateDate DESC

			EXEC @RESULT=[dbo].[PDA_ProductionMOItemQuery]
			@I_Sender='GetParams',
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@EquipmentNo=@EquipmentNo,
			@EmployeeNo=@EmployeeNo,
			@SpecificationCode=@SpecificationCode,
			@MOName=@MOName,
			@LoadingItemLotId='',
			@IsFirstBack=0,
			@Command=''
			
			RETURN @RESULT
		END

		--判断是否是扫描基本信息
		IF ISNULL(@EmployeeNo,'')='' OR ISNULL(@EquipmentNo,'')='' OR ISNULL(@SpecificationCode,'')='' OR ISNULL(@MOName,'')=''
		BEGIN 
			IF ISNULL(@EmployeeNo,'')=''
			BEGIN
				IF NOT EXISTS(SELECT 1 FROM SysUser WHERE EmployeeNo=@InputScan)
				BEGIN
					SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
					SET @I_ReturnMessage='ServerMessage:员工编号['+@InputScan+']未维护，请重新扫描' +@Enter
					RETURN 0
				END

				EXEC @RESULT=[dbo].[PDA_ProductionMOItemQuery]
				@I_Sender='GetParams',
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@EquipmentNo=@EquipmentNo,
				@EmployeeNo=@InputScan,
				@SpecificationCode=@SpecificationCode,
				@MOName=@MOName,
				@LoadingItemLotId=@LoadingItemLotId,
				@IsFirstBack=0,
				@Command=''
			
				RETURN @RESULT
			END

			IF ISNULL(@EquipmentNo,'')=''
			BEGIN
				DECLARE @EquipmentId IDType
				DECLARE @EWorkCenterId IDType
				SELECT @EquipmentId=EquipmentId,@EWorkCenterId=WorkcenterId FROM Equipment WHERE IsAvalid=1 AND EquipmentNumber=@InputScan
				IF ISNULL(@EquipmentId,'')=''
				BEGIN
					SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
					SET @I_ReturnMessage='ServerMessage:设备编号['+@InputScan+']未维护，请重新扫描' +@Enter
					RETURN 0
				END

				--IF ISNULL(@EWorkCenterId,'')=''
				--BEGIN
				--	SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
				--	SET @I_ReturnMessage='ServerMessage:当前扫描设备未维护工作中心，请维护' +@Enter
				--	RETURN 0
				--END

				--带出当前设备计划生产时间最早的工单/优先带出正在加工的工单
				SELECT @MOName=ISNULL(MO.MOName,''),@SpecificationCode=ISNULL(SR.SpecificationCode,'') FROM LoadingItemLot LIL INNER JOIN MO ON LIL.MOId=MO.MOId
				INNER JOIN Specification S ON LIL.SpecificationId=S.SpecificationId
				INNER JOIN SpecificationRoot SR ON S.SpecificationRootId=SR.SpecificationRootId
				WHERE LIL.EquipmentId=@EquipmentId AND IsComplete=0 AND MO.MOStates='20'
				----没有正在加工的工单时带出计划开始时间最早的工单
				--IF ISNULL(@MOName,'')=''
				--BEGIN
				--	SELECT TOP 1 @MOName=MOName FROM MO WHERE EquipmentId=@EquipmentId AND MOStates='20' 
				--	--AND MOId NOT IN(SELECT MOId FROM LoadingItemLot WHERE EquipmentId=@EquipmentId AND IsComplete=1) 
				--	ORDER BY PlannedDateFrom
				--END

				--IF ISNULL(@MOName,'')=''
				--BEGIN
				--	SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
				--	SET @I_ReturnMessage='ServerMessage:当前扫描设备未绑定工单，请前往工单查询选择生产工单' +@Enter
				--	RETURN 0
				--END

				EXEC @RESULT=[dbo].[PDA_ProductionMOItemQuery]
				@I_Sender='GetParams',
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@EquipmentNo=@InputScan,
				@EmployeeNo=@EmployeeNo,
				@SpecificationCode=@SpecificationCode,
				@MOName=@MOName,
				@LoadingItemLotId=@LoadingItemLotId,
				@IsFirstBack=0,
				@Command=''
			
				RETURN @RESULT
			END

			IF ISNULL(@SpecificationCode,'')=''
			BEGIN
				IF NOT EXISTS(SELECT 1 FROM SpecificationRoot WHERE SpecificationCode=@InputScan)
				BEGIN
					SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
					SET @I_ReturnMessage='ServerMessage:规程代码['+@InputScan+']未维护，请重新扫描' +@Enter
					RETURN 0
				END
			
				EXEC @RESULT=[dbo].[PDA_ProductionMOItemQuery]
				@I_Sender='GetParams',
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@EquipmentNo=@EquipmentNo,
				@EmployeeNo=@EmployeeNo,
				@SpecificationCode=@InputScan,
				@MOName=@MOName,
				@LoadingItemLotId=@LoadingItemLotId,
				@IsFirstBack=0,
				@Command=''
			
				RETURN @RESULT
			END

			IF ISNULL(@MOName,'')=''
			BEGIN
				IF EXISTS(SELECT 1 FROM Lot WHERE LotSN=@InputScan)
				BEGIN
					SELECT @MOId=MOId FROM Lot WHERE LotSN=@InputScan AND LotStatus='1'

					SELECT @MOName=MOName,@MOStates=MOStates FROM MO WHERE MOId=@MOId
					IF ISNULL(@MOStates,'')<>'20'
					BEGIN
						SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
						SET @I_ReturnMessage='ServerMessage:工单['+@MOName+']未下达' +@Enter
						RETURN 0
					END
				END
				ELSE IF EXISTS(SELECT 1 FROM MO WHERE MOName=@InputScan)
				BEGIN
					SELECT @MOName=MOName,@MOStates=MOStates,@MOId=MOId FROM MO WHERE MOName=@InputScan
					IF ISNULL(@MOStates,'')<>'20'
					BEGIN
						SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
						SET @I_ReturnMessage='ServerMessage:工单['+@MOName+']未下达' +@Enter
						RETURN 0
					END

					IF NOT EXISTS(SELECT 1 FROM Lot WHERE MOId=@MOId AND LotStatus='1')
					BEGIN
						SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
						SET @I_ReturnMessage='ServerMessage:工单['+@MOName+']未启动工单批号' +@Enter
						RETURN 0
					END
				END
				ELSE
				BEGIN
					SELECT '' AS InputScan,'InputScan' AS ExceptionFieldName
					SET @I_ReturnMessage='ServerMessage:工单或批号['+@InputScan+']不存在' +@Enter
					RETURN 0
				END
			
				EXEC @RESULT=[dbo].[PDA_ProductionMOItemQuery]
				@I_Sender='GetParams',
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@EquipmentNo=@EquipmentNo,
				@EmployeeNo=@EmployeeNo,
				@SpecificationCode=@SpecificationCode,
				@MOName=@MOName,
				@LoadingItemLotId=@LoadingItemLotId,
				@IsFirstBack=0,
				@Command=''
			
				RETURN @RESULT
			END
		END

		--是否需要扫描其他标签
		IF @Command='CMDLOAD' OR @Command='CMDPSUPPLY' OR @Command=''--当前指令为上料/默认指令
		BEGIN

            --20260903拆包装工作流需要记录拆包装时间
            SELECT TOP 1  @MOId=MOId  FROM LoadingItemLot WHERE LoadingItemLotId=@LoadingItemLotId
            SELECT TOP 1 @WorkflowId=WorkflowId FROM Lot WHERE moid=@MOId
		    IF NOT EXISTS ( SELECT 1 FROM PUnpackRecord WHERE moid=@MOId ) AND @WorkflowId in('WKF1000000ZU')
		    BEGIN
                SET @I_ReturnMessage='ServerMessage:请先扫描开始拆包装，记录拆包装时间!'+@Enter
                SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
                RETURN 0
            END
            ELSE IF EXISTS ( SELECT 1 FROM PUnpackRecord WHERE moid=@MOId AND EndTime IS NULL ) AND @WorkflowId in('WKF1000000ZU')
            BEGIN
                SET @I_ReturnMessage='ServerMessage:正在拆包装中，请先扫描停止指令!'+@Enter
                SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
                RETURN 0
            END

			--判断是否是物料批次条码
			IF EXISTS(SELECT 1 FROM WW_RMInventory WHERE LotSN=@InputScan AND IsStorage=1 AND LotStatus='1')
			BEGIN
				--调用上料事件
				--EXEC @RESULT=[dbo].[PDA_ProductionMaking_LotSNScan]
				--@I_Sender='LotSNScan',
				--@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				--@I_PlugInCommand=@I_PlugInCommand,
				--@I_OrBitUserId=@I_OrBitUserId,
				--@I_ResourceId=@I_ResourceId,
				--@I_ResourceName=@I_ResourceName,
				--@LoadingItemLotId=@LoadingItemLotId,
				--@BoxOrLotSN=@InputScan,
				--@EmployeeNo=@EmployeeNo,
				--@UsedQty=@InputNumber OUTPUT,
				--@Command=@Command
				--IF @RESULT<>0
				--BEGIN
				--	SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
				--	RETURN @RESULT
				--END
				----执行批次上料
				--SELECT @InputNumber AS InputNumber,'InputNumber' AS ExceptionFieldName,'请录入上料数量!' AS Tips
				--RETURN 0

				--调用上料事件
				EXEC @RESULT=[dbo].[PDA_ProductionMaking_LotSNScan]
				@I_Sender='LotSNScan',
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_PlugInCommand=@I_PlugInCommand,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@I_ResourceName=@I_ResourceName,
				@LoadingItemLotId=@LoadingItemLotId,
				@BoxOrLotSN=@InputScan,
				@EmployeeNo=@EmployeeNo,
				@UsedQty=@InputNumber OUTPUT,
				@Command=@Command

				IF @Command='CMDPSUPPLY'
				BEGIN
					SELECT @InputNumber AS InputNumber,'InputNumber' AS ExceptionFieldName,'请录入上料数量!' AS Tips
					RETURN 0
				END

				SELECT @WaterProductId=P.ProductId FROM ProductRoot PR INNER JOIN Product P ON PR.ProductRootId=P.ProductRootId WHERE PR.ProductName='9999999999'
				SELECT @DiluentProductId=P.ProductId FROM ProductRoot PR INNER JOIN Product P ON PR.ProductRootId=P.ProductRootId WHERE PR.ProductName='1023450105'
				--获取当前要上的料
			

				SELECT @CurrMaterial=P.ProductDescription,
				@ItemQtyRequired=MOI.ItemQtyRequired,
				@ActualQty=LILD.ActualQty, 
				@LineSequence=MOI.LineSequence,
				@CurrMaterialId=MOI.ProductId,
				@MOQtyRequired=MO.MOQtyRequired
				FROM LoadingItemLot LIL 
				INNER JOIN MOItem MOI ON LIL.MOItemId=MOI.MOItemId
				INNER JOIN Product P ON MOI.ProductId=P.ProductId
				INNER JOIN LoadingItemLotDetail LILD ON LIL.LoadingItemLotId=LILD.LoadingItemLotId AND LIL.MOItemId=LILD.MOItemId
				INNER JOIN MO ON LIL.MOId=MO.MOId
				WHERE LIL.LoadingItemLotId=@LoadingItemLotId

				SET @UsedQty=@ItemQtyRequired

				IF @WaterProductId=@CurrMaterialId
				BEGIN
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
					ELSE
					BEGIN
						SET @UsedQty=@ItemQtyRequired-@ActualQty
					END
				END
				ELSE
				BEGIN
					SET @UsedQty=@ItemQtyRequired-@ActualQty
				END

				SET @ItemQtyRequired=@UsedQty

				SELECT @MOQtyRequired=MOQtyRequired,
				@LastMakingDate=LastMakingDate ,
				@SpecificationId=A.SpecificationId,
				@MOId=A.MOId
				FROM LoadingItemLot A 
				INNER JOIN MO B ON A.MOId=B.MOId 
				WHERE A.LoadingItemLotId=@LoadingItemLotId

				--获取下一物料
				IF ISNULL(@CurrMaterial,'')<>''
				BEGIN
					SET @Tips='请扫描物料条码进行上料!'
					SELECT TOP 1 @NextMaterial=C.ProductDescription FROM LoadingItemLotDetail L
					INNER JOIN MOItem A ON L.MOItemId=A.MOItemId
					INNER JOIN Product C ON A.ProductId=C.ProductId
					WHERE L.LoadingItemLotId=@LoadingItemLotId
					AND ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>L.ActualQty
					AND A.ProductId NOT IN (@WaterProductId,@DiluentProductId) 
					AND ((A.LineSequence>@LineSequence AND @CurrMaterialId NOT IN (@WaterProductId,@DiluentProductId)) OR @CurrMaterialId IN (@WaterProductId,@DiluentProductId))
					ORDER BY A.LineSequence

					IF ISNULL(@NextMaterial,'')=''
					BEGIN
						SELECT TOP 1 @NextMaterial=P.ProductDescription FROM LoadingItemLotDetail LILD 
						INNER JOIN MOItem MOI ON LILD.MOItemId=MOI.MOItemId
						INNER JOIN Product P ON MOI.ProductId=P.ProductId
						WHERE LILD.LoadingItemLotId=@LoadingItemLotId AND ISNULL(MOI.DeleteFlag,'') IN('','0')
						AND MOI.ProductId IN (@WaterProductId,@DiluentProductId) AND LILD.ActualQty<MOI.ItemQtyRequired 
						AND ((MOI.ProductId =@WaterProductId AND LILD.ActualQty>0 AND MOI.ProductId<>@CurrMaterialId)
						OR (MOI.ProductId =@DiluentProductId AND LILD.ActualQty=0))
						ORDER BY LineSequence
					END
				END

				EXEC @RESULT = [dbo].[PDA_VerifyFeedingProcess]
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
				@LoadingItemLotId=@LoadingItemLotId,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@IsFeeding=1,
				@MinStirringTime=@MinStirringTime OUTPUT,
				@MinStirringSpeed=@MinStirringSpeed OUTPUT,
				@MaxStirringSpeed=@MaxStirringSpeed OUTPUT,
				@Tips=@Tips OUTPUT
				IF @RESULT=-1 RETURN @RESULT
		
				IF @MinStirringTime<>0
				BEGIN
					SET @Tips+='工艺投料搅拌时间剩余['+CAST(@MinStirringTime AS VARCHAR(19))+']分钟'+@Enter
				END

				IF ISNULL(@CurrMaterial,'')<>'' AND ISNULL(@Tips,'')='' SET @Tips='请扫描物料条码进行上料!'

				IF ISNULL(@CurrMaterial,'')=''
				BEGIN
					--如果没有录入转速，提醒录入转速
					IF NOT EXISTS(SELECT 1 FROM LoadingItemLotParams WHERE LoadingItemLotId=@LoadingItemLotId AND ParamsType='CMDSPEED')
					BEGIN
						SET @Tips+='您还没有录入转速，请扫描转速指令录入转速!'+@Enter
					END
					SET @MixingTime=[dbo].[MixingTime](@SpecificationCode,@MOQtyRequired,@LastMakingDate)
					IF @MixingTime>0 
					BEGIN
						SET @Tips+='工艺结束搅拌时间剩余['+CAST(@MixingTime AS VARCHAR(19))+']秒'+@Enter
						UPDATE Lot SET MixingEndTime=DATEADD(SECOND,@MixingTime,GETDATE()) WHERE MOId=@MOId AND SpecificationId=@SpecificationId AND LotStatus='1'
					END
					ELSE
					BEGIN
						SET @Tips+='搅拌结束，请结束工艺!'+@Enter
					END 
				END

				SELECT '' AS InputScan,0 AS InputNumber,@CurrMaterial AS CurrMaterial,@NextMaterial AS NextMaterial,@ItemQtyRequired AS ItemQtyRequired,@ActualQty AS ActualQty,@Tips AS Tips
				RETURN @RESULT
			END
			ELSE
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
				SET @I_ReturnMessage='ServerMessage:[' +@InputScan +']为无效批次，检查是否存在或锁定，请扫描正确的条码' +@Enter
				RETURN -1
			END
		END

		IF @Command='CMDWEIGH'--当前指令为称重
		BEGIN
			IF ISNULL(@InputScan,'')='' RETURN 0

			EXEC @RESULT=[dbo].[PDA_LotWeigh]
			@I_Sender='LotSNScan',
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_PlugInCommand=@I_PlugInCommand,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@I_ResourceName=@I_ResourceName,
			@LoadingItemLotId=@LoadingItemLotId,
			@LotQty=@InputNumber OUTPUT,
			@LotSN=@InputScan

			IF @RESULT<>0
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
				RETURN @RESULT
			END

			SELECT @InputNumber AS InputNumber,'InputNumber' AS ExceptionFieldName,'请录入批次重量!' AS Tips
			RETURN 0
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

			IF EXISTS(SELECT 1 FROM [dbo].[Operator] WHERE RefId=@LoadingItemLotId AND EmployeeId=@EmployeeId)
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
					   ,@LoadingItemLotId
					   ,@EmployeeId)

			SET @I_ReturnMessage='ServerMessage:员工工号['+@InputScan+']已添加为当前工序生产员工！' +@Enter
			SELECT '' AS InputScan,'CMDLOAD' AS Command,'InputScan' AS ExceptionFieldName,'请扫描操作指令!' AS Tips
			RETURN 0
		END

		IF @Command='CMDLOTMOVE'--当前指令为批次过站
		BEGIN
			--调用批次下线事件
			EXEC @RESULT=[dbo].[PDA_ProductionMakingSubmit]
			@I_Sender='TonBarrelSNScan',
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_PlugInCommand=@I_PlugInCommand,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@I_ResourceName=@I_ResourceName,
			@LoadingItemLotId=@LoadingItemLotId,
			@CurrWeight=@InputNumber OUTPUT,
			@TonBarrelSN=@InputScan
			IF @RESULT<>0
			BEGIN
				SELECT '' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName
				RETURN @RESULT
			END
			
			--执行批次下线
			SELECT @InputNumber AS InputNumber,'InputNumber' AS ExceptionFieldName,'请录入批次重量!' AS Tips
			RETURN 0
		END

		SET @I_ReturnMessage='ServerMessage:不可识别的操作指令' +@Enter
		RETURN 0
	END

	IF @I_Sender='LILPMakeCheckInputNumber'
	BEGIN
		SET @I_ExceptionFieldName='InputScan'
	    --工艺参数录入
		IF @Command IN ('CMDTEMPER','CMDPRESSE','CMDPSPEED','CMDSSCALE','CMDCURREN','CMDSPEED','CMDMWATER')
		BEGIN
			EXEC @RESULT=[dbo].[PDA_AddLoadingItemLotParams]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@LoadingItemLotId=@LoadingItemLotId,
			@ParamsType=@Command,
			@ParamsValue=@InputNumber
			IF @RESULT=0
			BEGIN
				SET @I_ReturnMessage='ServerMessage:工艺参数录入成功' +@Enter
			END

			SELECT 'CMDLOAD' AS Command,0 as InputNumber,'请扫描操作指令!' AS Tips
			RETURN @RESULT
		END

		IF @Command='CMDLOAD' OR @Command='CMDPSUPPLY' OR @Command=''--上料
		BEGIN
			IF ISNULL(@InputScan,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:请扫描物料条码' +@Enter
				RETURN 0
			END
			--调用上料事件
			EXEC @RESULT=[dbo].[PDA_ProductionMaking_LotSNScan]
			@I_Sender='UsedQtyScan',
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_PlugInCommand=@I_PlugInCommand,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@I_ResourceName=@I_ResourceName,
			@LoadingItemLotId=@LoadingItemLotId,
			@BoxOrLotSN=@InputScan,
			@EmployeeNo=@EmployeeNo,
			@UsedQty=@InputNumber,
			@Command=@Command

			SELECT @WaterProductId=P.ProductId FROM ProductRoot PR INNER JOIN Product P ON PR.ProductRootId=P.ProductRootId WHERE PR.ProductName='9999999999'
			SELECT @DiluentProductId=P.ProductId FROM ProductRoot PR INNER JOIN Product P ON PR.ProductRootId=P.ProductRootId WHERE PR.ProductName='1023450105'
			--获取当前要上的料
			

			SELECT @CurrMaterial=P.ProductDescription,
			@ItemQtyRequired=MOI.ItemQtyRequired,
			@ActualQty=LILD.ActualQty, 
			@LineSequence=MOI.LineSequence,
			@CurrMaterialId=MOI.ProductId
			FROM LoadingItemLot LIL 
			INNER JOIN MOItem MOI ON LIL.MOItemId=MOI.MOItemId
			INNER JOIN Product P ON MOI.ProductId=P.ProductId
			INNER JOIN LoadingItemLotDetail LILD ON LIL.LoadingItemLotId=LILD.LoadingItemLotId AND LIL.MOItemId=LILD.MOItemId
			WHERE LIL.LoadingItemLotId=@LoadingItemLotId

			SELECT @MOQtyRequired=MOQtyRequired,
			@LastMakingDate=LastMakingDate 
			FROM LoadingItemLot A 
			INNER JOIN MO B ON A.MOId=B.MOId 
			WHERE A.LoadingItemLotId=@LoadingItemLotId

			--获取下一物料
			IF ISNULL(@CurrMaterial,'')<>''
			BEGIN
				SET @Tips='请扫描物料条码进行上料!'
				SELECT TOP 1 @NextMaterial=C.ProductDescription FROM LoadingItemLotDetail L
				INNER JOIN MOItem A ON L.MOItemId=A.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				WHERE L.LoadingItemLotId=@LoadingItemLotId
				AND ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>L.ActualQty
				AND A.ProductId NOT IN (@WaterProductId,@DiluentProductId) 
				AND ((A.LineSequence>@LineSequence AND @CurrMaterialId NOT IN (@WaterProductId,@DiluentProductId)) OR @CurrMaterialId IN (@WaterProductId,@DiluentProductId))
				ORDER BY A.LineSequence

				IF ISNULL(@NextMaterial,'')=''
				BEGIN
					SELECT TOP 1 @NextMaterial=P.ProductDescription FROM LoadingItemLotDetail LILD 
					INNER JOIN MOItem MOI ON LILD.MOItemId=MOI.MOItemId
					INNER JOIN Product P ON MOI.ProductId=P.ProductId
					WHERE LILD.LoadingItemLotId=@LoadingItemLotId AND ISNULL(MOI.DeleteFlag,'') IN('','0')
					AND MOI.ProductId IN (@WaterProductId,@DiluentProductId) AND LILD.ActualQty<MOI.ItemQtyRequired 
					AND ((MOI.ProductId =@WaterProductId AND LILD.ActualQty>0 AND MOI.ProductId<>@CurrMaterialId)
					OR (MOI.ProductId =@DiluentProductId AND LILD.ActualQty=0))
					ORDER BY LineSequence
				END
			END

			EXEC @RESULT = [dbo].[PDA_VerifyFeedingProcess]
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
			@LoadingItemLotId=@LoadingItemLotId,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@IsFeeding=1,
			@MinStirringTime=@MinStirringTime OUTPUT,
			@MinStirringSpeed=@MinStirringSpeed OUTPUT,
			@MaxStirringSpeed=@MaxStirringSpeed OUTPUT,
			@Tips=@Tips OUTPUT
			IF @RESULT=-1 RETURN @RESULT
		
			IF @MinStirringTime<>0
			BEGIN
				SET @Tips+='工艺投料搅拌时间剩余['+CAST(@MinStirringTime AS VARCHAR(19))+']分钟'+@Enter
			END

			IF ISNULL(@CurrMaterial,'')<>'' AND ISNULL(@Tips,'')='' SET @Tips='请扫描物料条码进行上料!'

			IF ISNULL(@CurrMaterial,'')=''
			BEGIN
				SET @MixingTime=[dbo].[MixingTime](@SpecificationCode,@MOQtyRequired,@LastMakingDate)
				IF @MixingTime>0 SET @Tips+='工艺结束搅拌时间剩余['+CAST(@MixingTime AS VARCHAR(19))+']秒'+@Enter
				ELSE SET @Tips+='搅拌结束，请结束工艺!'+@Enter
			END

			SELECT '' AS InputScan,0 AS InputNumber,@CurrMaterial AS CurrMaterial,@NextMaterial AS NextMaterial,@ItemQtyRequired AS ItemQtyRequired,@ActualQty AS ActualQty,@Tips AS Tips
			RETURN @RESULT
		END
		IF @Command='CMDLOTMOVE'--批次过站
		BEGIN
			IF ISNULL(@InputScan,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:请扫描批次条码' +@Enter
				RETURN 0
			END
			
			--调用批次下线事件
			EXEC @RESULT=[dbo].[PDA_ProductionMakingSubmit]
			@I_Sender='LotMove',
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_PlugInCommand=@I_PlugInCommand,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@I_ResourceName=@I_ResourceName,
			@LoadingItemLotId=@LoadingItemLotId,
			@CurrWeight=@InputNumber,
			@TonBarrelSN=@InputScan

			IF @RESULT<>0 RETURN @RESULT
			
			--所有批次下线完成后自动完成制作
			IF NOT EXISTS(SELECT TOP 1 1 FROM LoadingItemLot LIL 
			INNER JOIN MOItem MOI ON LIL.MOId=MOI.MOId
			INNER JOIN MOItemLot MOIL ON MOI.MOItemId=MOIL.MOItemId
			INNER JOIN Lot ON MOIL.LotSN=Lot.LotSN AND LIL.SpecificationId=Lot.SpecificationId
			WHERE LIL.LoadingItemLotId=@LoadingItemLotId)
			BEGIN
				--调用制作完成事件
				EXEC @RESULT=[dbo].[PDA_ProductionMakingSubmit]
				@I_Sender='MakingComplete',
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_PlugInCommand=@I_PlugInCommand,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@I_ResourceName=@I_ResourceName,
				@LoadingItemLotId=@LoadingItemLotId
				IF @RESULT<>0
				BEGIN
					SELECT '' AS InputScan,0 AS InputNumber
					RETURN @RESULT
				END

				SELECT '' AS EmployeeNo,'' AS EquipmentNo,0 AS SeqNum,'' AS SpecificationCode,
				'' AS MOName,'' AS Command,'' AS InputScan,0 AS InputNumber,'' AS CurrMaterial,'' AS MOProduct,'' AS LoadingItemLotId,'请扫描操作指令!' AS Tips
				SET @I_ReturnMessage='ServerMessage:所有批次已下线成功，工单已完成制作，请重新选择工单!'+@Enter
				RETURN @RESULT
			END
			
			SET @I_ReturnMessage='ServerMessage:批次条码['+@InputScan+']下线成功' +@Enter
			SELECT '' AS InputScan,0 AS InputNumber,'请扫描操作指令!' AS Tips
			RETURN @RESULT
		END

		IF @Command='CMDWEIGH'--当前指令为称重
		BEGIN
			IF ISNULL(@InputScan,'')=''
			BEGIN
				SET @I_ReturnMessage='ServerMessage:请扫描批次条码' +@Enter
				RETURN 0
			END

			IF ISNULL(@InputScan,'')='' RETURN 0

			EXEC @RESULT=[dbo].[PDA_LotWeigh]
			@I_Sender='LotQtyScan',
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_PlugInCommand=@I_PlugInCommand,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@I_ResourceName=@I_ResourceName,
			@LoadingItemLotId=@LoadingItemLotId,
			@LotQty=@InputNumber OUTPUT,
			@LotSN=@InputScan

			IF @RESULT<>0 RETURN @RESULT

			SET @I_ReturnMessage='ServerMessage:批次称重完成' +@Enter
			SELECT 'CMDLOAD' AS Command,'' AS InputScan,0 AS InputNumber,'InputScan' AS ExceptionFieldName,'请扫描操作指令!' AS Tips
			RETURN @RESULT
		END
		SET @I_ReturnMessage='ServerMessage:请先扫描操作指令' +@Enter
		RETURN 0
	END
	SET @I_ReturnMessage='ServerMessage:请扫描' +@Enter


	RETURN 0
END
GO
