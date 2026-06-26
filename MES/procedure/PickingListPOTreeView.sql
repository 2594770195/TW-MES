
-- =============================================
-- Author:		<HH0102 Orbchay>
-- Create date: <04  07 2021 10:18AM>
-- Description:	为PickingList创建导航树视图
-- Revision: 1.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListPOTreeView]
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
@POName NVARCHAR(50)='',
@StartDate DATETIME=NULL,
@EndDate DATETIME=NULL
AS
BEGIN
	-- This Stored Procedure is created by OrBit-MetaObject engine	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--执行TreeView,注意：以下过程必须根据业务的需求进行调整
	--如果您不了解TreeView过程如何编写，请参考我们提供的示例_SampleProjectTreeView

	DECLARE @IsVendorUser BIT=0 --是否供应商用户

	SELECT 
		@IsVendorUser = ISNULL(SysUser.IsVendorUser,0)
	FROM SysUser 
	WHERE SysUser.UserId = @I_OrBitUserId

	--DB搜索;UPDATE;orbchay,HH0102;2020/12/31 11:40:07:0098
	IF @I_IsDBSerch=1
	BEGIN
		DECLARE @POId CHAR(12)=''
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
			IF @IsVendorUser =1
			BEGIN 
				INSERT INTO @Table
					 (
						 PickingListId
					 )
				SELECT PickingListId
				FROM dbo.PickingList
				INNER JOIN (SELECT VendorId
							FROM dbo.Vendor_User WHERE UserId=@I_OrBitUserId
							)tempVendor_User ON tempVendor_User.VendorId = PickingList.VendorId
				WHERE PickingListName=@PickingListName AND PickingListClass='04'
			END
			ELSE
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
				WHERE PickingListName=@PickingListName AND PickingListClass='04'
			END
		END
		ELSE IF ISNULL(@POName,'')<>''
		BEGIN
			SELECT @POId=POId
			FROM dbo.PO
			WHERE POName=@POName

			IF ISNULL(@POId,'')<>''
			BEGIN 
				IF @IsVendorUser =1
				BEGIN 
					INSERT INTO @Table
						 (
							 PickingListId
						 )
					SELECT DISTINCT PickingList.PickingListId
					FROM dbo.PickingList
					INNER JOIN (SELECT VendorId
								FROM dbo.Vendor_User WHERE UserId=@I_OrBitUserId
								)tempVendor_User ON tempVendor_User.VendorId = PickingList.VendorId
					INNER JOIN dbo.PickingListItem ON PickingListItem.PickingListId = PickingList.PickingListId
					WHERE POId=@POId AND PickingListClass='04'
				END
				ELSE
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
					WHERE POId=@POId AND PickingListClass='04'
				END
			END
		END
		ELSE IF @StartDate IS NOT NULL
		BEGIN
			IF @IsVendorUser =1
			BEGIN 
				INSERT INTO @Table
						(
							PickingListId
						)
				SELECT TOP 10000 PickingListId 
				FROM dbo.PickingList
				INNER JOIN (SELECT VendorId
							FROM dbo.Vendor_User WHERE UserId=@I_OrBitUserId
							)tempVendor_User ON tempVendor_User.VendorId = PickingList.VendorId
				WHERE CreateDate>=@StartDate AND CreateDate<=@EndDate
				AND PickingListClass='04'
				ORDER BY CreateDate DESC
			END
			ELSE
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
				AND PickingListClass='04'
				ORDER BY CreateDate DESC
			END
		END


		SELECT 
			PickingList.PickingListId, 
			PickingListName,
			PickingList.PickingListStates+' '+ISNULL(BillState.BillStatesDescription,'') AS PickingListStates,
			FactoryName,
			PickingList.CreateDate
		FROM @Table A
		INNER JOIN dbo.PickingList ON PickingList.PickingListId = A.PickingListId
		LEFT JOIN dbo.Factory ON Factory.FactoryId = PickingList.FactoryId
		LEFT JOIN dbo.BillStates_Table('PickingListPO')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
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
			PickingList.CreateDate
		FROM         dbo.PickingList
		LEFT JOIN dbo.Factory ON Factory.FactoryId = PickingList.FactoryId
		LEFT JOIN dbo.BillStates_Table('PickingListPO')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
		WHERE PickingListId=@I_PKId 
		ORDER BY PickingListName DESC

		RETURN 0
	END



	-- 供应商
	IF @IsVendorUser =1
	BEGIN
		SELECT TOP 500
			PickingListId, 
			PickingListName,
			PickingList.PickingListStates+' '+ISNULL(BillState.BillStatesDescription,'') AS PickingListStates,
			FactoryName,
			PickingList.CreateDate
		FROM         dbo.PickingList
		INNER JOIN (SELECT VendorId
					FROM dbo.Vendor_User WHERE UserId=@I_OrBitUserId
					)tempVendor_User ON tempVendor_User.VendorId = PickingList.VendorId
		LEFT JOIN dbo.Factory ON Factory.FactoryId = PickingList.FactoryId
		LEFT JOIN dbo.BillStates_Table('PickingListPO')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
		WHERE PickingListClass='04'
		ORDER BY PickingList.CreateDate DESC

		RETURN 0
	END
	

	SELECT TOP 500
		PickingListId, 
		PickingListName,
		PickingList.PickingListStates+' '+ISNULL(BillState.BillStatesDescription,'') AS PickingListStates,
		FactoryName,
		PickingList.CreateDate
	FROM dbo.PickingList
	INNER JOIN (SELECT FactoryId
				FROM dbo.Factory_User
				WHERE UserId=@I_OrBitUserId
				)tempFactory ON tempFactory.FactoryId = PickingList.FactoryId
	LEFT JOIN dbo.Factory ON Factory.FactoryId = PickingList.FactoryId
	LEFT JOIN dbo.BillStates_Table('PickingListPO')  BillState ON PickingListStates = BillState.BillStatesName AND BillState.IsERP=0
	WHERE PickingListClass='04'
	ORDER BY PickingList.CreateDate DESC

	RETURN 0
END





go

