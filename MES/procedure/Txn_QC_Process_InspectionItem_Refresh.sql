
-- =============================================
-- Author:		<OrBit Team Admin>
-- Create date: <2020.05.27>
-- Description:	<过程检验-根据批号获取检验项明细>
-- Rev: 15.00
-- =============================================
CREATE PROCEDURE [dbo].[Txn_QC_Process_InspectionItem_Refresh]
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
@InsName NVARCHAR(50) = '',
@Operator NVARCHAR(50) = '' 					--	检验员

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @QC_ProcessInsId CHAR(12)= ''
	DECLARE @InsStates CHAR(3)= ''
	DECLARE @MOId CHAR(12)= ''
	DECLARE @MOName NVARCHAR(50)= ''
	DECLARE @ProductId CHAR(12)= ''
	DECLARE @ProductName NVARCHAR(50)= ''
	DECLARE @ProductFamilyId CHAR(12)= ''
	DECLARE @ProductFamilyName NVARCHAR(50)= ''
	DECLARE @QCType VARCHAR(10)= ''

	DECLARE @ProductFamily_QCItemId CHAR(12)= ''
	DECLARE @Product_QCItemId CHAR(12)= ''
	DECLARE @QCMode CHAR(4)= ''
	DECLARE @ItemMaxValue FLOAT = 0
	DECLARE @ItemMinValue FLOAT = 0
	DECLARE @ItemName NVARCHAR(50)= ''
	DECLARE @ItemSequence CHAR(10)= ''
	DECLARE @AQLInsLvCode CHAR(10) = ''
	DECLARE @AQLInsValue CHAR(10) = ''
	DECLARE @SubmissQty INT = 0
	DECLARE @SampleSize FLOAT = 0
	DECLARE @Ac FLOAT= 0
	DECLARE @Re FLOAT= 0
	DECLARE @ItemResult CHAR(4) = ''
	DECLARE @DefectTotal INT = 0

	DECLARE @RowId INT = 1
	DECLARE @Rows INT = 0

	DECLARE @ItemType NVARCHAR(50)= ''
	DECLARE @ItemDescription NVARCHAR(80)= ''
	DECLARE @ItemSTDValue DECIMAL(18,6) = 0
	DECLARE @ItemUOMId CHAR(12)= ''
	DECLARE @CheckMethod NVARCHAR(50)= ''
	DECLARE @IsAllowArtificialJudge bit  = 0 -- 0:表示按AQL执行；1:表示人工判定
	DECLARE @ReferDocument NVARCHAR(50)= ''
	DECLARE @DrawDocument NVARCHAR(50)= ''

	DECLARE @QC_ProcessIns_ItemId CHAR(12)= ''

	DECLARE @Enter CHAR(10)= CHAR(13)+CHAR(10)

	-- 检验项目
    DECLARE @QCItem_Temp TABLE
	(
		ID INT IDENTITY(1,1),
		ProductFamily_QCItemId CHAR(12) 
	)

	DECLARE @QC_ProdItem_Temp TABLE
	(
		ID INT IDENTITY(1,1),
		Product_QCItemId CHAR(12)
	)

	-- 定义产品族检验项
	DECLARE @ProductFam_Temp TABLE
	(
		ID INT IDENTITY(1,1) ,
		QCType CHAR(4),
	    QCMode CHAR(3),
	    ItemSequence CHAR(10),
	    ItemType NVARCHAR(50),
	    ItemName NVARCHAR(50),
	    ItemDescription NVARCHAR(80),
	    ItemSTDValue DECIMAL(18,6),
	    ItemMaxValue DECIMAL(18,6),
	    ItemMinValue DECIMAL(18,6),
	    ItemUOMId CHAR(12),
		CheckLevelCode CHAR(10) ,
		AQLQualityStandard CHAR(10) ,
	    CheckMethod NVARCHAR(50),
	    IsAllowArtificialJudge bit ,
	    ReferDocument NVARCHAR(50),
	    DrawDocument NVARCHAR(50),
	    ModifyUserId CHAR(12),
	    ModifyDate DATETIME,
	    CreateUserId CHAR(12),
	    Createdate DATETIME
	)

	-- 显示检验项列标题按钮
	IF ISNULL(@I_Sender,'') = 'InsItemColumnShow'
	BEGIN
		-- 返回网格数据
		--SELECT 	
		--	'11' AS QC_ProcessIns_ItemId,
		--	'22' AS ItemName , 
		--	'22' AS QCMode ,
		--	'22' AS ItemType,
		--	'22' AS ItemResult ,
		--	'22' AS InspectionQty ,
		--	'33' AS DefectCount ,
		--	'1' AS ItemSTDValue,
		--	'2' AS ItemMaxValue,
		--	'3' AS ItemMinValue,
		--	'mm' AS UOMName

		--RETURN 0

		-- 返回网格数据
		SELECT 	
			'' AS QC_ProcessIns_ItemId,
			'' AS ItemName , 
			'' AS QCMode ,
			'' AS ItemType,
			'' AS ItemResult ,
			'' AS InspectionQty ,
			'' AS DefectTotal ,
			'' AS ItemSTDValue,
			'' AS ItemMaxValue,
			'' AS ItemMinValue,
			'' AS UOMName

		RETURN 0
	end

	-- 检查是否有检验单号
	IF ISNULL(@InsName,'') = ''
	BEGIN

		SET @I_ReturnMessage = 'ServerMessage:未获取到检验单号，请先扫描批号获取 !'

		RETURN -1
	END
    
	-- 获取过程检验单号数据
	SET @QC_ProcessInsId = ''
	SET @InsStates = ''
	SET @MOId = ''
	SET @QCType = ''
	SET @SubmissQty = 0

	SELECT
		@QC_ProcessInsId = dbo.QC_ProcessIns.QC_ProcessInsId ,
		@InsStates = dbo.QC_ProcessIns.InsStates ,
		@MOId = dbo.QC_ProcessIns.MOId ,
		@QCType = dbo.QC_ProcessIns.SubmissCategory ,
		@SubmissQty = dbo.QC_ProcessIns.SubmissQty
	FROM 
		dbo.QC_ProcessIns
	WHERE 
		dbo.QC_ProcessIns.InsName = @InsName AND InsStates='10'

	IF ISNULL(@QC_ProcessInsId,'')=''
	BEGIN
		SELECT
			@QC_ProcessInsId = dbo.QC_ProcessIns.QC_ProcessInsId ,
			@InsStates = dbo.QC_ProcessIns.InsStates ,
			@MOId = dbo.QC_ProcessIns.MOId ,
			@QCType = dbo.QC_ProcessIns.SubmissCategory ,
			@SubmissQty = dbo.QC_ProcessIns.SubmissQty
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
	IF EXISTS(SELECT 1 FROM dbo.SysUser WHERE EmployeeNo = @Operator AND IsActivity = 0)
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:扫描工号【'+@Operator+'】未激活 !'

		RETURN -1
	end
		--TODO
		--2026年1月23日 取消已做检验时，新增检验项无法实时刷新的问题，不再默认取已录入检验项明细，而是根据维护项刷新
	IF NOT EXISTS(SELECT 1 FROM QC_ProcessIns_Item WHERE QC_ProcessInsId = @QC_ProcessInsId)
	BEGIN
		-- 获取工单对应产品Id
		SET @ProductId = ''
		SET @MOName = ''

		SELECT
			@ProductId = MO.ProductId ,
			@MOName = MO.MOName
		FROM 
			dbo.MO
		WHERE 
			dbo.MO.MOId = @MOId

		-- 获取产品所对应产品族ID
		SET @ProductFamilyId = ''
		SET @ProductName = ''

		SELECT
			@ProductFamilyId = dbo.ProductRoot.ProductFamilyId ,
			@ProductName = dbo.ProductRoot.ProductName
		FROM 
			dbo.Product
			INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
		WHERE 
			dbo.Product.ProductId = @ProductId

		-- 获取产品族
		SET @ProductFamilyName = ''

		SELECT
			@ProductFamilyName = dbo.ProductFamily.ProductFamilyName
		FROM 
			dbo.ProductFamily
		WHERE 
			ProductFamilyId = @ProductFamilyId

		--如果是生产墨水进行D浆检测，查找BOM中半成品D浆的检验项
		IF @QCType='DPQC' AND NOT EXISTS
			(
				SELECT 
					1 
				FROM 
					dbo.Product_QCItem 
				WHERE 
					Product_QCItem.ProductId = @ProductId
				AND
					Product_QCItem.QCType = @QCType
			)
		BEGIN
			DECLARE @DProductId CHAR(12)
			
			SELECT @ProductId=ProductId FROM QC_Inspection WHERE MOId=@MOId
			IF ISNULL(@DProductId,'')=''
			BEGIN
				SELECT TOP 1 @ProductId=A.ProductId FROM MOItem A
				INNER JOIN Product B ON A.ProductId=B.ProductId 
				WHERE A.MOId=@MOId AND (CASE WHEN LEN(B.ProductDescription)>3 THEN LEFT(B.ProductDescription,3) ELSE '' END)<>'COM'
				AND B.ProductClassify=2 AND A.LineSequence<>'000'
			END

			SELECT
				@ProductFamilyId = dbo.ProductRoot.ProductFamilyId ,
				@ProductName = dbo.ProductRoot.ProductName
			FROM 
				dbo.Product
				INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
			WHERE 
				dbo.Product.ProductId = @ProductId

			SET @QCType='IPQC'

			--判断是否存在检验项
			--IF EXISTS(SELECT 1 FROM Product_QCItem WHERE ProductId=@DProductId AND QCType='IPQC')
			--BEGIN
			--	SELECT ROW_NUMBER() OVER(ORDER BY Createdate) AS QCItemId,
			--		Product_QCItemId,
			--		ProductId,
			--		VendorId,
			--		QCType,
			--		QCMode,
			--		ItemSequence,
			--		ItemType,
			--		ItemName,
			--		ItemDescription,
			--		ItemSTDValue,
			--		ItemMaxValue,
			--		ItemMinValue,
			--		ItemUOMId,
			--		CheckLevelCode,
			--		AQLQualityStandard,
			--		CheckMethod,
			--		IsAllowArtificialJudge,
			--		ReferDocument,
			--		DrawDocument,
			--		ModifyUserId,
			--		ModifyDate,
			--		CreateUserId,
			--		Createdate  
			--	INTO #TEMP FROM Product_QCItem WHERE ProductId=@DProductId AND QCType='IPQC'

			--	DECLARE @QCItemCount INT 
			--	DECLARE @QCItemId INT=1
			

			--	SELECT @QCItemCount=COUNT(1) FROM #TEMP
			--	WHILE @QCItemId<=@QCItemCount
			--	BEGIN
			--		-- 申请主键
			--		EXEC dbo.SysGetObjectPKId 
			--			@ObjectId = '',      
			--			@ObjectName = N'Product_QCItem',   
			--			@PKID = @Product_QCItemId OUTPUT 

			--		-- 写入产品检验设置表
			--		INSERT INTO dbo.Product_QCItem
			--		(
			--			Product_QCItemId,
			--			ProductId,
			--			VendorId,
			--			QCType,
			--			QCMode,
			--			ItemSequence,
			--			ItemType,
			--			ItemName,
			--			ItemDescription,
			--			ItemSTDValue,
			--			ItemMaxValue,
			--			ItemMinValue,
			--			ItemUOMId,
			--			CheckLevelCode,
			--			AQLQualityStandard,
			--			CheckMethod,
			--			IsAllowArtificialJudge,
			--			ReferDocument,
			--			DrawDocument,
			--			ModifyUserId,
			--			ModifyDate,
			--			CreateUserId,
			--			Createdate 
			--		)
			--		SELECT @Product_QCItemId,
			--			@ProductId,
			--			VendorId,
			--			'DPQC',
			--			QCMode,
			--			ItemSequence,
			--			ItemType,
			--			ItemName,
			--			ItemDescription,
			--			ItemSTDValue,
			--			ItemMaxValue,
			--			ItemMinValue,
			--			ItemUOMId,
			--			CheckLevelCode,
			--			AQLQualityStandard,
			--			CheckMethod,
			--			IsAllowArtificialJudge,
			--			ReferDocument,
			--			DrawDocument,
			--			@I_OrBitUserId,
			--			GETDATE(),
			--			@I_OrBitUserId,
			--			GETDATE()  
			--		FROM #TEMP WHERE QCItemId=@QCItemId

			--		SET @QCItemId+=1
			--	END
			
			--END
		END

		-- 检查产品族检验设置与产品检验设置中是否都未维护检验项
		IF NOT EXISTS
			(
				SELECT 
					1 
				FROM 
					ProductFamily_QCItem 
				WHERE 
					ProductFamily_QCItem.ProductFamilyId = @ProductFamilyId
				AND
					ProductFamily_QCItem.QCType = @QCType
		
			)
		AND
			NOT EXISTS
			(
				SELECT 
					1 
				FROM 
					dbo.Product_QCItem 
				WHERE 
					Product_QCItem.ProductId = @ProductId
				AND
					Product_QCItem.QCType = @QCType
			)
		BEGIN
			SET @I_ReturnMessage = 'ServerMessage:过程检验单【'+@InsName+'】对应工单【'+@MOName+'】产品【'+@ProductName+'】和产品族【'+@ProductFamilyName+'】.'+@Enter
			+'都未维护检验项设置，二者请设置其中一个.'

			RETURN -1
		END

		-- 如果产品族中存在检验项设置，写入表变量中
		IF EXISTS(SELECT 
					1 
				FROM 
					ProductFamily_QCItem 
				WHERE 
					ProductFamily_QCItem.ProductFamilyId = @ProductFamilyId
				AND
					ProductFamily_QCItem.QCType = @QCType)
			AND
				NOT EXISTS(
					SELECT 1 FROM dbo.Product_QCItem WHERE ProductId = @ProductId AND QCType = @QCType
				)
		BEGIN
			-- 写入表变量
			INSERT INTO @QCItem_Temp
			(
				ProductFamily_QCItemId
			)
			SELECT
				ProductFamily_QCItemId
			FROM 
				ProductFamily_QCItem 
			WHERE 
				ProductFamily_QCItem.ProductFamilyId = @ProductFamilyId
			AND
				ProductFamily_QCItem.QCType = @QCType  

			-- 查找产品族检验项数据写入表变量
			INSERT INTO @ProductFam_Temp
			(
				QCType,
				QCMode,
				ItemSequence,
				ItemType,
				ItemName,
				ItemDescription,
				ItemSTDValue,
				ItemMaxValue,
				ItemMinValue,
				ItemUOMId,
				CheckLevelCode ,
				AQLQualityStandard ,
				CheckMethod,
				IsAllowArtificialJudge,
				ReferDocument,
				DrawDocument,
				ModifyUserId,
				ModifyDate,
				CreateUserId,
				Createdate
			)
			SELECT
				QCType,
				QCMode,
				ItemSequence,
				ItemType,
				ItemName,
				ItemDescription,
				ItemSTDValue,
				ItemMaxValue,
				ItemMinValue,
				ItemUOMId,
				CheckLevelCode ,
				AQLQualityStandard ,
				CheckMethod,
				IsAllowArtificialJudge,
				ReferDocument,
				DrawDocument,
				@I_OrBitUserId AS ModifyUserId,
				GETDATE() AS ModifyDate,
				@I_OrBitUserId AS CreateUserId,
				GETDATE() AS Createdate
			FROM 
				ProductFamily_QCItem 
			WHERE 
				ProductFamily_QCItem.ProductFamilyId = @ProductFamilyId
			AND
				ProductFamily_QCItem.QCType = @QCType
		
		END

		-- 统计表变量中个数
		SET @Rows = 0

		SELECT
			@Rows = COUNT(ID)
		FROM 
			@QCItem_Temp

		-- 赋值
		set @RowId = 1

		-- While循环检查 
		WHILE @RowId <= @Rows
		BEGIN
			-- 获取表变量数据
			set @ProductFamily_QCItemId = ''

			select
				@ProductFamily_QCItemId = TA.ProductFamily_QCItemId 
			from 
				@QCItem_Temp as TA
			where 
				TA.ID = @RowId

			-- 如果产品族检验项设置不为空
			-- 获取检验项信息
			-- 赋值
			SET @ItemName = ''
			SET @QCMode = ''
			SET @ItemMaxValue = 0
			SET @ItemMinValue = 0
			SET @AQLInsLvCode = ''
			SET @AQLInsValue = ''
			SET @IsAllowArtificialJudge = 0

			SELECT
				@ItemName= ItemName,
				@QCMode = QCMode,
				@ItemMaxValue = ItemMaxValue,
				@ItemMinValue = ItemMinValue ,
				@AQLInsValue = AQLQualityStandard ,
				@IsAllowArtificialJudge = dbo.ProductFamily_QCItem.IsAllowArtificialJudge
			FROM 
				ProductFamily_QCItem
			WHERE 
				ProductFamily_QCItem.ProductFamily_QCItemId = @ProductFamily_QCItemId

			-- 人工判定 0表示按钮AQL
			IF ISNULL(@IsAllowArtificialJudge,0) = 0
			BEGIN
				-- 检查产品族检验设置是否有维护检验方案
				IF EXISTS(SELECT 1 FROM ProductFamily_QCItem WHERE ProductFamily_QCItem.ProductFamily_QCItemId=@ProductFamily_QCItemId 
					AND ( ISNULL(CheckLevelCode,'')='' OR ISNULL(AQLQualityStandard,'')='') )
				BEGIN
					SET @I_ReturnMessage = 'ServerMessage:该送检单产品编码【'+@ProductName+'】产品族检验设置中检验项目【'+@ItemName+'】未维护检验方案！'

					RETURN -1
				END

				-- 检查输入AQL检验值是否数字
				IF ISNUMERIC(@AQLInsValue) <>1
				BEGIN
					SET @I_ReturnMessage = 'ServerMessage:该送检单产品编码【'+@ProductName+'】产品族检验设置中检验项目【'+@ItemName+'】'+CHAR(10)
					+'维护AQL检验值非数字.'

					RETURN -1
				END
			END 

			-- 如果是计量型则检查是否维护了上下限值
			IF ISNULL(@QCMode,'') ='01'
			BEGIN
				-- 检查计量型值上限值是否有维护
				IF ISNULL(@ItemMaxValue,0) <=0 
				BEGIN
					SET @I_ReturnMessage = 'ServerMessage:该送检单物料编码【'+@ProductName+'】检验项目【'+@ItemName+'】检验上限值必须大于零！'

					RETURN -1
				END

				-- 检查计量型值下限值是否有维护
				IF ISNULL(@ItemMinValue,0) <0 
				BEGIN
					SET @I_ReturnMessage = 'ServerMessage:该送检单物料编码【'+@ProductName+'】检验项目【'+@ItemName+'】检验下限值不能小于零！'

					RETURN -1
				END

				-- 检查下限值是否超过上限值
				IF ISNULL(@ItemMaxValue,0) <ISNULL(@ItemMinValue,0)
				BEGIN
					SET @I_ReturnMessage = 'ServerMessage:该送检单物料编码【'+@ProductName+'】检验项目【'+@ItemName+'】检验下限值不能大于上限值！'

					RETURN -1            
				END 
			END

			SET @RowId = @RowId + 1
		END

		-- 统计个数
		SET @Rows = 0

		SELECT
			@Rows = COUNT(ID)
		FROM 
			@ProductFam_Temp 

		-- 赋值
		SET @RowId = 1

		-- While 循环写入
		WHILE @RowId <= @Rows
		BEGIN
			-- 赋值
			SET @QCType = ''
			SET @QCMode = ''
			SET @ItemSequence = ''
			SET @ItemType = ''
			SET @ItemName = ''
			SET @ItemDescription = ''
			SET @ItemSTDValue = 0
			SET @ItemMaxValue = 0
			SET @ItemMinValue = 0
			SET @ItemUOMId = ''
			SET @AQLInsLvCode = ''
			SET @AQLInsValue = ''
			SET @CheckMethod = ''
			SET @IsAllowArtificialJudge = 0
			SET @ReferDocument = ''
			SET @DrawDocument = ''

			-- 获取数据
			SELECT
				@QCType = QCType,
				@QCMode = QCMode,
				@ItemType = ItemType,
				@ItemName = ItemName,
				@ItemDescription = ItemDescription,
				@ItemSTDValue = ItemSTDValue,
				@ItemMaxValue = ItemMaxValue,
				@ItemMinValue =ItemMinValue,
				@ItemUOMId = ItemUOMId,
				@AQLInsLvCode = CheckLevelCode ,
				@AQLInsValue = AQLQualityStandard ,
				@CheckMethod = CheckMethod,
				@IsAllowArtificialJudge = IsAllowArtificialJudge,
				@ReferDocument = ReferDocument,
				@DrawDocument = DrawDocument
			FROM 
				@ProductFam_Temp AS TA
			WHERE 
				TA.ID = @RowId

			-- 检查产品是否设置检验项
			IF NOT EXISTS(SELECT 1 FROM dbo.Product_QCItem WHERE ProductId = @ProductId AND QCType = @QCType AND ItemName = @ItemName)
			BEGIN
			
				-- 申请主键
				EXEC dbo.SysGetObjectPKId 
					@ObjectId = '',      
					@ObjectName = N'Product_QCItem',   
					@PKID = @Product_QCItemId OUTPUT 

				-- 获取行号
				if exists(select 1 from Product_QCItem where Product_QCItem.ProductId= @ProductId and Product_QCItem.QCType=@QCType)
					SELECT
						@ItemSequence = RIGHT('000'+CAST(CAST(MAX(ItemSequence)+1 AS INT) as varchar),4)
					FROM 
						Product_QCItem
					WHERE 
						Product_QCItem.ProductId = @ProductId 
					AND 
						Product_QCItem.QCType=@QCType
				else
					set @ItemSequence = RIGHT('000'+CAST(1 as varchar),4)

				-- 写入产品检验设置表
				INSERT INTO dbo.Product_QCItem
				(
					Product_QCItemId,
					ProductId,
					VendorId,
					QCType,
					QCMode,
					ItemSequence,
					ItemType,
					ItemName,
					ItemDescription,
					ItemSTDValue,
					ItemMaxValue,
					ItemMinValue,
					ItemUOMId,
					CheckLevelCode,
					AQLQualityStandard,
					CheckMethod,
					IsAllowArtificialJudge,
					ReferDocument,
					DrawDocument,
					ModifyUserId,
					ModifyDate,
					CreateUserId,
					Createdate 
				)
				VALUES
				(
					@Product_QCItemId ,
					@ProductId ,
					'' ,
					@QCType ,
					@QCMode ,
					@ItemSequence ,
					@ItemType ,
					@ItemName ,
					@ItemDescription ,
					@ItemSTDValue ,
					@ItemMaxValue ,
					@ItemMinValue ,
					@ItemUOMId ,
					@AQLInsLvCode ,
					@AQLInsValue ,
					@CheckMethod ,
					@IsAllowArtificialJudge ,
					@ReferDocument ,
					@DrawDocument ,
					@I_OrBitUserId ,
					GETDATE() ,
					@I_OrBitUserId ,
					GETDATE()
				)
			
			END

			SET @RowId = @RowId + 1
		end
		-- 清空检验项表变量
		DELETE FROM @QC_ProdItem_Temp

		--判定当前批号是否是IPQC二检状态，如果是，则只带出光谱和粘度信息
		IF EXISTS(SELECT 1 FROM QC_ProcessIns WHERE InsName=@InsName AND InsStates='20') AND @QCType='IPQC'
		BEGIN
			-- 再次写入检验项表变中
			INSERT INTO @QC_ProdItem_Temp
			(
				Product_QCItemId
			)
			SELECT 
				Product_QCItem.Product_QCItemId
			FROM 
				dbo.Product_QCItem 
			WHERE 
				Product_QCItem.ProductId = @ProductId
			AND
				Product_QCItem.QCType = @QCType
			AND 
				(ItemName LIKE '光%' OR ItemName LIKE '粘%')

			-- 检查产品检验设置中是否都未维护检验项
			--IF NOT EXISTS(SELECT 1 FROM @QC_ProdItem_Temp)
			--BEGIN
			--	SET @I_ReturnMessage = 'ServerMessage:过程检验单【'+@InsName+'】对应工单【'+@MOName+'】产品【'+@ProductName+'】'+@Enter
			--	+'未维护检验项设置，请维护.'

			--	RETURN -1
			--END
		END
		ELSE
		BEGIN
			-- 再次写入检验项表变中
			INSERT INTO @QC_ProdItem_Temp
			(
				Product_QCItemId
			)
			SELECT 
				Product_QCItem.Product_QCItemId
			FROM 
				dbo.Product_QCItem 
			WHERE 
				Product_QCItem.ProductId = @ProductId
			AND
				Product_QCItem.QCType = @QCType

			-- 检查产品检验设置中是否都未维护检验项
			IF NOT EXISTS(SELECT 1 FROM @QC_ProdItem_Temp)
			BEGIN
				SET @I_ReturnMessage = 'ServerMessage:过程检验单【'+@InsName+'】对应工单【'+@MOName+'】产品【'+@ProductName+'】'+@Enter
				+'未维护检验项设置，请维护.'

				RETURN -1
			END
		END

		-- 获取检验项中个数
		SET @Rows = 0

		SELECT
			@Rows = COUNT(ID)
		FROM 
			@QC_ProdItem_Temp

		-- 赋值
		SET @RowId = 1

		-- While 循环
		WHILE @RowId <= @Rows
		BEGIN
			-- 赋值
			SET @Product_QCItemId = ''

			-- 获取数据
			SELECT
				@Product_QCItemId = TA.Product_QCItemId
			FROM 
				@QC_ProdItem_Temp AS TA
			WHERE 
				TA.ID = @RowId

			-- 赋值
			SET @QCType = ''
			SET @QCMode = ''
			SET @ItemSequence = ''
			SET @ItemType = ''
			SET @ItemName = ''
			SET @ItemDescription = ''
			SET @ItemSTDValue = 0
			SET @ItemMaxValue = 0
			SET @ItemMinValue = 0
			SET @ItemUOMId = ''
			SET @AQLInsLvCode = ''
			SET @AQLInsValue = ''
			SET @CheckMethod = ''
			SET @IsAllowArtificialJudge = 0
			SET @ReferDocument = ''
			SET @DrawDocument = ''

			-- 获取数据
			SELECT
				@QCType = QCType,
				@QCMode = QCMode,
				@ItemType = ItemType,
				@ItemName = ItemName,
				@ItemDescription = ItemDescription,
				@ItemSTDValue = ItemSTDValue,
				@ItemMaxValue = ItemMaxValue,
				@ItemMinValue =ItemMinValue,
				@ItemUOMId = ItemUOMId,
				@AQLInsLvCode = CheckLevelCode ,
				@AQLInsValue = AQLQualityStandard ,
				@CheckMethod = CheckMethod,
				@IsAllowArtificialJudge = IsAllowArtificialJudge,
				@ReferDocument = ReferDocument,
				@DrawDocument = DrawDocument
			FROM 
				dbo.Product_QCItem AS TA
			WHERE 
				TA.Product_QCItemId = @Product_QCItemId

			-- 人工判定方式 0：按AQL 1：人工
			IF ISNULL(@IsAllowArtificialJudge,0) = 0
			BEGIN
				-- 检查产品族检验设置是否有维护检验方案
				IF EXISTS(SELECT 1 FROM Product_QCItem WHERE Product_QCItem.Product_QCItemId = @Product_QCItemId 
					AND ( ISNULL(CheckLevelCode,'')='' OR ISNULL(AQLQualityStandard,'')='') )
				BEGIN
					SET @I_ReturnMessage = 'ServerMessage:该送检单产品编码【'+@ProductName+'】检验设置中检验项目【'+@ItemName+'】未维护检验方案！'

					RETURN -1
				END
		 
				-- 检查输入AQL检验值是否数字
				IF ISNUMERIC(@AQLInsValue) <>1
				BEGIN
					SET @I_ReturnMessage = 'ServerMessage:该送检单产品编码【'+@ProductName+'】检验设置中检验项目【'+@ItemName+'】'+@Enter
					+'维护AQL检验值非数字.'

					RETURN -1
				END
			END

			-- 如果是计量型则检查是否维护了上下限值
			IF ISNULL(@QCMode,'') ='01'
			BEGIN
				-- 检查计量型值上限值是否有维护
				IF ISNULL(@ItemMaxValue,0) <0 
				BEGIN
					SET @I_ReturnMessage = 'ServerMessage:该检验单【'+@InsName+'】产品编码【'+@ProductName+'】检验项目【'+@ItemName+'】检验上限值未维护！'

					RETURN -1
				END

				-- 检查计量型值下限值是否有维护
				IF ISNULL(@ItemMinValue,0) <0 
				BEGIN
					SET @I_ReturnMessage = 'ServerMessage:该检验单【'+@InsName+'】产品编码【'+@ProductName+'】检验项目【'+@ItemName+'】检验下限值未维护！'

					RETURN -1
				END

				IF ISNULL(@ItemMaxValue,0) <ISNULL(@ItemMinValue,0)
				BEGIN
					SET @I_ReturnMessage = 'ServerMessage:该检验单【'+@InsName+'】产品编码【'+@ProductName+'】检验项目【'+@ItemName+'】检验下限值不能大于上限值！'

					RETURN -1            
				END 
			END

			-- 人工判定方式 0：按AQL 1：人工
			IF ISNULL(@IsAllowArtificialJudge,0) = 0
			BEGIN 
				-- 赋值
				SET @SampleSize = 0
				SET @Ac=0
				SET @Re=0

				-- 获取AQL样本数 、 AC 、RE数
				EXEC [dbo].[GetAQLValues]
					@SendQty			=	@SubmissQty ,			
					@StrictDegree		=	1 ,
					@CheckLevelCode		=	@AQLInsLvCode ,								
					@AQLQualityStandard =	@AQLInsValue,						
					@SampleSizeQty 		=	@SampleSize OUTPUT ,				
					@Ac					=	@Ac  OUTPUT ,
					@Re					=	@Re OUTPUT
			END

			--如果检验项目不存在，则写入
			IF NOT EXISTS(SELECT 1 FROM dbo.QC_ProcessIns_Item WHERE QC_ProcessIns_Item.QC_ProcessInsId = @QC_ProcessInsId AND ItemName = @ItemName)
			BEGIN
				-- 申请主键
				EXEC dbo.SysGetObjectPKId 
					@ObjectId = '',      
					@ObjectName = N'QC_ProcessIns_Item',   
					@PKID = @QC_ProcessIns_ItemId OUTPUT 
			
				-- 写入检验项表
				INSERT INTO QC_ProcessIns_Item
				(
					QC_ProcessIns_ItemId ,
					QC_ProcessInsId ,
					QCMode,
					ItemType,
					ItemName,
					ItemDescription,
					AQLInsLvCode ,
					AQLInsValue ,
					SampleSize ,
					AC ,
					RE,
					ItemResult ,
					ItemSTDValue ,
					ItemMaxValue ,
					ItemMinValue,
					ItemUOMId ,
					CreateUser ,
					ResourceId ,
					Manualdecmak
				)
				VALUES
				(
					@QC_ProcessIns_ItemId ,
					@QC_ProcessInsId ,
					@QCMode ,
					@ItemType,
					@ItemName ,
					@ItemDescription,
					@AQLInsLvCode ,
					@AQLInsValue ,
					@SampleSize ,
					@Ac ,
					@Re ,
					'' ,
					@ItemSTDValue ,
					@ItemMaxValue ,
					@ItemMinValue,
					@ItemUOMId,
					@Operator ,
					@I_ResourceId ,
					@IsAllowArtificialJudge
				)
			END 
			ELSE
			BEGIN
			
				-- 赋值
				SET @QC_ProcessIns_ItemId = ''

				SELECT 
					@QC_ProcessIns_ItemId =QC_ProcessIns_Item.QC_ProcessIns_ItemId 
				FROM 
					QC_ProcessIns_Item 
				WHERE 
					QC_ProcessIns_Item.QC_ProcessInsId = @QC_ProcessInsId 
				AND 
					ItemName = @ItemName

				-- 更新
				UPDATE 
					dbo.QC_ProcessIns_Item 
				SET
					QCMode=@QCMode,
					ItemType=@ItemType,
					ItemName=@ItemName,
					ItemDescription=@ItemDescription,
					AQLInsLvCode = @AQLInsLvCode ,
					AQLInsValue = @AQLInsValue ,
					SampleSize = @SampleSize ,
					AC = @Ac ,
					RE = @Re ,
					ItemSTDValue=@ItemSTDValue,
					ItemMaxValue=@ItemMaxValue,
					ItemMinValue=@ItemMinValue,
					ItemUOMId=@ItemUOMId ,
					Manualdecmak = @IsAllowArtificialJudge
				WHERE 
					QC_ProcessIns_ItemId = @QC_ProcessIns_ItemId
			END 

			-- 赋值
			SET @QC_ProcessIns_ItemId = ''

			SELECT 
				@QC_ProcessIns_ItemId =QC_ProcessIns_Item.QC_ProcessIns_ItemId 
			FROM 
				QC_ProcessIns_Item 
			WHERE 
				QC_ProcessIns_Item.QC_ProcessInsId = @QC_ProcessInsId 
			AND 
				ItemName = @ItemName

			SET @RowId = @RowId + 1
		END
	END

	-- 返回网格数据
	SELECT 	
		QC_ProcessIns_Item.QC_ProcessIns_ItemId,
		QC_ProcessIns_Item.ItemName , 
		CASE QC_ProcessIns_Item.QCMode WHEN '01' THEN '定量型' WHEN '02' THEN '定性型' END QCMode ,
		QC_ProcessIns_Item.ItemType,
		QC_ProcessIns_Item.ItemResult ,
		QC_ProcessIns_Item.InspectionQty ,
		QC_ProcessIns_Item.DefectTotal ,
		QC_ProcessIns_Item.AQLInsLvCode ,
		QC_ProcessIns_Item.AQLInsValue ,
		CONVERT(FLOAT,QC_ProcessIns_Item.SampleSize) AS SampleSize ,
		CONVERT(FLOAT,ISNULL(QC_ProcessIns_Item.AC,0)) AS AC,
		CONVERT(FLOAT,ISNULL(QC_ProcessIns_Item.RE,0)) AS RE,
		CONVERT(FLOAT,ISNULL(QC_ProcessIns_Item.ItemSTDValue,0)) AS ItemSTDValue,
		CONVERT(FLOAT,ISNULL(QC_ProcessIns_Item.ItemMaxValue,0)) AS ItemMaxValue,
		CONVERT(FLOAT,ISNULL(QC_ProcessIns_Item.ItemMinValue,0)) AS ItemMinValue,
		UOMName,
		dbo.QC_ProcessIns_Item.Manualdecmak ,
		'删除' AS Operate_ ,
		(CASE ItemResult WHEN 'OK' THEN '[ItemResult:XFY0Z]' WHEN 'NG' THEN '[ItemResult:X4Y0Z]' ELSE '' END ) AS ColorControlId
	FROM  
		QC_ProcessIns_Item
		LEFT JOIN dbo.UOM ON QC_ProcessIns_Item.ItemUOMId=UOM.UOMId
	WHERE 
		QC_ProcessIns_Item.QC_ProcessInsId = @QC_ProcessInsId
	
	SET @I_ReturnMessage ='ServerMessage:请开始检验.'

	SET @I_ExceptionFieldName = 'InspectionItem'

	RETURN 0
END
go

