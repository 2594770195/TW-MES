-- =============================================
-- Author:<OrBit Team Orbchay HK0325 >
-- Create date:   <2021/08/02 13:59:13:9938>
-- Description:<领料单确认：生产、杂发、委外、外协>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[PickingListConfirm_DoMethod]
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
@I_Parameter NVARCHAR(100)='',		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@CreateDate DATETIME=NULL 

AS
BEGIN 

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--通用信息
	DECLARE @return_value INT =-1
	DECLARE @Enter VARCHAR(2)=CHAR(13)+CHAR(10)

	--bill
	DECLARE @PickingListName NVARCHAR(50)=''

	IF ISNULL(@I_PKid,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请选择单据！'
		RETURN -1
	END

	SELECT @PickingListName=PickingListName
	FROM dbo.PickingList
	WHERE PickingListId=@I_PKid

	IF @I_PlugInCommand='PLOT'
	BEGIN 
		IF EXISTS(SELECT 1 FROM dbo.PickingList AS pl
		INNER JOIN dbo.PickingListItem AS pli ON pli.PickingListId = pl.PickingListId
		INNER JOIN dbo.CostCenter AS cc ON cc.CostCenterId = pli.CostCenterId
		WHERE cc.CostCenterName IN ('0000120000','0000180000','0000110000') AND ISNULL(pli.OrderName,'')='' AND pl.PickingListId=@I_PKid)
		BEGIN 
		DECLARE @CostCenterName NVARCHAR(50)=''
		DECLARE @Line NVARCHAR(50)=''

		SELECT TOP 1 @CostCenterName=cc.CostCenterDescription,@Line=pli.ItemSequence
		FROM dbo.PickingList AS pl
		INNER JOIN dbo.PickingListItem AS pli ON pli.PickingListId = pl.PickingListId
		INNER JOIN dbo.CostCenter AS cc ON cc.CostCenterId = pli.CostCenterId
		WHERE cc.CostCenterName IN ('0000120000','0000180000','0000110000') AND ISNULL(pli.OrderName,'')=''AND pl.PickingListId=@I_PKid

		  SET @I_ReturnMessage='ServerMessage:领料单【'+@PickingListName+'】的【'+@Line+'】行的成本中心为【'+@CostCenterName+'】,需要填写项目号，请填写！！！'
		  RETURN -1
		END 
	END
	--调用领料单统一确认接口
	EXEC @return_value=dbo.TxnBase_MBill_PickingListConfirm
		@I_Sender=@I_Sender,
		@I_ReturnMessage=@I_ReturnMessage OUTPUT,
		@I_PlugInCommand=@I_PlugInCommand,
		@I_OrBitUserId=@I_OrBitUserId,
		@I_OrBitUserName=@I_OrBitUserName,
		@I_ResourceId=@I_ResourceId,
		@I_ResourceName=@I_ResourceName,
		@I_Parameter=@I_Parameter,
		@PickingListName=@PickingListName,
		@I_PKid=@I_PKid,
		@CreateDate=@CreateDate
	
		--======================================2024/11/27begin 危化品不调拨到SOXB 留在XBTZ SAP没有SOXB==========================================================================================================
	-- PRD10002J41U K203G
	-- PRD10002IN5C 丁酮
	-- PRD10002HLR5 E224G
	-- WKC1000002HD SOXB仓库，WKC100000BQQ XBTZ
	--======================================    2026年2月6日 20:32:25 去掉该调拨逻辑,SAP已经有SOXB  ==========================================================================================================
--     if exists( -- 如果领料单明细有危化品
--         select 1 from PickingListItem
--             join PickingList
--             on PickingListItem.PickingListId = PickingList.PickingListId
--              where PickingList.PickingListName = @PickingListName and PickingList.PickingListStates = '40' and  ProductId in('PRD10002J41U','PRD10002IN5C','PRD10002HLR5')
--     )
--     begin
--         if exists( -- 检查在库的危化品是否存在SOXB的仓库
--             select 1 from WW_RMInventory where ProductId in('PRD10002J41U','PRD10002IN5C','PRD10002HLR5') and WorkcenterId = 'WKC1000002HD' and IsStorage = 1
--         )
--         begin   -- 重新更新到XBTZ
--             update WW_RMInventory set WorkcenterId = 'WKC100000BQQ' where ProductId in('PRD10002J41U','PRD10002IN5C','PRD10002HLR5') and WorkcenterId = 'WKC1000002HD' and IsStorage = 1
--         end
--     end
    --======================================    2026年2月6日 20:32:25 去掉该调拨逻辑,SAP已经有SOXB  ==========================================================================================================
    --======================================2024/11/27end 危化品不调拨到SOXB 留在XBTZ==========================================================================================================

	
	SET @I_ReturnMessage=@I_ReturnMessage
	RETURN @return_value
END
go

