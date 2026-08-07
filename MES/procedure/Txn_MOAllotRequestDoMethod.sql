SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OrBit Team HK0313_OWen>
-- Create date: <2021.06.21>
-- Description:	<工单调拨申请单生成仓库调拨单>
-- Rev: 1.00
--=============================================
CREATE PROC [dbo].[Txn_MOAllotRequestDoMethod]
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
@RequiredDate datetime=NULL,
@ProductionWhse NVARCHAR(10)='',
@MONames NVARCHAR(256)='',
@StartDate DATETIME=NULL,
@EndDate DATETIME=NULL,	
@ProductDescription NVARCHAR(256)='',
@OrderName VARCHAR(1000)=''

AS
BEGIN
	-- set NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	set NOCOUNT ON; 
	set TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
--
	--set @I_ReturnMessage='ServerMessage:'+@ToWareHouseId
	--	return -1

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

	DECLARE @RESULT INT=0,@ProductAllotDescription NVARCHAR(50)='多工单合并发料',
		@NowDate datetime =getdate(),@NewSN nvarchar(256)='',@MOId char(12),@ProductAllotId nvarchar(256)=''
		--游标使用参数
		,@FromFactoryId char(12)
		,@FromWareHouseId char(12)
		,@ToFactoryId char(12)
		,@ToWareHouseId char(12)
		,@ProductId char(12)
		,@AllotQty decimal(18,8)
		,@LineSequence INT
		,@UsageUOMId char(12)
		,@LotSN NVARCHAR(100)
		,@BoxSN nvarchar(100)
		,@LotQty decimal(18,8)
		,@CellId char(12)
		,@MOProductionLotId CHAR(12),
		@ToFactoryName NVARCHAR(128),
		@ToWareHouseName NVARCHAR(128)
		,@FSWorkCenterId CHAR(12)
		,@UVWorkCenterId CHAR(12)
		,@FSWorkCenterId1 CHAR(12)
		,@FSWorkCenterId2 CHAR(12)
		,@FSWorkCenterId3 CHAR(12)
		,@FSWorkCenterId4 CHAR(12)
        ,@HXWorkCenterId CHAR(12)
        ,@SXWorkCenterId CHAR(12)
        ,@TZWorkCenterId CHAR(12)
		,@ProductClassify char(10)
		,@WQty DECIMAL(18,8)

	declare @IsStorage bit =1
	declare @QtyZero decimal(18, 8)=0.0	

	DECLARE @ItemPKId char(12)=''
	DECLARE @ProductAllotName NVARCHAR(16)

	DECLARE @WaterProductId CHAR(12)
    DECLARE @ZR_WorkflowName NVARCHAR(255)
    
	DECLARE @Temp_Picking TABLE(
		MOAllotRequestId CHAR(12),
		FromFactoryId CHAR(12),
		FromWareHouseId CHAR(12),
		ToFactoryId CHAR(12),
		ToWareHouseId CHAR(12),
		ProductId CHAR(12),
		ProductClassify VARCHAR(10),
		ProductionLotNO VARCHAR(32),
		AllotQty DECIMAL(18,8),
		AllotQtyCurrent DECIMAL(18,8),
		WQty DECIMAL(18,8)
	)

	DECLARE @MOT TABLE(
		MOId CHAR(12),
		MOName VARCHAR(50),
		MOStates VARCHAR(10)
	)
	
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
				--=============================================添加水性的调拨 Irving 2026/01/19 （注意工作流id）=============================================================================
        IF @ProductionWhse=N'SX'
		BEGIN
			--去除已调拨完所有物料的工单
			WITH NOTALLOT AS(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(AllotQtyCurrent) AS AllotQty FROM MOAllotMODetail GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				WHERE ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0) AND A.LineSequence<>'000'
			)

			SELECT DISTINCT CAST(0 AS BIT) AS Sel,P.ProductDescription,MO.MOName ,MO.MOQtyRequired,MO.PlannedDateFrom
			FROM MO INNER JOIN Product P ON MO.ProductId=P.ProductId
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFA ON PR.ProductFamilyId=PFA.ProductFamilyId
			INNER JOIN NOTALLOT N ON MO.MOId=N.MOId
			WHERE MO.MOStates=20 and ISNULL(MO.DeleteFlag,'') IN('','0')
			--AND (@RequiredDate IS NULL OR DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0)
			AND ((PF.ProductLineCode ='SX'    --活性车间
			AND rtrim(ltrim(P.ProductClassify))='2'
			--AND ISNULL(PFA.ProductFamilyName,'')='102345' AND LEFT(P.ProductDescription,4)<>'COM.'
			    ) --todo 需要后续更改
			OR MO.WorkflowId IN ('')) -- todo 水性工作流
			--AND PF.FactoryId='FAC1000000SW' --9502
			AND (ISNULL(@ProductDescription,'')='' OR P.ProductDescription LIKE '%'+@ProductDescription+'%')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			AND MO.WorkflowId <>'WKF1000000Z2'--排除其他工作流程
			ORDER BY MO.PlannedDateFrom,MO.MOName DESC
		END
		--=============================================添加水性的调拨 Irving 2026/01/19 =============================================================================


		--=============================================添加活性的调拨 Irving 2026/01/19 =============================================================================
        IF @ProductionWhse=N'HX'
		BEGIN
			--去除已调拨完所有物料的工单
			WITH NOTALLOT AS(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(AllotQtyCurrent) AS AllotQty FROM MOAllotMODetail GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				WHERE ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0) AND A.LineSequence<>'000'
			)

			SELECT DISTINCT CAST(0 AS BIT) AS Sel,P.ProductDescription,MO.MOName ,MO.MOQtyRequired,MO.PlannedDateFrom
			FROM MO INNER JOIN Product P ON MO.ProductId=P.ProductId
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFA ON PR.ProductFamilyId=PFA.ProductFamilyId
			INNER JOIN NOTALLOT N ON MO.MOId=N.MOId
			WHERE MO.MOStates=20 and ISNULL(MO.DeleteFlag,'') IN('','0')
			--AND (@RequiredDate IS NULL OR DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0)
			AND ((PF.ProductLineCode ='HX'    --活性车间
			AND rtrim(ltrim(P.ProductClassify))='2'
			--AND ISNULL(PFA.ProductFamilyName,'')='102345' AND LEFT(P.ProductDescription,4)<>'COM.'
			    ) --todo 需要后续更改
			OR MO.WorkflowId IN ('WKF1000000ZB','WKF1000000ZC')) -- 活性半成品、活性水浆
			--AND PF.FactoryId='FAC1000000SW' --9502
			AND (ISNULL(@ProductDescription,'')='' OR P.ProductDescription LIKE '%'+@ProductDescription+'%')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			AND MO.WorkflowId <>'WKF1000000Z2'--排除其他工作流程
			ORDER BY MO.PlannedDateFrom,MO.MOName DESC
		END
		--=============================================添加活性的调拨 Irving 2026/01/19 =============================================================================

        		--=============================================添加特种TZ的调拨1 Irving 2024/04/03 （注意工作流id）=============================================================================
        IF @ProductionWhse=N'TZ'
		BEGIN
			--去除已调拨完所有物料的工单
			WITH NOTALLOT AS(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(AllotQtyCurrent) AS AllotQty FROM MOAllotMODetail GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				WHERE ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>=ISNULL(B.AllotQty,0) AND A.LineSequence<>'000'
			)

			SELECT DISTINCT CAST(0 AS BIT) AS Sel,P.ProductDescription,MO.MOName ,MO.MOQtyRequired,MO.PlannedDateFrom
			FROM MO INNER JOIN Product P ON MO.ProductId=P.ProductId
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFA ON PR.ProductFamilyId=PFA.ProductFamilyId
			INNER JOIN NOTALLOT N ON MO.MOId=N.MOId
			INNER join ZR_WorkflowConfig on mo.WorkflowId = ZR_WorkflowConfig.WorkflowId --===Irving 2025.04.17 begin / 改为名称判断 / end=====
			WHERE MO.MOStates=20 and ISNULL(MO.DeleteFlag,'') IN('','0')
			--AND (@RequiredDate IS NULL OR DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0)
			AND ((PF.ProductLineCode ='TZ'    -- todo 特种车间
			AND rtrim(ltrim(P.ProductClassify))='2'
			--AND ISNULL(PFA.ProductFamilyName,'')='102345' AND LEFT(P.ProductDescription,4)<>'COM.'
			    ) --todo 需要后续更改
			OR ZR_WorkflowConfig.WorkflowName IN ('TZ组合液生产流程','TZ色浆生产流程','TZ半成品墨水生产线')) --===Irving 2025.04.17 begin / 改为名称判断 / end=====
			--AND PF.FactoryId='FAC1000000SW' --9502
			AND (ISNULL(@ProductDescription,'')='' OR P.ProductDescription LIKE '%'+@ProductDescription+'%')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			AND MO.WorkflowId <>'WKF1000000Z2'--排除其他工作流程
			ORDER BY MO.PlannedDateFrom,MO.MOName DESC

		    --begin 检查是否存在不符合条件的 WorkflowId
            SELECT @ZR_WorkflowName = WorkflowName FROM MO left join ZR_WorkflowConfig on mo.WorkflowId = ZR_WorkflowConfig.WorkflowId
                                     WHERE MOName = @OrderName
            IF ISNULL(@ZR_WorkflowName,'') not in ('TZ组合液生产流程','TZ色浆生产流程','TZ半成品墨水生产线')
                begin
                    set @I_ReturnMessage='ServerMessage: ~该工单工作流是 '+ ISNULL(@ZR_WorkflowName,'') +' ，请重新选择 生产车间 或 检查修改工单工作流'
                    return -1
                end
            --end 检查是否存在不符合条件的 WorkflowId
		END
		--=============================================添加特种TZ的调拨1 Irving Irving 2024/04/03 （注意工作流id）=============================================================================

		IF @ProductionWhse=N'研磨'
		BEGIN
			--去除已调拨完所有物料的工单
			WITH NOTALLOT AS(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(AllotQtyCurrent) AS AllotQty FROM MOAllotMODetail GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				WHERE ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0) AND A.LineSequence<>'000'
			)

			SELECT CAST(0 AS BIT) AS Sel,P.ProductDescription,MO.MOName ,MO.MOQtyRequired
			FROM MO INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFA ON PR.ProductFamilyId=PFA.ProductFamilyId
			INNER JOIN NOTALLOT N ON MO.MOId=N.MOId
			WHERE MO.MOStates=20 and ISNULL(MO.DeleteFlag,'') IN('','0')
			--AND (@RequiredDate IS NULL OR DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0) 
			AND ((PF.ProductLineCode ='FS'    --分散车间
			AND rtrim(ltrim(P.ProductClassify))='2'
			AND ISNULL(PFA.ProductFamilyName,'')='102345' AND LEFT(P.ProductDescription,4)<>'COM.') --D浆
			OR MO.WorkflowId IN ('WKF1000000YQ','WKF1000000YR'))
			AND PF.FactoryId='FAC1000000T4' --9502
			AND (ISNULL(@ProductDescription,'')='' OR P.ProductDescription LIKE '%'+@ProductDescription+'%')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			AND MO.WorkflowId <>'WKF1000000Z2'--排除其他工作流程
			ORDER BY MO.PlannedDateFrom,MO.MOName DESC


