
-- =============================================
-- Author:		<OrBit Team HK0313>
-- Create Date: <2022.01.18>
-- Description:	PDA 工单领料查询
-- Version: 1
-- =============================================
CREATE PROCEDURE  [dbo].[PDA_MOPickingQuery]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT, --向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId CHAR(12)='',			--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKid CHAR(12) ='',				--主键
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(MAX)='',  		--插件参数

@MOName NVARCHAR(50)=''      --工单号

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	DECLARE @Enter NVARCHAR(50)=CHAR(13)+CHAR(10)--回车
	DECLARE @RESULT INT = 0                      --返回状态

	IF ISNULL(@MOName,'')=''
	BEGIN
		SELECT '' AS SOName,'' AS MOName,'' AS FinishedProductDescription,'' AS CustomerProduct,'' AS ProductDescription,
		'' AS LotSN,'' AS Qty,'' AS Models,'' AS ProductTxt,'' AS SoText
		SET @I_ExceptionFieldName = 'MOName'
		RETURN 0
	END

	IF NOT EXISTS(SELECT 1 FROM MO WHERE MOName=@MOName) AND NOT EXISTS(SELECT 1 FROM MO WHERE SOName=@MOName)
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:工单号['+@MOName+']不存在!' 
		SELECT '' AS MOName
		SET @I_ExceptionFieldName = 'MOName'
		RETURN -1
	END

	SELECT E.SOName,E.MOName AS MOName,F.TProductName AS FinishedProductDescription,E.CustomerProduct,D.ProductDescription,
	(CASE WHEN ISNULL(A.OrgLotSN,'')<>'' THEN A.OrgLotSN ELSE A.LotSN END) AS LotSN,A.Qty,E.Models,E.ProductTxt,E.SoText FROM PickingListItemLot A
	INNER JOIN PickingListItem B ON A.PickingListItemId=B.PickingListItemId
	INNER JOIN PickingList C ON B.PickingListId=C.PickingListId
	INNER JOIN Product D ON B.ProductId=D.ProductId
	INNER JOIN MO E ON B.MOId=E.MOId
	INNER JOIN Product F ON E.ProductId=F.ProductId
	WHERE D.ProductClassify='2'
	AND (E.MOName=@MOName OR E.SOName=@MOName OR D.ProductDescription LIKE '%'+@MOName+'%' OR E.Models LIKE '%'+@MOName+'%')

	RETURN 0

END
go

