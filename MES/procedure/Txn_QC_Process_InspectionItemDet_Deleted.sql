
-- =============================================
-- Author:		<OrBit Team Admin>
-- Create date: <2020.05.27>
-- Description:	<过程检验-检验项明细删除>
-- Rev: 15.00
-- =============================================
CREATE PROCEDURE [dbo].[Txn_QC_Process_InspectionItemDet_Deleted]
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
@InsItemId CHAR(12) = '' ,						-- 检验项Id
@ItemDetId CHAR(12) = '' 						--	检验项明细Id

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @QCMode CHAR(3)= ''
	DECLARE @TempQty INT = 0
	DECLARE @PTotal INT = 0
	DECLARE @DefectTotal INT = 0
	DECLARE @Manualdecmak BIT = 0
	DECLARE @ItemResult CHAR(2) = ''

	DECLARE @AC FLOAT = 0
	DECLARE @RE FLOAT = 0

	-- 检验项删除按钮
	IF ISNULL(@I_Sender,'') = 'InsItemDel'
	BEGIN
		IF ISNULL(@InsItemId,'') = ''
		BEGIN
			SET @I_ReturnMessage = 'ServerMessage:请选择需要删除检验项数据.'

			RETURN -1
		END

		-- 检查需要删除检验项是否存在检验项明细数据
		IF EXISTS(SELECT 1 FROM dbo.QC_ProcessIns_ItemDet WHERE dbo.QC_ProcessIns_ItemDet.QC_ProcessIns_ItemId = @InsItemId)
		BEGIN
			SET @I_ReturnMessage = 'ServerMessage:已存在检验项明细数据，请先删除检验项明细数据，再删除检验项数据.'

			RETURN -1
		END

		-- 执行删除
		DELETE FROM dbo.QC_ProcessIns_Item WHERE QC_ProcessIns_ItemId = @InsItemId

		SET @I_ReturnMessage = 'ServerMessage:检验项数据删除成功.'

		RETURN 0

	end

	-- 检查是否选择删除检验项明细数据
	IF ISNULL(@ItemDetId,'') = ''
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:请选择需要删除检验项明细数据.'

		RETURN -1
	END

	-- 获取检验项Id
	SET @InsItemId = ''

	SELECT
		@InsItemId = dbo.QC_ProcessIns_ItemDet.QC_ProcessIns_ItemId
	FROM 
		dbo.QC_ProcessIns_ItemDet
	WHERE 
		dbo.QC_ProcessIns_ItemDet.QC_ProcessIns_ItemDetId = @ItemDetId

	-- 根据检验项明细Id获取检验方式类型
	SELECT
		@QCMode = dbo.QC_ProcessIns_Item.QCMode ,
		@AC = QC_ProcessIns_Item.AC ,
		@RE = QC_ProcessIns_Item.RE ,
		@Manualdecmak = dbo.QC_ProcessIns_Item.Manualdecmak 
	FROM 
		dbo.QC_ProcessIns_Item
	WHERE
		QC_ProcessIns_ItemId = @InsItemId

	-- 删除检验项明细数据
	IF EXISTS(SELECT 1 FROM dbo.QC_ProcessIns_ItemDet WHERE QC_ProcessIns_ItemDetId = @ItemDetId)
	BEGIN
		-- 01:计量型 
		IF ISNULL(@QCMode,'') = '01'
		BEGIN
			-- 统计计量型数
			SET @TempQty = 0

			SELECT
				@TempQty = ISNULL(MeasureQty,0)
			FROM 
				QC_ProcessIns_ItemDet
			WHERE 
				QC_ProcessIns_ItemDetId = @ItemDetId

		END

		-- 02:表示计数型
		IF ISNULL(@QCMode,'') = '02'
		BEGIN
			-- 统计计量型数
			SET @TempQty = 0

			SELECT
				@TempQty = ISNULL(DefectQty,0)
			FROM 
				QC_ProcessIns_ItemDet
			WHERE 
				QC_ProcessIns_ItemDetId = @ItemDetId
		end

		-- 删除
		DELETE
			FROM dbo.QC_ProcessIns_ItemDet
		WHERE 
			QC_ProcessIns_ItemDetId = @ItemDetId
	END

	-- 01:计量型 
	IF ISNULL(@QCMode,'') = '01'
	BEGIN

		-- 统计计量型合格总数
		set @PTotal = 0

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

	end

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

	-- 更新检验项不良总数
	IF EXISTS(SELECT 1 FROM dbo.QC_ProcessIns_Item WHERE dbo.QC_ProcessIns_Item.QC_ProcessIns_ItemId = @InsItemId)
	BEGIN
		-- 更新扣减
		UPDATE
			dbo.QC_ProcessIns_Item
		SET
			dbo.QC_ProcessIns_Item.DefectTotal = IIF(
				ISNULL(dbo.QC_ProcessIns_Item.DefectTotal,0) - ISNULL(@TempQty,0) <= 0 ,
				0 ,
				ISNULL(dbo.QC_ProcessIns_Item.DefectTotal,0) - ISNULL(@TempQty,0)
			) ,
			dbo.QC_ProcessIns_Item.InspectionQty = IIF(
				ISNULL(dbo.QC_ProcessIns_Item.InspectionQty,0) - ISNULL(@TempQty,0) <= 0 ,
				NULL ,
				ISNULL(dbo.QC_ProcessIns_Item.InspectionQty,0) - ISNULL(@TempQty,0)
			) ,
			dbo.QC_ProcessIns_Item.ItemResult = @ItemResult
		WHERE 
			dbo.QC_ProcessIns_Item.QC_ProcessIns_ItemId = @InsItemId
	END

	-- 如果检验项明细没有数据清空检验结果
	IF NOT EXISTS(SELECT TOP 1 ISNULL(QC_ProcessIns_ItemDet.QC_ProcessIns_ItemDetId,'')  FROM dbo.QC_ProcessIns_ItemDet WHERE QC_ProcessIns_ItemId = @InsItemId)
	BEGIN
		SET @ItemResult = ''

		UPDATE
			dbo.QC_ProcessIns_Item
		SET
			ItemResult = @ItemResult
		WHERE
			dbo.QC_ProcessIns_Item.QC_ProcessIns_ItemId = @InsItemId
	END

	SET @I_ReturnMessage = 'ServerMessage:检验项明细数据删除成功'

	RETURN 0
END
go

