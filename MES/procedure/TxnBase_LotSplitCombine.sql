SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO








-- =============================================
-- Author:		<OBit Team Henry>
-- Create date: <2009.8.13>
-- Description:	<MES批号合并及拆分>
-- Rev: 10.00  
-- =============================================
CREATE PROCEDURE [dbo].[TxnBase_LotSplitCombine]
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)

--以下为客户化参数
@ShiftId char(12)='',
@SplitCombineReasonId char(12)='',
@SplitCombineType char(1)='',
@SplitLotSN nvarchar(40)='',
@SplitLotQty float=0,
@CombineLotSN nvarchar(40)='',
@UserComment nvarchar(1000)='',
@EmployeeId char(12)='',
@EquipmentId char(12)

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	if @SplitLotQty<=0
	begin
		set @I_ReturnMessage='Split Lot Qty must more than 0'
		return -1
	end

	--检查是否有这个Lot
	if not exists(select LotID from Lot where LotSN=@SplitLotSN)
	begin
		set @I_ReturnMessage='Split LotSN is not existed'
		return -1
	end

	--检查是否有这个Lot
	if not exists(select LotID from Lot where LotSN=@CombineLotSN)
	begin
		set @I_ReturnMessage='Combine LotSN is not existed'
		return -1
	end

	--变量申明
	declare @SplitLotId char(12)
	declare @CombineLotId char(12)
	declare @SplitTxnCode varchar(10)
	declare @CombineTxnCode varchar(10)
	declare @SplitOriginalLotQty float
	declare @CombineQty float

	declare @SplitLotSpecificationId char(12)
	declare @SplitLotWorkflowStepId char(12)
	declare @CombineLotSpecificationId char(12)
	declare @CombineLotWorkflowStepId char(12)
	declare @CombineOriginalLotQty float

	declare @WorkcenterId char(12)
	declare @OldShiftId char(12)
	declare @SplitProductId char(12)
	declare @CombineProductId char(12)
	
	declare @SplitMOId char(12)
	declare @SplitMOItemId char(12)
	
	declare @CombineMOId char(12)
	declare @CombineMOItemId char(12)

	--WMS同步相关变量
	declare @I_WMSReturnMessage nvarchar(max)=''
	declare @return_value_WMS1 int
	declare @return_value_WMS2 int
	declare @WMSAdjustQty float=0 --WMS调整数量（负数表示减少）

	--变量赋值
	set @SplitTxnCode='SPLIT'
	set @CombineTxnCode='COMBINE'	

	select  @SplitLotId=LotID,
			@SplitOriginalLotQty=Qty,
			@OldShiftId=ShiftId,
			@SplitProductId=ProductId,
			@SplitLotSpecificationId=SpecificationId,
			@SplitLotWorkflowStepId=WorkflowStepId ,
			@SplitMOId=MOId ,
			@SplitMOItemId=MOItemId
	from Lot where LotSN=@SplitLotSN
	
	if @ShiftId=''
		set @ShiftId=@OldShiftId

	--原批号数量不够
	if (@SplitOriginalLotQty<=0 or @SplitOriginalLotQty-@SplitLotQty<0)
	begin
		set @I_ReturnMessage='Split LotSN qty is not enough'
		return -1
	end


	select  @CombineLotId=LotID,
			@CombineOriginalLotQty=Qty,
			@CombineProductId=ProductId,
			@CombineLotSpecificationId=SpecificationId,
			@CombineLotWorkflowStepId=WorkflowStepId ,
			@CombineMOId=MOId,
			@CombineMOItemId=MOItemId
	from Lot where LotSN=@CombineLotSN

	--不是相同产品不允许合并
	if (@CombineProductId<>@SplitProductId)
	begin
		set @I_ReturnMessage='Product is not match'
		return -1
	end

	select @WorkcenterId=WorkcenterId from Resource where ResourceId=@I_ResourceId

	--申请主PKID	
	declare @DataChainId char(12)
	declare @DataChainSplitCombineId char(12)
	declare @SplitDataChainId char(12)
	declare @CombineDataChainId char(12)

	exec SysGetObjectPKid '','DataChainSplitCombine',@DataChainSplitCombineId  output

	--产生SplitDataChain返回数据链Id
	EXEC	[dbo].[TxnBase_DataChainMainLine]
		@DataChainId = @SplitDataChainId OUTPUT,
		@TxnCode =@SplitTxnCode,
		@I_PlugInCommand = @I_PlugInCommand,
		@I_OrBitUserId = @I_OrBitUserId,
		@I_ResourceId = @I_ResourceId,
		@LotId = @SplitLotId,
		@ProductId = @SplitProductId,
		@Qty = @SplitOriginalLotQty,
		@ShiftId = @ShiftId,
		@WorkcenterId = @WorkcenterId,
		@SpecificationId = @SplitLotSpecificationId,
		@WorkflowStepId = @SplitLotWorkflowStepId,
		@UserComment = @UserComment

	--产生CombineDataChain返回数据链Id
	EXEC	[dbo].[TxnBase_DataChainMainLine]
		@DataChainId = @CombineDataChainId OUTPUT,
		@TxnCode =@CombineTxnCode,
		@I_PlugInCommand = @I_PlugInCommand,
		@I_OrBitUserId = @I_OrBitUserId,
		@I_ResourceId = @I_ResourceId,
		@LotId = @CombineLotId,
		@MOId=@CombineMOId,
		@MOItemId=@CombineMOItemId,
		@ProductId = @CombineProductId,
		@Qty = @CombineOriginalLotQty,
		@ShiftId = @ShiftId,
		@WorkcenterId = @WorkcenterId,
		@SpecificationId = @CombineLotSpecificationId,
		@WorkflowStepId = @CombineLotWorkflowStepId,
		@UserComment = @UserComment

	insert into DataChainSplitCombine  (
			DataChainSplitCombineId,
			SplitDataChainId,
			CombineDataChainId,
			SplitCombineReasonId,
			SplitCombineType,
			SplitLotId,
			SplitOriginalLotQty,
			SplitLotQty,
			SplitMOId,
			SplitMOItemId,
			CombineLotId,
			CombineOriginalLotQty,
			CombineLotQty,
			CombineMOId,
			CombineMOItemId,
			ResourceId,
			ShiftId,
			UserId,
			SplitLotSpecificationId,
			SplitLotWorkflowStepId,
			CombineLotSpecificationId,
			CombineLotWorkflowStepId,
			EmployeeId,
			EquipmentId
			)
		Values  (
			@DataChainSplitCombineId,
			@SplitDataChainId,
			@CombineDataChainId,
			@SplitCombineReasonId,
			@SplitCombineType,
			@SplitLotId,
			@SplitOriginalLotQty,
			@SplitOriginalLotQty-@SplitLotQty,
			@SplitMOId,
			@SplitMOItemId,
			@CombineLotId,
			@CombineOriginalLotQty,
			@CombineOriginalLotQty+@SplitLotQty,
			@CombineMOId,
			@CombineMOItemId,
			@I_ResourceId,
			@ShiftId,
			@I_OrBitUserId,
			@SplitLotSpecificationId,
			@SplitLotWorkflowStepId,
			@CombineLotSpecificationId,
			@CombineLotWorkflowStepId,
			@EmployeeId,
			@EquipmentId
			)

	--更新批号
	--Begin tran
		Update Lot set qty=qty-@SplitLotQty,LatestActivityDate=getdate() where LotId=@SplitLotId
	--Commit Tran

	--Begin tran
		Update Lot set qty=qty+@SplitLotQty,LatestActivityDate=getdate() where LotId=@CombineLotId
	--Commit Tran

	----------------------------------------------------同步WMS START--------------------------------------------------------------------------------
	--提前计算WMS调整数量（拆分批号减少为负数）
	SET @WMSAdjustQty=-1*@SplitLotQty

	--调用WMS调整单：拆分批号减少库存
	EXEC @return_value_WMS1 = dbo.APISyncU_AdujstmentToWMS @I_ReturnMessage = @I_WMSReturnMessage OUTPUT,
													@lotsn = @SplitLotSN,
													@adjustQuantity = @WMSAdjustQty,
													@adjustReason = '批次拆分合并-减少',
													@Remark = ''

	--调用WMS调整单：合并批号增加库存
	EXEC @return_value_WMS2 = dbo.APISyncU_AdujstmentToWMS @I_ReturnMessage = @I_WMSReturnMessage OUTPUT,
													@lotsn = @CombineLotSN,
													@adjustQuantity = @SplitLotQty,
													@adjustReason = '批次拆分合并-增加',
													@Remark = ''

	--判断WMS同步结果
	IF @return_value_WMS1<>0 AND @return_value_WMS2<>0
	BEGIN
		SET @I_ReturnMessage='ServerMessage:批号【'+@SplitLotSN+'】WMS调整单(减少)失败! 批号【'+@CombineLotSN+'】WMS调整单(增加)失败！'
		RETURN -1
	END
	ELSE IF @return_value_WMS1<>0
	BEGIN
		SET @I_ReturnMessage='ServerMessage:批号【'+@SplitLotSN+'】WMS调整单(减少)失败!'
		RETURN -1
	END
	ELSE IF @return_value_WMS2<>0
	BEGIN
		SET @I_ReturnMessage='ServerMessage:批号【'+@CombineLotSN+'】WMS调整单(增加)失败！'
		RETURN -1
	END
	----------------------------------------------------同步WMS END--------------------------------------------------------------------------------

    set @I_ReturnMessage ='Lot has been split and combine'

	return 0

End






















GO
