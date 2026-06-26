-- =============================================
-- Author:		<OrBit Team Admin>
-- Create date: <2020.05.28>
-- Description:	<过程检验-提交判定结果>
-- Rev: 15.00
-- =============================================
CREATE PROCEDURE [dbo].[Txn_QC_Process_InspectionJudge_Submit]
@I_Sender NVARCHAR(200)='',						--	客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,		--	返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT,	--	向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',						--	客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',					--	插件命令
@I_OrBitUserId CHAR(12)='',						--	用户ID
@I_OrBitUserName NVARCHAR(100)='',				--	用户名
@I_ResourceId	CHAR(12)='',					--	资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',				--	资源名
@I_PKId CHAR(12) = '',							--	主键
@I_SourcePKId CHAR(12)='',						--	执行拷贝时传入的源主键  
@I_ParentPKId CHAR(12)='',						--	父级主键
@I_Parameter NVARCHAR(100)=''	,				--	插件参数	
-- ======================== 以上系统固定参数 ===========================
@InsName NVARCHAR(50) = '' ,
@Operator NVARCHAR(50) = '' ,					--	检验员
@RealJudge CHAR(3) = '' ,						--	判定结果
@XMLData NVARCHAR(MAX) = '', 					--	XML数据
@ProductTestTime NVARCHAR(MAX) = '' ,           -- 测试时间
@ErrorReasons NVARCHAR(MAX) = ''                -- 判定原因
    
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @FileName VARCHAR(30)
	declare @xml xml
	declare @idoc INT

	DECLARE @QC_ProcessInsId CHAR(12)= ''
	DECLARE @InsStates CHAR(3)= ''
	DECLARE @InsCategory CHAR(5)= ''

	DECLARE @QC_ProcessIns_ItemId CHAR(12)= ''
	DECLARE @ItemName NVARCHAR(50)= ''
	DECLARE @QCMode VARCHAR(20)	= ''		-- 检验项类型分类 01:计量型 02:计数型 
	DECLARE @ItemResult CHAR(2)= ''
	DECLARE @InspectionQty FLOAT = 0
	DECLARE @ItemSTDValue FLOAT = 0	 	-- 标准值
	DECLARE @ItemMaxValue FLOAT = 0		-- 上限值
	DECLARE @ItemMinValue FLOAT	= 0		-- 下限值
	DECLARE @QCModeDes NVARCHAR(20)= ''

	DECLARE @QC_ProcessIns_ItemDetId CHAR(12)= ''
	DECLARE @DefectTotal INT = 0			-- 不良总数

	DECLARE @RowId INT = 0
	DECLARE @Rows INT = 0

	DECLARE @DefectDes NVARCHAR(50) = ''

	DECLARE @ExceptionContent NVARCHAR(500)= ''
	DECLARE @ExceptionDes NVARCHAR(500)= ''
	DECLARE @MeasureQty FLOAT = 0
	DECLARE @MeasureValue FLOAT = 0
	DECLARE @MeasureResult CHAR(2)= ''   
	DECLARE @DefectQty FLOAT = 0
	DECLARE @DefectCodeName NVARCHAR(50) = ''

	DECLARE @ExceptionName NVARCHAR(50)= ''
	DECLARE @ExceptionStates CHAR(4)= ''
	DECLARE @QC_ExceptionId CHAR(12)= ''
	DECLARE @JdgeRes CHAR(2)= ''
	DECLARE @SysJudgeRes CHAR(2) = ''
	DECLARE @CurDate DATETIME =GETDATE()
	DECLARE @DataChainId CHAR(12)
	DECLARE @TxnCode VARCHAR(10)='MOVE'

	DECLARE @MOId CHAR(12)

	DECLARE @Enter CHAR(10)= CHAR(10)
	DECLARE @EntryQty DECIMAL(18,8)
	DECLARE @FinishingEntryName VARCHAR(50)
	DECLARE @FinishingEntryId CHAR(12)

	-- 定义XML临时表
	IF OBJECT_ID('tempdb..#XMLData') IS NOT NULL
		DROP TABLE #XMLData

	CREATE TABLE #XMLData
	(
		ID INT IDENTITY(1,1) ,
		QC_ProcessIns_ItemId CHAR(12) ,
		ItemName NVARCHAR(50) ,
		QCMode NVARCHAR(20) ,
		ItemType NVARCHAR(50) ,
		ItemResult CHAR(3) ,				-- 检验项结果
		InspectionQty FLOAT	,				-- 检验数
		ItemSTDValue FLOAT ,				-- 标准值
		ItemMaxValue FLOAT ,				-- 上限值
		ItemMinValue FLOAT					-- 下限值
	)

	-- 定义批号临时表
	IF OBJECT_ID('tempdb..#LotTable') IS NOT NULL
		DROP TABLE #LotTable

	CREATE TABLE #LotTable
	(
		ID INT IDENTITY(1,1) ,
		LotId CHAR(12) ,
		SpecificationId CHAR(12) ,
		WorkcenterId CHAR(12) ,
		MOItemTaskId CHAR(12) ,
		MOId CHAR(12) ,
		ProductId CHAR(12)
	)

	-- 定义批量主键临时表
	IF OBJECT_ID('tempdb..#PKTable') IS NOT NULL
		DROP TABLE #PKTable

	CREATE TABLE #PKTable
	(
		ID INT ,
		PKId CHAR(12)
	)

	set @FileName='/ResultDataSet/ResultDataSet'
	SET @xml = @XMlData
	SET @idoc = 0

	-- 检查是否有检验单号
	IF ISNULL(@InsName,'') = ''
	BEGIN

		SET @I_ReturnMessage = 'ServerMessage:未获取到检验单号，请先扫描批号获取 !'

		SET @I_ExceptionFieldName = 'LotSN'

		RETURN -1
	END

	-- 检查作业员工号是否为空
	IF ISNULL(@Operator,'') = ''
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:请扫描工号 !'

		SET @I_ExceptionFieldName = 'Operator'

		RETURN -1
	END 

	-- 检查作业员工号是否存在系统中
	IF NOT EXISTS(SELECT 1 FROM dbo.SysUser WHERE EmployeeNo = @Operator)
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:扫描工号【'+@Operator+'】不存在系统中 !'

		RETURN -1
	END
    
	-- 检查作业员工号是否存有效性
	--IF EXISTS(SELECT 1 FROM dbo.PersonInfo WHERE PersonNumber = @Operator AND IsActivity = 0)
	--BEGIN
	--	SET @I_ReturnMessage = 'ServerMessage:扫描工号【'+@Operator+'】已离职 !'

	--	RETURN -1
	--end
    
	IF ISNULL(@RealJudge,'') =''
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:请选择判定结果!'

		RETURN -1
	END
	-- 检查判定结果是否选择 OK,NG
	IF ISNULL(@RealJudge,'') NOT IN('OK','NG','NGJ','LH') AND ISNULL(@RealJudge,'') <>''
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:选择判定结果不合法 !'

		RETURN -1
	end

	--======================================Irving 2024.01.17 解决D点打印合格，但是需要重新品保检测 做判定（重新过滤or入库）1.1================================================================================
    --LHFlag 老化标记( 修改最终标记结果 )  GrindQCResult_PathCondition
    DECLARE @LHFlag INT = 0
    -- QA判断（QualityMark质量标记 合格则是 D点合格返回来的）
    IF ISNULL(@RealJudge,'') ='LH'
	BEGIN
	    --如果是选择 LH 老化，D点的逻辑改成OK，按正常OK的走（但是流向 墨水待判断处理 交给QA处理）
		SET @RealJudge = 'OK'
	    --设置 LHFlag = 1
	    set @LHFlag = 1
	END
	--======================================Irving 2024.01.17 解决D点打印合格，但是需要重新品保检测 做判定（重新过滤or入库）1.1================================================================================

	-- 检查检验项网格是否有数据
	if ISNULL(@XMlData,'')=''
	BEGIN

		set @I_ReturnMessage='ServerMessage:请先获取检验项数据!'

		return -1
	END
    
	--将XML转换成临时表
	exec sp_xml_preparedocument @idoc output, @xml

	-- 写入中间表 XMLData
	INSERT INTO #XMLData
	(
	    QC_ProcessIns_ItemId,
	    ItemName,
	    QCMode,
	    ItemType,
	    ItemResult,
	    InspectionQty ,
		ItemSTDValue ,
		ItemMaxValue ,
		ItemMinValue
	)
	SELECT 
		QC_ProcessIns_ItemId,
	    ItemName,
	    QCMode,
	    ItemType,
	    ItemResult,
	    InspectionQty ,
		ItemSTDValue ,
		ItemMaxValue ,
		ItemMinValue
	FROM 
		OPENXML(@idoc,@FileName,2)
	--与XML即Excel的列名一致
	WITH 
	(
		QC_ProcessIns_ItemId CHAR(12) ,
		ItemName NVARCHAR(50) ,
		QCMode NVARCHAR(20) ,
		ItemType NVARCHAR(50) ,
		ItemResult CHAR(3) ,				-- 检验项结果
		InspectionQty FLOAT	,				-- 检验数
		ItemSTDValue FLOAT ,
		ItemMaxValue FLOAT ,
		ItemMinValue FLOAT
	)

	-- 销毁XML
	exec sp_xml_removedocument @idoc

	-- 获取过程检验单号数据
	SET @InsStates = ''
	SET @QC_ProcessInsId = ''
	SET @InsCategory = ''

	-- 获取检验单数据
	SELECT
		@QC_ProcessInsId = dbo.QC_ProcessIns.QC_ProcessInsId ,
		@InsStates = dbo.QC_ProcessIns.InsStates ,
		@InsCategory = dbo.QC_ProcessIns.SubmissCategory,
		@MOId=dbo.QC_ProcessIns.MOId
	FROM 
		dbo.QC_ProcessIns
	WHERE 
		dbo.QC_ProcessIns.InsName = @InsName AND @InsStates='10'

	IF ISNULL(@QC_ProcessInsId,'')=''
	BEGIN
		SELECT
			@QC_ProcessInsId = dbo.QC_ProcessIns.QC_ProcessInsId ,
			@InsStates = dbo.QC_ProcessIns.InsStates ,
			@InsCategory = dbo.QC_ProcessIns.SubmissCategory,
			@MOId=dbo.QC_ProcessIns.MOId
		FROM 
			dbo.QC_ProcessIns
		WHERE 
			dbo.QC_ProcessIns.InsName = @InsName
	END

	-- 检查过程检验单号状态
	IF ISNULL(@InsStates,'')<>'10'
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:过程检验单【'+@InsName+'】不是待检状态.'

		RETURN -1
    END

	IF  ISNULL(@RealJudge,'')='NGJ' AND @InsCategory<>'IPQC'
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:此判定结果为墨水C点检验专用.'

		RETURN -1
	END

	-- 统计临时表个数
	SET @Rows = 0

	SELECT
		@Rows = COUNT(ID)
	FROM 
		#XMLData
	-- 赋值
	SET @RowId = 1
 
	-- While循环检查
	WHILE @RowId <= @Rows
	BEGIN
		-- 赋值
		SET @QC_ProcessIns_ItemId = ''
		SET @ItemName = ''
		SET @QCMode = ''
		SET @ItemResult = ''
		SET @InspectionQty = 0
		SET @ItemSTDValue = 0
		SET @ItemMaxValue = 0
		SET @ItemMinValue = 0
		SET @ExceptionDes = ''

		-- 获取数据
		SELECT
			@QC_ProcessIns_ItemId = TA.QC_ProcessIns_ItemId,
			@ItemName = TA.ItemName ,
			@QCMode = TA.QCMode ,
			@ItemResult = TA.ItemResult ,
			@InspectionQty = ISNULL(TA.InspectionQty,0) ,
			@ItemSTDValue = ISNULL(TA.ItemSTDValue ,0) ,
			@ItemMaxValue = ISNULL(TA.ItemMaxValue,0) ,
			@ItemMinValue = ISNULL(TA.ItemMinValue,0)
		FROM 
			#XMLData AS TA
		WHERE
			TA.ID = @RowId

		-- 计量型
		IF ISNULL(@QCMode,'') = '定量型'
		BEGIN
			-- 检查检验项结果是否出来
			IF ISNULL(@ItemResult,'') = ''
			BEGIN
				SET @I_ReturnMessage = 'ServerMessage:'+@QCMode+'检验项【'+@ItemName+'】判定结果未出.'

				RETURN -1
			END

			-- 检查是否录入检验项明细数据
			IF NOT EXISTS(SELECT 1 FROM dbo.QC_ProcessIns_ItemDet WHERE QC_ProcessIns_ItemDet.QC_ProcessIns_ItemId = @QC_ProcessIns_ItemId)
			BEGIN
				SET @I_ReturnMessage = 'ServerMessage:'+@QCMode+'检验项【'+@ItemName+'】判定结果【'+@ItemResult+'】必须录入检验明细数据.'

				RETURN -1
			END
			-- 检查如果是计量型检验项必须录入计量检验明细数据
			IF NOT EXISTS(SELECT 1 FROM dbo.QC_ProcessIns_ItemDet WHERE QC_ProcessIns_ItemDet.QC_ProcessIns_ItemId = @QC_ProcessIns_ItemId)
			BEGIN
				SET @I_ReturnMessage = 'ServerMessage:'+@QCMode+'检验项【'+@ItemName+'】判定结果【'+@ItemResult+'】必须录入【定量型】明细数据.'

				RETURN -1
			END

			-- 赋值
			SET @DefectTotal = 0

			SELECT
				@DefectTotal = ISNULL(SUM(QC_ProcessIns_ItemDet.MeasureQty),0)
			FROM 
				dbo.QC_ProcessIns_ItemDet
			WHERE 
				dbo.QC_ProcessIns_ItemDet.QC_ProcessIns_ItemId = @QC_ProcessIns_ItemId
			AND
				dbo.QC_ProcessIns_ItemDet.MeasureResult = 'NG'

			-- 获取计量型不良明细数
			SET @MeasureQty = 0
			SET @MeasureValue = 0
			SET @MeasureResult = ''

			SELECT
				@MeasureQty = QC_ProcessIns_ItemDet.MeasureQty ,
				@MeasureValue = QC_ProcessIns_ItemDet.MeasureValue ,
				@MeasureResult = QC_ProcessIns_ItemDet.MeasureResult
			FROM 
				dbo.QC_ProcessIns_ItemDet
			WHERE 
				dbo.QC_ProcessIns_ItemDet.QC_ProcessIns_ItemId = @QC_ProcessIns_ItemId
			AND
				dbo.QC_ProcessIns_ItemDet.MeasureResult = 'NG'

			-- 检验项结果为NG，保存异常内容
			SET @ExceptionDes = '【'+@QCMode+'】检验项【'+@ItemName+'】标准值【'+CAST(@ItemSTDValue AS VARCHAR)+'】 上限值【'+CAST(@ItemMaxValue AS VARCHAR)+'】'+@Enter
			+'下限值【'+CAST(@ItemMinValue AS VARCHAR)+'】不良总数【'+CAST(@DefectTotal AS VARCHAR)+'】'+@Enter
			+'不良明细:'+@Enter
			+' 计量数【'+CAST(@MeasureQty AS VARCHAR)+'】 计量值【'+CAST(@MeasureQty AS VARCHAR)+'】计量结果【'+@MeasureResult+'】 '
		END
			
		-- 计数型
		IF ISNULL(@QCMode,'') = '定性型'
		BEGIN
			--定性型未判定结果自动PASS
			IF ISNULL(@ItemResult,'') = ''
			BEGIN
				-- 申请主键
				EXEC dbo.SysGetObjectPKId 
				@ObjectId = '',      
				@ObjectName = N'QC_ProcessIns_ItemDet',  
				@PKID = @QC_ProcessIns_ItemDetId OUTPUT 

				-- 写入检验项明细表
				INSERT INTO dbo.QC_ProcessIns_ItemDet
				(
					QC_ProcessIns_ItemDetId,
					QC_ProcessIns_ItemId,
					DefectQty ,
					DefectCodeName ,
					DefectDescription ,
					ResourceId ,
					CreateUser,
					CreateDate
				)
				VALUES
				(  
					@QC_ProcessIns_ItemDetId,      
					@QC_ProcessIns_ItemId ,    
					1 ,
					'0000' ,
					'PASS' ,
					@I_ResourceId ,
					@I_OrBitUserName ,
					GETDATE()
				)

				-- 更新检验项不良总数
				UPDATE
					dbo.QC_ProcessIns_Item
				SET
					dbo.QC_ProcessIns_Item.DefectTotal = 1 ,
					dbo.QC_ProcessIns_Item.ItemResult = 'OK' ,
					dbo.QC_ProcessIns_Item.InspectionQty = 1
				WHERE 
					QC_ProcessIns_ItemId = @QC_ProcessIns_ItemId
			END

			-- 赋值
			SET @DefectTotal = 0

			SELECT
				@DefectTotal = ISNULL(SUM(QC_ProcessIns_ItemDet.DefectQty),0)
			FROM 
				dbo.QC_ProcessIns_ItemDet
			WHERE 
				dbo.QC_ProcessIns_ItemDet.QC_ProcessIns_ItemId = @QC_ProcessIns_ItemId
			AND
				ISNULL(dbo.QC_ProcessIns_ItemDet.DefectCodeName,'') <> ''

			-- 获取计数型不良明细数
			SET @DefectQty = 0
			SET @DefectCodeName = ''

			SELECT
				@DefectQty = QC_ProcessIns_ItemDet.DefectQty ,
				@DefectCodeName = QC_ProcessIns_ItemDet.DefectCodeName+' '+dbo.QC_ProcessIns_ItemDet.DefectDescription
			FROM 
				dbo.QC_ProcessIns_ItemDet
			WHERE 
				dbo.QC_ProcessIns_ItemDet.QC_ProcessIns_ItemId = @QC_ProcessIns_ItemId
			AND
				ISNULL(dbo.QC_ProcessIns_ItemDet.DefectCodeName,'') <> ''

			-- 检验项结果为NG，保存异常内容
			SET @ExceptionDes = '【'+@QCMode+'】检验项【'+@ItemName+'】检验数【'+CAST(@InspectionQty AS VARCHAR)+'】不良总数【'+CAST(@DefectTotal AS VARCHAR)+'】'+@Enter
			+'不良明细:'+@Enter
			+' 缺陷数【'+CAST(@DefectQty AS VARCHAR)+'】 缺陷代码【'+CAST(@DefectCodeName AS VARCHAR)+'】'
		END

		-- 拼接内容
		IF ISNULL(@ExceptionContent,'') = ''
			SET @ExceptionContent = @ExceptionDes
		ELSE
			SET @ExceptionContent = @ExceptionContent+@Enter+@ExceptionDes

		SET @RowId = @RowId + 1
	END

	SET @SysJudgeRes= 'OK'
	-- 如果检验中存在合格的且没有不合格的,则判定合格 
	IF EXISTS(SELECT 1 FROM dbo.QC_ProcessIns_Item WHERE QC_ProcessIns_Item.QC_ProcessInsId = @QC_ProcessInsId AND QC_ProcessIns_Item.ItemResult = 'OK' )
		AND NOT EXISTS(SELECT 1 FROM QC_ProcessIns_Item WHERE QC_ProcessIns_Item.QC_ProcessInsId = @QC_ProcessInsId AND QC_ProcessIns_Item.ItemResult = 'NG')
	BEGIN
		SET @SysJudgeRes= 'OK' -- 合格
	END

	-- 如果检验项中存在不合格的,则判定不合格
	IF EXISTS(SELECT 1 FROM QC_ProcessIns_Item WHERE QC_ProcessIns_Item.QC_ProcessInsId = @QC_ProcessInsId AND QC_ProcessIns_Item.ItemResult = 'NG')
	BEGIN
		SET @SysJudgeRes='NG' -- 不合格
	END

	-- 选择判定结果 NG 生成异常单
	IF ISNULL(@SysJudgeRes,'') = 'NG'
	BEGIN
		--申请单据号
		EXEC [dbo].[Txn_BillNewSN]
			@BillName = N'QC_Exception',
			@NewSN = @ExceptionName OUTPUT,
			@BillStates= @ExceptionStates OUTPUT

		if ltrim(@ExceptionName)=''
		begin
			set @I_ReturnMessage='ServerMessage:未申请到异常单号.'

			return -1
		END

		-- 申请主键
		EXEC dbo.SysGetObjectPKId 
			@ObjectId = '',      
		    @ObjectName = N'QC_Exception',   
		    @PKID = @QC_ExceptionId OUTPUT 
		
		-- 写入异常单表
		INSERT INTO QC_Exception
		(
			QC_ExceptionId ,
			ExceptionName ,
			ExceptionStates ,
			SourceBillName ,
			ExceptionType ,
			ExceptionContent ,
			CreateUser ,
			CreateDate
		)
		VALUES
		(
			@QC_ExceptionId ,
			@ExceptionName ,
			@ExceptionStates ,
			@InsName ,
			@InsCategory ,
			@ExceptionContent ,
			@Operator ,
			GETDATE()
		)

		-- 查找检验单对应所有批号写入临时表
		INSERT INTO #LotTable
		(
		    LotId,
		    SpecificationId,
		    WorkcenterId,
		    MOItemTaskId,
		    MOId,
		    ProductId
		)
		SELECT
			Lot.LotId ,
			Lot.SpecificationId ,
			Lot.WorkcenterId ,
			Lot.MOItemTaskId ,
			Lot.MOId ,
			Lot.ProductId
		FROM 
			dbo.QC_ProcessIns_SubLot
			INNER JOIN Lot ON Lot.LotId = QC_ProcessIns_SubLot.LotId
		WHERE
			QC_ProcessIns_SubLot.QC_ProcessInsId = @QC_ProcessInsId

		-- 统计批号临时表个数
		SET @Rows = 0

		SELECT
			@Rows = COUNT(ID)
		FROM 
			#LotTable

		-- 批量申请主键
		INSERT INTO #PKTable
		(
		    ID,
		    PKId
		)
		EXEC dbo.SysGetObjectPKIdBatch 
			@ObjectId = '',    
		    @ObjectName = N'AlarmItemInfo', 
		    @RowCount = @Rows  
			
		-- 批号写入报警信息明细表
		INSERT INTO dbo.AlarmItemInfo
		(
		    AlarmItemInfoId,
			MOItemTaskId ,
		    MOId,
		    ProductId,
		    LotId,
		    SpecificationId,
		    WorkcenterId,
		    ResourceId,
		    Operator,
		    CreateDate
		)
		SELECT
			TB.PKId ,
			TA.MOItemTaskId ,
			TA.MOId ,
			TA.ProductId ,
			TA.LotId ,
			TA.SpecificationId ,
			TA.WorkcenterId ,
			@I_ResourceId AS ResourceId ,
			@Operator ,
			GETDATE() AS CreateDate
		FROM 
			#LotTable AS TA
			INNER JOIN #PKTable AS TB ON TB.ID = TA.ID 

		SET @JdgeRes = 'NG'
	end
	
	-- 统计检验项中不良总数
	SET @DefectTotal = 0

	SELECT
		@DefectTotal = ISNULL(SUM(DefectTotal),0)
	FROM 
		dbo.QC_ProcessIns_Item
	WHERE 
		QC_ProcessIns_Item.QC_ProcessInsId = @QC_ProcessInsId

	-- 更新检验单数据
	UPDATE
		dbo.QC_ProcessIns
	SET
		dbo.QC_ProcessIns.RealInQty = ISNULL(dbo.QC_ProcessIns.SubmissQty,0) - ISNULL(@DefectTotal,0) ,
		dbo.QC_ProcessIns.TotalDefectQty = @DefectTotal ,
		dbo.QC_ProcessIns.InsResult = @SysJudgeRes ,
		dbo.QC_ProcessIns.RealInsResult = @RealJudge ,
		dbo.QC_ProcessIns.InsDate = GETDATE() ,
		dbo.QC_ProcessIns.Inspector = @Operator ,
		dbo.QC_ProcessIns.InsStates = '20'
	WHERE
		dbo.QC_ProcessIns.QC_ProcessInsId = @QC_ProcessInsId

	-- 如果存在异常信息，则插入扩展信息
	IF ISNULL(@ErrorReasons,'') != '' OR ISNULL(@ProductTestTime,'') != ''
	BEGIN
        INSERT INTO dbo.ZR_QC_ProcessIns_Extend  (
            QC_ProcessInsId, ErrorReasons, ProductTestTime,CreateUser,CreateDate
        ) VALUES (@QC_ProcessInsId,@ErrorReasons,@ProductTestTime,@Operator,GETDATE())
    END


    --========================================Irving 2025.01.18 添加D点老化（合格）===========================================================================
	-- 处理 GrindQCResult_PathCondition 路径返回判断是否为真，OK路径会修改入库单为20，添加LH不做修改个，返回真
    IF ISNULL(@LHFlag,'') = 1
    BEGIN
        UPDATE
            dbo.QC_ProcessIns
        SET
            dbo.QC_ProcessIns.RealInsResult = 'LH'
        WHERE
		    dbo.QC_ProcessIns.QC_ProcessInsId = @QC_ProcessInsId
    End
    --========================================Irving 2025.01.18 添加D点老化（合格）===========================================================================

	-- 更新检验项明细中检验项结果、检验项检验数
	UPDATE
		dbo.QC_ProcessIns_Item
	SET 
		dbo.QC_ProcessIns_Item.ItemResult = CASE WHEN ISNULL(dbo.QC_ProcessIns_Item.ItemResult,'') = '' THEN TA.ItemResult ELSE dbo.QC_ProcessIns_Item.ItemResult END
	FROM 
		dbo.QC_ProcessIns_Item
		INNER JOIN #XMLData AS TA ON TA.QC_ProcessIns_ItemId = QC_ProcessIns_Item.QC_ProcessIns_ItemId
	WHERE
		QC_ProcessIns_Item.QC_ProcessInsId = @QC_ProcessInsId

	IF EXISTS(SELECT 1 FROM QC_ProcessIns_SubLot A 
	INNER JOIN Lot B ON A.LotSN=B.LotSN
	INNER JOIN Specification C ON B.SpecificationId=C.SpecificationId
	INNER JOIN SpecificationRoot D ON C.SpecificationRootId=D.SpecificationRootId
	WHERE A.QC_ProcessInsId=@QC_ProcessInsId AND (CASE D.SpecificationCode WHEN 'COMIPQC' THEN 'IPQC' ELSE D.SpecificationCode END)=@InsCategory)OR EXISTS
	(SELECT 1 FROM QC_ProcessIns_SubLot A 
	INNER JOIN Lot B ON A.LotSN=B.LotSN
	INNER JOIN Specification C ON B.SpecificationId=C.SpecificationId
	INNER JOIN SpecificationRoot D ON C.SpecificationRootId=D.SpecificationRootId
	INNER JOIN dbo.Workflow E ON E.WorkflowId = B.WorkflowId
	WHERE A.QC_ProcessInsId=@QC_ProcessInsId 
	AND (D.SpecificationCode IN('UBXR','GL+','TE','SFGW') AND E.WorkflowDescription LIKE '%UV半成品墨水%')) --TODO 只针对UV半成品跳过C点
	BEGIN
		--C点检验判定不合格开启调单，否则传送到下一道工序
		IF (ISNULL(@RealJudge,'') = 'NG' AND RTRIM(LTRIM(@InsCategory)) ='IPQC') OR RTRIM(LTRIM(@InsCategory))='DPQC'
		BEGIN
			--开启调单
			IF RTRIM(LTRIM(@InsCategory))<>'DPQC'
			BEGIN
				UPDATE MO SET IsAdjustment=1,AdjustmentNumber=(ISNULL(AdjustmentNumber,1)+1) WHERE MOId=@MOId
			END
			SET @I_ReturnMessage = 'ServerMessage:【'+@InsCategory+'】检验单【'+@InsName+'】判定结果【'+CASE WHEN ISNULL(@RealJudge,'')<>'' THEN @RealJudge ELSE @SysJudgeRes END +'】，请调整工单用量. '
			
			--TODO 直接移送到墨水待处理 2026年3月4日
			IF EXISTS
				(SELECT 1 FROM QC_ProcessIns_SubLot A 
				INNER JOIN Lot B ON A.LotSN=B.LotSN
				INNER JOIN Specification C ON B.SpecificationId=C.SpecificationId
				INNER JOIN SpecificationRoot D ON C.SpecificationRootId=D.SpecificationRootId
				INNER JOIN dbo.Workflow E ON E.WorkflowId = B.WorkflowId
				WHERE A.QC_ProcessInsId=@QC_ProcessInsId
				AND (D.SpecificationCode IN('UBXR','GL+','TE','SFGW') AND E.WorkflowDescription LIKE '%UV半成品墨水%')) --TODO 只针对UV半成品跳过C点
			BEGIN
				DECLARE @LotSN02 NVARCHAR(100)=''
				SELECT TOP 1  @LotSN02=LotSN FROM QC_ProcessIns
				LEFT JOIN dbo.Lot ON Lot.MOId = QC_ProcessIns.MOId WHERE SubmissCategory='IPQC' AND LOT.MOId= @MOId AND QC_ProcessInsId = @QC_ProcessInsId ORDER BY dbo.QC_ProcessIns.CreateDate DESC
				--移送到下一道工序 会移动到墨水待处理
				EXEC [dbo].[TxnBase_LotMove] 
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@LotSN=@LotSN02,
				@LotInDate=@CurDate	
			END;
		END
		ELSE
		BEGIN
			select TOP 1 ROW_NUMBER() OVER(ORDER BY QCP.LotSN) AS ROWKEY,QCP.LotId,QCP.LotSN,L.MOId,L.ProductId,L.WorkcenterId,L.SpecificationId,L.WorkflowStepId,L.Qty INTO #TEMP from QC_ProcessIns_SubLot QCP
			inner join Lot L ON QCP.LotId=L.LotId
			INNER JOIN Specification S ON L.SpecificationId=S.SpecificationId
			INNER JOIN SpecificationRoot SR ON S.SpecificationRootId=SR.SpecificationRootId 

			where QCP.QC_ProcessInsId=@QC_ProcessInsId AND (CASE SR.SpecificationCode WHEN 'COMIPQC' THEN 'IPQC' ELSE SR.SpecificationCode END)=RTRIM(LTRIM(@InsCategory))



			DECLARE @ROWNUMBER INT=0
			DECLARE @ROWKEY INT=1
			DECLARE @LotId CHAR(12)
			DECLARE @WorkcenterId CHAR(12)
			DECLARE @SpecificationId CHAR(12)
			DECLARE @WorkflowStepId CHAR(12)
			DECLARE @ProductId CHAR(12)
			DECLARE @LotSN VARCHAR(100)

			SELECT @ROWNUMBER=COUNT(1) FROM #TEMP

			WHILE @ROWKEY<=@ROWNUMBER
			BEGIN
				SELECT 
					@LotId=LotId,
					@MOId=MOId,
					@ProductId=ProductId,
					@WorkcenterId=WorkcenterId,
					@SpecificationId=SpecificationId,
					@WorkflowStepId=WorkflowStepId,
					@LotSN=LotSN,
					@EntryQty=Qty
				FROM #TEMP WHERE ROWKEY=@ROWKEY

				UPDATE Lot SET QualityMark=(CASE ISNULL(@RealJudge,'') WHEN 'OK' THEN 'Q' ELSE 'NQ' END) WHERE LotSN=@LotSN

				IF RTRIM(LTRIM(@InsCategory))='TE' AND ISNULL(@RealJudge,'') = 'OK'
				BEGIN
					SELECT @FinishingEntryId=C.FinishingEntryId FROM FinishingEntryItemLot A
					INNER JOIN FinishingEntryItem B ON A.FinishingEntryItemId=B.FinishingEntryItemId
					INNER JOIN FinishingEntry C ON B.FinishingEntryId=C.FinishingEntryId
					WHERE A.LotSN=@LotSN

					IF ISNULL(@FinishingEntryId,'')<>''
					BEGIN
						UPDATE FinishingEntry SET FinishingEntryStates='20',
						ApproveUserId = @I_OrBitUserId, 
						ApproveDate = GETDATE() 
						WHERE FinishingEntryId=@FinishingEntryId
					END
				END

				IF @InsCategory='OQC' AND ISNULL(@RealJudge,'') = 'OK'
				BEGIN TRY
					EXEC dbo.Txn_FinishedEntry_Scan
					@I_Sender=@I_Sender,
					@I_ReturnMessage=@I_ReturnMessage OUTPUT, -- nvarchar(max)
					@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT, -- nvarchar(100)
					@I_LanguageId=@I_LanguageId,
					@I_PlugInCommand=@I_PlugInCommand,
					@I_OrBitUserId=@I_OrBitUserId,
					@I_OrBitUserName=@I_OrBitUserName,
					@I_ResourceId=@I_ResourceId,
					@I_ResourceName=@I_ResourceName,
					@I_PKid=@I_PKid,
					@I_ParentPKId=@I_ParentPKId,
					@I_Parameter=@I_Parameter,
					@WhCategoryCode='02',
					@WhCategory='成品入库',
					@WareHouseId='WKC1000007Q2',
					@WareHouseName='A101',
					@CellName='A101',
					@ScanSN=@LotSN,
					@EntryQty=@EntryQty

					
					SELECT @FinishingEntryName=C.FinishingEntryName FROM FinishingEntryItemLot A
					INNER JOIN FinishingEntryItem B ON A.FinishingEntryItemId=B.FinishingEntryItemId
					INNER JOIN FinishingEntry C ON B.FinishingEntryId=C.FinishingEntryId
					WHERE A.LotSN=@LotSN

					EXEC dbo.TxnBase_MBill_FinishingEntryConfirm
					@I_Sender='FinishingEntryConfirm',
					@I_ReturnMessage=@I_ReturnMessage OUTPUT, -- nvarchar(max)
					@I_PlugInCommand='FINEA',
					@I_OrBitUserId=@I_OrBitUserId,
					@I_OrBitUserName=@I_OrBitUserName,
					@I_ResourceId=@I_ResourceId,
					@I_ResourceName=@I_ResourceName,
					@I_Parameter=@I_Parameter,
					@FinishingEntryName=@FinishingEntryName
				END TRY
				BEGIN CATCH
					SET @I_ReturnMessage
                  = 'ServerMessage: 发生错误：' + CHAR(13) + CHAR(10) + '[行号：'
                  + LTRIM(RTRIM(CONVERT(CHAR(100), ERROR_LINE()))) + ' 错误号：'
                  + LTRIM(RTRIM(CONVERT(CHAR(100), ERROR_NUMBER()))) + ']，存储过程名：'+ERROR_PROCEDURE() + ERROR_MESSAGE();
				  RETURN -1
				END CATCH
                ELSE IF @InsCategory='IPQC' AND ISNULL(@RealJudge,'') = 'OK' 
                AND EXISTS (SELECT 1 FROM QC_ProcessIns_SubLot A 
                            INNER JOIN Lot B ON A.LotSN=B.LotSN
                            INNER JOIN dbo.Workflow E ON E.WorkflowId = B.WorkflowId
                            WHERE A.QC_ProcessInsId=@QC_ProcessInsId AND E.WorkflowDescription LIKE '%UV组合液%')
				BEGIN TRY
                    --移送到下一道工序 会移动到半成品入库
                    EXEC [dbo].[TxnBase_LotMove] 
                    @I_ReturnMessage=@I_ReturnMessage OUTPUT,
                    @I_OrBitUserId=@I_OrBitUserId,
                    @I_ResourceId=@I_ResourceId,
                    @LotSN=@LotSN,
                    @LotInDate=@CurDate	

                    EXEC dbo.PDA_FinishedEntryReceive_Scan
					@I_Sender=@I_Sender,
					@I_ReturnMessage=@I_ReturnMessage OUTPUT, -- nvarchar(max)
					@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT, -- nvarchar(100)
					@I_LanguageId=@I_LanguageId,
					@I_PlugInCommand=@I_PlugInCommand,
					@I_OrBitUserId=@I_OrBitUserId,
					@I_OrBitUserName=@I_OrBitUserName,
					@I_ResourceId=@I_ResourceId,
					@I_ResourceName=@I_ResourceName,
					@I_PKid=@I_PKid,
					@I_ParentPKId=@I_ParentPKId,
					@I_Parameter=@I_Parameter,
					@WareHouseId='WKC100000HR6',
					@WareHouseName='UVXB',
					@CellName='',
					@ScanSN=@LotSN
				END TRY
				BEGIN CATCH
					SET @I_ReturnMessage
                  = 'ServerMessage: 发生错误：' + CHAR(13) + CHAR(10) + '[行号：'
                  + LTRIM(RTRIM(CONVERT(CHAR(100), ERROR_LINE()))) + ' 错误号：'
                  + LTRIM(RTRIM(CONVERT(CHAR(100), ERROR_NUMBER()))) + ']，存储过程名：'+ERROR_PROCEDURE() + ERROR_MESSAGE();
				  RETURN -1
				END CATCH
				ELSE
				BEGIN
					--移送到下一道工序
					EXEC [dbo].[TxnBase_LotMove] 
					@I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@I_OrBitUserId=@I_OrBitUserId,
					@I_ResourceId=@I_ResourceId,
					@LotSN=@LotSN,
					@LotInDate=@CurDate	
				END
				
				SET @ROWKEY+=1
			END
			SET @I_ReturnMessage = 'ServerMessage:【'+@InsCategory+'】检验单【'+@InsName+'】判定结果【'+CASE WHEN ISNULL(@RealJudge,'')<>'' THEN @RealJudge ELSE @SysJudgeRes END +'】，请继续检验. '

		END
	END
	ELSE
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:【'+@InsCategory+'】检验单【'+@InsName+'】判定结果【'+CASE WHEN ISNULL(@RealJudge,'')<>'' THEN @RealJudge ELSE @SysJudgeRes END +'】，请继续检验. '
	END

	-- ==============================================2026年2月7日 13:50:24 如果C点检测通过,发送一个不需要调单的信息到DCS ================================================
	if ISNULL(@RealJudge,'') = 'OK' AND @InsCategory = 'IPQC'
	BEGIN
	    if exists (select * from ZR_DCS_ORDER where moid = @moId)
	        BEGIN
            DECLARE @jsonObj_Signal nvarchar(max); -- 调单信号JSON变量

            DECLARE @instanceRootId VARCHAR(100);
            DECLARE @moName VARCHAR(100);

            select @moName = MO.MOName from QC_ProcessIns
            left join MO on QC_ProcessIns.MOId=MO.MOId
            where QC_ProcessIns.InsName = @InsName

            select @instanceRootId=dcsProcedureId from ZR_DCS_ORDER where moid = @moId

            if ISNULL(@moName,'') != '' and ISNULL(@instanceRootId,'') != ''
                BEGIN
                    -- 核心：生成调单信号JSON，动态取instanceId和dataType
                    SET @jsonObj_Signal = (
                        SELECT
                            @instanceRootId AS instanceRootId,
                            -- 核心：WITHOUT_ARRAY_WRAPPER 让instanceParams输出为单个对象（非数组）
                            JSON_QUERY((
                                SELECT
                                    @instanceRootId AS instanceId, -- instanceParams下的instanceId
                                    -- JSON_QUERY包裹targetValues数组，字段严格匹配目标格式
                                    JSON_QUERY((
                                        SELECT
                                            N'BACK_QA' AS [param.name], -- 固定名称
--                                             N'是否进行调单(1:不调单 2:调单)' AS [param.description], -- 固定描述
                                            3 AS [param.dataType], -- 移除关联后用固定值3（原默认值）
                                            CAST(1 AS BIT) AS [param.isEditable], -- 布尔值true
--                                             1 AS [param.value], -- 固定值1不调单
                                            '1' AS runtimeValue, -- 固定runtimeValue=1
                                            @instanceRootId AS instanceId -- targetValues内的instanceId
                                        FOR JSON PATH -- 保留targetValues数组格式
                                    )) AS targetValues
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER -- 关键：instanceParams为单个对象
                            )) AS instanceParams
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
                    );

                    -- 调试用：打印调单信号JSON（按需保留）
                    -- SELECT @jsonObj_Signal AS Signal_GeneratedJson;
                    BEGIN TRY 
                    -- 调用DCS接口发送调单信号（复用第一步的接口存储过程）
                    DECLARE @RESULT_DCS_SIGNAL nvarchar(max);
                    EXEC @RESULT_DCS_SIGNAL=[dbo].[MESUpdateDCSDoMethod]
                        @I_Sender=@I_Sender,
                        @I_ReturnMessage=@I_ReturnMessage output,
                        @I_ExceptionFieldName=@I_ExceptionFieldName output,
                        @I_LanguageId=@I_LanguageId,
                        @I_PlugInCommand=@I_PlugInCommand,
                        @I_OrBitUserId=@I_OrBitUserId,
                        @I_OrBitUserName=@I_OrBitUserName,
                        @I_ResourceId=@I_ResourceId,
                        @I_ResourceName=@I_ResourceName,
                        @I_PKid=@I_PKid,
                        @I_ParentPKId=@I_ParentPKId,
                        @I_Parameter=@I_Parameter,
                        @jsonObj=@jsonObj_Signal; -- 传入调单信号JSON
                        
                        --C点通过后修改通知表状态
                        update ZR_DCS_C_NOTICE set isNotice = 'N' where moname = @moname
                        
                        insert into ZR_DCS_INTERFACE_LOG(id,intType,inputParam,outParam,createTime) 
                        values(newid(),'DCS-C点通过：' + @moName,@jsonObj_Signal,@RESULT_DCS_SIGNAL,getdate())
                    END TRY
                    BEGIN CATCH
                        insert into ZR_DCS_INTERFACE_LOG(id,intType,inputParam,outParam,createTime) 
                        values(newid(),'DCS-C点通过接口异常：' + @moName,@jsonObj_Signal,@RESULT_DCS_SIGNAL,getdate())
                        SET @I_ReturnMessage
                        = 'ServerMessage: 发生错误：' + CHAR(13) + CHAR(10) + '[行号：'
                        + LTRIM(RTRIM(CONVERT(CHAR(100), ERROR_LINE()))) + ' 错误号：'
                        + LTRIM(RTRIM(CONVERT(CHAR(100), ERROR_NUMBER()))) + ']，存储过程名：'+ERROR_PROCEDURE() + ERROR_MESSAGE();
                        RETURN -1
                    END CATCH
                    
      
                END
        end
	END
	

	-- 返回界面字段数据
	SELECT
		@ExceptionName AS ExceptionName ,
		'' AS LotSN ,
		'' AS InsName ,
		'' AS XMLData ,
		'' AS JudgeResult,
		@JdgeRes AS JdgeRes

	SET @I_ExceptionFieldName = 'LotSN'

	-- 删除临时表
	DROP TABLE #XMLData

	DROP TABLE #LotTable

	DROP TABLE #PKTable

	RETURN 0
END
go

