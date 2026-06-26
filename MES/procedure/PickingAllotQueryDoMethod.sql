-- =============================================
-- Author:		<OrBit HK0282 >
-- Create date: <2008.8.8>
-- Description:	领料缺料的查询事件
-- =============================================
CREATE  PROCEDURE  [dbo].[PickingAllotQueryDoMethod]
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
	if isnull(@StartTime,'')<>'' and ISNULL(@EndTime,'')<>'' 
	begin
		if ISNULL(@StartTime,'')>ISNULL(@EndTime,'')
		begin
			set @I_ReturnMessage='ServerMessage:开始日期不能大于结束日期！'
			return -1
		end
  end 

	IF @I_Sender='AllotQuery'
	BEGIN 

		SELECT pa.ProductAllotName,pa.ProductAllotStates+BillState.BillStatesDescription AS ProductAllotStates ,p2.TProductName,p2.ProductDescription,
			CASE WHEN p2.ProductClassify=1 THEN '成品'
		     WHEN p2.ProductClassify=2 THEN '半成品'
			 WHEN p2.ProductClassify=4 OR pf2.ProductFamilyName IN ('102850','102855','102857','102859','101750','573008') THEN '包材'
		     WHEN p2.ProductClassify=3 THEN '原材料'
		      END AS '类型',
		CAST(pai.AllotQty AS NUMERIC(18,3)) AS AllotQty,CAST(t.qty AS NUMERIC(18,3)) AS qty,
		 (select top 1 pf.ProductLineCode from  Product_Factory as pf 
where  p2.ProductId =pf.ProductId) AS ProductLineCode,
		t.FactoryName,t.WorkcenterName,
				CAST(CONVERT(NVARCHAR(10),pa .CreateDate,23)AS NVARCHAR(10)) AS Date,
			CONVERT(NVARCHAR(50),pa.CreateDate,24) AS CreateTime
				FROM dbo.ProductAllot AS pa
				INNER JOIN dbo.ProductAllotItem AS pai ON pai.ProductAllotId = pa.ProductAllotId AND NOT EXISTS(SELECT 1 FROM dbo.ProductAllotItemLot p WHERE pai.ProductAllotItemId=p.ProductAllotItemId)
				INNER JOIN dbo.Product AS p2 ON p2.ProductId = pai.ProductId
				LEFT JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p2.ProductRootId
				LEFT JOIN dbo.ProductFamily AS pf2 ON pf2.ProductFamilyId = pr.ProductFamilyId
				LEFT OUTER JOIN ( SELECT BillStates.BillStatesId,BillStates.BillStatesName ,BillStates.BillStatesDescription FROM Bill
						LEFT OUTER JOIN BillStates ON Bill.BillId = BillStates.BillId
						WHERE Bill.BillName = N'ProductAllot' ) AS BillState ON pa.ProductAllotStates = BillState.BillStatesName 
				LEFT JOIN (SELECT SUM(wri.Qty) AS qty ,wri.ProductId,wri.FactoryId,wri.WorkcenterId,f.FactoryName,w.WorkcenterName FROM dbo.WW_RMInventory AS wri 
				INNER JOIN dbo.Factory AS f ON f.FactoryId = wri.FactoryId
				INNER JOIN dbo.Workcenter AS w ON w.WorkcenterId = wri.WorkcenterId
				WHERE wri.LotStatus='1' AND wri.IsStorage=1 AND wri.Qty>0 
				GROUP BY wri.ProductId,wri.FactoryId,wri.WorkcenterId,f.FactoryName,w.WorkcenterName) t ON t.ProductId = pai.ProductId AND t.FactoryId = pa.FactoryId AND t.WorkcenterId = pa.ToWorkcenterId
				--INNER JOIN dbo.MOAllotMODetail AS mamd ON mamd.MOAllotRequestId = pa.MOAllotRequestId AND mamd.ProductId=
				--INNER JOIN dbo.MO AS m ON m.MOId = mamd.MOId
				--INNER JOIN dbo.MOItem AS mi ON mi.MOId = m.MOId AND mi.ProductId=pai.ProductId
				WHERE pa.ProductAllotDescription='多工单合并发料' 
		AND (@StartTime IS NULL OR CONVERT(VARCHAR,@StartTime,23)<=CONVERT(VARCHAR ,pa.CreateDate,23))
		AND (@EndTime IS NULL OR CONVERT(VARCHAR,@EndTime,23)>=CONVERT(VARCHAR ,pa.CreateDate,23))
				ORDER BY pa.ProductAllotName,p2.TProductName
	END 

	IF @I_Sender='PickQuery'
	BEGIN 

		SELECT DISTINCT pa.PickingListName,pa.PickingListStates +BillState.BillStatesDescription AS PickingListStates,p2.TProductName,p2.ProductDescription,
		CASE WHEN p2.ProductClassify=1 THEN '成品'
		     WHEN p2.ProductClassify=2 THEN '半成品'
			 WHEN p2.ProductClassify=4 OR pf2.ProductFamilyName IN ('102850','102855','102857','102859','101750','573008') THEN '包材'
		     WHEN p2.ProductClassify=3 THEN '原材料'
		      END AS '类型',
			 CAST(pai.QtyRequired AS NUMERIC(18,3)) AS AllotQty,CAST(t.qty AS NUMERIC(18,3)) AS qty,
			 mo.ProductLine AS ProductLineCode,

				CAST(CONVERT(NVARCHAR(10),pa .CreateDate,23)AS NVARCHAR(10)) AS Date,
			CONVERT(NVARCHAR(50),pa.CreateDate,24) AS CreateTime
				FROM dbo.PickingList  AS pa
				INNER JOIN dbo.PickingListItem AS pai ON pai.PickingListId = pa.PickingListId AND NOT EXISTS(SELECT 1 FROM dbo.PickingListItemLot p WHERE pai.PickingListItemId=p.PickingListItemId)
				INNER JOIN dbo.Product AS p2 ON p2.ProductId = pai.ProductId
				INNER JOIN dbo.PickingList_MO AS plm ON plm.PickingListId = pa.PickingListId
				INNER JOIN dbo.MO  ON MO.MOId = plm.MOId
				LEFT JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p2.ProductRootId
				LEFT JOIN dbo.ProductFamily AS pf2 ON pf2.ProductFamilyId = pr.ProductFamilyId
				LEFT OUTER JOIN ( SELECT  BillStates.BillStatesId,BillStates.BillStatesName ,BillStates.BillStatesDescription FROM Bill
						LEFT OUTER JOIN BillStates ON Bill.BillId = BillStates.BillId
						WHERE Bill.BillName = N'PickingListPR' ) AS BillState ON pa.PickingListStates = BillState.BillStatesName 
				LEFT JOIN (SELECT  SUM(wri.Qty) AS qty ,wri.ProductId,wri.FactoryId,wri.WorkcenterId,f.FactoryName,w.WorkcenterName FROM dbo.WW_RMInventory AS wri 
				INNER JOIN dbo.Factory AS f ON f.FactoryId = wri.FactoryId
				INNER JOIN dbo.Workcenter AS w ON w.WorkcenterId = wri.WorkcenterId
				WHERE wri.LotStatus='1' AND wri.IsStorage=1 AND wri.Qty>0 
				GROUP BY wri.ProductId,wri.FactoryId,wri.WorkcenterId,f.FactoryName,w.WorkcenterName) t ON t.ProductId = pai.ProductId AND t.FactoryId = pa.FactoryId AND t.WorkcenterId = pa.ToWorkcenterId
				--INNER JOIN dbo.MOAllotMODetail AS mamd ON mamd.MOAllotRequestId = pa.MOAllotRequestId AND mamd.ProductId=
				--INNER JOIN dbo.MO AS m ON m.MOId = mamd.MOId
				--INNER JOIN dbo.MOItem AS mi ON mi.MOId = m.MOId AND mi.ProductId=pai.ProductId
				WHERE 1=1
		AND (@StartTime IS NULL OR CONVERT(VARCHAR,@StartTime,23)<=CONVERT(VARCHAR ,pa.CreateDate,23))
		AND (@EndTime IS NULL OR CONVERT(VARCHAR,@EndTime,23)>=CONVERT(VARCHAR ,pa.CreateDate,23))
				ORDER BY pa.PickingListName,p2.TProductName
	END 



 
	RETURN 0

END
go

