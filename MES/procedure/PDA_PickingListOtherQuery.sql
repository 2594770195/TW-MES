
-- =============================================
-- Author:		<OrBit Team Orbchay>
-- Create Date: <2020.05.07>
-- Description:	PDA 杂发单领料查询
-- Version: 12
-- =============================================
CREATE PROCEDURE  dbo.PDA_PickingListOtherQuery
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
@CurCellId CHAR(12)=''--当前扫描的储位号

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


	


	--**********begin 一、移动事务名：Material Issue To PickingListOther Query； begin*******************
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
			WHERE BillName='PickingListOther' 
			AND BillStatesName='20' AND IsERP=0



			--初始化单据列表：
			SELECT 
				PickingListName,
				temp.BillStatesDescription AS PickingListStates,
				PickingList.CreateDate
			FROM dbo.PickingList
			LEFT JOIN (SELECT BillStatesName,BillStatesDescription 
					  FROM dbo.Bill
					  INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
					  WHERE BillName='PickingListOther' AND IsERP=0
					  )temp ON PickingList.PickingListStates=temp.BillStatesName
			WHERE (CreateDate>=@StartDate AND CreateDate<=@EndDate)
			AND PickingListStates=@BillStatesId
			AND PickingListClass='02'
			ORDER BY PickingListId DESC


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
			RETURN -1
		END
		

		--获取单据列表
		SELECT 
			PickingListName,
			temp.BillStatesDescription AS PickingListStates,
			PickingList.CreateDate
		FROM dbo.PickingList
		LEFT JOIN (SELECT BillStatesName,BillStatesDescription 
				  FROM dbo.Bill
				  INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
				  WHERE BillName='PickingListOther' AND IsERP=0
				  )temp ON PickingList.PickingListStates=temp.BillStatesName
		WHERE (CreateDate>=@StartDate AND CreateDate<=@EndDate)
		AND PickingListStates=@BillStatesId
		AND PickingListClass='02'
		ORDER BY PickingList.PickingListStates,PickingListId DESC

		RETURN 0
	END
	--**********end 一、移动事务名：Material Issue To PickingListOther Query； end*******************










	--**********begin 二、移动事务名Material Issue To PickingListOther； begin*******************
	IF @I_Sender='Get_Bill'
	BEGIN
		SELECT @PickingListName AS PickingListName
		RETURN 0
	END

	--获取单据明细
	IF @I_Sender='Get_BillItemList'
	BEGIN 
		DECLARE @Temp_PickingListItem TABLE(
			RowId INT IDENTITY(1,1),
			RowLogo NVARCHAR(50),
			ItemSequence VARCHAR(20),
			ProductName NVARCHAR(50),
			QtyRequired FLOAT,
			QtyIssued FLOAT,
			OweQty FLOAT,
			WarehouseName NVARCHAR(50)
		)
		IF ISNULL(@PickingListName,'')=''
		BEGIN
			SELECT RowId, 
				   RowLogo, 
				   ProductName, 
				   QtyRequired, 
				   QtyIssued, 
				   OweQty, 
				   WarehouseName,
				   ItemSequence
			FROM @Temp_PickingListItem ORDER BY RowId
			RETURN 0
		END

		--获取单据明细
		SELECT @PickingListId=PickingListId
		FROM dbo.PickingList 
		WHERE PickingListName=@PickingListName

		IF ISNULL(@PickingListId,'')=''
		BEGIN
			SELECT RowId, 
				   RowLogo, 
				   ProductName, 
				   QtyRequired, 
				   QtyIssued, 
				   OweQty, 
				   WarehouseName,
				   ItemSequence
			FROM @Temp_PickingListItem ORDER BY RowId
			RETURN 0
		END

		SET @CurProductId=ISNULL(@CurProductId,'')

		
		--先插入当前产品
		INSERT INTO @Temp_PickingListItem
		     (
				 RowLogo,
				 ItemSequence,
		         ProductName,
		         QtyRequired,
		         QtyIssued,
		         OweQty,
		         WarehouseName
		     )
		SELECT 
			
			CASE WHEN (QtyRequired-QtyIssued)<=0 THEN '★√' --★当前扫描的物料，√代表已扫完
				 ELSE '★' END AS RowLogo, --★当前扫描的物料
			ItemSequence,
			ProductName,
			QtyRequired,
			QtyIssued,
			CASE WHEN (QtyRequired-QtyIssued)>=0 THEN (QtyRequired-QtyIssued)
				 ELSE 0 END AS OweQty,
			WorkcenterName AS WarehouseName
		FROM dbo.PickingListItem 
		INNER JOIN dbo.Product ON Product.ProductId=PickingListItem.ProductId
		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
		LEFT JOIN dbo.Workcenter ON Workcenter.WorkcenterId = PickingListItem.WorkcenterId
		WHERE PickingListId=@PickingListId 
		AND PickingListItem.ProductId=@CurProductId
		AND PickingListItem.DeleteFlag<>'X'
		ORDER BY ItemSequence

		--再插入其它产品
		INSERT INTO @Temp_PickingListItem
		     (
				 RowLogo,
				 ItemSequence,
		         ProductName,
		         QtyRequired,
		         QtyIssued,
		         OweQty,
		         WarehouseName
		     )
		SELECT 
			
			CASE WHEN (QtyRequired-QtyIssued)<=0 THEN '√'
				 ELSE '' END AS RowLogo,
			ItemSequence,
			ProductName,
			QtyRequired,
			QtyIssued,
			CASE WHEN (QtyRequired-QtyIssued)>=0 THEN (QtyRequired-QtyIssued)
				 ELSE 0 END AS OweQty,
			WorkcenterName AS WarehouseName
		FROM dbo.PickingListItem 
		INNER JOIN dbo.Product ON Product.ProductId=PickingListItem.ProductId
		INNER JOIN dbo.ProductRoot ON ProductRoot.ProductRootId=Product.ProductRootId
		LEFT JOIN dbo.Workcenter ON Workcenter.WorkcenterId = PickingListItem.WorkcenterId
		WHERE PickingListId=@PickingListId 
		AND PickingListItem.ProductId<>@CurProductId
		AND PickingListItem.DeleteFlag<>'X'
		ORDER BY RowLogo,ItemSequence


		--返回网格数据
		SELECT RowId, 
				RowLogo, 
				ProductName, 
				QtyRequired, 
				QtyIssued, 
				OweQty, 
				WarehouseName,
				ItemSequence
		FROM @Temp_PickingListItem ORDER BY RowId
		RETURN 0
	END


	--建议批次
	IF @I_Sender='Get_AdviceLot'
	BEGIN	
		DECLARE @AdviceCell NVARCHAR(MAX)=''

		EXEC dbo.TxnBase_MBill_PickingListAdviceLot
		    @I_ReturnMessage=@I_ReturnMessage OUTPUT,
		    @I_OrBitUserId=@I_OrBitUserId,
		    @I_OrBitUserName=@I_OrBitUserName,
		    @I_ResourceId=@I_ResourceId,
		    @I_ResourceName=@I_ResourceName,
		    @I_PlugInCommand=@I_PlugInCommand,
		    @PickingListName=@PickingListName,
		    @ProductId='',
		    @CurWareHouseId=@CurWareHouseId,
		    @CurCellId=@CurCellId,
		    @MaxQty=30,--显示多少个条码
		    @AdviceCell=@AdviceCell OUTPUT

		RETURN 0
	END
	--**********end 二、移动事务名：Material Issue To PickingListOther； end*******************

	RETURN 0


END
 












go

