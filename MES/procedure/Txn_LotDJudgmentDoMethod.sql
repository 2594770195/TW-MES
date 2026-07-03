SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OrBit Team Merefield>
-- Create date: <2021.07.29>
-- Description:	<批号核验>
-- Rev: 12.00
--=============================================
CREATE  PROCEDURE  [dbo].[Txn_LotDJudgmentDoMethod]
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
@LotJudgmentId IDType='',         --批次待检判定
@SpecificationCode VARCHAR(16)='',
@LotSN VARCHAR(100)='',
@FtpFileId IDType='',             --附件
@QualityMark VARCHAR(16)='',        --质量标准
@ReasonMsg NVARCHAR(256)=''         --原因说明

AS
BEGIN
	-- set NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @return_value INT =-1
	DECLARE @DataChainId IDType
	DECLARE @TxnCode VARCHAR(10)='MOVE'
	DECLARE @Productname VARCHAR(50)=''
	DECLARE @WorkcenterName VARCHAR(50)=''
	DECLARE @ProductionLotNO VARCHAR(50)=''
	DECLARE @Qty VARCHAR(50)=''
	DECLARE @LotId IDType
	DECLARE @MOId IDType
	DECLARE @ProductId IDType
	DECLARE @WorkcenterId IDType
	DECLARE @SpecificationId IDType
	DECLARE @LotSpecificationId IDType
	DECLARE @WorkflowStepId IDType
	DECLARE @WorkflowStepName NVARCHAR(64)
	DECLARE @CurDate DATETIME=GETDATE()
	DECLARE @RESULT INT =0
	DECLARE @IsJudgment BIT=0
	DECLARE @CurrentCount INT
	DECLARE @AlarmContent NVARCHAR(256)=''
	DECLARE @DJudgmentInfoId IDType
	DECLARE @InterfaceItemId CHAR(12)=''

		--发送邮件参数
	DECLARE @CheckName NVARCHAR(200)=''
	DECLARE @MailId CHAR(12)=''
	DECLARE @MailAdd VARCHAR(256)=''
	DECLARE @Copy_recipients VARCHAR(512)=''
	DECLARE @SubjectStr NVARCHAR(MAX)=''
	DECLARE @MailAddress NVARCHAR(MAX)=''
	DECLARE @AttributeValue NVARCHAR(16)=''
	DECLARE @RowId INT =1
	DECLARE @RowCount INT =0
	
	DECLARE @OrgQualityMark VARCHAR(16)='' --Irving 2024.01.07 添加变化记录 

		IF @I_Sender='QueryList'
		BEGIN
		SELECT ROW_NUMBER() OVER(ORDER BY W.CreateDate) AS RN,W.LotSN,C.TProductName AS ProductName,C.ProductDescription,B.Qty,
		dbo.FormatQualityMark(B.QualityMark) AS QualityMark  FROM WW_RMInventory W
		INNER JOIN Lot B ON W.LotSN=B.LotSN
		INNER JOIN Product C ON B.ProductId=C.ProductId
		LEFT JOIN LotJudgment A ON W.LOTSN=A.LotSN
		WHERE (B.QualityMark='Y' OR B.QualityMark='R' )AND IsStorage=1 AND (W.LotSN=@LotSN OR ISNULL(@LotSN,'')='')
		END
	IF @I_Sender='JudgmentSubmit'
	BEGIN
		--获取资源对应的工作中心
		--select
		--	@WorkcenterId=WorkcenterId
		--from dbo.Resource
		--where Resource.ResourceId=@I_ResourceId

		--if isnull(@WorkcenterId,'')=''
		--BEGIN
		--	set @I_ReturnMessage='ServerMessage:资源['+@I_ResourceName+']未维护工作中心，请检查!'
		--	return -1
		--end

		IF ISNULL(@QualityMark,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择质量标准'
			RETURN -1
		END


		SELECT @LotId=Lot.LotId,@MOId=Lot.MOId,@ProductId=Lot.ProductId
		FROM WW_RMInventory W INNER JOIN Lot ON W.LotSN=Lot.LotSN WHERE W.LotSN=@LotSN

		IF ISNULL(@LotId,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:批次错误，请重新选择'
			RETURN -1
		END


		IF  @QualityMark  IN ('YG','RG','G')
		BEGIN
			UPDATE dbo.WW_RMInventory SET
				   LotStatus='1' --只要单据没有确认就是9，单据确认后才变为1
			WHERE LotSN=@LotSN

				select @WorkcenterName=WorkcenterName,@Productname=TProductName,@Qty=Qty,@ProductionLotNO=ProductionLotNO
			from WW_RMInventory
			inner join Workcenter on Workcenter.WorkcenterId=WW_RMInventory.WorkcenterId
			inner join product on Product.ProductId=WW_RMInventory.ProductId
			where LotSN=@LotSN
	 DECLARE  @ItemName NVARCHAR(MAX)='U_ProductAllot'
  DECLARE @outXmlStr NVARCHAR(MAX);
    DECLARE @SAPSyncMessage NVARCHAR(MAX);
    DECLARE @rMsg NVARCHAR(MAX);
    EXEC dbo.ClrLoadRfcEdi @ip = '192.73.80.142',
                           @dbName = 'OrBitMOM',
                           @userID = 'sa',
                           @pwd = 'prt#$159S',
                           @TIMEOUT = '30000',
                           @itemName = @ItemName, -- nvarchar(50)
                           @outXmlStr = @outXmlStr OUTPUT; -- nvarchar(max)

SELECT @outXmlStr


SET @outXmlStr='
<SAPDB>
 <IV_ID />
 <POSTDAT>'+(Select CONVERT(varchar(100), GETDATE(), 112))+'</POSTDAT>
  <ITEM_MOVE>
    <MATERIAL>'+@Productname+'</MATERIAL>
    <STGE_LOC>'+@WorkcenterName+'</STGE_LOC>
	<BATCH>'+@ProductionLotNO+'</BATCH>
    <ENTRY_QNT>'+@Qty+'</ENTRY_QNT>
    <ENTRY_UOM>KG</ENTRY_UOM>
	<PLANT>9502</PLANT>
	<MOVE_TYPE>311</MOVE_TYPE>
	<MOVE_PLANT>9502</MOVE_PLANT>
	<MOVE_STLOC>LFS1</MOVE_STLOC>
	<MOVE_BATCH>'+@ProductionLotNO+'</MOVE_BATCH>
    <MOVE_MAT>'+@Productname+'</MOVE_MAT>
    <SPEC_STOCK />
    <SALES_ORD />
    <S_ORD_ITEM />
    <VAL_SALES_ORD />
    <VAL_S_ORD_ITEM />
  </ITEM_MOVE>
</SAPDB>
'
    EXEC dbo.CLR_SAPSync @I_ReturnMessage = @SAPSyncMessage OUTPUT,                 -- nvarchar(max)
                         @LocalWCFUrl = N'http://192.73.80.141/OrBitWCFServiceR15/', -- nvarchar(4000)
                         @IsEventLog = 1,                                            -- bit
                         @SapName = N'PD8',                                          -- nvarchar(100)
                         @SapServer = N'192.73.80.138',                                -- nvarchar(100)
                         @SapClient = N'890',                                        -- nvarchar(100)
                         @SapUser = N'hualei',                                       -- nvarchar(100)
                         @SapPassword = N'hualei',                                -- nvarchar(100)
                         @SapSystem = N'00',                                         -- nvarchar(100)
                         @SapLanguage = N'ZH',                                       -- nvarchar(100)
                         @ItemName = @ItemName,                             -- nvarchar(100)
                         @InputXml = @outXmlStr;

SELECT @SAPSyncMessage

--SET @SAPSyncMessage = REPLACE(@SAPSyncMessage,'<(>','')
--SET @SAPSyncMessage = REPLACE(@SAPSyncMessage,'<)>','')
--SET @SAPSyncMessage = REPLACE(@SAPSyncMessage,'&','')
--SET @SAPSyncMessage = REPLACE(@SAPSyncMessage,'<(>&<)>','')




    EXEC dbo.ClrDownRfcEdi @ip = '192.73.80.142',
                           @dbName = 'OrBitMOM',
                           @userID = 'sa',
                           @pwd = 'prt#$159S',
                           @TIMEOUT = '30000',
                           @itemName = @ItemName,
                           @inXmlStr = @SAPSyncMessage, -- nvarchar(max)
                           @rMsg = @rMsg OUTPUT;         -- nvarchar(max)
    SELECT @rMsg
			--=================================Irving 2024.01.07 添加变化记录 begin=====================================================================================
			--todo 添加修改记录表
            select @OrgQualityMark = QualityMark from lot where LOTSN=@LotSN
			--=================================Irving 2024.01.07 添加变化记录 end=====================================================================================

			UPDATE LOT SET QualityMark=@QualityMark WHERE LOTSN=@LotSN
			--=================================Irving 2025.01.13 添加变化记录 begin=====================================================================================
            DECLARE @zr_TProductName varchar(255)
            DECLARE @zr_ProductDescription varchar(255)
            DECLARE @zr_QualityMark varchar(255)
            DECLARE @zr_workflowId varchar(12)
            DECLARE @zr_WorkflowStepId varchar(12)

            select @zr_TProductName = TProductName,
                   @zr_ProductDescription = ProductDescription,
                   @zr_QualityMark = QualityMark,
                   @zr_workflowId = lot.workflowId,
                   @zr_WorkflowStepId = lot.WorkflowStepId
            from lot join product on product.productId = lot.ProductId
            where lotsn = @Lotsn
            DECLARE @ZR_LotSNJMQualityMarkId char(12) = ''
                    EXEC SysGetObjectPKId '', 'ZR_LotSNJMQualityMark', @ZR_LotSNJMQualityMarkId OUTPUT
                    INSERT INTO [dbo].[ZR_LotSNJMQualityMark] (ZR_LotSNJMQualityMarkId, Lotsn,JudgmentDep,I_OrBitUserId,
                                                   TProductName, ProductDescription, QualityMark,DelFalg,EmployeeNo,workflowId,WorkflowStepId
                                                               )
                                    VALUES
                                    (@ZR_LotSNJMQualityMarkId, @Lotsn,'品保',@I_OrBitUserId,
                                                   @zr_TProductName, @zr_ProductDescription, @zr_QualityMark,0,'1',@zr_workflowId,@zr_WorkflowStepId
                                     )
			--=================================Irving 2025.01.13 添加变化记录 end=====================================================================================

			update WW_RMInventory set WorkcenterId='WKC1000009QI',CellId='CELL00000FM8' where LotSN=@LotSN


                     -- nvarchar(100)



		EXEC SysGetObjectPKId '','DJudgmentInfo',@DJudgmentInfoId OUTPUT
		INSERT INTO dbo.DJudgmentInfo
		(
		    DJudgmentInfoId,
		    ProductId,
			LotSN,
		    Remark,
		    FileId
		)
        SELECT
		@DJudgmentInfoId,
		wri.ProductId,
		wri.LotSN,
		@ReasonMsg,
		@FtpFileId
		FROM dbo.WW_RMInventory AS wri
		WHERE wri.LotSN=@LotSN
		END

		SELECT ROW_NUMBER() OVER(ORDER BY W.CreateDate) AS RN,W.LotSN,C.TProductName AS ProductName,C.ProductDescription,B.Qty,
		dbo.FormatQualityMark(B.QualityMark) AS QualityMark  FROM WW_RMInventory W
		INNER JOIN Lot B ON W.LotSN=B.LotSN
		INNER JOIN Product C ON B.ProductId=C.ProductId
		WHERE (W.LotSN=@LotSN OR ISNULL(@LotSN,'')='') AND ISNULL(W.LotSN,'')<>''
	--发送邮件
	BEGIN
		--查找收件人
		SELECT @MailId=MailId FROM Mail WHERE MailName='D浆待处理判定结果' AND IsActivity=1

		IF ISNULL(@MailId,'')<>''
		BEGIN
			SELECT ROW_NUMBER() OVER(ORDER BY CreateDate) AS RowId,MailAddress,AttributeValue INTO #MAI FROM MailItem WHERE MailId=@MailId

			SELECT @RowCount=COUNT(1) FROM #MAI
			SET @RowId=1;

			WHILE @RowId<=@RowCount
			BEGIN
				--
				SELECT @MailAddress=MailAddress,@AttributeValue=AttributeValue FROM #MAI WHERE RowId=@RowId
				IF ISNULL(@AttributeValue,'') ='主送'
				BEGIN
					SET @MailAdd = @MailAdd + @MailAddress+';'
				END
				ELSE
				BEGIN
					SET @Copy_recipients = @Copy_recipients + @MailAddress+';'
				END
				SET @RowId+=1;
			END
			--发送邮件
			IF ISNULL(@MailAdd,'')<>''
			BEGIN
				SET @SubjectStr=
				'半成品名称：'+(select ProductDescription from Product inner join lot on lot.productid=product.productid where LotId=@LotId)
-- 				+'，批号：'+@LotSN+'品保已判断，判定结果为'
				+'，批号：'+@LotSN+'品保已判断，由原来的 '
                --=================================Irving 2024.01.07 添加变化记录 begin=====================================================================================
                    +CASE
                        WHEN @OrgQualityMark ='YG'THEN '黄绿标'
                        WHEN @OrgQualityMark ='G'THEN '绿标'
                        WHEN @OrgQualityMark ='R'THEN '红标'
                        ELSE ''
                    END
				    +' ，现判定为 '
				--=================================Irving 2024.01.07 添加变化记录 end=====================================================================================
				+CASE WHEN @QualityMark ='YG'THEN '黄绿标'
				WHEN @QualityMark ='G'THEN '绿标'
				WHEN @QualityMark ='R'THEN '红标' end +'，原因说明为'+@ReasonMsg+'请及时跟进处理。'

				EXEC msdb.dbo.sp_send_dbmail--执行发送邮件
				@profile_name='pmzmes@printrite-nm.com',--配置文件名
				@recipients=@MailAdd,--接收邮件名
				@copy_recipients = @Copy_recipients, --抄送email地址
				@subject='浆待处理判定结果',--邮件主题
				@body=@SubjectStr,--邮件内容
				@importance ='HIGH',   --邮件 级别  HIGH Low Normal
				@body_format='HTML';--邮件格式'
			END

			TRUNCATE TABLE #MAI
			DROP TABLE #MAI
		END

	END
	RETURN 0

	END

	IF @I_Sender='QueryParams'
	BEGIN
		DECLARE @ProductionGrindId CHAR(12)=''


		SELECT @SpecificationId=SpecificationId FROM Specification A
		INNER JOIN SpecificationRoot B ON A.SpecificationRootId=B.SpecificationRootId
		WHERE B.SpecificationCode='Grind-JM'

		SELECT TOP 1 @ProductionGrindId=ProductionGrindId FROM ProductionGrind WHERE LotSN=@LotSN AND SpecificationId=@SpecificationId
		ORDER BY EndTime DESC

		SELECT CurrentCount AS PGrindStage,
			SUM (CASE ParamsType WHEN 'CMDTEMPER' THEN ParamsValue ELSE 0 END) AS TEMPER,
			SUM (CASE ParamsType WHEN 'CMDPRESSE' THEN ParamsValue ELSE 0 END) AS PRESSE,
			SUM (CASE ParamsType WHEN 'CMDPSPEED' THEN ParamsValue ELSE 0 END) AS PSPEED,
			SUM (CASE ParamsType WHEN 'CMDSPEED' THEN ParamsValue ELSE 0 END) AS SPEED,
			SUM (CASE ParamsType WHEN 'CMDSSCALE' THEN ParamsValue ELSE 0 END) AS SSCALE,
			SUM (CASE ParamsType WHEN 'CMDCURREN' THEN ParamsValue ELSE 0 END) AS CURREN,
			SUM (CASE ParamsType WHEN 'CMDMWATER' THEN ParamsValue ELSE 0 END) AS MWATER,
			SUM (CASE ParamsType WHEN 'CMDSIZED50' THEN ParamsValue ELSE 0 END) AS SIZED50,
			SUM (CASE ParamsType WHEN 'CMDSIZED99' THEN ParamsValue ELSE 0 END) AS SIZED99
		INTO #TEMP
		FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId GROUP BY CurrentCount

		IF NOT EXISTS(SELECT 1 FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId AND ParamsType='CMDTEMPER')
		BEGIN
			ALTER TABLE #TEMP DROP COLUMN TEMPER
		END
		IF NOT EXISTS(SELECT 1 FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId AND ParamsType='CMDPRESSE')
		BEGIN
			ALTER TABLE #TEMP DROP COLUMN PRESSE
		END
		IF NOT EXISTS(SELECT 1 FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId AND ParamsType='CMDPSPEED')
		BEGIN
			ALTER TABLE #TEMP DROP COLUMN PSPEED
		END
		IF NOT EXISTS(SELECT 1 FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId AND ParamsType='CMDSPEED')
		BEGIN
			ALTER TABLE #TEMP DROP COLUMN SPEED
		END
		IF NOT EXISTS(SELECT 1 FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId AND ParamsType='CMDSSCALE')
		BEGIN
			ALTER TABLE #TEMP DROP COLUMN SSCALE
		END
		IF NOT EXISTS(SELECT 1 FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId AND ParamsType='CMDCURREN')
		BEGIN
			ALTER TABLE #TEMP DROP COLUMN CURREN
		END
		--IF NOT EXISTS(SELECT 1 FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId AND ParamsType='CMDPERSON')
		--BEGIN
		--	ALTER TABLE #TEMP DROP COLUMN PERSON
		--END
		IF NOT EXISTS(SELECT 1 FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId AND ParamsType='CMDMWATER')
		BEGIN
			ALTER TABLE #TEMP DROP COLUMN MWATER
		END

		IF NOT EXISTS(SELECT 1 FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId AND ParamsType='CMDSIZED50')
		BEGIN
			ALTER TABLE #TEMP DROP COLUMN SIZED50
		END

		IF NOT EXISTS(SELECT 1 FROM PGrindParams WHERE ProductionGrindId=@ProductionGrindId AND ParamsType='CMDSIZED99')
		BEGIN
			ALTER TABLE #TEMP DROP COLUMN SIZED99
		END

		SELECT * FROM #TEMP

		TRUNCATE TABLE #TEMP
		DROP TABLE #TEMP
	END

END
GO
