

-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/04/08 09:20:22:4224>
-- Description:   <领料单类型：生产、杂发、委外、外协>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE [dbo].[PickingListType_ViewListPK] 
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKId char(12)='',				--主键ID
@I_ParentPKId char(12)='',			--父元对象主键ID
@QueryParameter nvarchar(100)=''
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
 
	--生产领料单
	IF @I_PlugInCommand='PLPR'
	BEGIN
    	SELECT BillTypeName+' '+BillTypeDescription AS PickingListType,
			   BillTypeName AS PickingListTypeCode
		FROM dbo.Bill
		INNER JOIN dbo.BillType ON BillType.BillId = Bill.BillId
		WHERE BillName='PickingListPR'

		RETURN 0
	END

	--杂发单
	IF @I_PlugInCommand='PLOT'
	BEGIN
    	SELECT BillTypeName+' '+BillTypeDescription AS PickingListType,
			   BillTypeName AS PickingListTypeCode
		FROM dbo.Bill
		INNER JOIN dbo.BillType ON BillType.BillId = Bill.BillId
		WHERE BillName='PickingListOther'

		RETURN 0
	END

	--委外领料单
	IF @I_PlugInCommand='PLOS'
	BEGIN
    	SELECT BillTypeName+' '+BillTypeDescription AS PickingListType,
			   BillTypeName AS PickingListTypeCode
		FROM dbo.Bill
		INNER JOIN dbo.BillType ON BillType.BillId = Bill.BillId
		WHERE BillName='PickingListOM'

		RETURN 0
	END

	--外协领料单
	IF @I_PlugInCommand='PLPO'
	BEGIN
    	SELECT BillTypeName+' '+BillTypeDescription AS PickingListType,
			   BillTypeName AS PickingListTypeCode
		FROM dbo.Bill
		INNER JOIN dbo.BillType ON BillType.BillId = Bill.BillId
		WHERE BillName='PickingListPO'

		RETURN 0
	END
	

	SELECT '' AS PickingListType,
		   '' AS PickingListTypeCode
END


go

