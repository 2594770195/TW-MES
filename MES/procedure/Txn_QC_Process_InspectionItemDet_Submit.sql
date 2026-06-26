
-- =============================================
-- Author:		<OrBit Team Admin>
-- Create date: <2020.05.27>
-- Description:	<过程检验-提交检验项数据>
-- Rev: 15.00
-- =============================================
CREATE PROCEDURE [dbo].[Txn_QC_Process_InspectionItemDet_Submit]
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
@Operator NVARCHAR(50) = '' ,					--	工号
@InsItemId CHAR(12) = '' ,						--  检验项明细ID
@XMLData NVARCHAR(MAX) = '' ,					--  XML数据
@DefectQty INT = 0 ,							--  缺陷数
@DefectCodeName NVARCHAR(50) = '' ,				--  缺陷代码
@MeasureQty INT = 0 ,							--  计量数
@MeasureValue FLOAT = 0,							--  计量值
@DefectRemark NVARCHAR(256)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @FileName VARCHAR(30) 
	declare @xml xml
	declare @idoc INT

	DECLARE @QC_ProcessInsId CHAR(12) = ''
	DECLARE @InsStates CHAR(3)= ''

	DECLARE @ItemName NVARCHAR(50)= ''
	DECLARE @QCMode CHAR(4)	= ''			-- 检验项类型分类 01:计量型 02:计数型 
	DECLARE @ItemType NVARCHAR(50)= ''
	DECLARE @ItemResult CHAR(2)= ''
	DECLARE @InspectionQty FLOAT = 0
	DECLARE @QCModeDes NVARCHAR(20)= ''

	DECLARE @ItemMaxValue FLOAT = 0
	DECLARE @ItemMinValue FLOAT = 0
	DECLARE @MeasureResult CHAR(2)= ''

	DECLARE @QC_ProcessIns_ItemDetId CHAR(12)= ''
	DECLARE @PTotal INT = 0					--	合格总数
	DECLARE @DefectTotal INT = 0			-- 不良总数
	DECLARE @InsQty INT = 0					-- 检验数
	DECLARE @Sum INT = 0

	DECLARE @RowId INT = 1
	DECLARE @Rows INT = 0

	DECLARE @DefectDes NVARCHAR(50)= ''
	DECLARE @Manualdecmak BIT = 0
	DECLARE @AC FLOAT = 0
	DECLARE @RE FLOAT = 0

	DECLARE @Enter CHAR(10)= CHAR(13)+CHAR(10)

	-- 定义XML临时表
	IF OBJECT_ID('tempdb..#XMLData') IS NOT NULL
		DROP TABLE #XMLData

	CREATE TABLE #XMLData
	(
		ID INT IDENTITY(1,1) ,
		QC_ProcessIns_ItemId CHAR(12) ,
		ItemName NVARCHAR(50) ,
		QCMode CHAR(2) ,
		ItemType NVARCHAR(50) ,
		ItemResult CHAR(3) ,				-- 检验项结果
		InspectionQty FLOAT					-- 检验数
	)

	set @FileName='/ResultDataSet/ResultDataSet'
	SET @xml = @XMlData
	SET @idoc = 0

	-- 检查是否有检验单号
	IF ISNULL(@InsName,'') = ''
	BEGIN

		SET @I_ReturnMessage = 'ServerMessage:未获取到检验单号，请先扫描批号获取 !'

		RETURN -1
	END

	-- 检查作业员工号是否为空
	IF ISNULL(@Operator,'') = ''
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:请扫描工号 !'

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
	    InspectionQty
	)
	SELECT 
		QC_ProcessIns_ItemId,
	    ItemName,
	    QCMode,
	    ItemType,
	    ItemResult,
	    InspectionQty
	FROM 
		OPENXML(@idoc,@FileName,2)
	--与XML即Excel的列名一致
	WITH 
	(
		QC_ProcessIns_ItemId CHAR(12) ,
		ItemName NVARCHAR(50) ,
		QCMode CHAR(2) ,
		ItemType NVARCHAR(50) ,
		ItemResult CHAR(3) ,				-- 检验项结果
		InspectionQty FLOAT					-- 检验数
	)

	-- 销毁XML
	exec sp_xml_removedocument @idoc
		
	-- 获取过程检验单号数据
	SET @InsStates = ''
	SET @QC_ProcessInsId = ''

	-- 获取检验单数据
	SELECT
		@QC_ProcessInsId = dbo.QC_ProcessIns.QC_ProcessInsId ,
		@InsStates = dbo.QC_ProcessIns.InsStates 
	FROM 
		dbo.QC_ProcessIns
	WHERE 
		dbo.QC_ProcessIns.InsName = @InsName

	-- 检查过程检验单号状态
	IF ISNULL(@InsStates,'')<>'10'
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:过程检验单【'+@InsName+'】不是待检状态.'

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

	-- 根据选中检验项明细Id获取检验项明细相应数据
	SET @QCMode = ''
	SET @ItemMaxValue = 0
	SET @ItemMinValue = 0
	SET @ItemName = ''
	SET @Manualdecmak = 0 -- 是否人工判定 0:系统判定 ;1:人工判定

	SELECT
		@QCMode = dbo.QC_ProcessIns_Item.QCMode ,
		@ItemMaxValue = dbo.QC_ProcessIns_Item.ItemMaxValue ,
		@ItemMinValue = dbo.QC_ProcessIns_Item.ItemMinValue ,
		@ItemName = dbo.QC_ProcessIns_Item.ItemName ,
		@Manualdecmak = dbo.QC_ProcessIns_Item.Manualdecmak ,
		@AC = QC_ProcessIns_Item.AC ,
		@RE = QC_ProcessIns_Item.RE
	FROM 
		dbo.QC_ProcessIns_Item
	WHERE 
		QC_ProcessIns_ItemId = @InsItemId

	-- 01:表示计量型
	IF ISNULL(@QCMode,'') = '01'
	BEGIN
		-- 检查计量数是否大于零
		IF ISNULL(@MeasureQty,0) <= 0
		BEGIN
			SET @I_ReturnMessage = 'ServerMessage:输入计量数必须大于零.'

			RETURN -1
		END 

		-- 检查输入计量值是大于零
		IF ISNULL(@MeasureValue,0) <= 0
		BEGIN
			SET @I_ReturnMessage = 'ServerMessage:输入计量值必须大于零.'

			RETURN -1
		END 

		-- 比较输入计量值大于下限值且小于上限值，则合格
		IF ISNULL(@MeasureValue,0) >= ISNULL(@ItemMinValue,0) AND ISNULL(@MeasureValue,0) <= ISNULL(@ItemMaxValue,0)
			SET @MeasureResult = 'OK'

		-- 比较输入计量值小于下限值 则不合格
		IF ISNULL(@MeasureValue,0) < ISNULL(@ItemMinValue,0) 
			SET @MeasureResult = 'NG'

		-- 比较输入计量值大于上限值 则不合格
		IF ISNULL(@MeasureValue,0) > ISNULL(@ItemMaxValue,0) 
			SET @MeasureResult = 'NG'
	end

	-- 02:表示计数型
	IF ISNULL(@QCMode,'') = '02'
	BEGIN
		-- 检查缺陷数是否大于零
		IF ISNULL(@DefectQty,0) <= 0 
		BEGIN
			SET @I_ReturnMessage = 'ServerMessage:输入缺陷数必须大于零.'

			RETURN -1
		END

		-- 检查不良代码是否存在系统中
		IF NOT EXISTS(SELECT 1 FROM dbo.DefectCode WHERE DefectCodeName = @DefectCodeName)
		BEGIN
			SET @I_ReturnMessage = 'ServerMessage:扫描缺陷代码【'+@DefectCodeName+'】不存在系统中.'

			RETURN -1
		END

		-- 检查扫描缺陷代码是否有效
		IF EXISTS(SELECT 1 FROM dbo.DefectCode WHERE DefectCodeName = @DefectCodeName AND IsActivity = 0)
		BEGIN
			SET @I_ReturnMessage = 'ServerMessage:扫描缺陷代码【'+@DefectCodeName+'】还未激活.'

			RETURN -1
		END

		-- 获取缺陷描述
		SET @DefectDes = ''

		SELECT
			@DefectDes = dbo.DefectCode.DefectCodeDescription
		FROM	
			dbo.DefectCode
		WHERE 
			DefectCodeName = @DefectCodeName
	END

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
	    MeasureQty,
	    MeasureValue,
	    MeasureResult,
		DefectQty ,
		DefectCodeName ,
	    DefectDescription ,
		ResourceId ,
	    CreateUser,
	    CreateDate,
		DefectRemark
	)
	VALUES
	(  
		@QC_ProcessIns_ItemDetId,      
	    @InsItemId ,       
	    @MeasureQty ,
		@MeasureValue ,
		@MeasureResult ,
		@DefectQty ,
		@DefectCodeName ,
		@DefectDes ,
		@I_ResourceId ,
		@I_OrBitUserName ,
		GETDATE(),
		@DefectRemark
	)

	-- 01:表示计量型
	IF ISNULL(@QCMode,'') = '01'
	BEGIN
		-- 统计计量型合格总数
		SET @PTotal = 0

		SELECT
			@PTotal = ISNULL(SUM(MeasureQty),0)
		FROM 
			QC_ProcessIns_ItemDet
		WHERE
			MeasureResult = 'OK'
		AND
			QC_ProcessIns_ItemId = @InsItemId
		AND
			ISNULL(DefectCodeName,'') =''

		-- 统计计量型不合格总数
		SET @DefectTotal = 0

		SELECT
			@DefectTotal = ISNULL(SUM(MeasureQty),0)
		FROM 
			QC_ProcessIns_ItemDet
		WHERE 
			MeasureResult = 'NG'
		AND
			QC_ProcessIns_ItemId = @InsItemId
		AND
			ISNULL(DefectCodeName,'') =''

		-- 获取总数
		SET @Sum = 0

		SELECT
			@Sum = ISNULL(SUM(MeasureQty),0)
		FROM 
			QC_ProcessIns_ItemDet
		WHERE
			QC_ProcessIns_ItemId = @InsItemId
		AND
			ISNULL(DefectCodeName,'') =''

	END

	-- 02:表示计数型
	IF ISNULL(@QCMode,'') = '02'
	BEGIN
		-- 统计计量型合格总数
		SET @PTotal = 0

		SELECT
			@PTotal = ISNULL(SUM(DefectQty),0)
		FROM 
			QC_ProcessIns_ItemDet
		WHERE
			ISNULL(DefectCodeName,'') ='0000'
		AND
			QC_ProcessIns_ItemId = @InsItemId
		AND
			ISNULL(DefectCodeName,'') <>''

		-- 统计计量型不合格总数
		SET @DefectTotal = 0

		SELECT
			@DefectTotal = ISNULL(SUM(DefectQty),0)
		FROM 
			QC_ProcessIns_ItemDet
		WHERE 
			ISNULL(DefectCodeName,'') <>''
		and
			ISNULL(DefectCodeName,'') <>'0000'
		AND
			QC_ProcessIns_ItemId = @InsItemId

		-- 获取总数
		SET @Sum = 0

		SELECT
			@Sum = ISNULL(SUM(DefectQty),0)
		FROM 
			QC_ProcessIns_ItemDet
		WHERE
			ISNULL(DefectCodeName,'') <>''
		AND
			QC_ProcessIns_ItemId = @InsItemId
	END

	-- 系统判定出结果 0:系统判定;1:人工判定
	if ISNULL(@Manualdecmak,0) = 0
	BEGIN
		-- 如果合格数大于等于允收数，则合格
		IF ISNULL(@PTotal,0) >= ISNULL(@Ac,0)
			SET @ItemResult = 'OK'

		-- 如果不良数大于等于拒收数，则不合格
		IF ISNULL(@DefectTotal,0) >= ISNULL(@Re,0)
			SET @ItemResult = 'NG'

	END

	SELECT @ItemResult=ItemResult FROM #XMLData WHERE QC_ProcessIns_ItemId = @InsItemId
	if ISNULL(@Manualdecmak,0) = 1 AND ISNULL(@ItemResult,'')=''
	BEGIN
	
		IF @QCMode='01'--定量型
		BEGIN
			IF @ItemMinValue<=@MeasureValue AND @MeasureValue<=@ItemMaxValue
				SET @ItemResult = 'OK'
			ELSE
				SET @ItemResult = 'NG'
			
		END

		IF @QCMode='02'--定性型
		BEGIN
			IF @DefectCodeName='0000'
				SET @ItemResult = 'OK'
			ELSE
				SET @ItemResult = 'NG'
		END
	END

	-- 更新检验项不良总数
	UPDATE
		dbo.QC_ProcessIns_Item
	SET
		dbo.QC_ProcessIns_Item.DefectTotal = @DefectTotal ,
		dbo.QC_ProcessIns_Item.ItemResult = @ItemResult ,
		dbo.QC_ProcessIns_Item.InspectionQty = @Sum
	WHERE 
		QC_ProcessIns_ItemId = @InsItemId

	-- 更新检验项明细中检验项结果、检验项检验数
	UPDATE
		dbo.QC_ProcessIns_Item
	SET 
		dbo.QC_ProcessIns_Item.ItemResult = CASE WHEN ISNULL(dbo.QC_ProcessIns_Item.ItemResult,'') = '' THEN TA.ItemResult ELSE dbo.QC_ProcessIns_Item.ItemResult end
	FROM 
		dbo.QC_ProcessIns_Item
		INNER JOIN #XMLData AS TA ON TA.QC_ProcessIns_ItemId = QC_ProcessIns_Item.QC_ProcessIns_ItemId
	WHERE
		dbo.QC_ProcessIns_Item.QC_ProcessInsId = @QC_ProcessInsId

	-- 01:表示计量型
	IF ISNULL(@QCMode,'') = '01'
	BEGIN
		-- 返回字段数据
		SELECT
			'' AS XMLData ,
			'' AS MeasureQty ,
			'' AS MeasureValue

		SET @I_ExceptionFieldName = 'MeasureQty'

		SET @I_ReturnMessage = 'ServerMessage:'+@QCMode+'检验项【'+@ItemName+'】提交成功. '
	end

	-- 02:表示计数型
	IF ISNULL(@QCMode,'') = '02'
	BEGIN
		-- 返回字段数据
		SELECT
			'' AS XMLData ,
			'' AS DefectQty ,
			'' AS DefectCodeName

		SET @I_ExceptionFieldName = 'DefectQty'

		SET @I_ReturnMessage = 'ServerMessage:'+@QCMode+'检验项【'+@ItemName+'】提交成功. '
	END

	SET @I_ReturnMessage = @I_ReturnMessage

	-- 删除临时表
	DROP TABLE #XMLData

	RETURN 0
END
go

