
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/04/14 16:06:39:8129>
-- Description:   <领料单打印：生产领料单、杂发、委外领料、外协领料单>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  dbo.PickingListPrintDoMethod
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
@I_Parameter NVARCHAR(max)=''		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.


AS
BEGIN 
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--TY
	DECLARE @RowId INT=0
	DECLARE @TempStr NVARCHAR(2000)=''
	DECLARE @BillName NVARCHAR(50)=''

	--bill
	DECLARE @PickingListId CHAR(12)=''
	DECLARE @PickingListName NVARCHAR(50)=''
	DECLARE @PickingListStates VARCHAR(20)=''
	DECLARE @PickingListClass VARCHAR(2)=''
	--billItem
	DECLARE @PickingListItemId CHAR(12)=''
	DECLARE @ProductId CHAR(12)=''
	DECLARE @WorkcenterId CHAR(12)=''
	DECLARE @QtyRequired DECIMAL(18,6)=0
	DECLARE @QtyIssued DECIMAL(18,6)=0
	DECLARE @OweQty DECIMAL(18,6)=0 --欠料数

	--储位信息
	DECLARE @CellId CHAR(12)=''
	DECLARE @CellAdmin NVARCHAR(500)=''

	IF ISNULL(@I_Parameter,'')=''
	 BEGIN 
	   SET  @I_Parameter=@I_PKid
	 END

	--建议信息
	DECLARE @AdviceInfo TABLE(
		RowId INT IDENTITY(1,1),
		ProductId CHAR(12),
		WorkcenterId CHAR(12),
		CellId CHAR(12),
		CellName NVARCHAR(50),
		CellAdmin NVARCHAR(500) --储位管理员
	)

	--组合建议信息
	DECLARE @AdviceInfo_Combine TABLE(
		ProductId CHAR(12),
		WorkcenterId CHAR(12),
		CellAndAdmin NVARCHAR(2000) --按“储位:管理员;”进行组合
	)


	IF ISNULL(@I_PKid,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请选择有效项!'
		RETURN -1
	END

	--获取领料单 信息
	SELECT 
		@PickingListId=PickingListId,
		@PickingListName=PickingListName,
		@PickingListStates=PickingListStates,
		@PickingListClass=PickingListClass
	FROM dbo.PickingList 
	WHERE PickingListId IN (SELECT cptt.parameter_Value FROM  dbo.ConvertParameterToTable(@I_Parameter,';') AS cptt)

	SET @BillName=CASE @PickingListClass
					   WHEN '01' THEN  'PickingListPR'
					   WHEN '02' THEN 'PickingListOther'
					   WHEN '03' THEN 'PickingListOM'
					   WHEN '04' THEN 'PickingListPO'
					   ELSE '' END

	--IF ISNULL(@PickingListStates,'')<>'20'
	--BEGIN
	--	SET @I_ReturnMessage='ServerMessage:单据【'+@PickingListName+'】未审核，不允许打印!'
	--	RETURN -1
	--END

	--IF ISNULL(@PickingListStates,'')>='30'
	--BEGIN
	--	SET @I_ReturnMessage='ServerMessage:单据【'+@PickingListName+'】已确认，不需要再次打印!'
	--	RETURN -1
	--END



	--****************begin 获取：建议的储位和储位管理员信息 begin*****************
	--游标1循环处理：获取建议储位信息
	DECLARE cursor_1 CURSOR LOCAL FAST_FORWARD FOR  
	SELECT ProductId, WorkcenterId, SUM(ISNULL(QtyRequired,0)), SUM(ISNULL(QtyIssued,0) )
	FROM dbo.PickingListItem 
	WHERE PickingListId=@PickingListId
	AND QtyRequired>QtyIssued 
	AND DeleteFlag<>'X'
	GROUP BY ProductId,WorkcenterId
	OPEN cursor_1
	FETCH NEXT FROM cursor_1 
	INTO @ProductId,@WorkcenterId,@QtyRequired,@QtyIssued
	WHILE @@FETCH_STATUS = 0 
	BEGIN
		SET @OweQty=ISNULL(@QtyRequired,0)-ISNULL(@QtyIssued,0)

		--散货、生产日期、路线
		INSERT INTO @AdviceInfo
			 (
				 ProductId,
				 WorkcenterId,
				 CellId,
				 CellName
			 )
		SELECT  DISTINCT
				ProductId,
				@WorkcenterId,
				T3.CellId,
				T3.CellName
		FROM
		(
			--T2:“每列的累加汇总”往下推移一列
			SELECT *,LAG(SQty) OVER( ORDER BY(RowId)) AS SQty_LAG FROM 
			(
				--T1:列出“每列的累加汇总”
				SELECT *,SUM(Qty)OVER(ORDER BY RowId) SQty  FROM
				(
					SELECT 
						WW.ProductId,
						WW.LotSN,
						WW.Qty,
						UOMName,
						WW.ProductionDate,
						WW.CellId,
						Cell.CellName,
						ROW_NUMBER()OVER(ORDER BY (WW.OrgQty-WW.Qty) DESC ,IsSM DESC,WW.ProductionDate,Cell.RouteOrder) AS RowId
					FROM dbo.WW_RMInventory WW
					LEFT JOIN dbo.Cell ON Cell.CellId = WW.CellId
					LEFT JOIN dbo.UOM ON UOM.UOMId = WW.UOMId
					WHERE WW.ProductId=@ProductId AND WW.IsStorage=1 
					AND WW.WorkcenterId=@WorkcenterId AND WW.LotStatus='1'
					AND WW.Qty>0 -- AND (WW.ValidityEndDate>@CurDate OR WW.ValidityEndDate IS NULL)
				) T1
			)T2
		)T3 WHERE ISNULL(t3.SQty_LAG,0)<@OweQty

		
		FETCH NEXT FROM cursor_1 
		INTO  @ProductId,@WorkcenterId,@QtyRequired,@QtyIssued
	END
	CLOSE cursor_1
	DEALLOCATE cursor_1 

	
	--游标2循环处理：获取储位的管理员，一个储位允许有多个管理员
	DECLARE cursor_2 CURSOR LOCAL FAST_FORWARD FOR  
	SELECT RowId,CellId FROM @AdviceInfo
	OPEN cursor_2
	FETCH NEXT FROM cursor_2 
	INTO @RowId,@CellId
	WHILE @@FETCH_STATUS = 0 
	BEGIN
		SET @CellAdmin=''

		SELECT @CellAdmin=CASE @CellAdmin WHEN '' THEN ISNULL(UserDescription,'') 
										  ELSE @CellAdmin+'/'+ISNULL(UserDescription,'') END
		FROM dbo.Cell_User
		INNER JOIN dbo.SysUser ON SysUser.UserId = Cell_User.UserId
		WHERE CellId=@CellId
		
		UPDATE @AdviceInfo SET CellAdmin=@CellAdmin
		WHERE RowId=@RowId
	
		FETCH NEXT FROM cursor_2 
		INTO  @RowId,@CellId
	END
	CLOSE cursor_2
	DEALLOCATE cursor_2 
	
	--游标3循环处理：按“储位:管理员;”进行组合
	DECLARE cursor_3 CURSOR LOCAL FAST_FORWARD FOR  
	SELECT DISTINCT ProductId,WorkcenterId FROM @AdviceInfo
	OPEN cursor_3
	FETCH NEXT FROM cursor_3 
	INTO @ProductId,@WorkcenterId
	WHILE @@FETCH_STATUS = 0 
	BEGIN
		SET @TempStr=''

		--组合
		SELECT @TempStr=CASE @TempStr WHEN '' THEN ISNULL(CellName,'')+IIF(ISNULL(CellAdmin,'')='','','：')+ISNULL(CellAdmin,'')
									  ELSE @TempStr+'；'+ISNULL(CellName,'')++IIF(ISNULL(CellAdmin,'')='','','：')+ISNULL(CellAdmin,'')
									  END
		FROM @AdviceInfo
		WHERE ProductId=@ProductId AND WorkcenterId=@WorkcenterId
		

		--保存
		INSERT INTO @AdviceInfo_Combine
			 (
				 ProductId,
				 WorkcenterId,
				 CellAndAdmin
			 )
		VALUES
			 (
				 @ProductId,
				 @WorkcenterId,
				 @TempStr
			 )
	
		FETCH NEXT FROM cursor_3 
		INTO  @ProductId,@WorkcenterId
	END
	CLOSE cursor_3
	DEALLOCATE cursor_3 
	--****************end   获取：建议的储位和储位管理员信息 end  *****************






	--打印单据
	IF @PickingListClass ='01'
	BEGIN
	  
		SELECT  PickingList.PickingListId,
			PickingListName,
			CASE @PickingListClass
						WHEN '01' THEN  '生产领料单'
						WHEN '02' THEN '杂发单'
						WHEN '03' THEN '委外领料单'
						WHEN '04' THEN '外协领料单'
						ELSE '' END AS PickingListClass,
			BillType.BillTypeDescription AS PickingListType, 
			FactoryName,
			DivisionName,
			Workcenter.WorkcenterName,
			CONVERT(varchar(20), CASE WHEN ISNULL(DateRequired,'')='' THEN PickingList.CreateDate ELSE DateRequired END  , 111) AS DateRequired,
			CreateUser.UserName AS CreateUserName,
			CONVERT(varchar(20), PickingList.CreateDate, 111) AS CreateDate,
			ApproveUser.UserName AS ApproveUserName,
			CONVERT(varchar(20), PickingList.ApproveDate, 111) AS ApproveDate,
			ItemSequence,
			MOName,
			ProductName,
			ProductDescription ,
			CAST(QtyRequired AS FLOAT) AS QtyRequired,
			UOMName,
			Warehouse.WorkcenterName AS WarehouseName,
			a.CellAndAdmin,
			dbo.FindPickingLot(PickingListItem.PickingListItemId) AS LotSN,
			PickingListItem.QtyIssued
		FROM     dbo.PickingList
		INNER JOIN dbo.PickingListItem ON PickingList.PickingListId = PickingListItem.PickingListId
		INNER JOIN  dbo.Product ON PickingListItem.ProductId = Product.ProductId 
		INNER JOIN  dbo.ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId
		LEFT JOIN dbo.MO ON MO.MOId = PickingListItem.MOId
		LEFT JOIN  dbo.UOM ON PickingListItem.UOMId = UOM.UOMId 
		LEFT JOIN dbo.Factory ON PickingList.FactoryId = Factory.FactoryId 
		LEFT JOIN dbo.Division ON Division.DivisionId=PickingList.DivisionId
		LEFT JOIN dbo.SysUser CreateUser ON PickingList.CreateUserId = CreateUser.UserId
		LEFT JOIN dbo.SysUser ApproveUser ON PickingList.ApproveUserId = ApproveUser.UserId
		LEFT JOIN dbo.Workcenter ON PickingList.ToWorkcenterId=Workcenter.WorkcenterId
		LEFT JOIN dbo.Workcenter Warehouse ON PickingListItem.WorkcenterId = Warehouse.WorkcenterId 
		LEFT JOIN @AdviceInfo_Combine a ON a.WorkcenterId = PickingListItem.WorkcenterId AND a.ProductId = PickingListItem.ProductId
		LEFT JOIN (SELECT BillTypeName,BillTypeDescription
				   FROM dbo.Bill
				   INNER JOIN dbo.BillType ON BillType.BillId = Bill.BillId
				   WHERE BillName=@BillName
				   )BillType ON PickingList.PickingListType=BillType.BillTypeName
		WHERE PickingList.PickingListId IN (SELECT cptt.parameter_Value FROM  dbo.ConvertParameterToTable(@I_Parameter,';') AS cptt)
		ORDER BY PickingListItem.ItemSequence

	END
	ELSE IF @PickingListClass='02'
	BEGIN 
		SELECT  
			PickingListName,
			CASE @PickingListClass
						WHEN '01' THEN  '生产领料单'
						WHEN '02' THEN '杂发单'
						WHEN '03' THEN '委外领料单'
						WHEN '04' THEN '外协领料单'
						ELSE '' END AS PickingListClass,
			BillType.BillTypeName AS PickingListType, 
			FactoryName,
			DivisionName,
			Workcenter.WorkcenterName,
			CONVERT(varchar(20), DateRequired, 111) AS DateRequired,
			CreateUser.UserName AS CreateUserName,
			CONVERT(varchar(20), PickingList.CreateDate, 111) AS CreateDate,
			ApproveUser.UserName AS ApproveUserName,
			CONVERT(varchar(20), PickingList.ApproveDate, 111) AS ApproveDate,
			ItemSequence,
			ProductName,
			ProductDescription ,
			CAST(QtyRequired AS FLOAT) AS QtyRequired,
			UOMName,
			Warehouse.WorkcenterName AS WarehouseName,
			a.CellAndAdmin,
			dbo.FindPickingLot(PickingListItem.PickingListItemId) AS LotSN
		FROM     dbo.PickingList
		INNER JOIN dbo.PickingListItem ON PickingList.PickingListId = PickingListItem.PickingListId
		INNER JOIN  dbo.Product ON PickingListItem.ProductId = Product.ProductId 
		INNER JOIN  dbo.ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId
		LEFT JOIN  dbo.UOM ON PickingListItem.UOMId = UOM.UOMId 
		LEFT JOIN dbo.Factory ON PickingList.FactoryId = Factory.FactoryId 
		LEFT JOIN dbo.Division ON Division.DivisionId=PickingList.DivisionId
		LEFT JOIN dbo.SysUser CreateUser ON PickingList.CreateUserId = CreateUser.UserId
		LEFT JOIN dbo.SysUser ApproveUser ON PickingList.ApproveUserId = ApproveUser.UserId
		LEFT JOIN dbo.Workcenter ON PickingList.ToWorkcenterId=Workcenter.WorkcenterId
		LEFT JOIN dbo.Workcenter Warehouse ON PickingListItem.WorkcenterId = Warehouse.WorkcenterId 
		LEFT JOIN @AdviceInfo_Combine a ON a.WorkcenterId = PickingListItem.WorkcenterId AND a.ProductId = PickingListItem.ProductId
		LEFT JOIN (SELECT BillTypeName,BillTypeDescription
				   FROM dbo.Bill
				   INNER JOIN dbo.BillType ON BillType.BillId = Bill.BillId
				   WHERE BillName=@BillName
				   )BillType ON PickingList.PickingListType=BillType.BillTypeName
		WHERE PickingList.PickingListId=@I_PKid
	END
	ELSE IF @PickingListClass='03'
	BEGIN 
		SELECT  
			PickingListName,
			CASE @PickingListClass
						WHEN '01' THEN  '生产领料单'
						WHEN '02' THEN '杂发单'
						WHEN '03' THEN '委外领料单'
						WHEN '04' THEN '外协领料单'
						ELSE '' END AS PickingListClass,
			BillType.BillTypeName AS PickingListType, 
			FactoryName,
			Vendor.VendorShortName AS VendorName,
			Workcenter.WorkcenterName,
			CONVERT(varchar(20), DateRequired, 111) AS DateRequired,
			CreateUser.UserName AS CreateUserName,
			CONVERT(varchar(20), PickingList.CreateDate, 111) AS CreateDate,
			ApproveUser.UserName AS ApproveUserName,
			CONVERT(varchar(20), PickingList.ApproveDate, 111) AS ApproveDate,
			ItemSequence,
			MOName,
			ProductName,
			ProductDescription ,
			CAST(QtyRequired AS FLOAT) AS QtyRequired,
			UOMName,
			Warehouse.WorkcenterName AS WarehouseName,
			a.CellAndAdmin
		FROM     dbo.PickingList
		INNER JOIN dbo.PickingListItem ON PickingList.PickingListId = PickingListItem.PickingListId
		INNER JOIN  dbo.Product ON PickingListItem.ProductId = Product.ProductId 
		INNER JOIN  dbo.ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId
		LEFT JOIN dbo.MO ON MO.MOId = PickingListItem.MOId
		LEFT JOIN  dbo.UOM ON PickingListItem.UOMId = UOM.UOMId 
		LEFT JOIN dbo.Factory ON PickingList.FactoryId = Factory.FactoryId 
		LEFT JOIN dbo.Vendor ON Vendor.VendorId = PickingList.VendorId
		LEFT JOIN dbo.SysUser CreateUser ON PickingList.CreateUserId = CreateUser.UserId
		LEFT JOIN dbo.SysUser ApproveUser ON PickingList.ApproveUserId = ApproveUser.UserId
		LEFT JOIN dbo.Workcenter ON PickingList.ToWorkcenterId=Workcenter.WorkcenterId
		LEFT JOIN dbo.Workcenter Warehouse ON PickingListItem.WorkcenterId = Warehouse.WorkcenterId 
		LEFT JOIN @AdviceInfo_Combine a ON a.WorkcenterId = PickingListItem.WorkcenterId AND a.ProductId = PickingListItem.ProductId
		LEFT JOIN (SELECT BillTypeName,BillTypeDescription
				   FROM dbo.Bill
				   INNER JOIN dbo.BillType ON BillType.BillId = Bill.BillId
				   WHERE BillName=@BillName
				   )BillType ON PickingList.PickingListType=BillType.BillTypeName
		WHERE PickingList.PickingListId=@I_PKid
	END
	ELSE IF @PickingListClass='04'
	BEGIN 
		SELECT  
			PickingListName,
			CASE @PickingListClass
						WHEN '01' THEN  '生产领料单'
						WHEN '02' THEN '杂发单'
						WHEN '03' THEN '委外领料单'
						WHEN '04' THEN '外协领料单'
						ELSE '' END AS PickingListClass,
			BillType.BillTypeName AS PickingListType, 
			FactoryName,
			Vendor.VendorShortName AS VendorName,
			Workcenter.WorkcenterName,
			CONVERT(varchar(20), DateRequired, 111) AS DateRequired,
			CreateUser.UserName AS CreateUserName,
			CONVERT(varchar(20), PickingList.CreateDate, 111) AS CreateDate,
			ApproveUser.UserName AS ApproveUserName,
			CONVERT(varchar(20), PickingList.ApproveDate, 111) AS ApproveDate,
			ItemSequence,
			POName,
			ProductName,
			ProductDescription ,
			CAST(QtyRequired AS FLOAT) AS QtyRequired,
			UOMName,
			Warehouse.WorkcenterName AS WarehouseName,
			a.CellAndAdmin
		FROM     dbo.PickingList
		INNER JOIN dbo.PickingListItem ON PickingList.PickingListId = PickingListItem.PickingListId
		INNER JOIN  dbo.Product ON PickingListItem.ProductId = Product.ProductId 
		INNER JOIN  dbo.ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId
		LEFT JOIN dbo.PO ON PO.POId = PickingListItem.POId
		LEFT JOIN  dbo.UOM ON PickingListItem.UOMId = UOM.UOMId 
		LEFT JOIN dbo.Factory ON PickingList.FactoryId = Factory.FactoryId 
		LEFT JOIN dbo.Vendor ON Vendor.VendorId = PickingList.VendorId
		LEFT JOIN dbo.SysUser CreateUser ON PickingList.CreateUserId = CreateUser.UserId
		LEFT JOIN dbo.SysUser ApproveUser ON PickingList.ApproveUserId = ApproveUser.UserId
		LEFT JOIN dbo.Workcenter ON PickingList.ToWorkcenterId=Workcenter.WorkcenterId
		LEFT JOIN dbo.Workcenter Warehouse ON PickingListItem.WorkcenterId = Warehouse.WorkcenterId 
		LEFT JOIN @AdviceInfo_Combine a ON a.WorkcenterId = PickingListItem.WorkcenterId AND a.ProductId = PickingListItem.ProductId
		LEFT JOIN (SELECT BillTypeName,BillTypeDescription
				   FROM dbo.Bill
				   INNER JOIN dbo.BillType ON BillType.BillId = Bill.BillId
				   WHERE BillName=@BillName
				   )BillType ON PickingList.PickingListType=BillType.BillTypeName
		WHERE PickingList.PickingListId=@I_PKid
	END

	RETURN 0
END









go

