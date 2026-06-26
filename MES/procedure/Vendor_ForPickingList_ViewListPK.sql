
-- =============================================
-- Author:		<OBit Team :Orbchay>
-- Create date: <2019.7.09>
-- Description:	<取得委外领料单的供应商清单>
-- Rev:1.00
-- =============================================
CREATE PROCEDURE [dbo].[Vendor_ForPickingList_ViewListPK]
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKId CHAR(12)='',				--主键ID
@I_ParentPKId CHAR(12)='',			--父元对象主键ID
@QueryParameter NVARCHAR(100)=''
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @IsVendorUser BIT=0

	SELECT 
		@IsVendorUser = SysUser.IsVendorUser 
	FROM SysUser 
	WHERE SysUser.UserId = @I_OrBitUserId 

	IF @IsVendorUser =1
	BEGIN
		SELECT  
			'' AS VendorId ,
			'' AS VendorName,
			'' AS VendorDescription
		UNION ALL
		SELECT    DISTINCT
			Vendor.VendorId ,
			Vendor.VendorShortName AS VendorName,
			Vendor.VendorDescription
		FROM    Vendor
		INNER JOIN Vendor_User ON Vendor.VendorId = Vendor_User.VendorId
		WHERE   ( Vendor_User.UserId = @I_OrBitUserId )
	END

	IF @IsVendorUser =0 
	BEGIN
		SELECT  
			'' AS VendorId ,
			'' AS VendorName,
			'' AS VendorDescription
		UNION ALL
		SELECT    DISTINCT
			Vendor.VendorId ,
			Vendor.VendorShortName AS VendorName,
			Vendor.VendorDescription
		FROM    Vendor
		INNER JOIN Vendor_User ON Vendor.VendorId = Vendor_User.VendorId
	END
    
	RETURN 0
END

go

