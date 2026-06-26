-- =============================================
-- Author:		<Gavin>
-- Create date: <03  2 2012 10:18AM>
-- Description:	为PickingList创建导航树视图
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListPRTreeView]
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_FiltCondition	NVARCHAR(MAX)='',	--过滤条件表达式
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKId CHAR(12) ='',				--主键
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(100)='',		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个TreeView过程中实现.
@I_IsDBSerch BIT =0,--是否进行数据库级参数过滤， 1执行数据库查找， 0不执行.
@PickingListName NVARCHAR(50)='',
@MOName NVARCHAR(50)='',
@StartDate DATETIME=NULL,
@EndDate DATETIME=NULL
AS
BEGIN
	-- This Stored Procedure is created by OrBit-MetaObject engine	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--执行TreeView,注意：以下过程必须根据业务的需求进行调整
	--如果您不了解TreeView过程如何编写，请参考我们提供的示例_SampleProjectTreeView

	--DB搜索;UPDATE;orbchay,HH0102;2020/12/31 11:40:07:0098
	IF @I_IsDBSerch=1
	BEGIN
		DECLARE @MOId CHAR(12)=''
		DECLARE @Table TABLE(
			PickingListId CHAR(12) PRIMARY KEY
		)

		IF @StartDate IS NOT NULL
			SET @StartDate=CAST(CONVERT(VARCHAR,@StartDate,23)+' 00:00:00' AS DATETIME)

		IF @EndDate IS NOT NULL
			SET @EndDate=CAST(CONVERT(VARCHAR,@EndDate,23)+' 23:59:59' AS DATETIME)
		ELSE
			SET @EndDate=GETDATE()


	--	--根据查询条件获取
		IF ISNULL(@PickingListName,'')<>''
		BEGIN
			INSERT INTO @Table
				 (
					 PickingListId
				 )
			SELECT PickingListId
			FROM dbo.PickingList
			INNER JOIN (SELECT FactoryId
						FROM dbo.Factory_User
						WHERE UserId=@I_OrBitUserId
						)tempFactory ON tempFactory.FactoryId = PickingList.FactoryId
			WHERE PickingListName=@PickingListName AND PickingListClass='01'
		END
		ELSE IF ISNULL(@MOName,'')<>''
		BEGIN
			SELECT @MOId=MOId
			FROM dbo.MO
			WHERE MOName=@MOName

			IF ISNULL(@MOId,'')<>''
			BEGIN 
				INSERT INTO @Table
					 (
						 PickingListId
					 )
				SELECT DISTINCT PickingList.PickingListId
				FROM dbo.PickingList
				INNER JOIN (SELECT FactoryId
							FROM dbo.Factory_User
							WHERE UserId=@I_OrBitUserId
							)tempFactory ON tempFactory.FactoryId = PickingList.FactoryId
				INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListId = PickingList.PickingListId
				WHERE MOId=@MOId AND (PickingListClass='01' OR EXISTS(SELECT 1 FROM dbo.PickingList_MO AS pli 
		WHERE pli.PickingListId=PickingList.PickingListId AND ISNULL(pli.ToSAPStates ,'')='') AND PickingList.PickingListStates IN ('40','41'))
			END
		END
		ELSE IF @StartDate IS NOT NULL
		BEGIN
			INSERT INTO @Table
					(
						PickingListId
					)
			SELECT TOP 10000 PickingListId 
			FROM dbo.PickingList
			INNER JOIN (SELECT FactoryId
						FROM dbo.Factory_User
						WHERE UserId=@I_OrBitUserId
						)tempFactory ON tempFactory.FactoryId = PickingList.FactoryId
			WHERE CreateDate>=@StartDate AND CreateDate<=@EndDate
			AND PickingListClass='01'
			ORDER BY CreateDate DESC
		END


		SELECT 
			PickingList.PickingListId, 
			PickingListName,
			CASE WHEN  EXISTS(SELECT 1 FROM dbo.PickingListItemLot AS plil 
			INNER JOIN dbo.PickingListItem AS pli ON pli.PickingListItemId = plil.PickingListItemId
			WHERE pli.PickingListId=PickingList.PickingListId) AND PickingList.PickingListStates='20' THEN  '21 领料中'
		WHEN EXISTS(SELECT 1 FROM dbo.PickingListItem AS pli 
		WHERE pli.PickingListId=PickingList.PickingListId AND ISNULL(pli.ToSAPStates ,'')='') AND PickingList.PickingListStates IN ('41') THEN  '42 部分过账'ELSE 
		PickingList.PickingListStates+' '+ISNULL(BillState.BillStatesDescription,'')END  AS PickingListStates,
		CASE WHEN EXISTS (SELECT 1  FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId 
		INNER JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p.ProductRootId
		INNER JOIN dbo.ProductFamily AS pf ON pf.ProductFamilyId = pr.ProductFamilyId
		WHERE pli2.PickingListId=PickingList.PickingListId AND pf.ProductFamilyName IN('102850','102855','102857','102859','101750','573008','102858'))
		THEN '包材领料单' 
		WHEN (SELECT TOP 1  p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='1'
		THEN '成品领料单'
		WHEN (SELECT TOP 1 p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='2'
		THEN '半成品领料单'
		WHEN (SELECT TOP 1 p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='3'
		THEN '原材料领料单'
		END AS '领料类型',
			ISNULL(FactoryName,'') AS FactoryName,
					CAST(CONVERT(NVARCHAR(10),PickingList.CreateDate,23)AS NVARCHAR(10)) AS Date,
			CONVERT(NVARCHAR(50),PickingList.CreateDate,24) AS CreateTime
		FROM @Table A
		INNER JOIN dbo.PickingList ON PickingList.PickingListId = A.PickingListId
		INNER JOIN (SELECT FactoryId
					FROM dbo.Factory_User
					WHERE UserId=@I_OrBitUserId
					)tempFactory ON tempFactory.FactoryId = PickingList.FactoryId
		LEFT JOIN dbo.Factory ON Factory.FactoryId = PickingList.FactoryId
		LEFT JOIN dbo.BillStates_Table('PickingListPR')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
	--	WHERE  PickingList.CreateDate>'2022-02-01'
		ORDER BY PickingList.CreateDate DESC

		RETURN 0
	END



	IF @I_PKId<>''
	BEGIN
			
		SELECT     
			PickingListId, 
			PickingListName,
			CASE WHEN  EXISTS(SELECT 1 FROM dbo.PickingListItemLot AS plil 
			INNER JOIN dbo.PickingListItem AS pli ON pli.PickingListItemId = plil.PickingListItemId
			WHERE pli.PickingListId=PickingList.PickingListId) AND PickingList.PickingListStates='20' THEN  '21 领料中'
		WHEN EXISTS(SELECT 1 FROM dbo.PickingListItem AS pli 
		WHERE pli.PickingListId=PickingList.PickingListId AND ISNULL(pli.ToSAPStates ,'')='') AND PickingList.PickingListStates IN ('41') THEN  '42 部分过账'ELSE 
		PickingList.PickingListStates+' '+ISNULL(BillState.BillStatesDescription,'')END  AS PickingListStates,
		CASE WHEN EXISTS (SELECT 1  FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId 
		INNER JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p.ProductRootId
		INNER JOIN dbo.ProductFamily AS pf ON pf.ProductFamilyId = pr.ProductFamilyId
		WHERE pli2.PickingListId=PickingList.PickingListId AND pf.ProductFamilyName IN('102850','102855','102857','102859','101750','573008','102858'))
		THEN '包材领料单' 
		WHEN (SELECT TOP 1  p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='1'
		THEN '成品领料单'
		WHEN (SELECT TOP 1 p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='2'
		THEN '半成品领料单'
		WHEN (SELECT TOP 1 p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='3'
		THEN '原材料领料单'
		END AS '领料类型',
			ISNULL(FactoryName,'') AS FactoryName,
					CAST(CONVERT(NVARCHAR(10),PickingList.CreateDate,23)AS NVARCHAR(10)) AS Date,
			CONVERT(NVARCHAR(50),PickingList.CreateDate,24) AS CreateTime
		FROM         dbo.PickingList
		LEFT JOIN dbo.Factory ON Factory.FactoryId = PickingList.FactoryId
		LEFT JOIN dbo.BillStates_Table('PickingListPR')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
		WHERE PickingListId=@I_PKId  AND PickingList.CreateDate>'2022-02-01'
		ORDER BY PickingList.CreateDate DESC

		RETURN 0
	END
	
	SELECT DISTINCT 
		PickingList.PickingListId, 
		PickingListName,
		CASE WHEN  EXISTS(SELECT 1 FROM dbo.PickingListItemLot AS plil 
		INNER JOIN dbo.PickingListItem AS pli ON pli.PickingListItemId = plil.PickingListItemId
		WHERE pli.PickingListId=PickingList.PickingListId) AND PickingList.PickingListStates='20' THEN  '21 领料中'
		WHEN EXISTS(SELECT 1 FROM dbo.PickingListItem AS pli 
		WHERE pli.PickingListId=PickingList.PickingListId AND ISNULL(pli.ToSAPStates ,'')='') AND PickingList.PickingListStates IN ('41') THEN  '42 部分过账'ELSE 
		PickingList.PickingListStates+' '+ISNULL(BillState.BillStatesDescription,'')END  AS PickingListStates,
		CASE WHEN EXISTS (SELECT 1  FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId 
		INNER JOIN dbo.ProductRoot AS pr ON pr.ProductRootId = p.ProductRootId
		INNER JOIN dbo.ProductFamily AS pf ON pf.ProductFamilyId = pr.ProductFamilyId
		WHERE pli2.PickingListId=PickingList.PickingListId AND pf.ProductFamilyName IN('102850','102855','102857','102859','101750','573008','102858'))
		THEN '包材领料单' 
		WHEN (SELECT TOP 1  p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='1'
		THEN '成品领料单'
		WHEN (SELECT TOP 1 p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='2'
		THEN '半成品领料单'
		WHEN (SELECT TOP 1 p.ProductClassify FROM dbo.PickingListItem AS pli2 INNER JOIN dbo.Product AS p ON p.ProductId = pli2.ProductId WHERE pli2.PickingListId=PickingList.PickingListId)='3'
		THEN '原材料领料单'
		END AS '领料类型',
		PickingListType+' '+BillType.BillTypeDescription  AS PickingListType,
		ISNULL(FactoryName,'') AS FactoryName,
		m.ProductLine,
				CAST(CONVERT(NVARCHAR(10),PickingList.CreateDate,23)AS NVARCHAR(10)) AS Date,
			CONVERT(NVARCHAR(50),PickingList.CreateDate,24) AS CreateTime,
		PickingList.CreateDate
	FROM         dbo.PickingList
	INNER JOIN (SELECT FactoryId
				FROM dbo.Factory_User
				WHERE UserId=@I_OrBitUserId
				)tempFactory ON tempFactory.FactoryId = PickingList.FactoryId
	LEFT JOIN dbo.Factory ON Factory.FactoryId = PickingList.FactoryId
	LEFT JOIN dbo.BillStates_Table('PickingListPR')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
	LEFT JOIN dbo.PickingList_MO AS plm ON plm.PickingListId = PickingList.PickingListId
	LEFT JOIN dbo.MO AS m ON m.MOId = plm.MOId
		LEFT JOIN dbo.BillType_Table('PickingListPR') BillType ON PickingListType = BillType.BillTypeName
	WHERE PickingListClass='01' 
	AND PickingList.CreateDate>GETDATE()-55
	ORDER BY PickingList.CreateDate DESC

	RETURN 0
END
go

