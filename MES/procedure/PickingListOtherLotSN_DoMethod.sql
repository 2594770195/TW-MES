
-- =============================================
-- Author:		<OrBit Team HK0313>
-- Create date: <2021.11.1>
-- Modify date: <2021.11.1>
-- Description:	<杂发单指定批次>
-- Rev: 10.00
-- =============================================
CREATE   PROCEDURE  [dbo].[PickingListOtherLotSN_DoMethod]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT, --向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKId CHAR(12) = '',				--主键
@I_SourcePKId CHAR(12)='',			--执行拷贝时传入的源主键  
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(100)='',		--插件参数	
-- ====================== 以上是系统参数 =========================
@LotSN NVARCHAR(50) = ''   -- 指定批号

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	IF ISNULL(@I_PKId,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:没有任何项目可以指定!'
			RETURN -1
	END

	--为空判定
	IF ISNULL(@LotSN,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:指定批号不允许为空!'
			RETURN -1
	END

	--IF ISNULL(@AssignQty,0)<=0
	--BEGIN
	--	SET @I_ReturnMessage='ServerMessage:指定数量必须大于0!'
	--		RETURN -1
	--END

	DECLARE @ProductId CHAR(12)
	DECLARE @PickingListItemLotId CHAR(12)
	DECLARE @LotId CHAR(12)
	DECLARE @CellId CHAR(12)
	DECLARE @BoxSN VARCHAR(100)
	DECLARE @PalletSN VARCHAR(100)
	DECLARE @LotStatus VARCHAR(10)
	DECLARE @IsStorage BIT
	DECLARE @PickingListName VARCHAR(50)
	DECLARE @WWId CHAR(12)
	DECLARE @LotQty DECIMAL(18,8)
	DECLARE @DeliveryQty DECIMAL(18,8)
	DECLARE @RealDeliveryQty DECIMAL(18,8)

	SELECT 
		@PickingListName=B.PickingListName,
		@DeliveryQty=A.QtyRequired,
		@RealDeliveryQty=A.QtyIssued
	FROM PickingListItem A 
	INNER JOIN PickingList B ON A.PickingListId=B.PickingListId 
	WHERE A.PickingListItemId=@I_PKId

	IF ISNULL(@PickingListName,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:参数错误!'
			RETURN -1
	END

	IF @DeliveryQty<=@RealDeliveryQty
	BEGIN
		SET @I_ReturnMessage='ServerMessage:实际领料数量已满足需求数量!'
			RETURN -1
	END

	SELECT 
		@LotId=LotId,
		@CellId=CellId,
		@BoxSN=BoxSN,
		@PalletSN=PalletSN,
		@LotStatus=LotStatus,
		@IsStorage=IsStorage,
		@WWId=WWId,
		@LotQty=Qty 
	FROM WW_RMInventory 
	WHERE LotSN=@LotSN

	--IF ISNULL(@LotId,'')=''
	--BEGIN
	--	SET @I_ReturnMessage='ServerMessage:批次['+@LotSN+']不存在!'
	--		RETURN -1
	--END

	IF ISNULL(@LotStatus,'')<>'1'
	BEGIN
		SET @I_ReturnMessage='ServerMessage:批次['+@LotSN+']不是可用状态!'
			RETURN -1
	END

	IF ISNULL(@IsStorage,0)<>1
	BEGIN
		SET @I_ReturnMessage='ServerMessage:批次['+@LotSN+']不在库!'
			RETURN -1
	END

	IF ISNULL(@LotQty,0)<=0
	BEGIN
		SET @I_ReturnMessage='ServerMessage:指定批次数量必须大于0!'
			RETURN -1
	END

	DECLARE @return_value INT =-1
	EXEC @return_value=dbo.PDA_MaterialToPickingListOther @I_Sender = N'',                                      -- nvarchar(200)
	                                        @I_ReturnMessage = @I_ReturnMessage OUTPUT,           -- nvarchar(max)
	                                        @I_ExceptionFieldName = @I_ExceptionFieldName OUTPUT, -- nvarchar(100)
	                                        @I_LanguageId = @I_LanguageId,                                   -- char(1)
	                                        @I_PlugInCommand = @I_PlugInCommand,                                -- varchar(5)
	                                        @I_OrBitUserId = @I_OrBitUserId,                                  -- char(12)
	                                        @I_OrBitUserName = @I_OrBitUserName,                               -- nvarchar(100)
	                                        @I_ResourceId = @I_ResourceId,                                   -- char(12)
	                                        @I_ResourceName =@I_ResourceName,                                -- nvarchar(100)
	                                        @I_PKid = @I_PKid,                                         -- char(12)
	                                        @I_ParentPKId = @I_ParentPKId,                                   -- char(12)
	                                        @I_Parameter = @I_Parameter,                                   -- nvarchar(max)
	                                        @PickingListName =@PickingListName,                               -- nvarchar(50)
	                                        @BoxOrLotSN =@LotSN                                     -- nvarchar(100)
	

	RETURN @return_value
END
go

