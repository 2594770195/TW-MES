SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		<OrBit Team>
-- Create date:	<2026-06-03>
-- Description:	WebAPI 接口-CreatePickingListOtherFromWMS 杂发单从WMS回传创建
-- =============================================
CREATE PROCEDURE [dbo].[WebAPI_CreatePickingListOtherFromWMS]
    @OrBitUserName NVARCHAR(100)='',
    @ResourceName NVARCHAR(100)='',
    @UserParameter NVARCHAR(MAX)='',
    @UserData NVARCHAR(MAX)='',
    @MOName NVARCHAR(50) = '',
    @Qty INT = 0,
    @Body NVARCHAR(MAX) = ''
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

    -- =============================================
    -- 1. 声明变量
    -- =============================================
    DECLARE @JsonString NVARCHAR(MAX)=''
    DECLARE @JsonResult NVARCHAR(MAX)
    DECLARE @I_ReturnMessage NVARCHAR(MAX)=''
    DECLARE @return_Value INT=-1
    DECLARE @returnResult INT=-1
    DECLARE @UploadIngId CHAR(12)=''
    DECLARE @Enter NVARCHAR(10)=CHAR(13)+CHAR(10)

    -- 业务变量
    DECLARE @PickingListId CHAR(12)=''
    DECLARE @PickingListOtherName NVARCHAR(50)=''
    DECLARE @FactoryId CHAR(12)=''
    DECLARE @FactoryName NVARCHAR(50)=''
    DECLARE @DivisionId CHAR(12)=''
    DECLARE @RequiredDate DATETIME=GETDATE()
    DECLARE @NowDate DATETIME=GETDATE()
    DECLARE @PickingListDescription NVARCHAR(100)=''

    -- JSON解析变量
    DECLARE @DocCode NVARCHAR(50)=''
    DECLARE @ReqPickingListOtherName NVARCHAR(50)=''
    DECLARE @CostCenterId NVARCHAR(50)=''
    DECLARE @OrderName NVARCHAR(50)=''
    DECLARE @ProductName NVARCHAR(50)=''
    DECLARE @LotSN NVARCHAR(100)=''
    DECLARE @BoxSN NVARCHAR(100)=''
    DECLARE @PickingQty DECIMAL(18,8)=0
    DECLARE @WareHouseName NVARCHAR(50)=''
    DECLARE @ReqFactoryName NVARCHAR(50)=''

    -- 物料与仓库查询结果
    DECLARE @ProductId CHAR(12)=''
    DECLARE @ProductClassify CHAR(10)=''
    DECLARE @UsageUOMId CHAR(12)=''
    DECLARE @WareHouseId CHAR(12)=''
    DECLARE @ItemPKId CHAR(12)=''

    -- 固定值
    DECLARE @FixedPickingUser NVARCHAR(50)='WMS'

    -- =============================================
    -- 2. 接收请求并记录日志
    -- =============================================
    SET @JsonString = @Body

    EXEC SysGetObjectPKId '', 'UploadIngId', @UploadIngId OUTPUT
    INSERT INTO zr_edlog_wms (Type, InputParams, OutputParams, UploadIngId)
    VALUES ('PICKINGLISTOTHER', @Body, @I_ReturnMessage, @UploadIngId)

    -- =============================================
    -- 3. JSON非空校验
    -- =============================================
    IF ISNULL(@JsonString,'')=''
    BEGIN
        SET @I_ReturnMessage='ServerMessage:[MES]:输入Json字符串不允许为空！'
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    -- =============================================
    -- 4. 解析JSON
    -- =============================================
    SET @DocCode=JSON_VALUE(@JsonString,'$.DOC_CODE')
    SET @ReqPickingListOtherName=JSON_VALUE(@JsonString,'$.PickingListOtherName')
    SET @CostCenterId=JSON_VALUE(@JsonString,'$.CostCenterId')
    SET @OrderName=JSON_VALUE(@JsonString,'$.OrderName')
    SET @ProductName=JSON_VALUE(@JsonString,'$.ProductName')
    SET @LotSN=JSON_VALUE(@JsonString,'$.LotSN')
    SET @BoxSN=JSON_VALUE(@JsonString,'$.BoxSN')
    SET @PickingQty=TRY_CAST(JSON_VALUE(@JsonString,'$.Qty') AS DECIMAL(18,8))
    SET @WareHouseName=JSON_VALUE(@JsonString,'$.WareHouse')
    SET @ReqFactoryName=JSON_VALUE(@JsonString,'$.Factory')

    -- =============================================
    -- 5. 基础校验
    -- =============================================
    -- 5.1 单据类型校验
    IF ISNULL(@DocCode,'')<>'PICKINGLISTOTHER'
    BEGIN
        SET @I_ReturnMessage='校验失败：单据类型不是PICKINGLISTOTHER；'
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    -- 5.2 成本中心非空校验（WMS传入，必填）
    IF ISNULL(@CostCenterId,'')=''
    BEGIN
        SET @I_ReturnMessage='校验失败：成本中心CostCenterId不能为空；'
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    -- 5.3 物料编码非空校验
    IF ISNULL(@ProductName,'')=''
    BEGIN
        SET @I_ReturnMessage='校验失败：物料编码ProductName不能为空；'
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    -- 5.4 数量校验
    IF ISNULL(@PickingQty,0)<=0
    BEGIN
        SET @I_ReturnMessage='校验失败：杂发数量必须大于0；'
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    -- 5.5 批次/箱号非空校验（至少有一个）
    IF ISNULL(@LotSN,'')='' AND ISNULL(@BoxSN,'')=''
    BEGIN
        SET @I_ReturnMessage='校验失败：批次号LotSN或箱号BoxSN至少填写一个；'
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    -- =============================================
    -- 6. 物料存在性与成品限制校验
    -- =============================================
    SELECT @ProductId=p.ProductId, @ProductClassify=p.ProductClassify, @UsageUOMId=pr.UsageUOMId
    FROM dbo.Product p
    INNER JOIN dbo.ProductRoot pr ON pr.ProductRootId=p.ProductRootId
    WHERE pr.ProductName=@ProductName

    IF ISNULL(@ProductId,'')=''
    BEGIN
        SET @I_ReturnMessage='校验失败：物料编码【'+@ProductName+'】在MES系统中不存在；'
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    IF @ProductClassify='1'
    BEGIN
        SET @I_ReturnMessage='校验失败：物料【'+@ProductName+'】是成品，不能使用杂发功能；'
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    -- =============================================
    -- 7. 工厂与仓库校验
    -- =============================================
    IF ISNULL(@ReqFactoryName,'')='' OR ISNULL(@WareHouseName,'')=''
    BEGIN
        SET @I_ReturnMessage='校验失败：工厂Factory和仓库WareHouse不能为空；'
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    SELECT @FactoryId=FactoryId FROM dbo.Factory WHERE FactoryName=@ReqFactoryName
    IF ISNULL(@FactoryId,'')=''
    BEGIN
        SET @I_ReturnMessage='校验失败：工厂【'+@ReqFactoryName+'】在MES系统中不存在；'
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    SELECT @WareHouseId=WorkcenterId FROM dbo.Workcenter WHERE WorkcenterName=@WareHouseName AND FactoryId=@FactoryId
    IF ISNULL(@WareHouseId,'')=''
    BEGIN
        SET @I_ReturnMessage='校验失败：仓库【'+@WareHouseName+'】在工厂【'+@ReqFactoryName+'】下不存在；'
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    -- =============================================
    -- 8. 单据防重校验（若传入单号则校验是否存在）
    -- =============================================
    IF ISNULL(@ReqPickingListOtherName,'')<>''
    BEGIN
        IF EXISTS(SELECT 1 FROM dbo.PickingList WHERE PickingListName=@ReqPickingListOtherName)
        BEGIN
            SET @I_ReturnMessage='校验失败：杂发单【'+@ReqPickingListOtherName+'】已存在，不可重复创建；'
            SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
            SELECT @JsonResult AS JsonResult
            UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
            RETURN -1
        END
    END

    -- =============================================
    -- 9. 生成单据号（若WMS未传入则MES自动生成）
    -- =============================================
    EXEC SysGetObjectPKId '','PickingList',@PickingListId OUTPUT

    IF ISNULL(@ReqPickingListOtherName,'')<>''
        SET @PickingListOtherName=@ReqPickingListOtherName
    ELSE
    BEGIN
        -- 使用系统默认编号规则生成
        DECLARE @AutoBillNo NVARCHAR(50)=''
        SET @AutoBillNo='WMS'+REPLACE(CONVERT(VARCHAR(8),GETDATE(),112),'-','')+RIGHT('00000'+CAST(CAST(RAND()*100000 AS INT) AS VARCHAR),5)
        SET @PickingListOtherName=@AutoBillNo
    END

    -- =============================================
    -- 10. 创建杂发单主表
    -- =============================================
    SELECT @DivisionId=Division FROM dbo.SysUser WHERE UserId='WMS'
    IF ISNULL(@DivisionId,'')='' SET @DivisionId=''

    SET @PickingListDescription='WMS杂发 领料人：'+@FixedPickingUser

    BEGIN TRANSACTION Request

    EXEC @returnResult=PickingListOtherSaveData
        @I_ReturnMessage=@I_ReturnMessage OUTPUT,
        @I_OrBitUserId='WMS',
        @I_OrBitUserName=N'WMS',
        @I_PKId=@PickingListId,
        @PickingListDescription=@PickingListDescription,
        @FactoryId=@FactoryId,
        @DateRequired=@RequiredDate,
        @DivisionId=@DivisionId

    IF ISNULL(@returnResult,0)<>0
    BEGIN
        ROLLBACK TRANSACTION Request
        SET @I_ReturnMessage='杂发单主表创建失败：'+@I_ReturnMessage
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    -- 更新主表状态为已审核
    UPDATE dbo.PickingList
    SET PickingListStates='20',
        ApproveDate=@NowDate,
        ApproveUserId='WMS',
        PickingListName=@PickingListOtherName
    WHERE PickingListId=@PickingListId

    -- =============================================
    -- 11. 生成杂发单明细
    -- =============================================
    EXEC SysGetObjectPKId '','PickingListItem',@ItemPKId OUTPUT

    INSERT INTO dbo.PickingListItem(
        PickingListItemId,
        PickingListId,
        ItemSequence,
        ProductId,
        QtyRequired,
        UOMId,
        CostCenterId,
        OrderName
    ) VALUES (
        @ItemPKId,
        @PickingListId,
        '0001',
        @ProductId,
        @PickingQty,
        @UsageUOMId,
        @CostCenterId,
        @OrderName
    )

    -- =============================================
    -- 12. 批次下架（逐条调用PDA_MaterialToPickingListOther）
    -- =============================================
    DECLARE @BoxOrLotSN NVARCHAR(100)=''
    -- 优先使用箱号，其次批次号
    IF ISNULL(@BoxSN,'')<>''
        SET @BoxOrLotSN=@BoxSN
    ELSE
        SET @BoxOrLotSN=@LotSN

    EXEC @returnResult=PDA_MaterialToPickingListOther
        @I_ReturnMessage=@I_ReturnMessage OUTPUT,
        @I_OrBitUserId='WMS',
        @I_OrBitUserName=N'WMS',
        @I_PKId=@PickingListId,
        @PickingListName=@PickingListOtherName,
        @BoxOrLotSN=@BoxOrLotSN

    IF ISNULL(@returnResult,0)<>0
    BEGIN
        ROLLBACK TRANSACTION Request
        SET @I_ReturnMessage='批次下架失败：'+@I_ReturnMessage
        SELECT @JsonResult=(SELECT CAST(0 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        SELECT @JsonResult AS JsonResult
        UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId
        RETURN -1
    END

    COMMIT TRANSACTION Request

    -- =============================================
    -- 13. 自动确认杂发单（不管是否成功不影响返回）
    -- =============================================
    DECLARE @ConfirmReturn INT=0
    DECLARE @ConfirmMessage NVARCHAR(MAX)=''

    EXEC @ConfirmReturn=dbo.TxnBase_MBill_PickingListConfirm
        @I_Sender='WMS自动确认',
        @I_ReturnMessage=@ConfirmMessage OUTPUT,
        @I_PlugInCommand='',
        @I_OrBitUserId='WMS',
        @I_OrBitUserName=N'WMS',
        @I_ResourceId='',
        @I_ResourceName='',
        @I_Parameter='',
        @PickingListName=@PickingListOtherName

    -- =============================================
    -- 14. 返回结果
    -- =============================================
    IF @ConfirmReturn<>0
        SET @I_ReturnMessage='杂发单【'+@PickingListOtherName+'】创建成功，但自动确认失败，请手动到杂发单页面重新过账。确认失败原因：'+@ConfirmMessage
    ELSE
        SET @I_ReturnMessage='杂发单【'+@PickingListOtherName+'】创建并确认成功！'

    SELECT @JsonResult=(SELECT CAST(1 AS BIT) AS result, @I_ReturnMessage AS message FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    SELECT @JsonResult AS JsonResult
    UPDATE dbo.zr_edlog_wms SET OutputParams=@JsonResult WHERE UploadIngId=@UploadIngId

    RETURN 0
END
GO
