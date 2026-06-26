-- =============================================
-- Author:        <OrBit Team>
-- Create date:   <2026/06/15>
-- Description:   <D点检验查询：查询待检测状态的检验单及其子表和扩展信息>
-- Rev: 1.00
-- =============================================
CREATE PROCEDURE [dbo].[Txn_QC_DPointInspectionQuery]
    @FactoryId CHAR(12) = '',           -- 工厂ID（可选）
    @WorkcenterId CHAR(12) = '',        -- 仓库ID（可选）
    @MOId CHAR(12) = '',                -- 工单ID（可选）
    @StartDate DATETIME = NULL,         -- 开始日期（可选）
    @EndDate DATETIME = NULL,           -- 结束日期（可选）
    @I_ReturnMessage NVARCHAR(MAX) = '' OUTPUT  -- 返回信息
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    -- 通用变量
    DECLARE @Enter VARCHAR(2) = CHAR(13) + CHAR(10);
    SET @I_ReturnMessage = '';

    BEGIN TRY
        -- 查询待检测状态的检验单，关联子表和扩展信息
        SELECT 
            pi.QC_ProcessInsId,
            pi.InsName,
            pi.InsStates,
            pi.MOId,
            pi.FactoryId,
            pi.WorkcenterId,
            pi.Inspector,
            pi.InsDate,
            pi.SubmissQty,
            pi.TotalDefectQty,
            pi.CreateDate,
            pi.CreateUser,
            -- 关联查询子表数据（JSON格式）
            (SELECT 
                 i.QC_ProcessIns_ItemId,
                 i.ItemName,
                 i.ItemResult,
                 i.InspectionQty,
                 i.DefectTotal,
                 i.ItemSTDValue,
                 i.ItemMaxValue,
                 i.ItemMinValue
             FROM QC_ProcessIns_Item i 
             WHERE i.QC_ProcessInsId = pi.QC_ProcessInsId
             FOR JSON PATH) AS Items,
            -- 关联查询扩展信息（JSON格式）
            (SELECT 
                 e.ErrorReasons,
                 e.ProductTestTime
             FROM ZR_QC_ProcessIns_Extend e 
             WHERE e.QC_ProcessInsId = pi.QC_ProcessInsId
             FOR JSON PATH) AS ExtendInfo
        FROM QC_ProcessIns pi
        WHERE pi.InsStates = '10'  -- 待检测状态
          AND (@FactoryId = '' OR pi.FactoryId = @FactoryId)
          AND (@WorkcenterId = '' OR pi.WorkcenterId = @WorkcenterId)
          AND (@MOId = '' OR pi.MOId = @MOId)
          AND (@StartDate IS NULL OR pi.CreateDate >= @StartDate)
          AND (@EndDate IS NULL OR pi.CreateDate <= @EndDate)
        ORDER BY pi.CreateDate DESC;

        SET @I_ReturnMessage = '查询成功';
        RETURN 0;
    END TRY
    BEGIN CATCH
        SET @I_ReturnMessage = '查询失败: ' + ERROR_MESSAGE();
        RETURN -1;
    END CATCH
END
GO