-- =============================================
-- Author:		<OrBit Team Admin>
-- Create date: <2020.05.27>
-- Description:	<过程检验-提交检验项明细显示>
-- Rev: 15.00
-- =============================================
CREATE PROCEDURE [dbo].[Txn_QC_Process_InspectionItemDet_Refresh]
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
@InsItemId CHAR(12) = ''						--	检验项ID

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @QCMode CHAR(3)

	SET @QCMode = ''

	-- 检验项明细显示网格标题按钮
	IF ISNULL(@I_Sender,'') = 'InsItemDetColumnShow'
	BEGIN
		-- 返回网格数据
		SELECT
			'' AS QC_ProcessIns_ItemDetId ,
			'' AS DefectQty ,
			'' AS DefectCode,
			'' AS DefectDescription,
			'删除' AS Operate_ 
		RETURN 0
	END
  
	-- 根据检验项明细Id获取检验方式类型
	SELECT
		@QCMode = dbo.QC_ProcessIns_Item.QCMode
	FROM 
		dbo.QC_ProcessIns_Item
	WHERE
		QC_ProcessIns_ItemId = @InsItemId

	-- 01:定量型
	IF ISNULL(@QCMode,'') = '01'
	BEGIN
		-- 返回网格数据
		SELECT
			QC_ProcessIns_ItemDet.QC_ProcessIns_ItemDetId ,
			CONVERT(FLOAT,QC_ProcessIns_ItemDet.MeasureQty ) AS MeasureQty ,
			CONVERT(FLOAT,QC_ProcessIns_ItemDet.MeasureValue ) AS MeasureValue ,
			QC_ProcessIns_ItemDet.MeasureResult,
			'删除' AS Operate_ 
		FROM 
			QC_ProcessIns_ItemDet
		WHERE 
			QC_ProcessIns_ItemDet.QC_ProcessIns_ItemId = @InsItemId

		SELECT '1' AS MeasureQty,'' AS MeasureValue
	end

	-- 02:定性型 
	IF ISNULL(@QCMode,'') = '02'
	BEGIN
		-- 返回网格数据
		SELECT
			QC_ProcessIns_ItemDet.QC_ProcessIns_ItemDetId ,
			QC_ProcessIns_ItemDet.DefectQty AS DefectQty  ,
			QC_ProcessIns_ItemDet.DefectCodeName AS DefectCode,
			LTRIM(RTRIM(QC_ProcessIns_ItemDet.DefectDescription)) AS DefectDescription,
			QC_ProcessIns_ItemDet.DefectRemark,
			'删除' AS Operate_ 
		FROM 
			QC_ProcessIns_ItemDet
		WHERE 
			QC_ProcessIns_ItemDet.QC_ProcessIns_ItemId = @InsItemId

		SELECT '1' AS DefectQty,'' AS DefectCodeName
	end
	
	RETURN 0
END
go

