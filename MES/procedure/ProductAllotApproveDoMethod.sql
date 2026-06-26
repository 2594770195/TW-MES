SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		<OrBit Team benson>
-- Create date: <2018.03.19>
-- Description:	调拨单-审核
-- =============================================
CREATE PROCEDURE  [dbo].[ProductAllotApproveDoMethod]
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
@I_Parameter NVARCHAR(100)=''		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.


AS
BEGIN 

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON; 
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	DECLARE @ProductAllotId CHAR(12)
	DECLARE @ProductAllotStates VARCHAR(10)
	DECLARE @StatesName VARCHAR(10)
	DECLARE @StateDesc NVARCHAR(50)
	DECLARE @ProductAllotName NVARCHAR(50)
	DECLARE @ParameterValueEx NVARCHAR(200)
	DECLARE @return_value INT 

    DECLARE @FromFactoryId NVARCHAR(50)
    DECLARE @FromWareHouseId NVARCHAR(50)
    DECLARE @ToFactoryId NVARCHAR(50)
    DECLARE @ToWareHouseId NVARCHAR(50)

	SET @ProductAllotId=''
	SET @ProductAllotStates=''
	SET @StatesName=''
	SET @StateDesc=''
	SET @ProductAllotName=''
	SET @ParameterValueEx=''
	SET @return_value= -1

	IF ISNULL(@I_PKid,'')=''
	BEGIN
		SET @I_ReturnMessage='ServerMessage:请选择有效行项.'
		RETURN -1
	END

	---查询状态
	SELECT 
		@ProductAllotId=ProductAllotId,
		@ProductAllotStates=ProductAllotStates,
		@ProductAllotName=ProductAllotName,
        @FromFactoryId=FactoryId,
        @FromWareHouseId=WorkcenterId,
        @ToFactoryId=ToFactoryId,
        @ToWareHouseId=ToWorkcenterId
	FROM ProductAllot 
	WHERE ProductAllotId=@I_PKid

	SELECT     
		@StatesName=BillStates.BillStatesName,
		@StateDesc=BillStates.BillStatesDescription
	FROM	Bill 
	INNER JOIN BillStates ON Bill.BillId =BillStates.BillId
	WHERE Bill.BillName = N'ProductAllot' AND BillStates.BillStatesName=@ProductAllotStates
	AND IsERP=0

	--非“已创建”“待审核”状态，不允许审核操作
	IF @ProductAllotStates NOT IN ('10')
	BEGIN
		SET @I_ReturnMessage ='ServerMessage:此单据当前状态 ['+@StateDesc+'] 不允许审核操作！'
		RETURN -1
	END

	---执行审核
	UPDATE ProductAllot SET 
		ProductAllotStates='20', 
		ApproveUserId = @I_OrBitUserId, 
		ApproveDate = GETDATE() 
	WHERE ProductAllotId=@I_PKid

    --有原仓库和目标仓库则调用WMS发货单，没有原仓库则调用WMS发货通知
	IF ISNULL(@FromFactoryId,'')<>'' AND ISNULL(@FromWareHouseId,'')<>'' AND ISNULL(@ToFactoryId,'')<>'' AND ISNULL(@ToWareHouseId,'')<>''
    BEGIN
            EXEC @return_value = dbo.APISyncU_ProductAllotToWMS_Dos @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
											 @ItemName = N'U_WMSProductAllot_DOs',                            -- nvarchar(50)
											 @ProductAllotName = @ProductAllotName                      -- nvarchar(50)

    END
    ELSE IF ISNULL(@ToFactoryId,'')<>'' AND ISNULL(@ToWareHouseId,'')<>''
    BEGIN
        EXEC @return_value = dbo.APISyncU_ProductAllotToWMS @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
											 @ItemName = N'U_WMSProductAllot',                            -- nvarchar(50)
											 @ProductAllotName = @ProductAllotName                      -- nvarchar(50)
    END 
    ELSE 
    BEGIN
        SET @I_ReturnMessage ='ServerMessage:目标仓库不能为空！'
		RETURN -1
    END
    

	IF @return_value<>0
	BEGIN
		UPDATE dbo.ProductAllot SET 
					ProductAllotStates='10'
		WHERE ProductAllotId=@ProductAllotId 
		SET @I_ReturnMessage ='ServerMessage:审核失败！通知WMS失败，失败信息【'+@I_ReturnMessage+'】'
		RETURN -1
	END;
	ELSE
    BEGIN
        -- 接口内部修改
		-- UPDATE dbo.ProductAllot SET 
		-- 			ProductAllotStates='20'
		-- WHERE ProductAllotId=@ProductAllotId 
		SET @I_ReturnMessage ='ServerMessage:审核完成！通知WMS成功,成功信息【'+@I_ReturnMessage+'】'
		RETURN 0
	END;

   SET @I_ReturnMessage ='ServerMessage:审核完成.'

   RETURN 0
END






GO
