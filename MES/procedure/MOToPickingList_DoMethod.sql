
-- =============================================
-- Author:		<OrBit Team benson>
-- Create date: <2018.03.06>
-- Description:	工单生成领料单
-- =============================================
CREATE  PROCEDURE  [dbo].[MOToPickingList_DoMethod]
@I_Sender NVARCHAR(200)='',							--客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,			--返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT,		--向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',							--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',						--插件命令
@I_OrBitUserId CHAR(12)='',							--用户ID
@I_OrBitUserName NVARCHAR(100)='',					--用户名
@I_ResourceId	CHAR(12)='',						--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',					--资源名
@I_PKid CHAR(12) ='',								--主键
@I_ParentPKId CHAR(12)='',							--父级主键
@I_Parameter NVARCHAR(MAX)='', 						--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现. 
@DateRequired DATETIME=NULL,                         --计划领料日期
@SetsQty FLOAT=0, --套数
@WarehouseName NVARCHAR(50)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--TT
	DECLARE @return_value INT=-1
	DECLARE @MOTyesOM NVARCHAR(50)='' --MO委外工单

	--工单信息
	--bill
	DECLARE @MOType VARCHAR(20)=''
	DECLARE @MOStates NVARCHAR(10)=''
	DECLARE @MOName NVARCHAR(50)=''
	DECLARE @MOQtyRequired FLOAT=0
	DECLARE @FactoryId CHAR(12)=''
	DECLARE @DivisionId CHAR(12)=''
	DECLARE @MOProductId CHAR(12)=''
	DECLARE @MOId CHAR(12)=''
	DECLARE @IsOM BIT=0 --是否不是委外单
	--billItem
	DECLARE @MOItemId CHAR(12)=''
	DECLARE @ProductId CHAR(12)=''
	DECLARE @ProductName NVARCHAR(50)=''
	DECLARE @ItemQtyIssued FLOAT=0  --行已发数量
	DECLARE @ItemQtyOwe FLOAT=0--行欠料数
	DECLARE @CurQtyRequired FLOAT=0 --本次需求数
	DECLARE @UOMId CHAR(12)=''
	--领料工单
	DECLARE @PickingList_MOId CHAR(12)=''


	--领料单
	--bill
	DECLARE @PickingListId CHAR(12)=''
	DECLARE @PickingListName NVARCHAR(50)=''
	
	DECLARE @PickingListClass VARCHAR(20)=''
	--billItem
	DECLARE @PickingListItemId CHAR(12)=''
	DECLARE @ItemSequence VARCHAR(6)=''
	DECLARE @WarehouseId CHAR(12)=''

	DECLARE @MOItemTemp TABLE(
		MOItemId CHAR(12),
		ProductId CHAR(12),
		CurQtyRequired FLOAT,--当前需求
		ItemQtyIssued FLOAT, --行已发数
		ItemQtyOwe FLOAT,--行已欠料数
		UOMId CHAR(12)
	)


	--检查元对象方法用户是否有权限
	EXEC @return_value=[dbo].[MetadataPermissionCheckDoMethod]
		@I_ReturnMessage=@I_ReturnMessage OUTPUT,
		@I_OrBitUserId=@I_OrBitUserId,
		@I_OrBitUserName=@I_OrBitUserName,
		@I_Sender=@I_Sender

	IF @return_value=-1
	BEGIN
		SET @I_ReturnMessage=@I_ReturnMessage
		RETURN -1
	END

	--获取系统参数
	--获取委外单据
	SELECT @MOTyesOM=ParameterValueEx 
	FROM dbo.SysParameter WHERE ParameterName='[WES SysControl]' AND ParameterValue='Bill_MO_Type_OM'


	IF ISNULL(@I_PKid,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请选择有效行项.'
		RETURN -1
	END

	--如果领料日期为空，则默认为当天
	IF @DateRequired=NULL
		SET @DateRequired=GETDATE()
	
	-- 获取工单信息
	SELECT 
		@MOStates = MOStates ,
		@MOType=MOType,
		@MOId=MOId,
		@MOName = MOName,
		@MOProductId = ProductId,
		@MOQtyRequired = MOQtyRequired ,
		@FactoryId=FactoryId,
		@DivisionId=DivisionId
	FROM dbo.MO
	WHERE MOId = @I_PKid

	SELECT @IsOM=CASE ISNULL(OMType.parameter_Value,'') WHEN '' THEN 0 ELSE 1 END
	FROM dbo.Bill
	INNER JOIN dbo.BillType ON BillType.BillId = Bill.BillId
	LEFT JOIN (SELECT parameter_Value FROM dbo.ConvertParameterToTable(@MOTyesOM,';')) OMType ON BillTypeName=OMType.parameter_Value
	WHERE BillName='MO' AND BillTypeName=@MOType

	IF ISNULL(@FactoryId,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:此工单没有维护工厂，请检查！'
		RETURN -1
	END

	-- 检查领料部门是否选择
	IF ISNULL(@DivisionId,'') =''
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:此工单没有维护部门，请检查！！'
		RETURN -1
	END


	--领料套数
	IF ISNULL(@SetsQty,0)<=0
	BEGIN
		SET @I_ReturnMessage='ServerMessage:领料套数必须大于等于0！'
		RETURN -1
	END 

	IF  @SetsQty>@MOQtyRequired
	BEGIN
		SET @I_ReturnMessage='ServerMessage:领料套数不能大于工单计划数量！'
		RETURN -1
	END

	IF ISNULL(@WarehouseName,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:领料仓库不能为空！'
		RETURN -1
	END

	SELECT @WarehouseId=WorkcenterId
	FROM dbo.Workcenter WHERE WorkcenterName=@WarehouseName
	
	IF ISNULL(@WarehouseId,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:领料仓库【'+@WarehouseName+'】不存在！'
		RETURN -1
	END


	-- 工单明细中是否有物料数据
	IF NOT EXISTS(SELECT 1 FROM dbo.MOItem 
	WHERE MOId = @I_PKid AND LineSequence NOT IN('000','0000','00000'))
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:此工单没有行明细物料数据，不允许生成生产领料单！'
		RETURN -1
	END

	
	-- 获取工单BOM所有物料信息
	INSERT INTO @MOItemTemp
		 (
			 MOItemId,
			 ProductId,
			 CurQtyRequired,
			 ItemQtyIssued,
			 ItemQtyOwe,
			 UOMId
		 )
	SELECT   MOItemId,
			 ProductId,
			 BOMQtyRequired*@SetsQty,
			 ISNULL(ItemQtyIssued,0)-ISNULL(ItemQtyBack,0),
			 ISNULL(ItemQtyRequired,0)-(ISNULL(ItemQtyIssued,0)-ISNULL(ItemQtyBack,0)),
			 UOMId
	FROM dbo.MOItem
	WHERE MOId = @MOId 
	AND LineSequence NOT IN('000','0000','00000') 
	AND DeleteFlag IN('','0',NULL)


	--删除已创建领料单明细，但是还没有领料的物料
	DELETE @MOItemTemp
	WHERE MOItemId 
	IN(SELECT DISTINCT MOItemId
	   FROM dbo.PickingList
	   INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListId = PickingList.PickingListId
	   WHERE PickingListStates IN('10','20','21'))


	--是否有可领料数据
	IF NOT EXISTS(SELECT 1 FROM @MOItemTemp
	WHERE ItemQtyOwe>0)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:没有可领料数据 或 已创建领料单但还没有使用，请检查！'
		RETURN -1
	END

	--生成领料单主表
	IF ISNULL(@IsOM,1)=1 --是否是委外
	BEGIN 
		SET @PickingListClass='03' --委外领料单

		EXEC	[dbo].[Txn_BillNewSN]
				@BillName = N'PickingListOM',
				@NewSN = @PickingListName OUTPUT
	END
	ELSE
	BEGIN 
		SET @PickingListClass='01' --生产领料单

		EXEC	[dbo].[Txn_BillNewSN]
				@BillName = N'PickingListPR',
				@NewSN = @PickingListName OUTPUT
	END

	IF ISNULL(@PickingListName,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:领料单生成失败，请重新操作！'
		RETURN -1
	END

	IF EXISTS(SELECT  1 FROM dbo.PickingList WHERE PickingListName=@PickingListName)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:生成的领料单【'+@PickingListName+'】重复，请检查！'
		RETURN -1
	END
	
	EXEC	[dbo].[SysGetObjectPKId] '','PickingList',@PickingListId OUTPUT 
	INSERT INTO dbo.PickingList( 
			PickingListId ,
			PickingListName ,
			PickingListClass,
			PickingListStates,
			DivisionId,
			FactoryId,
			DateRequired,
			CreateUserId
			)
		VALUES ( 
			@PickingListId ,
			@PickingListName ,
			@PickingListClass,
			'10',
			@DivisionId,
			@FactoryId,
			GETDATE(),
			@I_OrBitUserId
			)

	--申请主键
	EXEC dbo.SysGetObjectPKId '','PickingList_MO',@PickingList_MOId OUTPUT
	INSERT INTO dbo.PickingList_MO
	     (
	         PickingList_MOId,
	         PickingListId,
	         MOId,
	         CreateDate,
	         ModifyDate
	     )
	VALUES
	     (
	         @PickingList_MOId,
	         @PickingListId, -- PickingListId - char(12)
	         @MOId, -- MOId - char(12)
	         GETDATE(), -- CreateDate - datetime
	         GETDATE() -- ModifyDate - datetime
	     )

	-- 游标循环获取数据
	DECLARE cursor1 CURSOR LOCAL FAST_FORWARD FOR
	SELECT MOItemId,ProductId,curQtyRequired,ItemQtyIssued,ItemQtyOwe,UOMId
	FROM @MOItemTemp
	WHERE ItemQtyOwe>0
	OPEN cursor1
	FETCH NEXT FROM cursor1 
	INTO @MOItemId,@ProductId,@CurQtyRequired,@ItemQtyIssued,@ItemQtyOwe,@UOMId
	WHILE @@FETCH_STATUS = 0
	BEGIN
		-- 获取领料单行号
		IF EXISTS(SELECT 1 FROM dbo.PickingListItem WHERE PickingListId=@PickingListId)
			SELECT
				@ItemSequence = RIGHT('000'+CAST(MAX(CAST(ItemSequence AS INT))+1 AS VARCHAR),4)
			FROM dbo.PickingListItem
			WHERE PickingListId = @PickingListId
		ELSE
			SET @ItemSequence = RIGHT('000'+CAST(1 AS VARCHAR),4)


		--需求数大于欠料数，则取欠料数
		IF @CurQtyRequired>@ItemQtyOwe
			SET @CurQtyRequired=@ItemQtyOwe
		
		-- 获取主键
		EXEC	[dbo].[SysGetObjectPKId] '','PickingListItem',@PickingListItemId OUTPUT
		-- 写入表
		INSERT INTO dbo.PickingListItem( 
				PickingListItemId ,
				PickingListId ,
				ItemSequence,
				MOId,
				MOItemId,
				ProductId ,
				QtyRequired,
				WorkcenterId,
				UOMId
				)
			VALUES  ( 
				@PickingListItemId,
				@PickingListId ,
				@ItemSequence,
				@MOId,
				@MOItemId,
				@ProductId,
				@CurQtyRequired,
				@WarehouseId,
				@UOMId
				)

		FETCH NEXT FROM cursor1 
		INTO @MOItemId,@ProductId,@CurQtyRequired,@ItemQtyIssued,@ItemQtyOwe,@UOMId
	END
	CLOSE cursor1
	DEALLOCATE cursor1
	
	SELECT @I_ReturnMessage= 'ServerMessage: 生成领料单 ['+ISNULL(@PickingListName,'')+'] 完成，请核查！'
	RETURN 0
END




go

