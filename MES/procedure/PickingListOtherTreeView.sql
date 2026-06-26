-- =============================================
-- Author:		<Gavin>
-- Create date: <03  2 2012 10:18AM>
-- Description:	为PickingList创建导航树视图
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListOtherTreeView]
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


		--根据查询条件获取
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
			WHERE PickingListName=@PickingListName AND PickingListClass='02'
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
			AND PickingListClass='02'
			ORDER BY CreateDate DESC
		END


		SELECT
			PickingList.PickingListId, 
			PickingListName,
			PickingList.PickingListStates+' '+ISNULL(BillState.BillStatesDescription,'') AS PickingListStates,
			FactoryName,
			PickingList.CreateDate,SAPInfor
		FROM @Table A
		INNER JOIN dbo.PickingList ON PickingList.PickingListId = A.PickingListId
		INNER JOIN (SELECT FactoryId
					FROM dbo.Factory_User
					WHERE UserId=@I_OrBitUserId
					)tempFactory ON tempFactory.FactoryId = PickingList.FactoryId
		LEFT JOIN dbo.Factory ON Factory.FactoryId = PickingList.FactoryId
		LEFT JOIN dbo.BillStates_Table('PickingListOther')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
		ORDER BY PickingList.CreateDate DESC

		RETURN 0
	END



	IF @I_PKId<>''
	BEGIN
		SELECT     
			PickingListId, 
			PickingListName,
			PickingList.PickingListStates+' '+ISNULL(BillState.BillStatesDescription,'') AS PickingListStates,
			FactoryName,
			PickingList.CreateDate,SAPInfor
			--SysUser.UserDescription
		FROM         dbo.PickingList
		LEFT JOIN dbo.Factory ON Factory.FactoryId = PickingList.FactoryId
		LEFT JOIN dbo.BillStates_Table('PickingListOther')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
		--inner join SysUser on SysUser.UserId=PickingList.ConfirmUserId
		WHERE PickingListId=@I_PKId 
		ORDER BY PickingList.CreateDate DESC

		RETURN 0
	END
	

	SELECT 
		PickingListId, 
		PickingListName,
		PickingList.PickingListStates+' '+ISNULL(BillState.BillStatesDescription,'') AS PickingListStates,
		FactoryName,
		PickingList.CreateDate,
		CASE WHEN ISNULL(ui.MatDoc,'')<>'' THEN ui.MatDoc COLLATE Chinese_PRC_CI_AS_KS ELSE SAPInfor END  AS  SAPInfor
		--SysUser.UserDescription

	FROM         dbo.PickingList
	INNER JOIN (SELECT FactoryId
				FROM dbo.Factory_User
				WHERE UserId=@I_OrBitUserId
				)tempFactory ON tempFactory.FactoryId = PickingList.FactoryId
	LEFT JOIN dbo.Factory ON Factory.FactoryId = PickingList.FactoryId
	LEFT JOIN dbo.BillStates_Table('PickingListOther')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
	LEFT JOIN dbo.UploadIng AS ui ON ui.UploadDateId=PickingListId AND ISNULL(ui.MatDoc,'')<>''
	--inner join SysUser on SysUser.UserId=PickingList.ConfirmUserId
	WHERE PickingListClass='02' 
	--and PickingList.CreateDate>getdate()-366
	ORDER BY PickingList.CreateDate DESC

	RETURN 0
END
go

