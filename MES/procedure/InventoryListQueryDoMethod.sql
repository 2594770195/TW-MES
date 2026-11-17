SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OrBit Team Neil>
-- Create date: <2017.2.21>
-- Description:	统计仓库库存
-- =============================================
CREATE PROCEDURE  [dbo].[InventoryListQueryDoMethod]
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
@FactoryId CHAR(12)='',
@WareHouseId CHAR(12) = '',
@ProductId CHAR(12) = '',
@ProductionLotNO VARCHAR(50)='',
@POName NVARCHAR(20)='',
@IQCCheckName  NVARCHAR(20)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	/*
	WES WW QCStatus/库存QC状态。URC100000AMP
	WES WW LotStatus/库存批号状态 。URC100000AA9
	WES WW IsolateStatus/库存隔离状态。URC100000AMQ
	*/




	SET @WareHouseId=ISNULL(@WareHouseId,'')
	SET @ProductId=ISNULL(@ProductId,'')
	SET @FactoryId=ISNULL(@FactoryId,'')

	-- =====================================================
	-- 2026年10月27日 容器码文本改造 + 性能优化
	-- 原写法把容器明细的聚合 CTE 直接写在 FROM 中，且被 ciLot / ciProd 引用两次；
	-- SQL Server 的 CTE 不物化，窗口函数与 FOR XML 拼接会对全量容器明细重复计算，查询明显变慢。
	-- 优化为三步：①主查询先落临时表（尽早用仓库/物料/工厂条件缩小结果集）
	--            ②仅对结果集中出现的批次聚合容器文本
	--            ③临时表关联输出，保证行数与列顺序不变
	-- =====================================================

	-- 步骤1：主查询（不含容器列）先落临时表
	SELECT 
		Cell.CellName,
		WW_RMInventory.LotSN,
		CONVERT(FLOAT,WW_RMInventory.Qty) AS Qty,
		LotStatusTable.UserCodeDescription AS LotStatus,
		QCStatusTable.UserCodeDescription AS QCStatus,
		IsolateStatusTable.UserCodeDescription AS IsolateStatus,
		OrgLotSN,
		BoxSN,
		PalletSN,
		TurnoverBoxSN,
		dbo.FormatQualityMark(Lot.QualityMark) AS QualityMark,
		WW_RMInventory.ProductionDate,
		WW_RMInventory.ProductionLotNO,
		ReceiveDate,
		WW_RMInventory.EntryDate,
		ValidityEndDate,
		LastestTxnCode,
		WW_RMInventory.SAPRemark,sp.Comments AS '库存初始化备注',pi.Note AS 'SAP备注',HoldResult as '锁定原因',
		MO.NoteMessage AS '生产备注信息',
		IsInternalLot,
		VendorName+':'+VendorShortName AS VendorName,
		CustomerName+':'+VendorShortName AS CustomerName,
		POName,
		MO.MOName,
		MO.SOName,
		WW_RMInventory.sSOName,
		WW_RMInventory.ModifyDate
	INTO #InvResult
	FROM dbo.WW_RMInventory 
	LEFT JOIN Cell ON Cell.CellId=WW_RMInventory.CellId
	LEFT JOIN UserCode_Table('URC100000AA9') LotStatusTable ON WW_RMInventory.LotStatus=LotStatusTable.UserCodeName
	LEFT JOIN UserCode_Table('URC100000AMP') QCStatusTable ON WW_RMInventory.QCStatus=QCStatusTable.UserCodeName
	LEFT JOIN UserCode_Table('URC100000AMQ') IsolateStatusTable ON WW_RMInventory.IsolateStatus=LotStatusTable.UserCodeName
	LEFT JOIN dbo.Vendor ON Vendor.VendorId = WW_RMInventory.VendorId
	LEFT JOIN dbo.Customer ON Customer.CustomerId = WW_RMInventory.CustomerId
	LEFT JOIN dbo.PO ON PO.POId = WW_RMInventory.POId
	LEFT JOIN dbo.MO ON MO.MOId = WW_RMInventory.MOId
	LEFT JOIN dbo.IQCCheckLot AS icil ON icil.LotSN = WW_RMInventory.LotSN
    LEFT JOIN dbo.IQCCheck AS ic ON ic.IQCCheckId = icil.IQCCheckId
	LEFT JOIN StartProduct sp ON sp.ProductId = WW_RMInventory.ProductId AND sp.ProductionLotNO=WW_RMInventory.ProductionLotNO
	LEFT JOIN ProductInventory pi ON pi.ProductId = WW_RMInventory.ProductId AND pi.LotSN=WW_RMInventory.ProductionLotNO AND
	pi.WorkcenterId=WW_RMInventory.WorkcenterId AND pi.DeleteFlag='0'
	LEFT JOIN Lot ON WW_RMInventory.LotSN=Lot.LotSN
	WHERE WW_RMInventory.WorkcenterId = @WareHouseId 
	AND WW_RMInventory.ProductId = @ProductId 
	AND WW_RMInventory.IsStorage = 1 
	AND WW_RMInventory.Qty>0
	AND WW_RMInventory.FactoryId=@FactoryId
	AND WW_RMInventory.LotStatus IN('1','0','9')
	AND (ISNULL(@ProductionLotNO,'')='' OR WW_RMInventory.ProductionLotNO=@ProductionLotNO)
	AND (ISNULL(@POName,'')='' OR PO.POName=@POName)
	AND (ISNULL(@IQCCheckName,'')='' OR ic.IQCCheckName=@IQCCheckName)

	-- 步骤2：收集结果集涉及的批次键
	-- 容器绑定的 CurrentProudctionLotSN 可能是 MES 批次号(LotSN)，也可能是生产批次号(ProductionLotNO)，两者都收集
	SELECT DISTINCT BatchKey
	INTO #BatchKey
	FROM (
		SELECT LotSN AS BatchKey FROM #InvResult
		UNION
		SELECT ProductionLotNO AS BatchKey FROM #InvResult
	) AS bk
	WHERE ISNULL(BatchKey, '') <> ''   -- 空批次不参与匹配

	-- 步骤3：仅针对目标批次取容器明细，每个容器码保留最新一条货位记录（按创建时间倒序编号）
	SELECT
		ZR_ContainerCode.CurrentProudctionLotSN,
		ZR_ContainerCode.ContainerCode,
		ZR_ContainerCodeDetails.CodeStatus,
		-- 数量为 float，先转 DECIMAL 再转文本，避免出现科学计数法；NULL 时由外层 ISNULL 处理
		CONVERT(NVARCHAR(50), CONVERT(DECIMAL(18, 4), ZR_ContainerCodeDetails.num)) AS num,
		ROW_NUMBER() OVER (
			PARTITION BY ZR_ContainerCode.CurrentProudctionLotSN, ZR_ContainerCode.ContainerCode
			ORDER BY ZR_ContainerCodeDetails.createDate DESC
		) AS RowNum
	INTO #ContainerLatest
	FROM ZR_ToFac_ContainerCode
	INNER JOIN ZR_ContainerCode ON ZR_ContainerCode.ZR_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ContainerCodeId
	INNER JOIN ZR_ContainerCodeDetails ON ZR_ContainerCodeDetails.ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ToFac_ContainerCodeID
	WHERE ZR_ContainerCode.CurrentProudctionLotSN IN (SELECT BatchKey FROM #BatchKey)

	-- 步骤4：按批次汇总，把每个容器的“容器码+货位码+数量”拼成一段文本，多个容器以分号分隔
	SELECT
		c1.CurrentProudctionLotSN,
		ContainerInfo = STUFF((
			SELECT ';' + ISNULL(c2.ContainerCode, '') + '+' + ISNULL(c2.CodeStatus, '') + '+' + ISNULL(c2.num, '')
			FROM #ContainerLatest c2
			WHERE c2.CurrentProudctionLotSN = c1.CurrentProudctionLotSN
			  AND c2.RowNum = 1           -- 每个容器码只取最新的一条货位明细
			ORDER BY c2.ContainerCode     -- 按容器码排序，保证输出顺序稳定
			FOR XML PATH(''), TYPE
		).value('.', 'NVARCHAR(MAX)'), 1, 1, '')  -- 去掉首个分号
	INTO #ContainerText
	FROM #ContainerLatest c1
	WHERE c1.RowNum = 1
	GROUP BY c1.CurrentProudctionLotSN   -- 每个批次只输出一行，关联时不会扩行

	-- 步骤5：输出结果，列顺序与原过程保持一致，新增列追加在最后
	SELECT
		r.CellName,
		r.LotSN,
		r.Qty,
		r.LotStatus,
		r.QCStatus,
		r.IsolateStatus,
		r.OrgLotSN,
		r.BoxSN,
		r.PalletSN,
		r.TurnoverBoxSN,
		r.QualityMark,
		r.ProductionDate,
		r.ProductionLotNO,
		r.ReceiveDate,
		r.EntryDate,
		r.ValidityEndDate,
		r.LastestTxnCode,
		r.SAPRemark,
		r.[库存初始化备注],
		r.[SAP备注],
		r.[锁定原因],
		r.[生产备注信息],
		r.IsInternalLot,
		r.VendorName,
		r.CustomerName,
		r.POName,
		r.MOName,
		r.SOName,
		r.sSOName,
		r.ModifyDate,
		-- 2026年10月27日 新增：容器码+货位码+数量 拼接文本（同一生产批次存在多个容器时以分号分隔）
		-- 两个批次口径分别单键关联（#ContainerText 批次唯一，各匹配至多一行），再 COALESCE 择优取非空
		ISNULL(COALESCE(ciLot.ContainerInfo, ciProd.ContainerInfo), '') AS '容器码+货位码+数量'
	FROM #InvResult r
	LEFT JOIN #ContainerText ciLot ON ciLot.CurrentProudctionLotSN = r.LotSN
	LEFT JOIN #ContainerText ciProd ON ciProd.CurrentProudctionLotSN = r.ProductionLotNO
	ORDER BY r.ProductionDate  
	
	RETURN 0

END
GO
