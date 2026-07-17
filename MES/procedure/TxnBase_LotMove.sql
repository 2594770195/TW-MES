SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		<OBit Team Henry>
-- Create date: <2009.8.13>
-- Description:	<MES标准传送事务>
-- Rev: 10.01  开始支持MoveIn
-- =============================================
CREATE PROCEDURE [dbo].[TxnBase_LotMove]
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)

--以下为客户化参数
@LotSN varchar(40)='',
@LotInDate Datetime=null,
@ShiftId char(12)='',
@UserComment nvarchar(1000)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	
	--变量申明
	declare @LotId char(12)
	declare @MOId char(12)
	declare @MOItemId char(12)
	declare @TxnCode varchar(10)
	declare @NextWorkFlowStepId char(12)
	declare @Stack nvarchar(1000)
	declare @WorkflowId char(12)

	declare @PreviousWorkflowStepId char(12)
	declare @CurrentWorkFlowStepId char(12)
	declare @OldCurrentStepId char(12)
	declare @OldNextStepId char(12)
	declare @OldSpecificationId char(12)
	declare @LastResourceId char(12)
	declare @LastShiftId char(12)

	declare @RealWorkflowStepId  char(12)
	declare @RealNextWorkflowStepId  char(12)
	declare @RealSpecificationId  char(12)
	declare @WorkcenterId char(12)

	declare @ToWorkflowStepId char(12)
	declare @ProductId char(12)
	declare @LatestMoveDate datetime
	declare @Qty float
	
	declare @MoveInUserId char(12)
	declare @OldIsMoveIn bit
	declare @IsDoMoveIn bit=0 --是否应该执行MoveIn.

	--变量赋值
	set @TxnCode='MOVE'

	select 
		@LotId=LotID,
		@MOId =MOId,
		@MOItemId=MOItemId,
		@ProductId=ProductId,
		@OldCurrentStepId=WorkFlowStepId,
		@OldNextStepId= NextWorkFlowStepId, 
		@OldSpecificationId=SpecificationId,
		@LastResourceId=ResourceId, 
		@LatestMoveDate=LatestMoveDate,
		@Qty=Qty,
		@LastShiftId=ShiftId,
		@WorkflowId=WorkflowId,
		@PreviousWorkflowStepId=WorkflowStepId,
		@MoveInUserId =LatestUserId,
		@OldIsMoveIn=IsMoveIn
	from Lot 
	where LotSN=@LotSN

	--检查是否有这个Lot
	if ltrim(isnull(@LotID,''))=''
	begin
		set @I_ReturnMessage='Lot is not existed'
		return -1
	end
	
	if @ShiftId=''
		set @ShiftId=@LastShiftId
		
    if @OldIsMoveIn=1 
    begin
		set @MoveInUserId=@MoveInUserId
	end

	--检查该规程是否有MoveIn事件的定义。
	if @OldIsMoveIn=0
	begin
		if exists(	SELECT top 1  Specification_MESTxnObjectId 
                            FROM         dbo.Specification_MESTxnObject  
                            WHERE     (SpecificationId =@OldSpecificationId ) AND (IsMoveInTxn = 1))
		begin
			set @IsDoMoveIn=1;
			set @TxnCode='MOVE IN'
		end
	end

	--根据数据采集的结果重新调整下一步节点
	Exec TxnBase_WkfPathSelect @LotId, @LotSN, @OldCurrentStepId,@I_OrBitUserId,@I_ResourceId,@ShiftId

	select  
		@NextWorkFlowStepId=NextWorkFlowStepID ,
		@CurrentWorkFlowStepID=NextWorkFlowStepId
	from Lot 
	where LotId=@LotId

	
	if ltrim(@NextWorkFlowStepId)='[N]'
	begin
		set @I_ReturnMessage='Can not move to next step'
		return -1
	end

	select @Stack=Stack from  WorkflowStack where LotId=@LotId

	IF EXISTS(SELECT 1 FROM dbo.SysUser WHERE UserId=@I_OrBitUserId AND ISNULL(WorkcenterId,'')<>'')
		SELECT @WorkcenterId=WorkcenterId from dbo.SysUser where UserId=@I_OrBitUserId
	ELSE
		SELECT @WorkcenterId=WorkcenterId from Resource where ResourceId=@I_ResourceId

	if @LotInDate is null
		set @LotInDate=getdate()

	--如果批号的工序已经结束，则不再传送-最后一个节点不支持MoveIn
	if (@NextWorkFlowStepId is null or ltrim(@NextWorkFlowStepId)='') AND (ltrim(rtrim(@Stack)) =''  or @Stack is null) 
	begin
		set @I_ReturnMessage='Lot no next step'
		return -1
	end
	
	--处理DoMoveIn的条件，如果数据采集已经改变了既定流程，则执行跳转。
	if @IsDoMoveIn = 0 or ( @IsDoMoveIn = 1 and @OldNextStepId <> @NextWorkFlowStepId)
	begin
		set @TxnCode='MOVE'
		set @IsDoMoveIn = 0
		--展开马上要执行的工序
		Exec TxnBase_WkfExpandWorkflowStep @LotId, @CurrentWorkFlowStepID,@RealWorkflowStepId output ,@RealSpecificationId output 
	
		--将当前STACK放到OLDSTACK中
	
		if ltrim(isnull(@Stack,''))<>''
			Update WorkflowStack set OldStack=Stack Where LotId=@LotId
	

		/*取得当前工序的下一个工序*/
		select @ToWorkflowStepId=ToWorkflowStepId from WorkflowPath 
			where WorkflowStepId=@RealWorkflowStepId and IsDefaultWorkflowPath=1

		if  @ToWorkflowStepId is null or ltrim(@ToWorkflowStepId)=''
		begin
			if ltrim(isnull(@Stack,''))<>''
			begin
			   /*如果下一个工序已经结束，则返回它的父工序的下一个工序*/ 
				Declare @StackStepID char(12)
				Declare @StackNextStepID char(12)
				Declare @StackDefaultPathId char(12)
				Declare @StackToStepID char(12)

				While Len(@Stack)>0
				begin
					/*  从堆栈中取出当前工序的父工序 */
					select @StackStepID=right(@Stack,12 )
					--Begin Tran    
						Update WorkflowStack set Stack=left(@Stack,len(@Stack)-12)
							where LotId=@LotId
					--Commit Tran
				
					select @StackToStepID=ToWorkflowStepId from WorkflowPath 
						where WorkflowStepId=@StackStepID and IsDefaultWorkflowPath=1
				
					select @Stack=Stack from WorkflowStack where LotId=@LotId

					if Len(@StackToStepID)>0
						 Break
					else
						Continue
					end
	
					--Begin Tran  
						Update Lot set 
							WorkFlowStepID=@RealWorkflowStepId,
							SpecificationId=@RealSpecificationId,
							WorkCenterId=@WorkCenterId,						
							LatestTxnCode=@TxnCode,
							ResourceID=@I_ResourceId,
							ShiftID=@ShiftID,
							NextWorkFlowStepID=@StackToStepID,
							PreviousWorkflowStepId=@PreviousWorkflowStepId,
							--TxnRecord='',
							LatestMoveDate=getdate(),
							IsMoveIn =0,
							LatestActivityDate=getdate()
           					where LotId=@LotId
					-- Commit Tran
				end	   
			else   
				begin
					/*如果没有父工序的下一个工序，则结束*/
					--Begin Tran  
					Update Lot set 
							WorkFlowStepID=@RealWorkflowStepId,
							SpecificationId=@RealSpecificationId,
							WorkCenterId=@WorkCenterId,
							LatestTxnCode=@TxnCode,
							--TxnRecord='',
							ResourceID=@I_ResourceId,
							ShiftID=@ShiftID,
							NextWorkFlowStepID='',
							PreviousWorkflowStepId=@PreviousWorkflowStepId,
							LatestMoveDate=getdate(),
							IsMoveIn =0,
							LatestActivityDate=getdate()
							where LotID=@LotID
					--Commit Tran   
				end	
			end
		else
		begin    
			/*正常情况下，将下一个工序移到当前工序*/
			select @RealNextWorkflowStepId=ToWorkflowStepId from WorkflowPath 
			where WorkflowStepId=@RealWorkflowStepId and IsDefaultWorkflowPath=1		   		  
			--Begin Tran 
				Update Lot set 	
						WorkFlowStepID=@RealWorkflowStepId,
						SpecificationId=@RealSpecificationId,
						WorkCenterId=@WorkCenterId,
						NextWorkFlowStepID=@RealNextWorkflowStepId,
						PreviousWorkflowStepId=@PreviousWorkflowStepId,
						LatestTxnCode=@TxnCode,
						--TxnRecord='',
						ResourceID=@I_ResourceId,
						ShiftID=@ShiftID,
						IsMoveIn =0,
						LatestMoveDate=getdate(),
						LatestActivityDate=getdate()
						where LotId=@LotId
			--Commit Tran 
		end

		declare @fSpecID char(12)
		declare @fWorkFlowStepID char(12)
		declare @fNextWorkFlowStepID char(12)
		declare @fStack varchar(1000)

		select @fStack=Stack from WorkflowStack where LotId=@LotId
		select 
			@fSpecID=SpecificationId,
			@fWorkFlowStepID=WorkFlowStepID,
			@fNextWorkFlowStepID=NextWorkFlowStepID 
		from Lot 
		where LotId=@LotId

		if @fWorkFlowStepId is Null
			Update Lot set WorkFlowStepId='',SpecificationId='' where  LotId=@LotId

		if @fNextWorkFlowStepId is Null
			Update Lot set NextWorkFlowStepId='' where  LotId=@LotId

		if @fStack is Null
			DELETE WorkflowStack WHERE LotId=@LotId

		--申请主PKID	
		declare @DataChainId char(12)
		declare @DataChainMoveId char(12)

		exec SysGetObjectPKid '','DataChainMove',@DataChainMoveId  output

		--产生DataChain返回数据链Id
		EXEC	[dbo].[TxnBase_DataChainMainLine]
			@DataChainId = @DataChainId OUTPUT,
			@TxnCode =@TxnCode,
			@I_PlugInCommand = @I_PlugInCommand,
			@I_OrBitUserId = @I_OrBitUserId,
			@I_ResourceId = @I_ResourceId,
			@LotId = @LotId,
			@MOId=@MOId,
			@MOItemId=@MOItemId,
			@ProductId = @ProductId,
			@Qty = @Qty,
			@ShiftId = @ShiftId,
			@WorkcenterId = @WorkcenterId,
			@SpecificationId = @RealSpecificationId,
			@WorkflowStepId = @RealWorkflowStepId,
			@UserComment = @UserComment

		/*将LOT的状态记录在MoveHistory中*/
		declare @CycleTime1 float
		declare @CycleTime2 float
	

		select @CycleTime2=datediff(ss,@LotInDate,getdate())
  
		if @OldIsMoveIn =1
		   select @CycleTime1=datediff(ss,@LatestMoveDate,getdate())
  
		insert into DataChainMove  (
				DataChainMoveId,
				DataChainId,
				LotId,
				MOId,
				MOItemId,
				Qty,
				NonStdMoveReasonId,
				IsNonStdMove,
				WorkflowStepId,
				ToWorkflowStepId,
				ResourceId,
				ToResourceId,
				WorkflowId,
				ToWorkflowId,
				ShiftId,
				ToShiftId,
				LotInDate,
				LotOutDate,
				CycleTime1,
				CycleTime2,
				UserId,
				MoveInDate,
				MoveInUserId,
				MoveInResourceId
				)
			Values  (
				@DataChainMoveId,
				@DataChainId,
				@LotId,
				@MOId,
				@MOItemId,
				@Qty,
				'',
				0,
				@OldCurrentStepId,
				@fWorkFlowStepID,
				@LastResourceId,
				@I_ResourceId,
				@WorkflowId,
				@WorkflowId,
				@LastShiftId,				
				@ShiftId,
				@LotInDate,
				getdate(),
				@CycleTime1,
				@CycleTime2,
				@I_OrBitUserId,
				@LatestMoveDate,
				@MoveInUserId,
				@LastResourceId
				)
		 

		--清理堆栈中的已失效批号数据
		if  exists(select 1  from WorkflowStack where LotId=@LotId)
		begin
			declare  @ST nvarchar(1000)
			declare  @OST nvarchar(1000)
			select   @ST=Stack,@OST=OldStack from  WorkflowStack  where LotId=@LotId
			if ltrim(rtrim(ltrim(@ST)+ltrim(@OST)))=''
				DELETE WorkflowStack WHERE LotId=@LotId

		end

		--检查并执行WW事件
		exec TxnBase_WkfWWEvent @LotID,@OldCurrentStepId,0  --从老节点离开
		exec TxnBase_WkfWWEvent @LotID,@CurrentWorkFlowStepID,1 --再进入新节点

		declare @OldWorkflowStepName nvarchar(100)
		declare @OldWorkflowStepEvent nvarchar(100)
		declare @OldWorkflowStepParameter nvarchar(200)
		declare @I_ReturnMsg nvarchar(max)
		declare @CurrentWorkflowStepEntryEvent nvarchar(100)
		declare @CurrentWorkflowStepParameter nvarchar(200)

		declare @WorkflowStepName nvarchar(100)
		select @OldWorkflowStepName=WorkflowStepName,
				@OldWorkflowStepEvent=WorkflowStepEvent,
				@OldWorkflowStepParameter=WorkflowStepParameter
				from WorkflowStep
				where WorkflowStepId=@OldCurrentStepId
				
		select @CurrentWorkflowStepEntryEvent=WorkflowStepEntryEvent,
				@WorkflowStepName=WorkflowStepName,
				@CurrentWorkflowStepParameter= WorkflowStepParameter 
				from WorkflowStep
				where WorkflowStepId=@fWorkFlowStepID

		set @I_ReturnMessage='ServerMessage:批号 [' + @LotSN + '] 传送成功,从 [' + 
				isnull(@OldWorkflowStepName,'') + '] 传送到 [' + 
				isnull(@WorkflowStepName,'') + '].'
		
		declare @sql nvarchar(max)

		--动态执行工作流节点上的自定义事件过程（节点离开事件）
		if @OldWorkflowStepEvent is not null and ltrim(@OldWorkflowStepEvent)<>''
		begin
			

			if @I_ResourceId is null set @I_ResourceId=''
			if @I_OrBitUserId is null set @I_OrBitUserId=''
			if @OldWorkflowStepParameter is null set @OldWorkflowStepParameter=''
			if @fWorkFlowStepID is null set @fWorkFlowStepID=''
			if @OldCurrentStepId is null set @OldCurrentStepId=''

			set @sql='EXEC	[dbo].[' + ltrim(@OldWorkflowStepEvent) +']
					@I_ReturnMessage = @I_ReturnMessage OUTPUT,
					@TxnCode = N''' + @TxnCode + ''',
					@LotId = N''' + @LotId + ''',
					@LotSN = N''' + @LotSN + ''',
					@FromWorkflowStepId = N''' + @OldCurrentStepId + ''',
					@ToWorkflowStepId = N''' + @fWorkFlowStepID + ''',
					@WorkflowStepParameter = N''' + @OldWorkflowStepParameter + ''',
					@I_OrBitUserId =''' + @I_OrBitUserId + ''',
					@I_ResourceId =''' + @I_ResourceId + ''''
			
			EXEC sp_executesql @sql,N'@I_ReturnMessage nvarchar(max) OUTPUT', @I_ReturnMsg OUTPUT
			
			if ltrim(@I_ReturnMsg)<>''
				set @I_ReturnMessage=@I_ReturnMessage+ ' ' + ltrim(@I_ReturnMsg)

		end

		--动态执行工作流节点上的自定义事件过程（下一个节点的进入事件）
		if @CurrentWorkflowStepEntryEvent is not null and ltrim(@CurrentWorkflowStepEntryEvent)<>''
		begin

			if @I_ResourceId is null set @I_ResourceId=''
			if @I_OrBitUserId is null set @I_OrBitUserId=''
			if @OldWorkflowStepParameter is null set @OldWorkflowStepParameter=''
			if @fWorkFlowStepID is null set @fWorkFlowStepID=''
			if @OldCurrentStepId is null set @OldCurrentStepId=''

			set @sql='EXEC	[dbo].[' + ltrim(@CurrentWorkflowStepEntryEvent) +']
					@I_ReturnMessage = @I_ReturnMessage OUTPUT,
					@TxnCode = N''' + @TxnCode + ''',
					@LotId = N''' + @LotId + ''',
					@LotSN = N''' + @LotSN + ''',
					@FromWorkflowStepId = N''' + @OldCurrentStepId + ''',
					@ToWorkflowStepId = N''' + @fWorkFlowStepID + ''',
					@WorkflowStepParameter = N''' + @CurrentWorkflowStepParameter + ''',
					@I_OrBitUserId =''' + @I_OrBitUserId + ''',
					@I_ResourceId =''' + @I_ResourceId + ''''
			
			EXEC sp_executesql @sql,N'@I_ReturnMessage nvarchar(max) OUTPUT', @I_ReturnMsg OUTPUT
			
			if ltrim(@I_ReturnMsg)<>''
				set @I_ReturnMessage=@I_ReturnMessage+ ' ' + ltrim(@I_ReturnMsg)

		end
	end
	else
	begin --执行MOVE IN					
		update Lot set 
			IsMoveIn=1,
			LatestUserId=@I_OrBitUserId,
			LatestTxnCode='MOVE IN',
			LatestMoveDate=GETDATE(),
			LatestActivityDate=GETDATE()
		where LotId=@LotId 	
		  
		Declare @MovInWorkflowStepName nvarchar(100)
		select @MovInWorkflowStepName=WorkflowStepName from WorkflowStep where WorkflowStepId=@OldCurrentStepId	
		set @I_ReturnMessage='ServerMessage:批号 [' + @LotSN + '] 于 ['+ @MovInWorkflowStepName +']成功入站.' 
	end		
	
	--写入初次传送表,用于记录线体投入数量 benson 2016-11-01
	if ISNULL(@WorkcenterId,'')<>''
	begin
		if not exists(select 1 from LotFirstMove where LotId=@LotId)
		begin
			declare @LotFirstMoveId char(12)

			exec SysGetObjectPKId '','LotFirstMove',@LotFirstMoveId output

			insert into LotFirstMove(
					LotFirstMoveId,
					LotId,
					WorkflowStepId,
					MOId,
					ProductId,
					WorkcenterId,
					ModifyDate
					)
				values(
					@LotFirstMoveId,
					@LotId,
					@OldCurrentStepId,
					@MOId,
					@ProductId,
					@WorkcenterId ,
					GETDATE()
					)
		END
        ELSE
        BEGIN
			UPDATE LotFirstMove
			SET ModifyDate = GETDATE()
			WHERE LotId=@LotId
		END
	end		
				
	return 0
	
END 


 
GO
