-- =============================================
-- Author:		<OrBit HK0282 >
-- Create date: <2008.8.8>
-- Description:	来料看板的查询事件
-- =============================================
CREATE  PROCEDURE  [dbo].[PickingQueryDoMethod]
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
@I_Parameter nvarchar(100)='',		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@StartTime DATETIME=NULL,
@EndTime DATETIME=NULL



AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED


--SELECT 
--t1.CreateDate,
--t2.QtyRequired,
--t4.ProductAllotName,
--pr.ProductName,
--t7.ProductDescription,
--m.PlannedDateFrom,
--u.UOMName,
--wri.Qty,
--w.WorkcenterName,
--t2.QtyIssued,
--su.UserDescription,
--t1.PickingListStates,
--t3.LotSN
--FROM dbo.PickingList t1 
--LEFT JOIN dbo.PickingListItem t2 ON t2.PickingListId = t1.PickingListId
--LEFT JOIN dbo.PickingListItemLot t3 ON t3.PickingListItemId = t2.PickingListItemId
--LEFT JOIN dbo.ProductAllot t4 ON t4.PickingListId=t1.PickingListId
--LEFT JOIN dbo.Product  t7 ON t7.ProductId=t2.ProductId
--LEFT JOIN dbo.ProductRoot AS pr ON pr.ProductRootId=t7.ProductRootId
--LEFT JOIN dbo.PickingList_MO AS plm ON plm.PickingListId=t1.PickingListId
--LEFT JOIN dbo.MO AS m ON m.MOId=plm.MOId
--LEFT JOIN dbo.UOM AS u ON u.UOMId=t7.UsageUOMId
--LEFT JOIN dbo.WW_RMInventory AS wri ON wri.ProductId=t2.ProductId AND wri.WorkcenterId=t2.WorkcenterId
--LEFT JOIN dbo.Workcenter AS w ON w.WorkcenterId=t4.ToWorkcenterId
--LEFT JOIN dbo.SysUser AS su ON su.UserId=t4.CreateUserId
--WHERE t2.DeleteFlag<>'X'
--AND (@StartTime IS NULL OR CONVERT(VARCHAR,@StartTime,23)<=CONVERT(VARCHAR ,t1.CreateDate,23))
--AND (@EndTime IS NULL OR CONVERT(VARCHAR,@EndTime,23)>=CONVERT(VARCHAR ,t1.CreateDate,23))


SELECT 
ROW_NUMBER() OVER (ORDER BY  pr.ProductName  ASC) AS '序号',
--REPLACE(CONVERT(VARCHAR ,pa.CreateDate,23),'-','') AS '发料日期',
REPLACE(SUBSTRING(CONVERT(VARCHAR ,pa.RequiredDate,120), 6, 6),'-','')AS '需求时间',
--CONVERT(VARCHAR ,pa.RequiredDate,24) AS '需求时间',
pa.ProductAllotName AS '调拨单号',
pr.ProductName AS '物料代码',
p.ProductDescription AS '物料描述',
wri2.ProductionLotNO AS '物料批号',
pai.AllotQty AS '需求数量',
u.UOMName AS '单位',
(SELECT SUM(wri.Qty) FROM dbo.WW_RMInventory AS wri WHERE p.ProductId=wri.ProductId AND wri.WorkcenterId !='WKC1000002OA'
AND wri.WorkcenterId!='WKC1000002P8' AND wri.IsStorage=1) AS '库存数量',
(SELECT SUM(wri.Qty) FROM dbo.WW_RMInventory AS wri WHERE p.ProductId=wri.ProductId AND wri.WorkcenterId ='WKC1000002OA'
OR  wri.WorkcenterId='WKC1000002P8' AND wri.IsStorage=1) AS '线边仓数量',
LEFT(w.WorkcenterName,2) AS '用料车间',
pai.RealAllotQty AS '发料数量',
CASE WHEN BillState.BillStatesDescription='已确认' THEN '已调拨'
     ELSE  '待拣货' END AS  '发料状态'
FROM dbo.ProductAllot AS pa
LEFT JOIN dbo.ProductAllotItem AS pai ON pai.ProductAllotId = pa.ProductAllotId
LEFT JOIN dbo.ProductAllotItemLot AS pail ON pail.ProductAllotItemId = pai.ProductAllotItemId
LEFT JOIN dbo.WW_RMInventory AS wri2 ON wri2.LotSN = pail.LotSN
LEFT JOIN dbo.Product AS p ON p.ProductId = pai.ProductId
LEFT JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p.ProductRootId
LEFT JOIN dbo.UOM AS u ON u.UOMId=p.UsageUOMId
LEFT JOIN dbo.Workcenter AS w ON w.WorkcenterId=pa.ToWorkcenterId
LEFT JOIN dbo.BillStates_Table('ProductAllot')  BillState ON pa.ProductAllotStates = BillState.BillStatesName AND BillState.IsERP=0
LEFT JOIN dbo.SysUser AS su ON 	su.UserId=pa.ConfirmUserId	
WHERE (w.WorkcenterName='UVXB' OR w.WorkcenterName='FSXB')
AND  pai.DeleteFlag<>'X'
AND (@StartTime IS NULL OR CONVERT(VARCHAR,@StartTime,23)<=CONVERT(VARCHAR ,pa.CreateDate,23))
AND (@EndTime IS NULL OR CONVERT(VARCHAR,@EndTime,23)>=CONVERT(VARCHAR ,pa.CreateDate,23))
ORDER BY  pr.ProductName ASC

 
	return 0

END
go

