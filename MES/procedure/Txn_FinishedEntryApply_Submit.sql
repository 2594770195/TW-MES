SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2020/08/22 13:38:10:5298>
-- Description:   <入库申请：提交>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[Txn_FinishedEntryApply_Submit]
@I_Sender NVARCHAR(200)='',						--	客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,		--	返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT,	--	向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',						--	客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',					--	插件命令
@I_OrBitUserId CHAR(12)='',						--	用户ID
@I_OrBitUserName NVARCHAR(100)='',				--	用户名
@I_ResourceId CHAR(12)='',						--	资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',				--	资源名
@I_PKid CHAR(12) ='',							--	主键
@I_ParentPKId CHAR(12)='',						--	父级主键
@I_Parameter NVARCHAR(MAX)='',  				--	插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@FinishingEntryName NVARCHAR(50) = '',			-- 入库单
@NoteMessage NVARCHAR(200)='',
@NoteInfor NVARCHAR(200)='',
@Barrelage NVARCHAR(200)=''

AS

BEGIN
	-- set NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	/*
		Content1:方案说明：
		1.本方案由产线先“入库申请”扫描，入库申请时，生成单据的状态是10（待审核），扫描完之后点击“提交”，状态更新为20（已审核）
		2.仓库有对应的功能“入库接收”
	*/

	--TY
	DECLARE @Enter VARCHAR(2) = CHAR(13)+CHAR(10)
	DECLARE @return_value INT=-1

	--bill
	DECLARE @FinishingEntryId CHAR(12)=''
	DECLARE @FinishingEntryStates NVARCHAR(50)=''
	DECLARE @FinishingEntryStatesDesc NVARCHAR(100)=''
	DECLARE @WorkflowId CHAR(12)=''
	DECLARE @AlarmTitle NVARCHAR(64)
	DECLARE @AlarmContent NVARCHAR(128)
	DECLARE @LotQty DECIMAL(18,3)
	DECLARE @SpecificationId CHAR(12)
	DECLARE @ProductDescription NVARCHAR(50)

	DECLARE @CurDate DATETIME=GETDATE()


	IF ISNULL(@FinishingEntryName,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:入库单不能为空！'
		RETURN -1
	END

	-- 获取入库单信息
	SELECT 
		@FinishingEntryId = FinishingEntryId,
		@FinishingEntryStates=FinishingEntryStates
	FROM dbo.FinishingEntry 
	WHERE FinishingEntryName = @FinishingEntryName

	SELECT 
		@FinishingEntryStatesDesc=BillStatesDescription
	FROM dbo.Bill
	INNER JOIN dbo.BillStates ON BillStates.BillId=Bill.BillId
	WHERE BillName='FinishingEntry' AND BillStatesName=@FinishingEntryStates
	AND IsERP=0

	IF @FinishingEntryStates NOT IN ('10','21')
	BEGIN
		SET @I_ReturnMessage='ServerMessage:入库单【'+@FinishingEntryName+'】当前状态 【'+@FinishingEntryStatesDesc+'】不允许提交操作！'
		RETURN -1
	END

	-- 检查入库单明细行是否存在
	IF NOT EXISTS(SELECT 1 FROM dbo.FinishingEntryItem
	INNER JOIN dbo.FinishingEntryItemLot ON FinishingEntryItemLot.FinishingEntryItemId = FinishingEntryItem.FinishingEntryItemId
	WHERE FinishingEntryId =  @FinishingEntryId)
	BEGIN
		SELECT @I_ReturnMessage= 'ServerMessage:此入库单下没有任何产品明细,无法操作此功能!' 
		RETURN -1
	END

	-- 更新入库单状态
	--本方案 是先产线入库申请，然后仓库再“接收扫描”，所以产线提交时，单据更新为已审核状态

	--墨水、返工工作流无需更改状态
	IF NOT EXISTS(SELECT 1 FROM FinishingEntryItem A
	INNER JOIN FinishingEntryItemLot B ON A.FinishingEntryItemId=B.FinishingEntryItemId
	INNER JOIN Lot C ON B.LotSN=C.LotSN
	WHERE A.FinishingEntryId=@FinishingEntryId 
    --20260202 新增UV半成品墨水离心生产线、UV半成品墨水不离心生产线、SX-水性半成品：水性半成品生产流程、HX活性：活性半成品生产线，试制半成品
    AND C.WorkflowId IN('WKF1000000Z3','WKF1000000YT','WKF1000000YV',
                        'WKF1000000ZL','WKF1000000ZK','WKF1000000ZE','WKF1000000ZB','WKF1000000ZY'))
	BEGIN
		UPDATE dbo.FinishingEntry SET 
			FinishingEntryStates = '20', 
			ApproveUserId = @I_OrBitUserId, 
			ApproveDate = GETDATE() 
		WHERE FinishingEntryId = @FinishingEntryId
	END
	
	IF EXISTS(SELECT 1 FROM FinishingEntryItem A
	INNER JOIN FinishingEntryItemLot B ON A.FinishingEntryItemId=B.FinishingEntryItemId
	INNER JOIN Lot C ON B.LotSN=C.LotSN
	WHERE A.FinishingEntryId=@FinishingEntryId 
    --20260202 新增UV半成品墨水离心生产线、UV半成品墨水不离心生产线、SX-水性半成品：水性半成品生产流程、HX活性：活性半成品生产线，试制半成品
    AND C.WorkflowId IN('WKF1000000YT','WKF1000000YV',
                        'WKF1000000ZL','WKF1000000ZK','WKF1000000ZE','WKF1000000ZB','WKF1000000ZY'))
	BEGIN
		UPDATE dbo.FinishingEntry SET 
			FinishingEntryStates = '50', 
			ApproveUserId = @I_OrBitUserId, 
			ApproveDate = GETDATE() 
		WHERE FinishingEntryId = @FinishingEntryId
	END

	IF ISNULL(@NoteMessage,'')<>'' OR ISNULL(@NoteInfor,'')<>''
	BEGIN
		UPDATE MO SET NoteMessage=isnull(NoteMessage,'')+ ';' +ISNULL(@NoteMessage,'')+ISNULL(@NoteInfor,'') WHERE MOId IN(SELECT DISTINCT MOId FROM FinishingEntryItem WHERE FinishingEntryId=@FinishingEntryId)
	END

	--过站处理
	SELECT ROW_NUMBER() OVER(ORDER BY A.LotSN) AS RowId,A.LotSN,C.WorkflowId,C.SpecificationId,A.Qty INTO #TEMP FROM FinishingEntryItemLot A
	INNER JOIN FinishingEntryItem B ON A.FinishingEntryItemId=B.FinishingEntryItemId
	INNER JOIN Lot C ON A.LotSN=C.LotSN
	WHERE B.FinishingEntryId = @FinishingEntryId

	DECLARE @RowId INT=1
	DECLARE @RowCount INT=0
	DECLARE @LotSN VARCHAR(100)

	SELECT @RowCount=COUNT(1) FROM #TEMP

	WHILE @RowId<=@RowCount
	BEGIN
		SELECT @LotSN=LotSN,@WorkflowId=WorkflowId,@SpecificationId=SpecificationId,@LotQty=Qty FROM #TEMP WHERE RowId=@RowId

		IF EXISTS(SELECT 1 FROM Specification A INNER JOIN SpecificationRoot B ON A.SpecificationRootId=B.SpecificationRootId WHERE A.SpecificationId=@SpecificationId 
        AND B.SpecificationCode IN('FBXR','FCXR','UBXR','UCXR','OTXR','HXXR','SXXR'))--20260202新增活性水性申请节点
		BEGIN
            --20260202 新增UV半成品墨水离心生产线、UV半成品墨水不离心生产线、SX-水性半成品：水性半成品生产流程、HX活性：活性半成品生产线
			IF @WorkflowId IN('WKF1000000YT','WKF1000000YV','WKF1000000ZL','WKF1000000ZK','WKF1000000ZE','WKF1000000ZB') AND 
			(EXISTS(SELECT 1 FROM QC_ProcessIns_SubLot A INNER JOIN QC_ProcessIns B ON A.QC_ProcessInsId=B.QC_ProcessInsId WHERE A.LotSN=@LotSN AND InsStates='10')
			OR NOT EXISTS(SELECT 1 FROM QC_ProcessIns_SubLot A INNER JOIN QC_ProcessIns B ON A.QC_ProcessInsId=B.QC_ProcessInsId WHERE A.LotSN=@LotSN))
			BEGIN
				--发送邮件提醒
				SELECT @ProductDescription=B.ProductDescription FROM Lot A
				INNER JOIN Product B ON A.ProductId=B.ProductId
				WHERE A.LotSN=@LotSN

				SET @AlarmTitle=N'墨水['+@ProductDescription+']批号['+@LotSN+']入待处理仓提醒'
				SET @AlarmContent=N'批号['+@LotSN+']数量['+CAST(@LotQty AS NVARCHAR(19))+']已申请入待处理仓，请及时处理'
				EXEC [dbo].[AlarmSendMessage]
					@I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@AlarmCode='[In Processed]',
					@AlarmType='1',
					@AlarmSource='入待处理仓',
					@AlarmTitle=@AlarmTitle,
					@AlarmContent=@AlarmContent,
					@PluginCommand='',
					@PluginParameter='',
					@SourcePKID='',
					@Creator='SUR1000004CG',
					@WorkflowStepId='',
					@SPCTaskId='',
					@AlarmAttachFile1='',
					@SPCAlarmType='',
					@UserIdList='',
					@AlarmTypeList=''
			END

			--执行批次过站操作
			EXEC [dbo].[TxnBase_LotMove] 
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@LotSN=@LotSN,
			@LotInDate=@CurDate	
		END

		SET @RowId+=1;
	END


	SET @I_ReturnMessage= 'ServerMessage:入库单 ['+@FinishingEntryName+']提交完成！'

	IF @Barrelage!= NULL AND  @Barrelage!= 0
	BEGIN
	update tofac set Barrelage=@Barrelage where  ProudctionLotSN=LEFT(@LotSN, 10)
	END
	
	select '' AS NoteMessage,'' AS NoteInfor
	RETURN 0

END
GO
