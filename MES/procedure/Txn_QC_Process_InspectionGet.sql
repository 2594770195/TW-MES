
-- =============================================
-- Author:		<OrBit Team Admin>
-- Create date: <2020.05.26>
-- Description:	<过程检验-根据批号获取检验单>
-- Rev: 15.00
-- =============================================
CREATE PROCEDURE	[dbo].[Txn_QC_Process_InspectionGet]
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
@Operator NVARCHAR(50) = '', 					--	检验员
@LotSN NVARCHAR(50) = '',
@SpecificationCode NVARCHAR(50) = ''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @LotId CHAR(12)
	DECLARE @QC_ProcessInsId CHAR(12)
	DECLARE @InsName NVARCHAR(50)
	DECLARE @SpecificationId CHAR(12)
	DECLARE @SpecificationRootId CHAR(12)
	DECLARE @MOId CHAR(12)
	DECLARE @MOName VARCHAR(12)

	-- 定义结果表变量
	DECLARE @Result TABLE
	(
		ID INT IDENTITY(1,1) ,
		InsName NVARCHAR(50) ,
		SubmissQty FLOAT ,
		SubmissCategory VARCHAR(20) ,
		SubmissDate DATETIME ,
		SubmissUser NVARCHAR(50) ,
		MOName NVARCHAR(50) ,
		ProductName NVARCHAR(256)
	)

	SET @LotId = ''
	SET @QC_ProcessInsId = ''
	SET @InsName = ''

	-- 写入空值
	INSERT INTO @Result
	(
	    InsName,
	    SubmissQty,
	    SubmissCategory,
	    SubmissDate,
	    SubmissUser,
	    MOName,
	    ProductName
	)
	VALUES
	(  
		N'',       
	    0.0,       
	    '',        
	    NULL, 
	    N'',       
	    N'',       
	    N''        
	)

	-- 检查单显示列按钮
	IF ISNULL(@I_Sender,'') = 'ProcessInsColumnShow'
	BEGIN
		-- 返回网格
		SELECT
			ID ,
			InsName,
			CASE WHEN CONVERT(INT,SubmissQty) = 0 THEN '' ELSE cast(CONVERT(INT,SubmissQty) AS VARCHAR) END AS SubmissQty,
			SubmissCategory,
			SubmissDate,
			SubmissUser,
			MOName,
			ProductName
		FROM
			@Result

		RETURN 0
	end
	-- 检查作业员工号是否为空
	IF ISNULL(@Operator,'') = ''
	BEGIN
	-- 返回网格
		SELECT
			ID ,
			InsName,
			SubmissQty,
			SubmissCategory,
			SubmissDate,
			SubmissUser,
			MOName,
			ProductName
		FROM
			@Result

		-- 返回界面字段
		SELECT
			'Error.png' AS WarnImage
		SET @I_ReturnMessage = 'ServerMessage:请扫描工号 !'

		SET @I_ExceptionFieldName = 'Operator'
		RETURN -1
	END 

	-- 检查作业员工号是否存在系统中
	IF NOT EXISTS(SELECT 1 FROM dbo.SysUser WHERE EmployeeNo = @Operator)
	BEGIN
		-- 返回网格
		SELECT
			ID ,
			InsName,
			SubmissQty,
			SubmissCategory,
			SubmissDate,
			SubmissUser,
			MOName,
			ProductName
		FROM
			@Result

		-- 返回界面字段
		SELECT
			'Error.png' AS WarnImage

		SET @I_ReturnMessage = 'ServerMessage:扫描工号【'+@Operator+'】不存在系统中 !'

		SET @I_ExceptionFieldName = 'Operator'

		RETURN -1
	END

	--检查规程代码是否为空
	IF ISNULL(@SpecificationCode,'')=''
	BEGIN
		-- 返回网格
		SELECT
			ID ,
			InsName,
			SubmissQty,
			SubmissCategory,
			SubmissDate,
			SubmissUser,
			MOName,
			ProductName
		FROM
			@Result

		-- 返回界面字段
		SELECT
			'Error.png' AS WarnImage

		SET @I_ExceptionFieldName = 'SpecificationCode'
		SET @I_ReturnMessage = 'ServerMessage:请扫描规程代码 !'
		RETURN -1
	END
	
	SELECT @SpecificationRootId=SpecificationRootId FROM SpecificationRoot WHERE SpecificationCode=@SpecificationCode
	IF ISNULL(@SpecificationRootId,'')=''
	BEGIN
		-- 返回网格
		SELECT
			InsName,
			SubmissQty,
			SubmissCategory,
			SubmissDate,
			SubmissUser,
			MOName,
			ProductName
		FROM
			@Result

		-- 返回界面字段
		SELECT
			'Error.png' AS WarnImage ,
			'' AS LotSN

		SET @I_ReturnMessage = 'ServerMessage:规程代码【'+@SpecificationCode+'】不存在.'

		SET @I_ExceptionFieldName = 'SpecificationCode'

		RETURN -1
	END

	-- 检查批号是否为空
	IF ISNULL(@LotSN,'') = ''
	BEGIN
		-- 返回网格
		SELECT
			ID ,
			InsName,
			SubmissQty,
			SubmissCategory,
			SubmissDate,
			SubmissUser,
			MOName,
			ProductName
		FROM
			@Result

		-- 返回界面字段
		SELECT
			'Error.png' AS WarnImage

		SET @I_ReturnMessage = 'ServerMessage:请扫描检验批号或工单 !'
		SET @I_ExceptionFieldName = 'LotSN'
		RETURN -1
	END

	--如果是扫工单
	IF EXISTS(SELECT 1 FROM MO WHERE MOName=@LotSN)
	BEGIN
		SET @MOName=@LotSN;
		SELECT TOP 1 @LotSN=B.LotSN FROM QC_ProcessIns A
		INNER JOIN QC_ProcessIns_SubLot B ON A.QC_ProcessInsId=B.QC_ProcessInsId
		INNER JOIN Lot C ON B.LotSN=C.LotSN
		INNER JOIN Specification D ON C.SpecificationId=D.SpecificationId
		WHERE A.MOId=(SELECT TOP 1 MOId FROM MO WHERE MOName=@MOName) AND A.InsStates='10' AND D.SpecificationRootId=@SpecificationRootId

		IF ISNULL(@LotSN,'')=''
		BEGIN
			-- 返回网格
			SELECT
				ID ,
				InsName,
				SubmissQty,
				SubmissCategory,
				SubmissDate,
				SubmissUser,
				MOName,
				ProductName
			FROM
				@Result

			-- 返回界面字段
			SELECT
				'Error.png' AS WarnImage

			SET @I_ReturnMessage = 'ServerMessage:当前扫描工单['+@MOName+']，没有找到匹配的检验单!'
			SET @I_ExceptionFieldName = 'LotSN'
			RETURN -1
		END
	END
	
	-- 检查扫描批号是否存在系统中
	SELECT @SpecificationId=SpecificationId FROM dbo.Lot WHERE LotSN = @LotSN

	IF ISNULL(@SpecificationId,'')=''
	BEGIN
		-- 返回网格
		SELECT
			InsName,
			SubmissQty,
			SubmissCategory,
			SubmissDate,
			SubmissUser,
			MOName,
			ProductName
		FROM
			@Result

		-- 返回界面字段
		SELECT
			'Error.png' AS WarnImage

		SET @I_ReturnMessage = 'ServerMessage:检验批号【'+@LotSN+'】不存在系统中 !'

		SET @I_ExceptionFieldName = 'LotSN'

		RETURN -1
	END

	-- 获取批号Id
	SELECT
		@LotId = dbo.Lot.LotId,
		@MOId=dbo.Lot.MOId
	FROM 
		dbo.Lot
	WHERE 
		Lot.LotSN = @LotSN
		
	--创建检验单，工序移送
	IF EXISTS(SELECT 1 FROM Lot L INNER JOIN Specification S ON L.SpecificationId=S.SpecificationId INNER JOIN SpecificationRoot SR ON S.SpecificationRootId=SR.SpecificationRootId WHERE L.LotId=@LotId AND SR.SpecificationCode='P00')
	BEGIN
		DECLARE @MOStates VARCHAR(8)
		SELECT TOP 1 @MOStates=MOStates,@MOName=MOName FROM MO WHERE MOId=@MOId AND ISNULL(DeleteFlag,'')<>'X'
		IF @MOStates<>'20'
		BEGIN
			-- 返回网格
			SELECT
				InsName,
				SubmissQty,
				SubmissCategory,
				SubmissDate,
				SubmissUser,
				MOName,
				ProductName
			FROM
				@Result

			-- 返回界面字段
			SELECT
				'Error.png' AS WarnImage
			
			SET @I_ReturnMessage = 'ServerMessage:扫描检验批号【'+@LotSN+'】所属工单【'+@MOName+'】不是已下达状态 !'

			SET @I_ExceptionFieldName = 'LotSN'
		END
		EXEC [dbo].[PDA_P00LotMove] 
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@MOId=@MOId
	END

	-- 检查扫描批号是否属于送检批号
	IF NOT EXISTS(SELECT 1 FROM QC_ProcessIns_SubLot WHERE LotId = @LotId)
	BEGIN
		-- 返回网格
		SELECT
			InsName,
			SubmissQty,
			SubmissCategory,
			SubmissDate,
			SubmissUser,
			MOName,
			ProductName
		FROM
			@Result

		-- 返回界面字段
		SELECT
			'Error.png' AS WarnImage
			
		SET @I_ReturnMessage = 'ServerMessage:扫描检验批号【'+@LotSN+'】不属于送检批号 !'

		SET @I_ExceptionFieldName = 'LotSN'

		RETURN -1
	END

	DECLARE @SubmissCategory VARCHAR(50)

	SET @SubmissCategory=@SpecificationCode

	IF @SubmissCategory ='COMIPQC'
		SET @SubmissCategory='IPQC'

	-- 获取批号获取送检单数据
	SET @QC_ProcessInsId = ''

	SELECT
		@QC_ProcessInsId = dbo.QC_ProcessIns_SubLot.QC_ProcessInsId 
	FROM 
		QC_ProcessIns_SubLot
		INNER JOIN dbo.QC_ProcessIns ON QC_ProcessIns.QC_ProcessInsId = QC_ProcessIns_SubLot.QC_ProcessInsId
	WHERE 
		QC_ProcessIns_SubLot.LotId = @LotId
	AND QC_ProcessIns.InsStates = '10'
	AND SubmissCategory=@SubmissCategory

	-- 获取过程检验单号
	SET @InsName = ''

	SELECT
		@InsName = QC_ProcessIns.InsName
	FROM 
		QC_ProcessIns
	WHERE 
		QC_ProcessIns.QC_ProcessInsId = @QC_ProcessInsId

	-- 检查扫描批号对应送检单是否被检验过
	IF ISNULL(@QC_ProcessInsId,'') = ''
	BEGIN
		-- 返回网格
		SELECT
			InsName,
			SubmissQty,
			SubmissCategory,
			SubmissDate,
			SubmissUser,
			MOName,
			ProductName
		FROM
			@Result

		-- 返回界面字段
		SELECT
			'Error.png' AS WarnImage ,
			'' AS LotSN

		SET @I_ReturnMessage = 'ServerMessage:扫描检验批号【'+@LotSN+'】未获取到检验单号.'

		SET @I_ExceptionFieldName = 'LotSN'

		RETURN -1
	END

	DECLARE @WorkflowStepId CHAR(12)=''
	SELECT @SpecificationId=SpecificationId,@WorkflowStepId=WorkflowStepId FROM dbo.Lot WHERE LotId = @LotId
	--检查批号是否在当前工作节点
	IF NOT EXISTS(SELECT 1 FROM Specification WHERE SpecificationId=@SpecificationId AND SpecificationRootId=@SpecificationRootId) AND @SpecificationCode NOT IN('TE')
		AND NOT EXISTS(	SELECT 1 FROM WorkflowStep B
				INNER JOIN Specification C ON B.SpecificationId=C.SpecificationId
				INNER JOIN SpecificationRoot D ON C.SpecificationRootId=D.SpecificationRootId
				INNER JOIN dbo.Workflow E ON E.WorkflowId = B.WorkflowId
				WHERE 1=1 AND B.WorkflowStepId=@WorkflowStepId
				AND (B.WorkflowStepName LIKE '%半成品入库申请%' OR B.WorkflowStepName LIKE '正压过滤%' OR B.WorkflowStepName LIKE'%D点检测%' OR B.WorkflowStepName LIKE'%半成品入库接收%')  
				AND E.WorkflowDescription LIKE '%UV半成品墨水%')--TODO 2026年3月4日
	BEGIN
		 --返回网格
		SELECT
			InsName,
			SubmissQty,
			SubmissCategory,
			SubmissDate,
			SubmissUser,
			MOName,
			ProductName
		FROM
			@Result

		-- 返回界面字段
		SELECT
			'Error.png' AS WarnImage ,
			'' AS LotSN

		SET @I_ReturnMessage = 'ServerMessage:扫描检验批号【'+@LotSN+'】不在当前工序节点.'

		SET @I_ExceptionFieldName = 'LotSN'

		RETURN -1
	END

	-- 清空
	DELETE FROM @Result
 
	-- 写入临时表
	INSERT INTO @Result
	(
	    InsName,
	    SubmissQty,
	    SubmissCategory,
	    SubmissDate,
	    SubmissUser,
	    MOName,
	    ProductName
	)
	SELECT
		dbo.QC_ProcessIns.InsName ,
		dbo.QC_ProcessIns.SubmissQty ,
		CASE 
			dbo.QC_ProcessIns.SubmissCategory
			WHEN 'FAI' THEN '首检'
			WHEN 'DPQC' THEN 'D浆检验'
			WHEN 'IPQC' THEN 'C点检验'
			WHEN 'TE' THEN 'D点检验'
			WHEN 'OQC' THEN '出货检验'
		ELSE'' END AS SubmissCategory ,
		dbo.QC_ProcessIns.SubmissDate ,
		dbo.QC_ProcessIns.SubmissUser ,
		MO.MOName ,
		dbo.ProductRoot.ProductName+'  '+dbo.Product.ProductDescription
	FROM 
		QC_ProcessIns
		INNER JOIN dbo.MO ON MO.MOId = QC_ProcessIns.MOId
		INNER JOIN dbo.Product ON MO.ProductId = dbo.Product.ProductId
		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
	WHERE 
		QC_ProcessIns.QC_ProcessInsId = @QC_ProcessInsId

	-- 返回网格
	SELECT
		InsName,
	    SubmissQty,
	    SubmissCategory,
	    SubmissDate,
	    SubmissUser,
	    MOName,
	    ProductName
	FROM
		@Result

	-- 返回字段
	SELECT
		@InsName AS InsName ,
		'OK.png' AS WarnImage

	RETURN 0
END



go

