-- =============================================
-- Author:		<OrBit Team HK0313_OWen>
-- Create date: <2021.06.30>
-- Description:	<工单指定批次生成领料申请单>
-- Rev: 1.00
--=============================================
CREATE PROC [dbo].[Txn_MOPickingRequestDoMethod20220619]
(
	@I_Sender nvarchar(200)='', --客户端执行按钮
	@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
	@I_ExceptionFieldName nvarchar(100)='' output, --向客户端报告引起冲突的字段
	@I_LanguageId char(1)='1',				--客户端传入的语言ID
	@I_PlugInCommand varchar(5)='',		--插件命令
	@I_OrBitUserId char(12)='',			--用户ID
	@I_OrBitUserName nvarchar(100)='',	--用户名
	@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
	@I_ResourceName nvarchar(100)='',	--资源名
	@I_PKId char(12) = '',				--主键
	@I_SourcePKId char(12)='',			--执行拷贝时传入的源主键  
	@I_ParentPKId char(12)='',			--父级主键
	@I_Parameter nvarchar(100)='',		--插件参数	
	-- ======================= 以上是系统参数 ============================
	@TransId CHAR(32)='',
	@RequiredDate DATETIME=NULL,
	@ProductionWhse CHAR(4)='',
	@MONames NVARCHAR(256)='',
	@IsFirstXB BIT=0,
	@StartDate DATETIME=NULL,
	@EndDate DATETIME=NULL,	
	@OrderName VARCHAR(1000)=''
)
--WITH RECOMPILE
AS
BEGIN
	-- set NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	set NOCOUNT ON; 
	set TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	declare @IsStorage bit =1
	declare @QtyZero decimal(18, 8)=0.0	

	declare @WW_RMI TABLE(
		[WWId] [char](12) NOT NULL,
		[LotId] [char](12) NULL,
		[LotSN] [nvarchar](100) NULL,
		[LotStatus] [char](1) NULL,
		[QCStatus] [char](1) NULL,
		[IsolateStatus] [char](1) NULL,
		[Qty] [decimal](18, 8) NULL,
		[OrgQty] [decimal](18, 8) NULL,
		[IsSM] [bit] NULL,
		[UOMId] [char](12) NULL,
		[OrgLotSN] [nvarchar](100) NULL,
		[ProductId] [char](12) NULL,
		[ProductionLotNO] [varchar](50) NULL,
		[EntryDate] [datetime] NULL,
		[ValidityEndDate] [date] NULL,
		[FactoryId] [char](12) NULL,
		[WorkcenterId] [char](12) NULL,
		[CellId] [char](12) NULL,
		[IsStorage] [bit] NULL
	)

	--set @I_ReturnMessage='ServerMessage:'+@ToWareHouseId
	--	return -1
    IF ISNULL(@RequiredDate,'')=''
	BEGIN
	    SET @RequiredDate=GETDATE()
	END

	DECLARE @IsFirstXBE BIT 
  
    SELECT @IsFirstXBE = @IsFirstXB OPTION (OPTIMIZE FOR UNKNOWN)

	DECLARE @RESULT INT=0,@PickingListDescription NVARCHAR(100)='工单合并领料',
	@NowDate datetime =getdate(),@NewSN nvarchar(256)='',@MOId char(12),@MOName nvarchar(50),@ProductAllotId nvarchar(256)=''
	--游标使用参数
	,@FromFactoryId char(12)
	,@FromWareHouseId char(12)
	,@ToFactoryId char(12)
	,@ToWareHouseId char(12)
	,@ProductId char(12)
	,@AllotQty decimal(18,8)
	,@UOMName nvarchar(50)
	,@DivisionId CHAR(12)=''--领料部门Id
	,@MOItemId char(12)
	,@WareHouseId char(12)

	,@ProductClassify char(10)
	,@LotProductId char(12)
	,@LotSN NVARCHAR(100)
	,@LotQty decimal(18,8)
	,@ActualPickQty decimal(18,8)	
	,@CellId char(12)
	,@ToFactoryName NVARCHAR(128)
	,@ToWareHouseName NVARCHAR(128)
	,@FSWorkCenterId CHAR(12)
	,@UVWorkCenterId CHAR(12)
	,@HXWorkCenterId CHAR(12)
	,@SXWorkCenterId CHAR(12)
	,@TZWorkCenterId CHAR(12)
	,@PZWorkCenterId CHAR(12)
	,@B57ZWorkCenterId CHAR(12)

	DECLARE @ProductName NVARCHAR(100)

	DECLARE @PickingListName NVARCHAR(32)
	DECLARE @PickingList_MOId char(12)=''
	DECLARE @PickingListItemId char(12)=''
	DECLARE @PickingListItemLotId char(12)=''

	DECLARE @WaterProductId CHAR(12)
	DECLARE @ProductionLotNO VARCHAR(100)

	DECLARE @SMOItemId CHAR(12)
	DECLARE @SMOItemQty decimal(18,8)
	DECLARE @WQty DECIMAL(18,8)


	--DECLARE @OnlineStatus CHAR(2)

	--SELECT TOP 1 @OnlineStatus=OnlineStatus FROM ConfigurationLine 
	--WHERE ProductionLine=@ProductionWhse

	--IF ISNULL(@OnlineStatus,'')<>'' AND @OnlineStatus='1'
	--BEGIN
	--	SET @I_ReturnMessage='ServerMessage:当前选择生产车间产线未开放!'
	--	RETURN -1
	--END


	DECLARE @Temp_MONeed TABLE(
		MOId CHAR(12),
		MOItemId CHAR(12),
		AllotQty DECIMAL(18,8),
		AllotQtyCurrent DECIMAL(18,8)
	)

	DECLARE @Temp_Picking TABLE(
		MOAllotRequestId CHAR(12),
		FromFactoryId CHAR(12),
		FromWareHouseId CHAR(12),
		ToFactoryId CHAR(12),
		ToWareHouseId CHAR(12),
		MOId CHAR(12),
		MOItemId CHAR(12),
		ProductId CHAR(12),
		ProductClassify VARCHAR(10),
		ProductionLotNO VARCHAR(32),
		AllotQty DECIMAL(18,8),
		WQty DECIMAL(18,8)
	)

	DECLARE @MOT TABLE(
		MOId CHAR(12),
		MOName VARCHAR(50),
		MOStates VARCHAR(10),
		ProductLine VARCHAR(10)
	)

	SELECT TOP 1 @FSWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='FSXB'
	SELECT TOP 1 @UVWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='UVXB'
	SELECT TOP 1 @HXWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='HXXB'
	SELECT TOP 1 @SXWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='SXXB'
	SELECT TOP 1 @TZWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='SOXB'
	SELECT TOP 1 @PZWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='PZXB'
	SELECT TOP 1 @B57ZWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='B57Z'

	SET @ToFactoryId='FAC1000000SW'

	SET @ToWareHouseId=(CASE  
	WHEN @ProductionWhse IN('FS','FSS') THEN @FSWorkCenterId
	WHEN @ProductionWhse IN('YBFP','FSFT') THEN @PZWorkCenterId
	WHEN @ProductionWhse IN('HX','HXFT','HXS') THEN @HXWorkCenterId
	WHEN @ProductionWhse IN('SX','SXFT','SXS') THEN @SXWorkCenterId
	WHEN @ProductionWhse IN('TZ','TEFP','TEFT','TES') THEN @TZWorkCenterId
	WHEN @ProductionWhse IN('UV','UVFP','UVFT','UVS') THEN @UVWorkCenterId END);

	IF ISNULL(@ToWareHouseId,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:选择生产车间错误!'
		RETURN -1
	END

	--DECLARE @NOTPick TABLE(
	--	MOId CHAR(12)
	--)

	--DECLARE @MOI TABLE(
	--	MOId CHAR(12),
	--	ProductDescription NVARCHAR(100)
	--)
	
	IF @I_Sender='GetMOList'
	BEGIN
		IF ISNULL(@ProductionWhse,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择生产车间!'
			RETURN -1
		END

		IF ISNULL(@OrderName,'')<>''
		BEGIN
			IF len(@OrderName)>=13
			BEGIN
				IF(CHARINDEX ( @OrderName , '，' ))<=0
				BEGIN
				  SET @OrderName=REPLACE(@OrderName, '，', ',')
				END
				IF(CHARINDEX ( @OrderName , ';' ))<=0
				BEGIN
				  SET @OrderName=REPLACE(@OrderName, ';', ',')
				END
				
				IF(CHARINDEX ( @OrderName ,CHAR(10) ))<=0 OR (CHARINDEX ( @OrderName ,CHAR(13) )) <=0
				BEGIN
				  SET @OrderName=REPLACE(@OrderName, CHAR(10), ',')
				  SET @OrderName=REPLACE(@OrderName, CHAR(13), ',')
				  SET @OrderName=REPLACE(@OrderName, ',,', ',')
				END
			END
		END

		
		--UV/FS/SX/HX/TZ
		IF @ProductionWhse='FS'
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.SOName,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			LEFT JOIN InStorageMO IM ON MO.MOName=IM.MOName
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			(
				MO.ProductLine='FS' AND
				(
					(
						rtrim(ltrim(P.ProductClassify))='1' 
						OR IM.MOName IS NOT NULL
					)
					OR MO.WorkflowId IN ('WKF1000000Z2','WKF1000000YZ')
				)
			)
			AND PF.FactoryId='FAC1000000SW'
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='UV'
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			LEFT JOIN InStorageMO IM ON MO.MOName=IM.MOName
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			(
				MO.ProductLine='UV' AND 
				(
					(
						rtrim(ltrim(P.ProductClassify))='1' 
						OR IM.MOName IS NOT NULL
					)
					OR MO.WorkflowId IN ('WKF1000000Z2','WKF1000000Z0')
				)
			)
			AND PF.FactoryId='FAC1000000SW' --9502
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='SX'
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			LEFT JOIN InStorageMO IM ON MO.MOName=IM.MOName
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine='SX' 
			AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW' --9502
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='HX'
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			LEFT JOIN InStorageMO IM ON MO.MOName=IM.MOName
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine='HX' 
			AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW' --9502
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='TZ'
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			LEFT JOIN InStorageMO IM ON MO.MOName=IM.MOName
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine='TZ'
			AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW' --9502
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		
		IF @ProductionWhse='YBFP'--一部成品瓶装（FS、活性、水性）
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.SOName,MO.MOName,MO.MOQtyRequired 
			FROM MO  
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine IN('FS','HX','SX') AND MO.WorkflowId IN ('WKF1000000YZ','WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW' AND PFM.ProductFamilyName IN('102123','102124','102129')
			AND rtrim(ltrim(P.ProductClassify))='1' 
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='FSFT'--分散成品桶装
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.SOName,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='FS' AND MO.WorkflowId IN ('WKF1000000YZ')
			AND PF.FactoryId='FAC1000000SW' AND PFM.ProductFamilyName IN('102125','102131','102600')
			AND rtrim(ltrim(P.ProductClassify))='1' 
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='FSS'--分散半成品
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='FS' AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW'
			AND rtrim(ltrim(P.ProductClassify))='2' 
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='HXFT'--活性成品桶装
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='HX' AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW'
			AND rtrim(ltrim(P.ProductClassify))='1' AND PFM.ProductFamilyName IN('102125','102131','102600')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='HXS'--活性半成品
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='HX' AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW'
			AND rtrim(ltrim(P.ProductClassify))='2'
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='SXFT'--水性成品桶装
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.SOName,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='SX' AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW'
			AND rtrim(ltrim(P.ProductClassify))='1' AND PFM.ProductFamilyName IN('102125','102131','102600')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='SXS'--水性半成品
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='SX' AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW'
			AND rtrim(ltrim(P.ProductClassify))='2'
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='UVFP'--UV成品瓶装
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.SOName,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='UV' AND MO.WorkflowId IN ('WKF1000000Z2','WKF1000000Z0')
			AND PF.FactoryId='FAC1000000SW'
			AND rtrim(ltrim(P.ProductClassify))='1' AND PFM.ProductFamilyName IN('102123','102124','102129')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='UVFT'--UV成品桶装
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.SOName,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='UV' AND MO.WorkflowId IN ('WKF1000000Z2','WKF1000000Z0')
			AND PF.FactoryId='FAC1000000SW'
			AND rtrim(ltrim(P.ProductClassify))='1' AND PFM.ProductFamilyName IN('102125','102131','102600')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='UVS'--UV半成品
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='UV' AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW'
			AND rtrim(ltrim(P.ProductClassify))='2'
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='TEFP'--特种成品瓶装
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.SOName,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='TZ' AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW'
			AND rtrim(ltrim(P.ProductClassify))='1' AND PFM.ProductFamilyName IN('102123','102124','102129')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='TEFT'--特种成品桶装
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.SOName,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='TZ' AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW'
			AND rtrim(ltrim(P.ProductClassify))='1' AND PFM.ProductFamilyName IN('102125','102131','102600')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		IF @ProductionWhse='TES'--特种半成品
		BEGIN
			WITH NOTPick AS
			(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS AllotQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'','0') GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				INNER JOIN Product C ON A.ProductId=C.ProductId
				INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
				INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
				INNER JOIN MO F ON A.MOId=F.MOId
				INNER JOIN ConfigurationLine G ON F.ProductLine=G.ProductionLine
				WHERE ISNULL(A.DeleteFlag,'') IN(NULL,'','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0)-ISNULL(A.ItemQtyBack,0) AND A.LineSequence<>'000'
				AND ((ISNULL(G.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(G.OnlineStatus,'')<>'2')--部分上线只领包材
			),MOI AS 
			(
				SELECT A.MOId,MIN(B.ProductDescription) AS ProductDescription FROM MOItem A 
				INNER JOIN Product B ON A.ProductId=B.ProductId
				INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
				INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
				WHERE A.LineSequence<>'000' AND ISNULL(A.DeleteFlag,'') IN('','0') AND D.ProductFamilyName NOT IN('102850','102855','102857','102858','102859')
				GROUP BY A.MOId
			)
			SELECT CAST(0 AS BIT) AS Sel,(CASE WHEN P.ProductClassify='1' THEN ISNULL(M.ProductDescription,P.ProductDescription) ELSE P.ProductDescription END) AS ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO 
			--INNER JOIN CompletedMO CM ON MO.MOName=CM.MOName
			LEFT JOIN MOI M ON MO.MOId=M.MOId
			INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN NOTPick N ON MO.MOId=N.MOId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFM ON PR.ProductFamilyId=PFM.ProductFamilyId
			WHERE MO.MOStates='20' and ISNULL(MO.DeleteFlag,'') IN('','0')
			AND 
			--DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0 AND 
			MO.ProductLine ='TZ' AND MO.WorkflowId IN ('WKF1000000Z2')
			AND PF.FactoryId='FAC1000000SW'
			AND rtrim(ltrim(P.ProductClassify))='2'
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			ORDER BY MO.PlannedDateFrom DESC
		END

		RETURN 0
	END

	IF @I_Sender='CreateMOPickingDetail'
	BEGIN
		IF ISNULL(@ProductionWhse,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择生产车间!'
			RETURN -1
		END

		IF ISNULL(@MONames,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择需要领料申请的工单!'
			RETURN -1
		END

		IF EXISTS(SELECT 1 FROM MO WHERE MOName IN(SELECT col FROM DB_Split(@MONames,',')) AND DeleteFlag IN(NULL,'','0') AND MOStates<>'20')
		BEGIN
			SET @I_ReturnMessage='ServerMessage:存在未下达的工单，请重新选择!'
			RETURN -1
		END

		INSERT INTO @MOT(MOId,MOName,MOStates,ProductLine)
		SELECT B.MOId,A.col,B.MOStates,B.ProductLine FROM DB_Split(@MONames,',') A
		INNER JOIN MO B ON A.col=B.MOName

		SELECT @WaterProductId=P.ProductId FROM ProductRoot PR INNER JOIN Product P ON PR.ProductRootId=P.ProductRootId WHERE PR.ProductName='9999999999'

		SELECT TOP 1 @ToFactoryName=FactoryName+' '+FactoryDescription FROM Factory WHERE FactoryId=@ToFactoryId
		
		SELECT TOP 1 @ToWareHouseName=WorkcenterName+' '+WorkcenterDescription FROM Workcenter WHERE WorkcenterId=@ToWareHouseId;

		  WITH
		  WR AS (
			  --统计每个仓库物料的在库数量
			  SELECT FactoryId,WorkcenterId,ProductId,SUM(Qty) AS Qty FROM WW_RMInventory WHERE IsStorage=@IsStorage AND LotStatus='1' AND Qty>@QtyZero GROUP BY FactoryId,WorkcenterId,ProductId
		  )
		  ,MP AS(
			  --查询已指定批次的数量
			  --SELECT A.MOId,A.MOItemId,B.FactoryId,B.WorkcenterId,SUM(A.Qty) AS Qty FROM MOProductionLot A
			  --INNER JOIN WW_RMInventory B on A.LotSN=b.LotSN GROUP BY A.MOId,A.MOItemId,B.FactoryId,B.WorkcenterId

			  SELECT A.MOId,A.MOItemId,B.FactoryId,B.WorkcenterId,A.ProductionQty AS Qty FROM MOItem A
			  INNER JOIN (
				  SELECT ROW_NUMBER() OVER(PARTITION BY ProductionLotNO,ProductId ORDER BY IsSM DESC,EntryDate) AS RN,
				  ProductionLotNO,ProductId,FactoryId,WorkcenterId,EntryDate FROM WW_RMInventory
				  WHERE LotStatus='1' AND IsStorage=@IsStorage
			  ) B ON B.ProductionLotNO IN(SELECT TOP 1 col FROM DB_Split(A.ProductionLotNO,',')) AND A.ProductId=B.ProductId
			  WHERE ISNULL(A.ProductionLotNO,'')<>'' AND A.DeleteFlag IN (NULL,'','0') AND B.RN=1
		  )
		  ,WP AS(
			  --查询物料所在的仓库
			  SELECT * FROM (
				  SELECT ROW_NUMBER() OVER(PARTITION BY A.ProductId ORDER BY A.IsSM DESC,A.EntryDate) AS RN,
				  A.ProductId,A.FactoryId AS FactoryId,A.WorkcenterId AS WorkcenterId FROM 
				  (SELECT ProductId,FactoryId,WorkcenterId,MAX(CAST(IsSM AS INT)) AS IsSM,MIN(EntryDate) AS EntryDate 
				  FROM WW_RMInventory
				  WHERE IsStorage=@IsStorage AND Qty>@QtyZero AND ISNULL(FactoryId,'')='FAC1000000SW' AND LotStatus='1' 
				  AND (ISNULL(WorkcenterId,'') NOT IN('',@FSWorkCenterId,@UVWorkCenterId,@HXWorkCenterId,@SXWorkCenterId,@TZWorkCenterId,@PZWorkCenterId,@B57ZWorkCenterId) OR ISNULL(WorkcenterId,'')=@ToWareHouseId)
				  GROUP BY ProductId,FactoryId,WorkcenterId) A
				  INNER JOIN Factory B ON A.FactoryId=B.FactoryId
				  INNER JOIN Workcenter C ON A.WorkcenterId=C.WorkcenterId
				  
			  ) AS WWTABLE
		  )
		  ,WWP AS(
			  SELECT A.* FROM WP A
			  LEFT JOIN WP B ON A.ProductId=B.ProductId AND B.FactoryId=@ToFactoryId AND B.WorkcenterId=@ToWareHouseId
			  WHERE (@IsFirstXBE=0 AND A.RN=1) OR (@IsFirstXBE=1 AND ((B.RN IS NULL AND A.RN=1) OR (B.RN IS NOT NULL AND A.FactoryId=@ToFactoryId AND A.WorkcenterId=@ToWareHouseId)))
		  )
		  , T AS (
			  --获取每个工单物料需要调拨的物料用量
			  SELECT MOI.MOId,M.MOName,M.MOStates,MOI.MOItemId,MOI.ProductId,MOI.ProductionLotNO,MOI.ProductionQty,
			  (CASE WHEN MP.FactoryId IS NULL THEN WWP.FactoryId ELSE MP.FactoryId END) AS FactoryId,
			  (CASE WHEN MP.WorkcenterId IS NULL THEN WWP.WorkcenterId ELSE MP.WorkcenterId END) AS WorkcenterId,
			  MOI.ItemQtyRequired,CAST((CASE WHEN MP.MOItemId IS NULL THEN 0 ELSE 1 END) AS BIT) AS IsStorage,
			  MOI.ItemQtyRequired AS Qty,ISNULL(MOI.ItemQtyBack,0) AS ItemQtyBack
			  FROM  @MOT M 
			  INNER JOIN MOItem MOI ON MOI.MOId=M.MOId
			  LEFT JOIN MP ON MOI.MOId=MP.MOId AND MOI.MOItemId=MP.MOItemId
			  LEFT JOIN WWP ON MOI.ProductId=WWP.ProductId
			  INNER JOIN Product C ON MOI.ProductId=C.ProductId
			  INNER JOIN ProductRoot D ON C.ProductRootId=D.ProductRootId
			  INNER JOIN ProductFamily E ON D.ProductFamilyId=E.ProductFamilyId
			  INNER JOIN ConfigurationLine F ON M.ProductLine=F.ProductionLine
			  WHERE ISNULL(MOI.DeleteFlag,'') IN('','0') AND MOI.LineSequence<>'000'
			  AND MOI.ProductId<>@WaterProductId
			  AND ((ISNULL(F.OnlineStatus,'')='2' AND E.ProductFamilyName IN('102850','102855','102857','102858','102859')) OR ISNULL(F.OnlineStatus,'')<>'2')--部分上线只领包材
		  )
		  ,MAMD AS (
			  --查询工单已申请数量和已领料数量
			  --SELECT A.MOItemId,A.ProductionLotNO,A.ProductId,SUM(A.AllotQtyCurrent) AS RequestQty,
			  --SUM((CASE WHEN B.PickingListStates='30' THEN AllotQtyCurrent ELSE 0 END)) AS AllocatedQty FROM MOAllotMODetail A
			  --INNER JOIN PickingList B ON A.MOAllotRequestId=B.MOAllotRequestId AND A.ToFactoryId=B.FactoryId AND A.ToWareHouseId=B.ToWorkcenterId
			  --INNER JOIN PickingListItem PLI ON B.PickingListId=PLI.PickingListId AND A.MOItemId=PLI.MOItemId AND A.MOId=PLI.MOId
			  --GROUP BY A.MOItemId,A.ProductionLotNO,A.ProductId

			  SELECT A.MOItemId,B.ProductionLotNO,B.ProductId,SUM(QtyRequired) AS RequestQty,
			  SUM((CASE WHEN ISNULL(A.ToSAPStates,'')<>'' THEN QtyIssued ELSE 0 END)) AS AllocatedQty FROM PickingListItem A
			  INNER JOIN MOItem B ON A.MOItemId=B.MOItemId
			  GROUP BY A.MOItemId,B.ProductId,B.ProductionLotNO
		  )
		  ,LIL AS (
			  --统计每个工单物料的已上料数量
			  SELECT L.MOId,M.ProductId,SUM(LD.ActualQty) AS ActualQty FROM LoadingItemLotDetail LD 
			  INNER JOIN LoadingItemLot L ON LD.LoadingItemLotId=L.LoadingItemLotId
			  INNER JOIN MOItem M ON LD.MOItemId=M.MOItemId
			  GROUP BY L.MOId,M.ProductId
		  )
		  ,WA AS (
			  --统计线边仓中工单已调拨但未开始生产的物料数量
			  SELECT A.ToFactoryId,A.ToWareHouseId,A.ProductId,SUM((A.AllotQtyCurrent-ISNULL(LIL.ActualQty,0))) as Qty FROM MOAllotMODetail A
			  INNER JOIN ProductAllot B ON A.MOAllotRequestId=B.MOAllotRequestId AND A.TempFactoryId=B.FactoryId AND A.TempWorkcenterId=B.WorkcenterId AND A.ToFactoryId=B.ToFactoryId AND A.ToWareHouseId=B.ToWorkcenterId
			  LEFT JOIN LIL ON A.MOId=LIL.MOId AND A.ProductId=LIL.ProductId
			  WHERE B.ProductAllotStates ='30' 
			  GROUP BY A.ToFactoryId,A.ToWareHouseId,A.ProductId
		  )
		  ,WWQ AS (
			  --统计每个仓库可用库存量
			  SELECT WR.FactoryId,WR.WorkcenterId,WR.ProductId,(CASE WHEN (ISNULL(WR.Qty,0)-ISNULL(WA.Qty,0))>0 THEN (ISNULL(WR.Qty,0)-ISNULL(WA.Qty,0)) ELSE 0 END) as Qty FROM WR
			  LEFT JOIN WA ON WR.FactoryId=WA.ToFactoryId AND WR.WorkcenterId=WA.ToWareHouseId AND WR.ProductId=WA.ProductId
		  )
		  ,TW AS(
			  SELECT ProductId,SUM(Qty) AS Qty FROM WR GROUP BY ProductId
		  )
		  --,EX AS(
			 -- SELECT ProductId,SUM(SurplusExceedQty) AS SurplusExceedQty FROM ExceedPicking 
			 -- WHERE FactoryId=@ToFactoryId AND WorkcenterId=@ToWareHouseId GROUP BY ProductId
		  --)
		  --总查询
		  --(CASE WHEN ISNULL(TW.Qty,0)>(T.Qty-ISNULL(MAMD.RequestQty,0.00000000)) THEN (T.Qty-ISNULL(MAMD.RequestQty,0.00000000)) ELSE ISNULL(TW.Qty,0) END) as PickingQty
		  --ISNULL(TWWQ.SurplusExceedQty,0.00000000) AS ExceedPickingQty

		 SELECT CAST(0 AS BIT) AS [Check],T.MOId,T.MOName,T.MOItemId,T.ProductId,T.ProductionLotNO,T.IsStorage AS IsProduction,PR.ProductName,P.ProductDescription,
		 T.ItemQtyRequired,(T.Qty-(ISNULL(MAMD.RequestQty,0.00000000)-T.ItemQtyBack)) as PickingQty,
		 ISNULL(MAMD.AllocatedQty,0.00000000) AS PickedQty,ISNULL(MAMD.RequestQty,0.00000000) AS RequestQty,
		 ISNULL(WR.Qty,0.00000000) AS WarehouseQty,ISNULL(WWR.Qty,0) AS PLWarehouseQty,ISNULL(TW.Qty,0) AS TotalWarehouseQty,
		 T.FactoryId AS TempFactoryId,T.WorkcenterId AS TempWorkcenterId,(F.FactoryName+' '+F.FactoryDescription) AS TempFactoryName,
		 (W.WorkcenterName+' '+W.WorkcenterDescription) AS TempWorkcenterName,
		 @ToFactoryId AS ToFactoryId,@ToWareHouseId AS ToWareHouseId,@ToFactoryName AS ToFactoryName,@ToWareHouseName AS ToWareHouseName
		  FROM T
		 INNER JOIN Product P ON T.ProductId=P.ProductId
		 INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
		 LEFT JOIN Factory F ON T.FactoryId=F.FactoryId
		 LEFT JOIN Workcenter W ON T.WorkcenterId=W.WorkcenterId
		 LEFT JOIN MAMD 
		 ON T.MOItemId=MAMD.MOItemId AND T.ProductId=MAMD.ProductId
		 LEFT JOIN  WR ON T.ProductId=WR.ProductId AND WR.FactoryId=T.FactoryId AND WR.WorkcenterId=T.WorkcenterId
		 LEFT JOIN WR WWR ON T.ProductId=WWR.ProductId AND WWR.FactoryId=@ToFactoryId AND WWR.WorkcenterId=@ToWareHouseId
		 --LEFT JOIN  EX AS TWWQ ON T.ProductId=TWWQ.ProductId
		 LEFT JOIN TW ON T.ProductId=TW.ProductId
		 WHERE ISNULL(MAMD.RequestQty,0.00000000)-T.ItemQtyBack<T.ItemQtyRequired
		 --ORDER BY T.MOName

		 RETURN 0
	END

	IF @I_Sender='SubmitPicking'
	BEGIN
		select @RequiredDate=RequiredDate from MOAllotRequest WHERE MOAllotRequestId=@TransId
		
		IF ISNULL(@RequiredDate,'')=''
		BEGIN
			SET @RequiredDate=GETDATE()
		END

		DECLARE @PickingProductId CHAR(12)
		DECLARE @PickingMOId CHAR(12)
		SELECT @PickingProductId=A.ProductId,@PickingMOId=A.MOId FROM MOAllotMODetail A
		LEFT JOIN (SELECT MOId,MOItemId,SUM(QtyRequired) AS PickingQty FROM PickingListItem WHERE DeleteFlag IN(NULL,'0','') GROUP BY MOId,MOItemId) B ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
		INNER JOIN MOItem C ON A.MOId=C.MOId AND A.MOItemId=C.MOItemId
		WHERE A.MOAllotRequestId=@TransId AND ISNULL(A.AllotQty,0)+ISNULL(B.PickingQty,0)-ISNULL(C.ItemQtyBack,0)>C.ItemQtyRequired
		IF ISNULL(@PickingProductId,'')<>''
		BEGIN
			SELECT @MOName=MOName FROM MO WHERE MOId=@PickingMOId
			SELECT @ProductName=ProductDescription FROM Product WHERE ProductId=@PickingProductId
			SET @I_ReturnMessage='ServerMessage:工单['+ISNULL(@MOName,'')+']产品['+ISNULL(@ProductName,'')+']领料数量已超需求数，请确认!'
			DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
			DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
			DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
			RETURN -1
		END

		INSERT INTO @Temp_MONeed(MOId,MOItemId,AllotQty,AllotQtyCurrent)
		SELECT MOId,MOItemId,AllotQty,AllotQty FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId

		begin transaction Request
		--/***********************   已入库未指定小批号的工单指定生产批次    ****************************/
		--DECLARE @ReserveLot VARCHAR(100),@ReserveQty DECIMAL(18,8)
		--DECLARE @MPPKId char(12)=''
		--,@WWId char(12),@Qty decimal(18,8)
	
		--DECLARE WRTOMP CURSOR FOR
		--SELECT C.MOProductionLotId,D.WWId,D.LotSN,C.Qty FROM MOAllotMODetail A 
		--INNER JOIN MOItem B ON A.MOId=B.MOId AND A.ProductId=B.ProductId
		--INNER JOIN MOProductionLot C ON B.MOId=C.MOId AND B.MOItemId=C.MOItemId
		--LEFT JOIN WW_RMInventory D ON C.LotSN=D.LotSN
		--WHERE A.MOAllotRequestId=@TransId AND D.LotSN IS NOT NULL AND C.IsActivity=0
		----打开一个游标
		--OPEN WRTOMP
		----循环一个游标
		--FETCH NEXT FROM WRTOMP INTO @MPPKId,@WWId,@LotSN,@Qty
		--WHILE @@FETCH_STATUS =0
		--BEGIN
		--	--插入物料批号追踪表
		--	EXEC dbo.TxnBase_MLotTrack
		--		@I_OrBitUserId =@I_OrBitUserId, -- char(12)
		--		@I_PlugInCommand=@I_PlugInCommand,
		--		@I_ResourceId =@I_ResourceId, -- char(12)
		--		@LotSN = @LotSN, -- nvarchar(50) --物料批号
		--		@LotQty = @Qty, -- decimal(18, 6)--数量
		--		@TxnCode ='M-工单指定批号' , -- nvarchar(50) --事务码
		--		@OrderName =@MPPKId , -- nvarchar(50) --单据号
		--		@Remark = N'工单生产预指定批次预留物料' -- nvarchar(200) --备注

		--	--修改库存批次状态为预留
		--	UPDATE WW_RMInventory SET LotStatus='9' WHERE WWId=@WWId
		
		--	UPDATE MOProductionLot SET WWId=@WWId WHERE MOProductionLotId=@MPPKId
		
		--	FETCH NEXT FROM  WRTOMP INTO @MPPKId,@WWId,@LotSN,@Qty
		--END
		--CLOSE WRTOMP --关闭游标
		--DEALLOCATE WRTOMP --释放游标
		--/***********************   指定批次结束    ****************************/


		--从线边仓领料的物料和从其他仓库领料的物料分别生成领料单
		DECLARE @EACH INT=1

		WHILE @EACH<=2
		BEGIN
			--获取创建领料单所需数据（从A仓到B仓领料需求数量/可用库存）
			INSERT INTO @Temp_Picking(
				MOAllotRequestId,
				FromFactoryId,
				FromWareHouseId,
				ToFactoryId,
				ToWareHouseId,
				MOId,
				MOItemId,
				ProductId,
				ProductClassify,
				ProductionLotNO,
				AllotQty,
				WQty
			)
			SELECT A.*,ISNULL(W.Qty,0) AS WQty FROM (
				select MOAllotRequestId,TempFactoryId,TempWorkcenterId,ToFactoryId,ToWareHouseId,MAD.MOId,MAD.MOItemId,MAD.ProductId,P.ProductClassify,MAD.ProductionLotNO,MAD.AllotQty from MOAllotMODetail MAD
				INNER JOIN (
				SELECT A.ProductId,(CASE WHEN C.ProductFamilyName IN('102850','102855','102857','102858','102859') THEN '9' ELSE A.ProductClassify END) AS ProductClassify FROM Product A 
				INNER JOIN ProductRoot B ON A.ProductRootId=B.ProductRootId
				INNER JOIN ProductFamily C ON B.ProductFamilyId=C.ProductFamilyId
				) P ON MAD.ProductId=P.ProductId
				where MOAllotRequestId=@TransId
				AND ((@EACH=1 AND TempWorkcenterId =@ToWareHouseId) OR (@EACH=2 AND TempWorkcenterId <>@ToWareHouseId))
			) A
			LEFT JOIN (
				SELECT FactoryId,WorkcenterId,ProductId,SUM(Qty) AS Qty FROM WW_RMInventory 
				WHERE IsStorage=@IsStorage AND LotStatus='1' AND Qty>@QtyZero GROUP BY FactoryId,WorkcenterId,ProductId
			) W ON A.TempFactoryId=W.FactoryId AND A.TempWorkcenterId=W.WorkcenterId AND A.ProductId=W.ProductId
			
			DECLARE PickingRequest CURSOR  for
			--根据领料车间和产品类型生成多张领料单
			SELECT ToFactoryId,ToWareHouseId,ProductClassify,ProductionLotNO FROM @Temp_Picking group by ToFactoryId,ToWareHouseId,ProductClassify,ProductionLotNO

			OPEN PickingRequest
			FETCH NEXT FROM PickingRequest INTO @ToFactoryId,@ToWareHouseId,@ProductClassify,@ProductionLotNO
			WHILE @@FETCH_STATUS =0
			BEGIN
				select top 1 @DivisionId=DivisionId from Division where DivisionCode=(CASE WHEN @ToWareHouseId IN(@UVWorkCenterId,@TZWorkCenterId) THEN 'IPD2' ELSE 'IPD1' END)

				--根据有无库存可发料分别生成领料单，1、创建有库存的领料单
				IF EXISTS(SELECT 1 FROM @Temp_Picking WHERE WQty>0 AND AllotQty>0 AND ToFactoryId=@ToFactoryId AND ToWareHouseId=@ToWareHouseId AND ProductClassify=@ProductClassify AND ProductionLotNO=@ProductionLotNO)
				BEGIN
					EXEC SysGetObjectPKId '','PickingList',@I_PKId OUTPUT
					set @ProductAllotId+=('['+ISNULL(cast(@I_PKId as nvarchar(12)),'')+']')
					--调用生产领料单保存事件
					EXEC @RESULT= PickingListPRSaveData 
					@I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@I_OrBitUserId=@I_OrBitUserId,
					@I_OrBitUserName=@I_OrBitUserName,
					@I_PKId=@I_PKId,
					@CreateUserName=@I_OrBitUserName,
					@CreateDate=@NowDate,
					@DateRequired=@RequiredDate,
					@PickingListTypeCode='01',--01:普通发料，04：缺料发料
					@FactoryId=@ToFactoryId,
					@DivisionId=@DivisionId,
					@ToWorkcenterId=@ToWareHouseId,
					@PickingListDescription=@PickingListDescription

					IF ISNULL(@RESULT,0)<>0
					BEGIN 
						ROLLBACK transaction Request
						DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
						DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
						DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
							return -1
					END
					--把申请单号写入领料单
					IF EXISTS(SELECT top 1 1 from PickingList where PickingListId=@I_PKId)
					begin
						UPDATE PickingList SET MOAllotRequestId=@TransId,ProductClassify=@ProductClassify,ProductionLotNO=@ProductionLotNO where PickingListId=@I_PKId
					end

					select top 1 @PickingListName=ISNULL(PickingListName,'') from PickingList where PickingListId=@I_PKId
					IF ISNULL(@PickingListName,'')<>''
					BEGIN
						SET @NewSN+=('['+ISNULL(@PickingListName,'')+']')

						DECLARE PickingDetail CURSOR  for

						select MOI.MOItemId,MO.MOName,MO.MOId,MAD.ProductId,MAD.AllotQty,MAD.FromWareHouseId,UOM.UOMName from @Temp_Picking MAD 
						INNER JOIN MO ON MAD.MOId=MO.MOId
						INNER JOIN MOItem MOI ON MOI.MOId=MAD.MOId AND MOI.MOItemId=MAD.MOItemId AND MOI.DeleteFlag IN(NULL,'','0') AND MOI.LineSequence<>'000'
						INNER JOIN Product P ON P.ProductId=MAD.ProductId
						LEFT JOIN UOM ON P.UsageUOMId=UOM.UOMId
						where MAD.ToFactoryId=@ToFactoryId and MAD.ToWareHouseId=@ToWareHouseId AND MAD.ProductClassify=@ProductClassify 
						AND MAD.ProductionLotNO=@ProductionLotNO
						AND MAD.AllotQty>0 AND MAD.WQty>0 AND MOI.DeleteFlag IN(NULL,'','0')

						OPEN PickingDetail
						FETCH NEXT FROM PickingDetail INTO @MOItemId,@MOName,@MOId,@ProductId,@AllotQty,@WareHouseId,@UOMName
						WHILE @@FETCH_STATUS =0
						BEGIN
							SELECT @WQty=WQty FROM @Temp_Picking WHERE ToFactoryId=@ToFactoryId AND ToWareHouseId=@ToWareHouseId AND ProductClassify=@ProductClassify
							AND FromWareHouseId=@WareHouseId AND ProductId=@ProductId AND ProductionLotNO=@ProductionLotNO

							IF @AllotQty>@WQty
							BEGIN
								SET @AllotQty=@WQty
							END
							IF @AllotQty>0
							BEGIN
								--生成领料单明细
								EXEC SysGetObjectPKId '','PickingListItem',@PickingListItemId OUTPUT
								--调用生产领料单保存事件
								EXEC @RESULT= dbo.[PickingListItemPRSaveData] 
								@I_ReturnMessage=@I_ReturnMessage OUTPUT,
								@I_OrBitUserId=@I_OrBitUserId,
								@I_OrBitUserName=@I_OrBitUserName,
								@I_PKId=@PickingListItemId,
								@I_ParentPKId=@I_PKId,
								@MOItemIdNO=@MOItemId,
								@MOName=@MOName,
								@ProductId=@ProductId,
								@QtyRequired=@AllotQty,
								@QtyIssued=0,
								@WareHouseId=@WareHouseId,
								@UOMName=@UOMName

								IF ISNULL(@RESULT,0)<>0
								BEGIN 
									ROLLBACK transaction Request
									DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
									DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
									DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
										return -1
								END

								UPDATE @Temp_MONeed SET AllotQtyCurrent-=@AllotQty WHERE MOId=@MOId AND MOItemId=@MOItemId

								UPDATE @Temp_Picking SET WQty-=@AllotQty 
								WHERE FromWareHouseId=@WareHouseId AND ProductId=@ProductId AND ISNULL(RTRIM(LTRIM(ProductionLotNO)),'') =''
							END
							
					
							FETCH NEXT FROM PickingDetail INTO @MOItemId,@MOName,@MOId,@ProductId,@AllotQty,@WareHouseId,@UOMName
						END
						CLOSE PickingDetail --关闭游标
						DEALLOCATE PickingDetail --释放游标

						DECLARE PickingMO CURSOR  for
						select MAD.MOId,MO.MOName from @Temp_Picking MAD 
						INNER JOIN MO ON MAD.MOId=MO.MOId
						INNER JOIN @Temp_MONeed T ON MAD.MOId=T.MOId AND MAD.MOItemId=T.MOItemId
						where MAD.ToFactoryId=@ToFactoryId and MAD.ToWareHouseId=@ToWareHouseId AND MAD.ProductClassify=@ProductClassify
						AND T.AllotQty>T.AllotQtyCurrent AND MAD.ProductionLotNO=@ProductionLotNO
						group by MAD.MOId,MO.MOName

						OPEN PickingMO
						FETCH NEXT FROM PickingMO INTO @MOId,@MOName
						WHILE @@FETCH_STATUS =0
						BEGIN
							--生成生产领料单工单
							EXEC SysGetObjectPKId '','PickingList_MO',@PickingList_MOId OUTPUT
							--调用生产领料单保存事件
							EXEC @RESULT= dbo.[PickingList_MOSaveData] 
							@I_ReturnMessage=@I_ReturnMessage OUTPUT,
							@I_OrBitUserId=@I_OrBitUserId,
							@I_OrBitUserName=@I_OrBitUserName,
							@I_PKId=@PickingList_MOId,
							@I_ParentPKId=@I_PKId,
							@MOId=@MOId,
							@MOName=@MOName

							IF ISNULL(@RESULT,0)<>0
							BEGIN 
								ROLLBACK transaction Request
								DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
								DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
								DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
									return -1
							END

							--溶剂工单如果没有启动批号，则自动启动一个批号  of 2022/01/04
							IF EXISTS(SELECT 1 FROM MO WHERE MOId=@MOId AND ProductLine IN('TZ','HX','SX') AND ISNULL(WorkflowId,'')<>'')
							BEGIN
								SELECT @SMOItemId=MOItemId,@SMOItemQty=ItemQtyRequired FROM MOItem WHERE MOId=@MOId AND LineSequence='000' AND DeleteFlag IN(NULL,'','0')
								IF ISNULL(@SMOItemId,'')<>'' AND ISNULL(@SMOItemQty,0)>0
								BEGIN
									EXEC [dbo].[MOItem_StartHalfLot_DoMethod]
									@I_Sender=@I_Sender,
									@I_ReturnMessage=@I_ReturnMessage OUTPUT,
									@I_PlugInCommand=@I_PlugInCommand,
									@I_OrBitUserId=@I_OrBitUserId,
									@I_ResourceId=@I_ResourceId,
									@I_PKId=@SMOItemId,
									@StandardQtyInLot=@SMOItemQty,
									@StartQty=@SMOItemQty
								END
							END

						FETCH NEXT FROM  PickingMO INTO @MOId,@MOName
						END
						CLOSE PickingMO --关闭游标
						DEALLOCATE PickingMO --释放游标

						UPDATE PickingList SET PickingListStates='20',ApproveDate=GETDATE(),ApproveUserId=@I_OrBitUserId where PickingListId=@I_PKId

						/************************************************** 自动发料 BEGIN ******************************************************/
					
						--DECLARE PickingDetailLot CURSOR  for

						----线边仓领料自动发料
						--SELECT PickingListItemId FROM PickingListItem WHERE PickingListId=@I_PKId AND QtyIssued<QtyRequired AND DeleteFlag IN(NULL,'','0') AND WorkcenterId=@ToWareHouseId

						--OPEN PickingDetailLot
						--FETCH NEXT FROM PickingDetailLot INTO @PickingListItemId
						--WHILE @@FETCH_STATUS =0
						--BEGIN
						--	IF NOT EXISTS(SELECT 1 FROM PickingListItem WHERE PickingListItemId=@PickingListItemId AND QtyIssued<QtyRequired AND DeleteFlag IN(NULL,'','0'))
						--	BEGIN
						--		FETCH NEXT FROM PickingDetailLot INTO @PickingListItemId
						--		CONTINUE;
						--	END
						
						--	SELECT TOP 1 @WareHouseId=WorkcenterId,@ProductId=ProductId FROM PickingListItem WHERE PickingListItemId=@PickingListItemId AND QtyIssued<QtyRequired

						--	IF EXISTS(SELECT D.ProductFamilyName FROM PickingListItem A
						--	INNER JOIN Product B ON A.ProductId=B.ProductId
						--	INNER JOIN ProductRoot C ON B.ProductRootId=C.ProductRootId
						--	INNER JOIN ProductFamily D ON C.ProductFamilyId=D.ProductFamilyId
						--	WHERE A.PickingListItemId=@PickingListItemId AND D.ProductFamilyName IN('102850','102855','102857','102858','102859'))
						--	BEGIN
						--		SELECT @ProductName=TProductName FROM Product WHERE ProductId=@ProductId
						--		SET @LotSN='MES'+@ProductName;
						--	END
						--	ELSE
						--	BEGIN
						--		SELECT @LotSN=LotSN FROM WW_RMInventory WITH(NOLOCK)
						--		WHERE LotStatus='1' AND IsStorage=1 AND WorkcenterId=@WareHouseId AND ProductId=@ProductId AND ValidityEndDate>@NowDate 
						--		AND (ISNULL(@ProductionLotNO,'')='' OR ProductionLotNO IN(SELECT col FROM DB_Split(@ProductionLotNO,','))) AND IsExceedPicking=1
						--		ORDER BY IsSM DESC,EntryDate
						--	END
						
						--	IF EXISTS(SELECT 1 FROM WW_RMInventory WHERE LotSN=@LotSN AND LotStatus='1' AND Qty>0 AND IsStorage=1)
						--	BEGIN
						--		EXEC @RESULT=[dbo].[PDA_MaterialToPickingListPR]
						--		@I_Sender=@I_Sender,
						--		@I_ReturnMessage=@I_ReturnMessage OUTPUT,
						--		@I_OrBitUserId=@I_OrBitUserId,
						--		@I_ResourceId=@I_ResourceId,
						--		@PickingListName=@PickingListName,
						--		@BoxOrLotSN=@LotSN

						--		IF @RESULT<>0
						--		BEGIN
						--			ROLLBACK transaction Request

						--			DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
						--			DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
						--			DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
						--			return @RESULT
						--		END
						--	END
						
						--	FETCH NEXT FROM PickingDetailLot INTO @PickingListItemId
						--END
						--CLOSE PickingDetailLot --关闭游标
						--DEALLOCATE PickingDetailLot --释放游标
					
					
						/************************************************** 自动发料 END ******************************************************/

						--正常领料自动审核，超领料等待审核
						--IF NOT EXISTS(select MAMD.MOId from #TEMP MAD 
						--INNER JOIN MOAllotMODetail MAMD ON MAD.MOAllotRequestId=MAMD.MOAllotRequestId AND 
						--MAD.FromFactoryId=MAMD.TempFactoryId AND MAD.FromWareHouseId=MAMD.TempWorkcenterId AND MAD.ProductId=MAMD.ProductId
						--AND MAD.ToFactoryId=MAMD.ToFactoryId AND MAD.ToWareHouseId=MAMD.ToWareHouseId
						--INNER JOIN MOItem MOI ON MAMD.MOId=MOI.MOId AND MAMD.MOItemId=MOI.MOItemId AND MOI.DeleteFlag IN(NULL,'','0')
						--where MAD.ToFactoryId=@ToFactoryId and MAD.ToWareHouseId=@ToWareHouseId AND MAD.ProductClassify=@ProductClassify 
						--AND (ISNULL(MOI.ItemQtyRequired,0)-ISNULL(MOI.ItemQtyIssued,0)-ISNULL(MAMD.AllotQtyCurrent,0))<=0)
						--BEGIN
						--	UPDATE PickingList SET PickingListStates='20',ApproveDate=GETDATE(),ApproveUserId=@I_OrBitUserId where PickingListId=@I_PKId
						--END
					END

				END
				
				--2、除有库存外，其他物料创建一张领料单
				IF EXISTS(SELECT 1 FROM @Temp_Picking MAD
				INNER JOIN @Temp_MONeed T ON MAD.MOId=T.MOId AND MAD.MOItemId=T.MOItemId 
				WHERE T.AllotQtyCurrent>0 AND MAD.ToFactoryId=@ToFactoryId and MAD.ToWareHouseId=@ToWareHouseId AND MAD.ProductClassify=@ProductClassify AND MAD.ProductionLotNO=@ProductionLotNO)
				BEGIN
					EXEC SysGetObjectPKId '','PickingList',@I_PKId OUTPUT
					set @ProductAllotId+=('['+ISNULL(cast(@I_PKId as nvarchar(12)),'')+']')
					--调用生产领料单保存事件
					EXEC @RESULT= PickingListPRSaveData 
					@I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@I_OrBitUserId=@I_OrBitUserId,
					@I_OrBitUserName=@I_OrBitUserName,
					@I_PKId=@I_PKId,
					@CreateUserName=@I_OrBitUserName,
					@CreateDate=@NowDate,
					@DateRequired=@RequiredDate,
					@PickingListTypeCode='04',--01:普通发料，04：缺料发料
					@FactoryId=@ToFactoryId,
					@DivisionId=@DivisionId,
					@ToWorkcenterId=@ToWareHouseId,
					@PickingListDescription=@PickingListDescription

					IF ISNULL(@RESULT,0)<>0
					BEGIN 
						ROLLBACK transaction Request
						DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
						DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
						DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
							return -1
					END
					--把申请单号写入领料单
					IF EXISTS(SELECT top 1 1 from PickingList where PickingListId=@I_PKId)
					begin
						UPDATE PickingList SET MOAllotRequestId=@TransId,ProductClassify=@ProductClassify,ProductionLotNO=@ProductionLotNO where PickingListId=@I_PKId
					end

					select top 1 @PickingListName=ISNULL(PickingListName,'') from PickingList where PickingListId=@I_PKId
					IF ISNULL(@PickingListName,'')<>''
					BEGIN
						SET @NewSN+=('['+ISNULL(@PickingListName,'')+']')

						DECLARE PickingDetail CURSOR  for

						select MOI.MOItemId,MO.MOName,MAD.ProductId,T.AllotQtyCurrent,MAD.FromWareHouseId,UOM.UOMName from @Temp_Picking MAD 
						INNER JOIN MO ON MAD.MOId=MO.MOId
						INNER JOIN MOItem MOI ON MOI.MOId=MAD.MOId AND MOI.MOItemId=MAD.MOItemId AND MOI.DeleteFlag IN(NULL,'','0') AND MOI.LineSequence<>'000'
						INNER JOIN Product P ON P.ProductId=MAD.ProductId
						LEFT JOIN UOM ON P.UsageUOMId=UOM.UOMId
						INNER JOIN @Temp_MONeed T ON MAD.MOId=T.MOId AND MAD.MOItemId=T.MOItemId
						where MAD.ToFactoryId=@ToFactoryId and MAD.ToWareHouseId=@ToWareHouseId AND MAD.ProductClassify=@ProductClassify AND MAD.ProductionLotNO=@ProductionLotNO
						AND MAD.AllotQty>0 AND T.AllotQtyCurrent>0 AND MOI.DeleteFlag IN(NULL,'','0')

						OPEN PickingDetail
						FETCH NEXT FROM PickingDetail INTO @MOItemId,@MOName,@ProductId,@AllotQty,@WareHouseId,@UOMName
						WHILE @@FETCH_STATUS =0
						BEGIN
							IF @AllotQty>0
							BEGIN
								--生成领料单明细
								EXEC SysGetObjectPKId '','PickingListItem',@PickingListItemId OUTPUT
								--调用生产领料单保存事件
								EXEC @RESULT= dbo.[PickingListItemPRSaveData] 
								@I_ReturnMessage=@I_ReturnMessage OUTPUT,
								@I_OrBitUserId=@I_OrBitUserId,
								@I_OrBitUserName=@I_OrBitUserName,
								@I_PKId=@PickingListItemId,
								@I_ParentPKId=@I_PKId,
								@MOItemIdNO=@MOItemId,
								@MOName=@MOName,
								@ProductId=@ProductId,
								@QtyRequired=@AllotQty,
								@QtyIssued=0,
								@WareHouseId=@WareHouseId,
								@UOMName=@UOMName

								IF ISNULL(@RESULT,0)<>0
								BEGIN 
									ROLLBACK transaction Request
									DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
									DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
									DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
										return -1
								END

								--UPDATE @Temp_MONeed SET AllotQtyCurrent-=@AllotQty WHERE MOId=@MOId AND MOItemId=@MOItemId

								--UPDATE @Temp_Picking SET WQty-=@AllotQty 
								--WHERE ToFactoryId=@ToFactoryId AND ToWareHouseId=@ToWareHouseId AND ProductClassify=@ProductClassify
								--AND FromWareHouseId=@WareHouseId
							END
							
					
							FETCH NEXT FROM PickingDetail INTO @MOItemId,@MOName,@ProductId,@AllotQty,@WareHouseId,@UOMName
						END
						CLOSE PickingDetail --关闭游标
						DEALLOCATE PickingDetail --释放游标

						DECLARE PickingMO CURSOR  for
						select MAD.MOId,MO.MOName from @Temp_Picking MAD 
						INNER JOIN MO ON MAD.MOId=MO.MOId
						INNER JOIN @Temp_MONeed T ON MAD.MOId=T.MOId AND MAD.MOItemId=T.MOItemId
						where MAD.ToFactoryId=@ToFactoryId and MAD.ToWareHouseId=@ToWareHouseId AND MAD.ProductClassify=@ProductClassify
						AND T.AllotQtyCurrent>0 AND MAD.ProductionLotNO=@ProductionLotNO
						group by MAD.MOId,MO.MOName

						OPEN PickingMO
						FETCH NEXT FROM PickingMO INTO @MOId,@MOName
						WHILE @@FETCH_STATUS =0
						BEGIN
							--生成生产领料单工单
							EXEC SysGetObjectPKId '','PickingList_MO',@PickingList_MOId OUTPUT
							--调用生产领料单保存事件
							EXEC @RESULT= dbo.[PickingList_MOSaveData] 
							@I_ReturnMessage=@I_ReturnMessage OUTPUT,
							@I_OrBitUserId=@I_OrBitUserId,
							@I_OrBitUserName=@I_OrBitUserName,
							@I_PKId=@PickingList_MOId,
							@I_ParentPKId=@I_PKId,
							@MOId=@MOId,
							@MOName=@MOName

							IF ISNULL(@RESULT,0)<>0
							BEGIN 
								ROLLBACK transaction Request
								DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
								DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
								DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
									return -1
							END

							--溶剂工单如果没有启动批号，则自动启动一个批号  of 2022/01/04
							IF EXISTS(SELECT 1 FROM MO WHERE MOId=@MOId AND ProductLine='TZ' AND ISNULL(WorkflowId,'')<>'')
							BEGIN
								SELECT @SMOItemId=MOItemId,@SMOItemQty=ItemQtyRequired FROM MOItem WHERE MOId=@MOId AND LineSequence='000' AND DeleteFlag IN(NULL,'','0')
								IF ISNULL(@SMOItemId,'')<>'' AND ISNULL(@SMOItemQty,0)>0
								BEGIN
									EXEC [dbo].[MOItem_StartHalfLot_DoMethod]
									@I_ReturnMessage=@I_ReturnMessage OUTPUT,
									@I_PlugInCommand=@I_PlugInCommand,
									@I_OrBitUserId=@I_OrBitUserId,
									@I_ResourceId=@I_ResourceId,
									@I_PKId=@SMOItemId,
									@StandardQtyInLot=@SMOItemQty,
									@StartQty=@SMOItemQty
								END
							END

						FETCH NEXT FROM  PickingMO INTO @MOId,@MOName
						END
						CLOSE PickingMO --关闭游标
						DEALLOCATE PickingMO --释放游标

						--缺料单不自动审核
						UPDATE PickingList SET PickingListStates='20',ApproveDate=GETDATE(),ApproveUserId=@I_OrBitUserId where PickingListId=@I_PKId

					END

				END
				FETCH NEXT FROM  PickingRequest INTO @ToFactoryId,@ToWareHouseId,@ProductClassify,@ProductionLotNO
			END
			CLOSE PickingRequest --关闭游标
			DEALLOCATE PickingRequest --释放游标

			DELETE FROM @Temp_Picking

			SET @EACH+=1;
		END

		
	
		--回写调拨单号
		IF EXISTS(SELECT TOP 1 1 FROM MOAllotRequest WHERE MOAllotRequestId=@TransId)
		BEGIN
			UPDATE MOAllotRequest SET ProductAllotId=@ProductAllotId,MOAllotRequestStates=20 WHERE MOAllotRequestId=@TransId
		END

		--UPDATE MO SET IsPlanned=1 WHERE MOId IN (SELECT DISTINCT MOId FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId)

		--计算工单本次调拨数量
		UPDATE MOAllotMODetail SET AllotQtyCurrent=AllotQty FROM MOAllotMODetail 
		WHERE MOAllotRequestId=@TransId
		IF @@ERROR<>0
		BEGIN
			ROLLBACK transaction Request

			DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
			DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
			DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
			set @I_ReturnMessage='ServerMessage:工单领料申请失败!'
			return -1
		END
		ELSE
		BEGIN
			COMMIT transaction Request
		END
	
		set @I_ReturnMessage='ServerMessage:工单领料申请成功，领料单号'+@NewSN+'!'
		return 0
	END

	RETURN 0



END
go

