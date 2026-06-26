-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/04/09 12:35:00:7068>
-- Description:   <生产领料确认：生产领料单、杂发、委外、外协领料单>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROC dbo.PDA_PickingListConfirm
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

@PickingListName NVARCHAR(50)=''





--@I_Sender=N'PickingListConfirm',
--@I_ReturnMessage=@p2 output,
--@I_ExceptionFieldName=@p3 output,
--@I_LanguageId=N'2',
--@I_PlugInCommand=N'MIPL',
--@I_OrBitUserId=N'SUR1000003P0',
--@I_OrBitUserName=N'HH0082',
--@I_ResourceId=N'RES10000010I',
--@I_ResourceName=N'DESKTOP-LAC1HKT',
--@I_Parameter=N'[MOBILETXN:Material Issue]',

AS
BEGIN

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--通用信息
	DECLARE @return_value INT =-1
	DECLARE @Enter VARCHAR(2)=CHAR(13)+CHAR(10)

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
	    @PickingListName=@PickingListName

	--======================================2024/11/27begin 危化品不调拨到SOXB 留在XBTZ SAP没有SOXB==========================================================================================================
	--======================================    2026年2月6日 20:32:25 去掉该调拨逻辑,SAP已经有SOXB  ==========================================================================================================
    -- PRD10002J41U K203G
	-- PRD10002IN5C 丁酮
	-- WKC1000002HD SOXB仓库，WKC100000BQQ XBTZ
--         if exists( -- 如果领料单明细有危化品
--             select 1 from PickingListItem
--                 join PickingList
--                 on PickingListItem.PickingListId = PickingList.PickingListId
--                  where PickingList.PickingListName = @PickingListName and PickingList.PickingListStates = '40' and  ProductId in('PRD10002J41U','PRD10002IN5C')
--         )
--         begin
--             if exists( -- 检查在库的危化品是否存在SOXB的仓库
--                 select 1 from WW_RMInventory where ProductId in('PRD10002J41U','PRD10002IN5C') and WorkcenterId = 'WKC1000002HD' and IsStorage = 1
--             )
--             begin   -- 重新更新到XBTZ
--                 update WW_RMInventory set WorkcenterId = 'WKC100000BQQ' where ProductId in('PRD10002J41U','PRD10002IN5C') and WorkcenterId = 'WKC1000002HD' and IsStorage = 1
--             end
--         end

    --======================================    2026年2月6日 20:32:25 去掉该调拨逻辑,SAP已经有SOXB  ==========================================================================================================
    --======================================2024/11/27end 危化品不调拨到SOXB 留在XBTZ==========================================================================================================

	SET @I_ReturnMessage=@I_ReturnMessage+@Enter
	RETURN @return_value
END
go

