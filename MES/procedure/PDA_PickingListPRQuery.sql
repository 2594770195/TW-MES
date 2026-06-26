-- =============================================
-- Author:		<OrBit Team Orbchay>
-- Create Date: <2020.05.07>
-- Description:	PDA 领料单领料查询
-- Version: 12
-- =============================================
CREATE PROCEDURE  [dbo].[PDA_PickingListPRQuery]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT, --向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId CHAR(12)='',			--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKid CHAR(12) ='',				--主键
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(MAX)='',  		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@IsSwitchTab BIT=0,--是否是切换页签。为0时，不是切换页签，而是第一次打开插件
@StartDate DATETIME=NULL,
@EndDate DATETIME=NULL,
@BillStatesId VARCHAR(20)='',
@BillStates NVARCHAR(30)='',
@PickingListName NVARCHAR(50)='',
@CurProductId CHAR(12)='', --当前扫描的产品Id
@CurWareHouseId CHAR(12)='',--当前扫描的仓库
@CurCellId CHAR(12)='',--当前扫描的储位号
@ProductId CHAR(12)='',--产品
@Grid_RMInventory char(30) = '',
@Grid_PickinglistItem NVARCHAR(100)=''            --最小包/外箱 SN

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--通用
	DECLARE @return_value INT=-1
	DECLARE @Enter NVARCHAR(100)=CHAR(13)+CHAR(10)
	DECLARE @CurDate DATE=GETDATE()
	--bill
	DECLARE @PickingListId CHAR(12)=''



	--**********begin 一、移动事务名：Material Issue To PickingList Query； begin*******************
	--页面加载方法，即第一次打开插件：刷新单据列表
	IF @I_Sender='PageLoad'
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'

		--是否是切换页签。为0时，不是切换页签，而是第一次打开插件
		IF ISNULL(@IsSwitchTab,0)=0
		BEGIN
			--1.第一次打开插件，初始化界面参数
			SET @StartDate=GETDATE()-5 --开始时间往前多少天
			SET @EndDate=GETDATE()
			--只精确到天，比如：2020-05-07 00:00:00.000
			SET @StartDate=CAST(CONVERT(VARCHAR, @StartDate, 23) AS DATETIME)
			SET @EndDate=CAST(CONVERT(VARCHAR, @EndDate, 23)+' 23:59:59' AS DATETIME)

			--2.初始化选择的单据:20 已审核
			SELECT @BillStatesId=BillStatesName,
				   @BillStates=BillStatesDescription
			FROM dbo.Bill
			INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
			WHERE BillName='PickingListPR' 
			AND BillStatesName='20' AND IsERP=0



			--初始化单据列表：
			SELECT  DISTINCT
				PickingListName,
				m.ProductLine,
				CASE WHEN EXISTS (SELECT 1  FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId 
		INNER JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p.ProductRootId
		INNER JOIN dbo.ProductFamily AS pf ON pf.ProductFamilyId = pr.ProductFamilyId
		WHERE pli2.PickingListId=PickingList.PickingListId AND pf.ProductFamilyName IN('102850','102855','102857','102859','101750','573008','102858'))
		THEN '包材领料单' 
		WHEN (SELECT TOP 1  p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='1'
		THEN '成品领料单'
		WHEN (SELECT TOP 1 p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='2'
		THEN '半成品领料单'
		WHEN (SELECT TOP 1 p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='3'
		THEN '原材料领料单'
		END AS '领料类型',
				CASE WHEN  EXISTS(SELECT 1 FROM dbo.PickingListItemLot AS plil 
			INNER JOIN dbo.PickingListItem AS pli ON pli.PickingListItemId = plil.PickingListItemId
			WHERE pli.PickingListId=PickingList.PickingListId) AND PickingList.PickingListStates='20' THEN  '21 领料中'
		WHEN EXISTS(SELECT 1 FROM dbo.PickingList_MO AS pli 
		WHERE pli.PickingListId=PickingList.PickingListId AND ISNULL(pli.ToSAPStates ,'')='') AND PickingList.PickingListStates IN ('40','41') THEN  '42 部分过账'ELSE 
		PickingList.PickingListStates+' '+ISNULL(temp.BillStatesDescription,'')END  AS PickingListStates,
			--	temp.BillStatesDescription AS PickingListStates,
				PickingList.CreateDate
			FROM dbo.PickingList
			LEFT JOIN (SELECT BillStatesName,BillStatesDescription 
					  FROM dbo.Bill
					  INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
					  WHERE BillName='PickingListPR' AND IsERP=0
					  )temp ON PickingList.PickingListStates=temp.BillStatesName
            LEFT JOIN dbo.PickingList_MO AS plm ON plm.PickingListId = PickingList.PickingListId
	        LEFT JOIN dbo.MO AS m ON m.MOId = plm.MOId
			WHERE (PickingList.CreateDate>=@StartDate AND PickingList.CreateDate<=@EndDate)
			AND( PickingListStates=@BillStatesId   OR EXISTS(SELECT 1 FROM dbo.PickingList_MO AS pli 
		WHERE pli.PickingListId=PickingList.PickingListId AND ISNULL(pli.ToSAPStates ,'')='') AND PickingList.PickingListStates IN ('40','41'))
			AND PickingListClass='01'
			--ORDER BY PickingList.PickingListId DESC


			--初始化界面参数
			SELECT @StartDate AS StartDate,@EndDate AS EndDate,
				   @BillStatesId AS BillStatesId,
				   @BillStates AS BillStates,
					1 AS IsSwitchTab

			RETURN 0
		END

		RETURN 0
	END



	--获取单据列表
	IF @I_Sender='Get_BillList'
	BEGIN
		SET @I_ExceptionFieldName='PickingListName'

		IF @StartDate IS NULL
		BEGIN
			SET @I_ReturnMessage='ServerMessage:开始日期不能为空！'+@Enter
			SELECT '' AS PickingListName,'' AS PickingListStates,'' AS CreateDate
			RETURN -1
		END

		IF @EndDate IS NULL
		BEGIN
			SET @I_ReturnMessage='ServerMessage:结束日期不能为空！'+@Enter
			SELECT '' AS PickingListName,'' AS PickingListStates,'' AS CreateDate
			RETURN -1
		END

		--只精确到天，比如：2020-05-07 00:00:00.000
		SET @StartDate=CAST(CONVERT(VARCHAR, @StartDate, 23) AS DATETIME)
		SET @EndDate=CAST(CONVERT(VARCHAR, @EndDate, 23)+' 23:59:59:999' AS DATETIME)

		IF @EndDate<@StartDate
		BEGIN
			SET @I_ReturnMessage='ServerMessage:开始日期不能大于结束日期！'+@Enter
			SELECT '' AS PickingListName,'' AS PickingListStates,'' AS CreateDate
			RETURN -1
		END

		IF ISNULL(@BillStatesId,'')='' OR ISNULL(@BillStates,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:单据状态不能为空！'+@Enter
			SELECT '' AS PickingListName,'' AS PickingListStates,'' AS CreateDate
			RETURN -1
		END
		

		--获取单据列表
		SELECT DISTINCT
			PickingListName,
			m.ProductLine,
			CASE WHEN EXISTS (SELECT 1  FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId 
		INNER JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p.ProductRootId
		INNER JOIN dbo.ProductFamily AS pf ON pf.ProductFamilyId = pr.ProductFamilyId
		WHERE pli2.PickingListId=PickingList.PickingListId AND pf.ProductFamilyName IN('102850','102855','102857','102859','101750','573008','102858'))
		THEN '包材领料单' 
		WHEN (SELECT TOP 1  p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='1'
		THEN '成品领料单'
		WHEN (SELECT TOP 1 p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='2'
		THEN '半成品领料单'
		WHEN (SELECT TOP 1 p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='3'
		THEN '原材料领料单'
		END AS '领料类型',
			(CASE WHEN PIT.QtyIssued>0 AND PickingList.PickingListStates='20' THEN '21 领料中' WHEN PM.NUM>0 AND PickingList.PickingListStates ='20' THEN '31 部分过账' 
			ELSE PickingList.PickingListStates+' '+ISNULL(temp.BillStatesDescription,'') END) AS PickingListStates,
			--	temp.BillStatesDescription AS PickingListStates,
			PickingList.CreateDate
		FROM dbo.PickingList
		LEFT JOIN (SELECT BillStatesName,BillStatesDescription 
				  FROM dbo.Bill
				  INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
				  WHERE BillName='PickingListPR' AND IsERP=0
				  )temp ON PickingList.PickingListStates=temp.BillStatesName
        LEFT JOIN dbo.PickingList_MO AS plm ON plm.PickingListId = PickingList.PickingListId
	    LEFT JOIN dbo.MO AS m ON m.MOId = plm.MOId
		LEFT JOIN (SELECT PickingListId,COUNT(1) AS NUM FROM dbo.PickingList_MO WHERE IsPost=1 GROUP BY PickingListId) AS PM ON PickingList.PickingListId=PM.PickingListId
		LEFT JOIN (SELECT PickingListId,SUM(QtyIssued) AS QtyIssued FROM dbo.PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY PickingListId) AS PIT ON PickingList.PickingListId=PIT.PickingListId
		WHERE (PickingList.CreateDate>=@StartDate AND PickingList.CreateDate<=@EndDate)
		AND((@BillStatesId='21' AND PIT.QtyIssued>0 AND PickingList.PickingListStates='20') OR 
		(@BillStatesId='31' AND PM.NUM>0 AND PickingList.PickingListStates ='20') OR 
		PickingListStates=@BillStatesId)
		AND PickingListClass='01'
	--	ORDER BY PickingList.PickingListStates,PickingList.PickingListId DESC

		RETURN 0
	END
	--**********end 一、移动事务名：PDA_PickingListPRQuery； end*******************










	--**********begin 二、移动事务名：Material Issue To PickingList； begin*******************
	IF @I_Sender='Get_Bill'
	BEGIN
		SELECT @PickingListName AS PickingListName,'' as ProductId

		RETURN 0
	END

	IF @I_Sender='Get_RMLotSN'
	BEGIN
	    DECLARE  @BoxLotSN NVARCHAR(100) = ''
		SELECT @BoxLotSN=Lotsn FROM WW_RMInventory WHERE WW_RMInventory.WWId =  @Grid_RMInventory 
	    select @BoxLotSN as BoxOrLotSN

		RETURN 0
	END

	--获取单据明细
	IF @I_Sender='Get_BillItemList'
	BEGIN 
		DECLARE @Temp_PickingListItem TABLE(
			RowId INT IDENTITY(1,1),
			RowLogo NVARCHAR(50),
			ItemSequence VARCHAR(20),
            MoName NVARCHAR(30),
			ProductId CHAR(12),
			ProductName NVARCHAR(50),
			ProductDescription NVARCHAR(100),
			QtyRequired FLOAT,
			QtyIssued FLOAT,
			OweQty FLOAT,
			WarehouseName NVARCHAR(50),
			ISBC BIT
		)
		IF ISNULL(@PickingListName,'')=''
		BEGIN
			SELECT RowId, 
				   RowLogo, 
				   ProductId,
				   MoName,
				   ProductName, 
				   ProductDescription,
				   QtyRequired, 
				   QtyIssued, 
				   OweQty, 
				   WarehouseName,
				   ItemSequence,
				   ISBC
			FROM @Temp_PickingListItem ORDER BY RowId
		END

		--获取单据明细
		SELECT @PickingListId=PickingListId
		FROM dbo.PickingList 
		WHERE PickingListName=@PickingListName

		IF ISNULL(@PickingListId,'')=''
		BEGIN
			SELECT RowId, 
				   RowLogo, 
				   ProductId,
				   MoName,
				   ProductName, 
				   ProductDescription,
				   QtyRequired, 
				   QtyIssued, 
				   OweQty, 
				   WarehouseName,
				   ItemSequence,
				   ISBC
			FROM @Temp_PickingListItem ORDER BY RowId
		END

		SET @CurProductId=ISNULL(@CurProductId,'')

		
		--先插入当前产品
		INSERT INTO @Temp_PickingListItem
			 (
				 RowLogo,
				 ItemSequence,
				 ProductId,
			     MoName,
				 ProductName,
				 ProductDescription,
				 QtyRequired,
				 QtyIssued,
				 OweQty,
				 WarehouseName,
				 ISBC
			 )
		SELECT 		
			CASE WHEN (QtyRequired-QtyIssued)<=0 THEN '★√' --★当前扫描的物料，√代表已扫完
				 ELSE '★' END AS RowLogo, --★当前扫描的物料
			ItemSequence,
			PickingListItem.ProductId,
			MoName,
			ProductName,
			ProductDescription,
			QtyRequired,
			QtyIssued,
			CASE WHEN (QtyRequired-QtyIssued)>=0 THEN (QtyRequired-QtyIssued)
				 ELSE 0 END AS OweQty,
			WorkcenterName AS WarehouseName,
			(CASE WHEN ProductFamily.ProductFamilyName IN('102850','102855','102857','102858','102859') THEN 1 ELSE 0 END) ISBC
		FROM dbo.PickingListItem 
		INNER JOIN dbo.Product ON Product.ProductId=PickingListItem.ProductId
		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
		LEFT JOIN dbo.Workcenter ON Workcenter.WorkcenterId = PickingListItem.WorkcenterId
		INNER JOIN ProductFamily ON ProductRoot.ProductFamilyId=ProductFamily.ProductFamilyId
		LEFT JOIN MO ON MO.MOId = PickingListItem.MOId
		WHERE PickingListId=@PickingListId 
		AND PickingListItem.ProductId=@CurProductId
		AND PickingListItem.DeleteFlag<>'X'
		ORDER BY ItemSequence

		--再插入其它产品
		INSERT INTO @Temp_PickingListItem
			 (
				 RowLogo,
				 ItemSequence,
				 ProductId,
			     MoName,
				 ProductName,
				 ProductDescription,
				 QtyRequired,
				 QtyIssued,
				 OweQty,
				 WarehouseName,
				 ISBC
			 )
		SELECT 
			CASE WHEN (QtyRequired-QtyIssued)<=0 THEN '√'
				 ELSE '' END AS RowLogo,
			ItemSequence,
			PickingListItem.ProductId,
			MoName,
			ProductName,
			ProductDescription,
			QtyRequired,
			QtyIssued,
			CASE WHEN (QtyRequired-QtyIssued)>=0 THEN (QtyRequired-QtyIssued)
				 ELSE 0 END AS OweQty,
			WorkcenterName AS WarehouseName,
			(CASE WHEN ProductFamily.ProductFamilyName IN('102850','102855','102857','102858','102859') THEN 1 ELSE 0 END) ISBC
		FROM dbo.PickingListItem 
		INNER JOIN dbo.Product ON Product.ProductId=PickingListItem.ProductId
		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
		INNER JOIN ProductFamily ON ProductRoot.ProductFamilyId=ProductFamily.ProductFamilyId
		LEFT JOIN dbo.Workcenter ON Workcenter.WorkcenterId = PickingListItem.WorkcenterId
		LEFT JOIN MO ON MO.MOId = PickingListItem.MOId
		WHERE PickingListId=@PickingListId 
		AND PickingListItem.ProductId<>@CurProductId
		AND PickingListItem.DeleteFlag<>'X'
		ORDER BY RowLogo,ItemSequence


		--返回网格数据
		SELECT RowId, 
				RowLogo, 
				ProductId,
				MoName,
				ProductName, 
				ProductDescription,
				QtyRequired, 
				QtyIssued, 
				OweQty, 
				WarehouseName,
				ItemSequence,
				ISBC
-- 		       ,
-- 				'[ProductDescription:300]' ColumnWidth
		FROM @Temp_PickingListItem ORDER BY RowId
		RETURN 0
	END


	--建议批次
	IF @I_Sender='Get_AdviceLot'
	BEGIN	
		DECLARE @AdviceCell NVARCHAR(MAX)=''

		-- EXEC dbo.TxnBase_MBill_PickingListAdviceLot
		--     @I_ReturnMessage=@I_ReturnMessage OUTPUT,
		--     @I_OrBitUserId=@I_OrBitUserId,
		--     @I_OrBitUserName=@I_OrBitUserName,
		--     @I_ResourceId=@I_ResourceId,
		--     @I_ResourceName=@I_ResourceName,
		--     @I_PlugInCommand=@I_PlugInCommand,
		--     @PickingListName=@PickingListName,
		--     @ProductId=@ProductId,
		--     @CurWareHouseId=@CurWareHouseId,
		--     @CurCellId=@CurCellId,
		--     @MaxQty=30,--显示多少个条码
		--     @AdviceCell=@AdviceCell OUTPUT
        
        EXEC dbo.TxnBase_MBill_PickingListAdviceLot_NEW
		    @I_ReturnMessage=@I_ReturnMessage OUTPUT,
		    @I_OrBitUserId=@I_OrBitUserId,
		    @I_OrBitUserName=@I_OrBitUserName,
		    @I_ResourceId=@I_ResourceId,
		    @I_ResourceName=@I_ResourceName,
		    @I_PlugInCommand=@I_PlugInCommand,
		    @PickingListName=@PickingListName,
		    @ProductId=@ProductId,
		    @CurWareHouseId=@CurWareHouseId,
		    @CurCellId=@CurCellId,
		    @MaxQty=30,--显示多少个条码
		    @AdviceCell=@AdviceCell OUTPUT

		RETURN 0
	END

    --获取物料库存
    IF @I_Sender='Get_RMInventory'
	BEGIN

        select top 100
                WW_RMInventory.WWId,
                Factory.FactoryName,
                Workcenter.WorkcenterName,
                Product.TProductName,
                Product.ProductDescription,
                WW_RMInventory.LotSN AS LotSN,
                WW_RMInventory.ProductionLotNO,
                WW_RMInventory.Qty,
                LotStatusTable.UserCodeDescription AS LotStatus,
                QCStatusTable.UserCodeDescription AS QCStatus,
                IsolateStatusTable.UserCodeDescription AS IsolateStatus,
                WW_RMInventory.ProductionDate,
                WW_RMInventory.EntryDate,
                WW_RMInventory.ValidityEndDate,
                WW_RMInventory.SAPRemark,pi.Note AS 'SAP备注',HoldResult as '锁定原因',
		        MO.NoteMessage AS '生产备注信息'

        from WW_RMInventory  
        left join Workcenter on WW_RMInventory.WorkcenterId=Workcenter.WorkcenterId
        left join Factory on Factory.FactoryId=Workcenter.FactoryId
        left join product on product.ProductId=WW_RMInventory.ProductId
        LEFT JOIN UserCode_Table('URC100000AA9') LotStatusTable ON WW_RMInventory.LotStatus=LotStatusTable.UserCodeName
        LEFT JOIN UserCode_Table('URC100000AMP') QCStatusTable ON WW_RMInventory.QCStatus=QCStatusTable.UserCodeName
        LEFT JOIN UserCode_Table('URC100000AMQ') IsolateStatusTable ON WW_RMInventory.IsolateStatus=LotStatusTable.UserCodeName
        LEFT JOIN dbo.MO ON MO.MOId = WW_RMInventory.MOId
        LEFT JOIN ProductInventory pi ON pi.ProductId = WW_RMInventory.ProductId AND pi.LotSN=WW_RMInventory.ProductionLotNO AND
            pi.WorkcenterId=WW_RMInventory.WorkcenterId AND pi.DeleteFlag='0'
        where WW_RMInventory.ProductId = @ProductId 
        AND WW_RMInventory.IsStorage = 1 
        AND WW_RMInventory.Qty>0
        AND WW_RMInventory.LotStatus IN('1','0','9')

		RETURN 0
	END
	--**********end 二、移动事务名：Material Issue To PickingList； end*******************

	RETURN 0

END
go

