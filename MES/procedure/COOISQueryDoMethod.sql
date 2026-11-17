SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		
-- Create date: <2026.10.15>
-- Description:	COOIS--SAP模块移植至MES
-- =============================================
CREATE PROC [dbo].[COOISQueryDoMethod]
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
@I_Parameter NVARCHAR(100)='',		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.

@FactoryName NVARCHAR(100)='',
@ProductName NVARCHAR(100)='',
@MoName NVARCHAR(100)=''


AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

    -- =============================================
    -- 报表 COOIS：工单组件（物料需求）明细清单
    -- 数据库：OrBitMOM（生产库）/ OrBitMOMTestBack_WMSQAS（开发库）
    -- 行粒度：工单(MO) + 工单物料行(MOItem)
    -- 说明：
    --   1) 订单    = MO.MOName。
    --   2) 物料    = 工单物料行物料的编号 ProductRoot.ProductName（经 Product.ProductRootId 关联）。
    --   3) BOM 项目 = MOItem.SAPLineSequence（SAP 项目行号），无值时用空串兜底。
    --   4) 需求日期 = MO.PlannedDateFrom（工单计划开始日期），格式化为 dd.mm.yyyy（SAP 展示格式）。
    --   5) 需求数   = MOItem.ItemQtyRequired（工单物料行需求数量）。
    --   6) 撤回数   = 领料数 = MOItem.ItemQtyIssued（已领用数量），无值时按 0 展示。
    --   7) 单位     = UOM.UOMName（经 MOItem.UOMId 关联），物料未设单位时为空串。
    --   8) 物料描述 = Product.ProductDescription。
    --   9) 工厂     = Factory.FactoryName。
    --  10) 批次 = MOItem.ProductionLotNO；项目 = MOItem.SAPLineSequence（同 BOM 项目行号）。
    --  11) 过滤：排除已逻辑删除的工单与物料行；排除工单占位物料行(LineSequence='000')。
    --      —— 此处未限定工单状态；如需只看未完工工单，可追加 AND mo.MOStates='20'。
    --  12) 入参过滤：@ProductName(物料编号)、@MoName(工单号) 至少有一个有值，否则直接返回提示；
    --      传入的参数一律按等值过滤，未传(@='')的维度不过滤；@FactoryName 同理可不传。
    -- =============================================

    -- 【入参校验】物料编号与工单号必须至少有一个有值，避免无条件全表扫描
    IF LTRIM(RTRIM(ISNULL(@ProductName, ''))) = ''
       AND LTRIM(RTRIM(ISNULL(@MoName, ''))) = ''
    BEGIN
        SET @I_ReturnMessage = N'查询条件不足：物料编号(@ProductName)与工单号(@MoName)至少填写一个。'
        SELECT @I_ReturnMessage
        RETURN 0
    END

    SELECT
        mo.MOName                                            AS 订单,       -- 工单号
        pr.ProductName                                       AS 物料,       -- 物料编号
        ISNULL(mi.SAPLineSequence, '')                       AS [BOM 项目], -- SAP 项目行号
        -- 【需求日期】工单计划开始日期，格式化为 dd.mm.yyyy；为空时不展示
        CASE WHEN mo.PlannedDateFrom IS NULL THEN ''
            ELSE CONVERT(varchar(10), mo.PlannedDateFrom, 104) END AS 需求日期,
        CONVERT(decimal(18, 6), ISNULL(mi.ItemQtyRequired, 0)) AS 需求数,    -- 需求数量
        CONVERT(decimal(18, 6), ISNULL(mi.ItemQtyIssued, 0))   AS 撤回数,    -- 领料数（已领用数量）
        ISNULL(u.UOMName, '')                                AS 单位,       -- 计量单位
        ISNULL(p.ProductDescription, '')                     AS 物料描述,   -- 物料描述
        mi.ProductionLotNO                                   AS 批次,       -- 批次
        mi.SAPLineSequence                                                   AS 项目,       -- 项目（暂占位）
        f.FactoryName                                        AS 工厂        -- 工厂名称
    FROM dbo.MO mo
        -- 【关联】工单 → 工单物料行 → 物料 → 物料编号 / 描述
        INNER JOIN dbo.MOItem mi      ON mi.MOId = mo.MOId
        INNER JOIN dbo.Product p      ON p.ProductId = mi.ProductId
        INNER JOIN dbo.ProductRoot pr ON pr.ProductRootId = p.ProductRootId
        -- 【关联】工单 → 工厂
        INNER JOIN dbo.Factory f      ON f.FactoryId = mo.FactoryId
        -- 【关联】计量单位（物料未设单位时保留该行，单位显示空串）
        LEFT JOIN  dbo.UOM u          ON u.UOMId = mi.UOMId
    -- 【过滤】排除已逻辑删除的工单与物料行，排除工单占位物料行
    WHERE ISNULL(mo.DeleteFlag, '') <> '1'
    AND ISNULL(mi.DeleteFlag, '') <> '1'
    AND ISNULL(mi.LineSequence, '') <> '000'
    -- 【入参过滤】未传(@='' 或 NULL)的维度不过滤；传入则按等值匹配（两侧去空格后比较）
    AND (ISNULL(@FactoryName, '') = '' OR f.FactoryName  = LTRIM(RTRIM(@FactoryName)))
    AND (ISNULL(@ProductName, '') = '' OR pr.ProductName = LTRIM(RTRIM(@ProductName)))
    AND (ISNULL(@MoName, '')      = '' OR mo.MOName      = LTRIM(RTRIM(@MoName)))
    -- 如需仅统计未完工(已审核/在制)工单，取消下一行注释
    --  AND mo.MOStates = '20'
    ORDER BY mo.MOName, mi.SAPLineSequence, mi.LineSequence


    select @I_ReturnMessage
	RETURN 0
		
	
END
GO