-- ========================================================  --临时测试test1111=========================================================
-- DECLARE @TestTempId char(12) = ''
-- 		EXEC SysGetObjectPKId '', 'TestTemp', @TestTempId OUTPUT
-- INSERT INTO [dbo].[TestTemp] ([TestTempId], [str2],str3,str4,str5) VALUES (@TestTempId, @ProductDescription,@OrderName,@StartDate,@EndDate)
-- ========================================================  --临时测试test1111=========================================================

		END
		
		IF @ProductionWhse='分散'
		BEGIN
			WITH NOTALLOT AS(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(AllotQtyCurrent) AS AllotQty FROM MOAllotMODetail GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				WHERE ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0) AND A.LineSequence<>'000'
			)

			SELECT CAST(0 AS BIT) AS Sel,P.ProductDescription,MO.MOName ,MO.MOQtyRequired
			FROM MO INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFA ON PR.ProductFamilyId=PFA.ProductFamilyId
			INNER JOIN NOTALLOT N ON MO.MOId=N.MOId
			WHERE MO.MOStates=20 and ISNULL(MO.DeleteFlag,'') IN('','0')
			--AND (@RequiredDate IS NULL OR DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0) 
			AND ((PF.ProductLineCode IN ('FS','WB')    --分散车间
			AND rtrim(ltrim(P.ProductClassify))='2'
			AND (ISNULL(PFA.ProductFamilyName,'')<>'102345' OR LEFT(P.ProductDescription,4)='COM.')) --半成品
			OR MO.WorkflowId IN ('WKF1000000YT','WKF1000000YV','WKF1000000YS'))
			AND PF.FactoryId='FAC1000000T4' --9502
			AND (ISNULL(@ProductDescription,'')='' OR P.ProductDescription LIKE '%'+@ProductDescription+'%')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			AND MO.WorkflowId <>'WKF1000000Z2'--排除其他工作流程
			ORDER BY MO.PlannedDateFrom,MO.MOName DESC
		END

		IF @ProductionWhse='UVS'
		BEGIN
			WITH NOTALLOT AS(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(AllotQtyCurrent) AS AllotQty FROM MOAllotMODetail GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				WHERE ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0) AND A.LineSequence<>'000'
			)

			SELECT CAST(0 AS BIT) AS Sel,P.ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFA ON PR.ProductFamilyId=PFA.ProductFamilyId
			INNER JOIN NOTALLOT N ON MO.MOId=N.MOId
			WHERE MO.MOStates=20 and ISNULL(MO.DeleteFlag,'') IN('','0')
			--AND (@RequiredDate IS NULL OR DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0) 
			AND ((PF.ProductLineCode='UV'    --分散车间
			AND rtrim(ltrim(P.ProductClassify))='2' --半成品
			AND ISNULL(PFA.ProductFamilyName,'')='102345')
			OR MO.WorkflowId IN ('WKF1000000YW'))
			AND PF.FactoryId='FAC1000000T4' --9502
			AND (ISNULL(@ProductDescription,'')='' OR P.ProductDescription LIKE '%'+@ProductDescription+'%')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			AND MO.WorkflowId <>'WKF1000000Z2'--排除其他工作流程
			ORDER BY MO.PlannedDateFrom,MO.MOName DESC
		END

		IF @ProductionWhse='UVP'
		BEGIN
			WITH NOTALLOT AS(
				SELECT DISTINCT A.MOId FROM MOItem A
				LEFT JOIN (SELECT MOId,MOItemId,SUM(AllotQtyCurrent) AS AllotQty FROM MOAllotMODetail GROUP BY MOId,MOItemId) B
				ON A.MOId=B.MOId AND A.MOItemId=B.MOItemId
				WHERE ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>ISNULL(B.AllotQty,0) AND A.LineSequence<>'000'
			)

			SELECT CAST(0 AS BIT) AS Sel,P.ProductDescription,MO.MOName,MO.MOQtyRequired 
			FROM MO INNER JOIN Product P ON MO.ProductId=P.ProductId  
			INNER JOIN dbo.Product_Factory PF ON PF.ProductId = P.ProductId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			INNER JOIN ProductFamily PFA ON PR.ProductFamilyId=PFA.ProductFamilyId
			INNER JOIN NOTALLOT N ON MO.MOId=N.MOId
			WHERE MO.MOStates=20 and ISNULL(MO.DeleteFlag,'') IN('','0')
			--AND (@RequiredDate IS NULL OR DATEDIFF(DAY,MO.PlannedDateFrom,ISNULL(@RequiredDate,GETDATE()))=0) 
			AND ((PF.ProductLineCode='UV'    --分散车间
			AND rtrim(ltrim(P.ProductClassify))='2' --半成品
			AND ISNULL(PFA.ProductFamilyName,'')<>'102345')
			OR MO.WorkflowId IN ('WKF1000000YX','WKF1000000YY'))
			AND PF.FactoryId='FAC1000000T4' --9502
			AND (ISNULL(@ProductDescription,'')='' OR P.ProductDescription LIKE '%'+@ProductDescription+'%')
			AND (ISNULL(@OrderName,'')='' OR MO.SOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')) OR MO.MOName IN(SELECT parameter_Value FROM dbo.ConvertParameterToTable(@OrderName,',')))
			AND (@StartDate IS NULL OR MO.PlannedDateFrom>=@StartDate)
			AND (@EndDate IS NULL OR MO.PlannedDateFrom<=@EndDate)
			AND MO.WorkflowId <>'WKF1000000Z2'--排除其他工作流程
			ORDER BY MO.PlannedDateFrom,MO.MOName DESC
		END
		RETURN 0
	END

	IF @I_Sender='CreateMOAllotDetail'
	BEGIN
		IF ISNULL(@ProductionWhse,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择生产车间!'
			RETURN -1
		END

		IF ISNULL(@MONames,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择需要调拨申请的工单!'
			RETURN -1
		END

		IF EXISTS(SELECT 1 FROM MO WHERE MOName IN(SELECT col FROM DB_Split(@MONames,',')) AND DeleteFlag<>'X' AND MOStates<>'20')
		BEGIN
			SET @I_ReturnMessage='ServerMessage:存在未下达的工单，请重新选择!'
			RETURN -1
		END

		INSERT INTO @MOT(MOId,MOName,MOStates)
		SELECT B.MOId,A.col,B.MOStates FROM DB_Split(@MONames,',') A
		INNER JOIN MO B ON A.col=B.MOName

		INSERT INTO @WW_RMI([WWId],[LotId],[LotSN],[LotStatus],[QCStatus],[IsolateStatus],[Qty],[OrgQty],
		[IsSM],[UOMId],[OrgLotSN],[ProductId],[ProductionLotNO],[EntryDate],[ValidityEndDate],[FactoryId],
		[WorkcenterId],[CellId],[IsStorage])
		SELECT [WWId],[LotId],[LotSN],[LotStatus],[QCStatus],[IsolateStatus],[Qty],[OrgQty],
		[IsSM],[UOMId],[OrgLotSN],[ProductId],[ProductionLotNO],[EntryDate],[ValidityEndDate],[FactoryId],
		[WorkcenterId],[CellId],[IsStorage] FROM WW_RMInventory WHERE ProductId IN(
		SELECT B.ProductId FROM @MOT A
		INNER JOIN MOItem B ON A.MOId=B.MOId
		WHERE B.LineSequence<>'000' AND B.DeleteFlag NOT IN('','1')) AND IsStorage=1

		SELECT @WaterProductId=P.ProductId FROM ProductRoot PR INNER JOIN Product P ON PR.ProductRootId=P.ProductRootId WHERE PR.ProductName='9999999999'
		SELECT TOP 1 @FSWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='FSXB'
		SELECT TOP 1 @UVWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='UVXB'
		SELECT TOP 1 @FSWorkCenterId1=WorkcenterId FROM Workcenter WHERE WorkcenterName='LFS1'
		SELECT TOP 1 @FSWorkCenterId2=WorkcenterId FROM Workcenter WHERE WorkcenterName='LFS2'
		SELECT TOP 1 @FSWorkCenterId3=WorkcenterId FROM Workcenter WHERE WorkcenterName='LYM1'
		SELECT TOP 1 @FSWorkCenterId4=WorkcenterId FROM Workcenter WHERE WorkcenterName='LYM2'
        SELECT TOP 1 @HXWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='HXXB'
        SELECT TOP 1 @SXWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='SXXB'
		SELECT TOP 1 @TZWorkCenterId=WorkcenterId FROM Workcenter WHERE WorkcenterName='TZXB'

		SET @ToFactoryId='FAC1000000SW'

		-- IF @ProductionWhse='研磨'
		-- BEGIN
		-- SET @ToWareHouseId=@FSWorkCenterId4
		-- END
		-- else if @ProductionWhse='分散'
		-- BEGIN
		-- SET @ToWareHouseId=@FSWorkCenterId2
		-- END
		-- ELSE
		-- BEGIN
		-- SET @ToWareHouseId=@UVWorkCenterId  
		-- END
        SET @ToWareHouseId=(CASE
		    WHEN @ProductionWhse IN('研磨','分散') THEN @FSWorkCenterId
		    WHEN @ProductionWhse IN('HX')  THEN @HXWorkCenterId --添加活性的调拨 Irving 2024/11/26
		    WHEN @ProductionWhse IN('SX')  THEN @SXWorkCenterId --添加活性的调拨 Irving 2024/12/03

		    WHEN @ProductionWhse IN('TZ')  THEN @TZWorkCenterId --添加特种的调拨 Irving 2025/04/03
		ELSE @UVWorkCenterId  END);

		SELECT TOP 1 @ToFactoryName=FactoryName+' '+FactoryDescription FROM Factory WHERE FactoryId=@ToFactoryId

		SELECT TOP 1 @ToWareHouseName=WorkcenterName+' '+WorkcenterDescription FROM Workcenter WHERE WorkcenterId=@ToWareHouseId;

		  WITH
		  MP AS(
			  --查询已指定批次的数量
			  --SELECT A.MOId,A.MOItemId,B.FactoryId,B.WorkcenterId,SUM(A.Qty) AS Qty FROM MOProductionLot A
			  --INNER JOIN WW_RMInventory B on A.LotSN=b.LotSN GROUP BY A.MOId,A.MOItemId,B.FactoryId,B.WorkcenterId

			  SELECT A.MOId,A.MOItemId,B.FactoryId,B.WorkcenterId,A.ProductionQty AS Qty FROM MOItem A
			  INNER JOIN (
				  SELECT ROW_NUMBER() OVER(PARTITION BY ProductionLotNO,ProductId ORDER BY IsSM,EntryDate) AS RN,
				  ProductionLotNO,ProductId,FactoryId,WorkcenterId,EntryDate FROM @WW_RMI
				  WHERE LotStatus='1' AND IsStorage=@IsStorage
			  ) B ON B.ProductionLotNO IN(SELECT TOP 1 col FROM DB_Split(A.ProductionLotNO,',')) AND A.ProductId=B.ProductId
			  WHERE ISNULL(A.ProductionLotNO,'')<>'' AND A.DeleteFlag IN (NULL,'','0')	
			  AND ISNULL(B.WorkcenterId,'') NOT IN('',@FSWorkCenterId,@UVWorkCenterId,@FSWorkCenterId1,@FSWorkCenterId2,@FSWorkCenterId3,@FSWorkCenterId4) AND B.RN=1
		  )
		  ,WP AS(
			  --查询物料所在的仓库
			  SELECT * FROM (
			  SELECT ROW_NUMBER() OVER(PARTITION BY A.ProductId ORDER BY A.IsSM,A.EntryDate) AS RN,
			  A.ProductId,A.FactoryId AS FactoryId,A.WorkcenterId AS WorkcenterId FROM @WW_RMI A
			  INNER JOIN Factory B ON A.FactoryId=B.FactoryId
			  INNER JOIN Workcenter C ON A.WorkcenterId=C.WorkcenterId
			  WHERE A.IsStorage=@IsStorage AND A.Qty>@QtyZero AND ISNULL(A.FactoryId,'')<>'' AND A.LotStatus='1' AND ISNULL(A.WorkcenterId,'')<>''
			  AND ISNULL(A.WorkcenterId,'') NOT IN('',@FSWorkCenterId,@UVWorkCenterId,@FSWorkCenterId1,@FSWorkCenterId2,@FSWorkCenterId3,@FSWorkCenterId4) 
			  ) AS WWTABLE WHERE RN=1
		  )
		  , T AS (
			  --获取每个工单物料需要调拨的物料用量
			  SELECT MOI.MOId,M.MOName,M.MOStates,MOI.MOItemId,MOI.ProductId,MOI.ProductionLotNO,
			  (CASE WHEN MP.FactoryId IS NULL THEN WP.FactoryId ELSE MP.FactoryId END) AS FactoryId,
			  (CASE WHEN MP.WorkcenterId IS NULL THEN WP.WorkcenterId ELSE MP.WorkcenterId END) AS WorkcenterId,
			  MOI.ItemQtyRequired,CAST((CASE WHEN MP.MOItemId IS NULL THEN 0 ELSE 1 END) AS BIT) AS IsStorage,
			  (CASE WHEN MOI.ProductionQty IS NULL THEN MOI.ItemQtyRequired ELSE ISNULL(MP.Qty,0) END) AS Qty
			  FROM  @MOT M 
			  INNER JOIN MOItem MOI ON MOI.MOId=M.MOId
			  LEFT JOIN MP ON MOI.MOId=MP.MOId AND MOI.MOItemId=MP.MOItemId
			  LEFT JOIN WP ON MOI.ProductId=WP.ProductId 
			  WHERE ISNULL(MOI.DeleteFlag,'') IN('','0') AND MOI.LineSequence<>'000'
			  AND MOI.ProductId<>@WaterProductId
		  )
		  ,MAMD AS (
			  --查询工单已申请数量和已调拨数量
			  SELECT A.MOId,A.ProductionLotNO,A.ProductId,SUM(AllotQtyCurrent) AS RequestQty,
			  SUM((CASE WHEN B.ProductAllotStates='30' THEN AllotQtyCurrent ELSE 0 END)) AS AllocatedQty FROM MOAllotMODetail A
			  INNER JOIN ProductAllot B ON A.MOAllotRequestId=B.MOAllotRequestId  AND A.TempFactoryId=B.FactoryId AND A.TempWorkcenterId=B.WorkcenterId AND A.ToFactoryId=B.ToFactoryId AND A.ToWareHouseId=B.ToWorkcenterId
			  INNER JOIN ProductAllotItem PA ON B.ProductAllotId=PA.ProductAllotId AND PA.ProductId=A.ProductId
			  --INNER JOIN MOAllotDetail C ON A.MOAllotRequestId=C.MOAllotRequestId AND A.TempFactoryId=C.FromFactoryId AND A.TempWorkcenterId=C.FromWareHouseId AND A.ToFactoryId=C.ToFactoryId AND A.ToWarehouseId=C.ToWareHouseId AND A.ProductId=C.ProductId
			  GROUP BY A.MOId,A.ProductionLotNO,A.ProductId
		  )
		  ,WR AS (
			  --统计每个仓库物料的在库数量
			  SELECT FactoryId,WorkcenterId,ProductId,SUM(Qty) AS Qty FROM @WW_RMI WHERE IsStorage=@IsStorage AND LotStatus='1' GROUP BY FactoryId,WorkcenterId,ProductId
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
			  --INNER JOIN MOAllotDetail C ON A.MOAllotRequestId=C.MOAllotRequestId AND A.TempFactoryId=C.FromFactoryId AND A.TempWorkcenterId=C.FromWareHouseId AND A.ToFactoryId=C.ToFactoryId AND A.ToWarehouseId=C.ToWareHouseId AND A.ProductId=C.ProductId
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
		  --总查询
		 SELECT CAST(0 AS BIT) AS [Check],T.MOId,T.MOItemId,T.MOName,T.ProductId,T.ProductionLotNO,T.IsStorage AS IsProduction,PR.ProductName,P.ProductDescription,
		 T.ItemQtyRequired,(T.Qty-ISNULL(MAMD.RequestQty,0.00000000)) as AllotQty,
		 ISNULL(MAMD.AllocatedQty,0.00000000) AS AllocatedQty,ISNULL(MAMD.RequestQty,0.00000000) AS RequestQty,
		 ISNULL(WR.Qty,0.00000000) AS WarehouseQty,ISNULL(TWWQ.Qty,0.00000000) AS PLWarehouseQty,ISNULL(TW.Qty,0) AS TotalWarehouseQty,
		 T.FactoryId AS TempFactoryId,T.WorkcenterId AS TempWorkcenterId,(F.FactoryName+' '+F.FactoryDescription) AS TempFactoryName,(W.WorkcenterName+' '+W.WorkcenterDescription) AS TempWorkcenterName,
		 @ToFactoryId AS ToFactoryId,@ToWareHouseId AS ToWareHouseId,@ToFactoryName AS ToFactoryName,@ToWareHouseName AS ToWareHouseName
		  FROM T
		 INNER JOIN Product P ON T.ProductId=P.ProductId
		 INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
		 LEFT JOIN Factory F ON T.FactoryId=F.FactoryId
		 LEFT JOIN Workcenter W ON T.WorkcenterId=W.WorkcenterId
		 LEFT JOIN MAMD 
		 ON T.MOId=MAMD.MOId AND T.ProductId=MAMD.ProductId
		 LEFT JOIN  WR ON T.ProductId=WR.ProductId AND WR.FactoryId=T.FactoryId AND WR.WorkcenterId=T.WorkcenterId
		 LEFT JOIN  WR AS TWWQ ON T.ProductId=TWWQ.ProductId AND TWWQ.FactoryId=@ToFactoryId AND TWWQ.WorkcenterId=@ToWareHouseId
		 LEFT JOIN TW ON T.ProductId=TW.ProductId
		 WHERE ISNULL(MAMD.RequestQty,0.00000000)<T.ItemQtyRequired
		 ORDER BY T.MOName

		 RETURN 0
	END
		
	IF @I_Sender='SubmitAllot'
	BEGIN
		--select MOAllotRequestId,FromFactoryId,FromWareHouseId,ToFactoryId,ToWareHouseId,MAD.ProductId,P.ProductClassify,SUM(AllotQty) as AllotQty into #TEMP from MOAllotDetail MAD
		--INNER JOIN Product P ON MAD.ProductId=P.ProductId
		--where MOAllotRequestId=@TransId group by MOAllotRequestId,FromFactoryId,FromWareHouseId,ToFactoryId,ToWareHouseId,MAD.ProductId,ProductClassify

		--获取创建领料单所需数据（从A仓到B仓领料需求数量/可用库存）
		INSERT INTO @Temp_Picking(
			MOAllotRequestId,
			FromFactoryId,
			FromWareHouseId,
			ToFactoryId,
			ToWareHouseId,
			ProductId,
			ProductClassify,
			AllotQty,
			AllotQtyCurrent,
			WQty
		)
		SELECT A.*,ISNULL(W.Qty,0) AS WQty FROM (
			select MOAllotRequestId,TempFactoryId,TempWorkcenterId,ToFactoryId,ToWareHouseId,MAD.ProductId,P.ProductClassify,SUM(AllotQty) as AllotQty,SUM(AllotQty) as AllotQtyCurrent from MOAllotMODetail MAD
			INNER JOIN Product P ON MAD.ProductId=P.ProductId
			where MOAllotRequestId=@TransId
			group by MOAllotRequestId,TempFactoryId,TempWorkcenterId,ToFactoryId,ToWareHouseId,MAD.ProductId,ProductClassify
		) A
		LEFT JOIN (
			SELECT FactoryId,WorkcenterId,ProductId,SUM(Qty) AS Qty FROM WW_RMInventory 
			WHERE IsStorage=@IsStorage AND LotStatus='1' AND Qty>@QtyZero GROUP BY FactoryId,WorkcenterId,ProductId
		) W ON A.TempFactoryId=W.FactoryId AND A.TempWorkcenterId=W.WorkcenterId AND A.ProductId=W.ProductId

		select @RequiredDate=RequiredDate from MOAllotRequest WHERE MOAllotRequestId=@TransId


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

		BEGIN transaction Request
		DECLARE AllotRequest CURSOR  for
		SELECT FromFactoryId,FromWareHouseId,ToFactoryId,ToWareHouseId,ProductClassify FROM @Temp_Picking group by FromFactoryId,FromWareHouseId,ToFactoryId,ToWareHouseId,ProductClassify

		OPEN AllotRequest
		FETCH NEXT FROM AllotRequest INTO @FromFactoryId,@FromWareHouseId,@ToFactoryId,@ToWareHouseId,@ProductClassify
		WHILE @@FETCH_STATUS =0
		BEGIN
			IF EXISTS(SELECT 1 FROM @Temp_Picking WHERE WQty>0 AND AllotQty>0 AND FromFactoryId=@FromFactoryId AND FromWareHouseId=@FromWareHouseId AND ToFactoryId=@ToFactoryId AND ToWareHouseId=@ToWareHouseId AND ProductClassify=@ProductClassify)
			BEGIN
				EXEC SysGetObjectPKId 'SOB1000000XC','ProductAllot',@I_PKId OUTPUT
				set @ProductAllotId+=('['+ISNULL(cast(@I_PKId as nvarchar(12)),'')+']')
				--调用仓库调拨单保存事件
				EXEC @RESULT= ProductAllotSaveData 
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_OrBitUserName=@I_OrBitUserName,
				@I_PKId=@I_PKId,
				@ProductAllotDescription=@ProductAllotDescription,
				@FromWareHouseId=@FromWareHouseId,
				@ToWareHouseId=@ToWareHouseId,
				@ToFactoryId=@ToFactoryId,
				@FromFactoryId=@FromFactoryId,
				@ProductAllotStates=10,
				@CreateUserName=@I_OrBitUserName,
				@CreateDate=@NowDate,
				@RequiredDate=@RequiredDate

				IF ISNULL(@RESULT,0)<>0
				BEGIN 
					ROLLBACK transaction Request
					DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
					DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
					DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
						return -1
				END
				--把申请单号写入调拨单
				IF EXISTS(SELECT top 1 1 from ProductAllot where ProductAllotId=@I_PKId)
				begin
					UPDATE ProductAllot SET MOAllotRequestId=@TransId where ProductAllotId=@I_PKId
				end

				select top 1 @ProductAllotName=ISNULL(ProductAllotName,'') from ProductAllot where ProductAllotId=@I_PKId
				IF ISNULL(@ProductAllotName,'')<>''
				BEGIN
					SET @NewSN+=('['+ISNULL(@ProductAllotName,'')+']')
					DECLARE AllotDetail CURSOR  for
					select allot.LineSequence,allot.ProductId,allot.AllotQty,PR.UsageUOMId from (SELECT ROW_NUMBER() OVER(ORDER BY ProductId) AS LineSequence,ProductId,SUM(AllotQty) AS AllotQty FROM (SELECT ProductId,AllotQty FROM @Temp_Picking 
					where FromFactoryId=@FromFactoryId and FromWareHouseId=@FromWareHouseId and ToFactoryId=@ToFactoryId and ToWareHouseId=@ToWareHouseId AND ProductClassify=@ProductClassify
					AND AllotQty>0 AND WQty>0) AS T
					GROUP BY ProductId) as allot LEFT JOIN Product PR on allot.ProductId=PR.ProductId

					OPEN AllotDetail
					FETCH NEXT FROM AllotDetail INTO @LineSequence,@ProductId,@AllotQty,@UsageUOMId
					WHILE @@FETCH_STATUS =0
					BEGIN
						SELECT @WQty=WQty FROM @Temp_Picking WHERE ToFactoryId=@ToFactoryId AND ToWareHouseId=@ToWareHouseId AND ProductClassify=@ProductClassify
						AND FromFactoryId=@FromFactoryId AND FromWareHouseId=@FromWareHouseId AND ProductId=@ProductId

						IF @AllotQty>@WQty
						BEGIN
							SET @AllotQty=@WQty
						END
						IF @AllotQty>0
						BEGIN
							--生成仓库调拨单明细
							EXEC SysGetObjectPKId 'SOB1000000XD','ProductAllotItem',@ItemPKId OUTPUT
							INSERT INTO ProductAllotItem(
										ProductAllotItemId,
										ProductAllotId,
										ItemSequence,
										ProductId,
										AllotQty,
										ItemUOMId
								)VALUES(
										@ItemPKId,
										@I_PKId,
										RIGHT('000'+CAST(@LineSequence AS VARCHAR),4),
										@ProductId,
										@AllotQty,
										@UsageUOMId)

							UPDATE @Temp_Picking SET WQty-=@AllotQty,AllotQtyCurrent-=@AllotQty
							WHERE ToFactoryId=@ToFactoryId AND ToWareHouseId=@ToWareHouseId AND ProductClassify=@ProductClassify
							AND FromFactoryId=@FromFactoryId AND FromWareHouseId=@FromWareHouseId AND ProductId=@ProductId
						END
						

									--DECLARE AllotDetailLot CURSOR  for

									----只有指定了批次的工单物料才会生成批号明细，没有工单明细的物料按正常逻辑扫描调拨
									--SELECT MPL.LotSN,MPL.BoxSN,MPL.Qty,MPL.CellId,MPL.MOProductionLotId FROM #TEMP MAD 
									--INNER JOIN MOAllotMODetail MAMD ON MAD.MOAllotRequestId=MAMD.MOAllotRequestId 
									--AND MAD.ProductId=MAMD.ProductId AND MAD.FromFactoryId=MAMD.TempFactoryId AND MAD.FromWareHouseId=MAMD.TempWorkcenterId
									--INNER JOIN (SELECT T1.*,T2.BoxSN,T2.ProductId,T2.FactoryId,T2.WorkcenterId,T2.CellId FROM MOProductionLot T1 
									--LEFT JOIN WW_RMInventory T2 ON T1.WWId=T2.WWId WHERE T1.IsActivity=0) MPL 
									--ON MAMD.MOId=MPL.MOId AND MAMD.ProductId=MPL.ProductId
									--AND MAD.FromFactoryId=MPL.FactoryId AND MAD.FromWareHouseId=MPL.WorkcenterId
									--WHERE MAD.ProductId=@ProductId and MAD.FromFactoryId=@FromFactoryId AND MAD.FromWareHouseId=@FromWareHouseId
									--AND MAD.ToFactoryId=@ToFactoryId and MAD.ToWareHouseId=@ToWareHouseId AND ISNULL(MAMD.ProductionLotNO,'')<>''
									--AND MAD.ProductClassify=@ProductClassify

									--OPEN AllotDetailLot
									--FETCH NEXT FROM AllotDetailLot INTO @LotSN,@BoxSN,@LotQty,@CellId,@MOProductionLotId
									--WHILE @@FETCH_STATUS =0
									--BEGIN
									--	--生成调拨明细批次
									--	DECLARE @ItemLotPKId char(12)=''
									--	EXEC SysGetObjectPKId '','ProductAllotItemLot',@ItemLotPKId OUTPUT
									--	INSERT INTO [dbo].[ProductAllotItemLot]
									--					([ProductAllotItemLotId]
									--					,[ProductAllotItemId]
									--					,[LotSN]
									--					,[BoxSN]
									--					,[Qty]
									--					,[CellId]
									--					,[ToCellId]
									--					,[IsAOScan]
									--					,[IsAEScan]
									--					,[AllotType]
									--					,[CreateUserId]
									--					,[MOProductionLotId])
									--				VALUES
									--					(@ItemLotPKId
									--					,@ItemPKId
									--					,@LotSN
									--					,@BoxSN
									--					,@LotQty
									--					,@CellId
									--					,NULL
									--					,0
									--					,0
									--					,'R'
									--					,@I_OrBitUserId
									--					,@MOProductionLotId)
									--FETCH NEXT FROM AllotDetailLot INTO @LotSN,@BoxSN,@LotQty,@CellId,@MOProductionLotId
									--END
									--CLOSE AllotDetailLot --关闭游标
									--DEALLOCATE AllotDetailLot --释放游标
						FETCH NEXT FROM  AllotDetail INTO @LineSequence,@ProductId,@AllotQty,@UsageUOMId
						END
					CLOSE AllotDetail --关闭游标
					DEALLOCATE AllotDetail --释放游标

					UPDATE ProductAllot SET ProductAllotStates='20',ApproveDate=@NowDate,ApproveUserId=@I_OrBitUserId where ProductAllotId=@I_PKId

					--正常调拨自动审核，超领料等待审核
					--IF NOT EXISTS(select MAMD.MOId from #TEMP MAD 
					--INNER JOIN MOAllotMODetail MAMD ON MAD.MOAllotRequestId=MAMD.MOAllotRequestId AND 
					--MAD.FromFactoryId=MAMD.TempFactoryId AND MAD.FromWareHouseId=MAMD.TempWorkcenterId AND MAD.ProductId=MAMD.ProductId
					--AND MAD.ToFactoryId=MAMD.ToFactoryId AND MAD.ToWareHouseId=MAMD.ToWareHouseId
					--INNER JOIN MOItem MOI ON MAMD.MOId=MOI.MOId AND MAMD.ProductId=MOI.ProductId
					--where MAD.ToFactoryId=@ToFactoryId and MAD.ToWareHouseId=@ToWareHouseId AND MAD.ProductClassify=@ProductClassify 
					--AND (ISNULL(MOI.ItemQtyRequired,0)-ISNULL(MOI.ItemQtyIssued,0)-ISNULL(MAMD.AllotQtyCurrent,0))<=0)
					--BEGIN
					--	UPDATE ProductAllot SET ProductAllotStates='20',ApproveDate=@NowDate,ApproveUserId=@I_OrBitUserId where ProductAllotId=@I_PKId
					--END
				END
			END

			IF EXISTS(SELECT 1 FROM @Temp_Picking A WHERE AllotQtyCurrent>0 AND FromFactoryId=@FromFactoryId AND FromWareHouseId=@FromWareHouseId AND ToFactoryId=@ToFactoryId AND ToWareHouseId=@ToWareHouseId AND ProductClassify=@ProductClassify)
			BEGIN
				EXEC SysGetObjectPKId 'SOB1000000XC','ProductAllot',@I_PKId OUTPUT
				set @ProductAllotId+=('['+ISNULL(cast(@I_PKId as nvarchar(12)),'')+']')
				--调用仓库调拨单保存事件
				EXEC @RESULT= ProductAllotSaveData 
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_OrBitUserName=@I_OrBitUserName,
				@I_PKId=@I_PKId,
				@ProductAllotDescription=N'多工单合并发料【缺料物料】',
				@FromWareHouseId=@FromWareHouseId,
				@ToWareHouseId=@ToWareHouseId,
				@ToFactoryId=@ToFactoryId,
				@FromFactoryId=@FromFactoryId,
				@ProductAllotStates='10',
				@CreateUserName=@I_OrBitUserName,
				@CreateDate=@NowDate,
				@RequiredDate=@RequiredDate

				IF ISNULL(@RESULT,0)<>0
				BEGIN 
					ROLLBACK transaction Request
					DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
					DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
					DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
						return -1
				END
				--把申请单号写入调拨单
				IF EXISTS(SELECT top 1 1 from ProductAllot where ProductAllotId=@I_PKId)
				begin
					UPDATE ProductAllot SET MOAllotRequestId=@TransId where ProductAllotId=@I_PKId
				end
				

				select top 1 @ProductAllotName=ISNULL(ProductAllotName,'') from ProductAllot where ProductAllotId=@I_PKId
				IF ISNULL(@ProductAllotName,'')<>''
				BEGIN
					SET @NewSN+=('['+ISNULL(@ProductAllotName,'')+']')
					DECLARE AllotDetail CURSOR  for
					select allot.LineSequence,allot.ProductId,allot.AllotQty,PR.UsageUOMId from (SELECT ROW_NUMBER() OVER(ORDER BY ProductId) AS LineSequence,ProductId,SUM(AllotQtyCurrent) AS AllotQty FROM (SELECT ProductId,AllotQtyCurrent FROM @Temp_Picking 
					where FromFactoryId=@FromFactoryId and FromWareHouseId=@FromWareHouseId and ToFactoryId=@ToFactoryId and ToWareHouseId=@ToWareHouseId AND ProductClassify=@ProductClassify
					AND AllotQtyCurrent>0) AS T
					GROUP BY ProductId) as allot LEFT JOIN Product PR on allot.ProductId=PR.ProductId

					OPEN AllotDetail
					FETCH NEXT FROM AllotDetail INTO @LineSequence,@ProductId,@AllotQty,@UsageUOMId
					WHILE @@FETCH_STATUS =0
					BEGIN
						IF @AllotQty>0
						BEGIN
							--生成仓库调拨单明细
							EXEC SysGetObjectPKId 'SOB1000000XD','ProductAllotItem',@ItemPKId OUTPUT
							INSERT INTO ProductAllotItem(
										ProductAllotItemId,
										ProductAllotId,
										ItemSequence,
										ProductId,
										AllotQty,
										ItemUOMId
								)VALUES(
										@ItemPKId,
										@I_PKId,
										RIGHT('000'+CAST(@LineSequence AS VARCHAR),4),
										@ProductId,
										@AllotQty,
										@UsageUOMId)
						END
						
						FETCH NEXT FROM  AllotDetail INTO @LineSequence,@ProductId,@AllotQty,@UsageUOMId
						END
					CLOSE AllotDetail --关闭游标
					DEALLOCATE AllotDetail --释放游标

					--缺料单不自动审核
					--UPDATE ProductAllot SET ProductAllotStates='20',ApproveDate=@NowDate,ApproveUserId=@I_OrBitUserId where ProductAllotId=@I_PKId
				END
			END
		    
			FETCH NEXT FROM  AllotRequest INTO @FromFactoryId,@FromWareHouseId,@ToFactoryId,@ToWareHouseId,@ProductClassify
		END
		CLOSE AllotRequest --关闭游标
		DEALLOCATE AllotRequest --释放游标
	
		--回写调拨单号
		IF EXISTS(SELECT TOP 1 1 FROM MOAllotRequest WHERE MOAllotRequestId=@TransId)
		BEGIN
			UPDATE MOAllotRequest SET ProductAllotId=@ProductAllotId,MOAllotRequestStates=20 WHERE MOAllotRequestId=@TransId
		END

		UPDATE MO SET IsPlanned=1 WHERE MOId IN (SELECT DISTINCT MOId FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId)
		
		--计算工单本次调拨数量/只有勾选的工单物料才会计算
		UPDATE MOAllotMODetail SET AllotQtyCurrent=AllotQty FROM MOAllotMODetail 
		WHERE MOAllotRequestId=@TransId
		IF @@ERROR<>0
		BEGIN
			ROLLBACK transaction Request

			DELETE FROM MOAllotDetail WHERE MOAllotRequestId=@TransId
			DELETE FROM MOAllotMODetail WHERE MOAllotRequestId=@TransId
			DELETE FROM MOAllotRequest WHERE MOAllotRequestId=@TransId
			set @I_ReturnMessage='ServerMessage:工单调拨申请失败!'
			return -1
		END
		ELSE
		BEGIN
			COMMIT transaction Request

			--TRUNCATE TABLE #TEMP
			--DROP TABLE #TEMP
			set @I_ReturnMessage='ServerMessage:工单调拨申请成功，调拨单号'+@NewSN+'!'
		END
	END
	
	return 0
END
GO
