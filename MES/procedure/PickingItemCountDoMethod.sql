
-- ==============================================
-- Author:		<Jack>
-- Create date: <2017-02-21>
-- Revision: 1.00
-- Comment:按展开工单BOM、领料单进行物料统计
-- ==============================================
CREATE PROCEDURE  [dbo].[PickingItemCountDoMethod]
@I_Sender nvarchar(200)='', --客户端执行按钮
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_ExceptionFieldName nvarchar(100)='' output, --向客户端报告引起冲突的字段
@I_LanguageId char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKid char(12) ='',				--主键
@I_ParentPKId char(12)='',			--父级主键
@I_Parameter nvarchar(100)=''		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.

AS
BEGIN

	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	
	if exists(select * from PickingList where PickingListId=@I_ParentPKId and isnull(PickingListStates,'')!='10')
	begin
		set @I_ReturnMessage ='ServerMessage:审批之后的备料单不可修改！'
		return -1
	end
	if not exists(select * from PickingListMR where PickingListId=@I_ParentPKId)
	begin
		set @I_ReturnMessage ='ServerMessage:工单/领料单为空，请检查！'
		return -1
	end
	if exists(select * from PickingListItem where PickingListId=@I_ParentPKId )
	begin
		update PickingList set pickStatus='' where PickingListId=@I_ParentPKId
		delete PickingListItem where PickingListId=@I_ParentPKId
	end

	declare @MOId char(12)
	declare @RequisitionId char(12)
	declare @productId char(12)
	declare @MOQtyRequired int
	declare @PKCount int

	declare @Picklisttmp table(ProductId char(12), QtyRequired int)
	declare @Picklist table(id int identity primary key, ProductId char(12), QtyRequired int)
	declare @PKtmp table(id int, PKid char(12))

	--展开工单或领料单
	DECLARE acur cursor for
	select MOId,RequisitionId from PickingListMR where PickingListMR.PickingListId=@I_ParentPKId
	open acur
	fetch next from acur into @MOId,@RequisitionId
	while (@@fetch_status=0)
	begin
		if isnull(@MOId,'')!=''
		begin
			select @productId=productId,@MOQtyRequired=MOQtyRequired from MO where MOId=@MOId
			insert into @Picklisttmp
			select productId,QtyRequired*@MOQtyRequired from dbo.ExpandBOM(@productId,1) abom where abom.Levelint>0
		end

		if isnull(@RequisitionId,'')!=''
		begin		
			insert into @Picklisttmp
			select productId,QtyRequired from RequisitionItem where RequisitionId=@RequisitionId
		end

		fetch next from acur into @MOId,@RequisitionId
	end
	close acur
	deallocate acur

	insert into @Picklist
	select ProductId,sum(QtyRequired) from @Picklisttmp group by ProductId

	--插入Picklistitem
	--申请主键
	select @PKCount=count(ProductId) from @Picklist
	
	if @PKCount=0
	begin
		set @I_ReturnMessage ='ServerMessage:展开无明细！'
		return -1
	end
	
	insert into @PKtmp
	Exec SysGetObjectPKIdBatch '','PickingListItem',@PKCount

	insert into PickingListItem(PickingListItemId, PickingListId, ProductId, QtyRequired,CreateDate)
	select pktm.PKid,@I_ParentPKId,ProductId,QtyRequired,GETDATE() from @Picklist pist inner join @PKtmp pktm on pist.id=pktm.id

	set @I_ReturnMessage ='ServerMessage:操作完成！'
	return 0

END
go

