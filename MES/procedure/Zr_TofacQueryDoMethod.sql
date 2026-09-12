SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Irving>
-- Create date: <2025.02.06>
-- Description: <转厂记录查询>
-- =============================================
CREATE PROCEDURE [dbo].[Zr_TofacQueryDoMethod]
@I_Sender nvarchar(200)='',						--	客户端执行按钮
@I_ReturnMessage nvarchar(max)='' output,		--	返回的信息,支持多语言
@I_ExceptionFieldName nvarchar(100)='' output,	--	向客户端报告引起冲突的字段
@I_LanguageId char(1)='1',						--	客户端传入的语言ID
@I_PlugInCommand varchar(5)='',					--	插件命令
@I_OrBitUserId char(12)='',						--	用户ID
@I_OrBitUserName nvarchar(100)='',				--	用户名
@I_ResourceId	char(12)='',					--	资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',				--	资源名
@I_PKid char(12) ='',							--	主键
@I_ParentPKId char(12)='',						--	父级主键
@I_Parameter nvarchar(100)=''	,				--	插件参数

--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@ProudctionLotSN NVARCHAR(50) = '',
@ContainerCode NVARCHAR(50) = '',
@TProductName NVARCHAR(50) = '',
@ProductDescription NVARCHAR(50) = '',
@BeginCreateDate datetime = '',
@EndCreateDate datetime = ''
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	-- ========== 参数归一化：日期参数空字符串/NULL 统一视为"未填写" ==========
	-- 避免空字符串被隐式转换为 1900-01-01，导致只填写一个日期时过滤条件异常
	IF ISNULL(@BeginCreateDate, '') = '' SET @BeginCreateDate = NULL;
	IF ISNULL(@EndCreateDate, '') = '' SET @EndCreateDate = NULL;

	-- 如果开始时间和结束时间均未填写，则默认查询最近一年的数据
	IF @BeginCreateDate IS NULL AND @EndCreateDate IS NULL
	BEGIN
		SET @BeginCreateDate = DATEADD(YEAR, -1, GETDATE());
		SET @EndCreateDate = GETDATE();
	END

	-- 预先计算结束日期边界（结束日期次日零点），避免在 WHERE 中逐行重复计算
	-- 说明：@EndCreateDate 为 NULL 时结果也为 NULL，此时 WHERE 中通过 IS NULL 判断短路跳过
	DECLARE @EndDateExclusive datetime = DATEADD(DAY, 1, @EndCreateDate);

    if @I_Sender = 'TofacQuery'
        begin
--             select product.TProductName '产品名称',
--                product.ProductDescription '产品描述',
--                Tofac.PrintDate '打印日期',
--                mo.soname '销售单号',
--                ToFac.ProudctionLotSN '批次号',
--                Tofac.Barrelage '桶数',
--                ZR_ContainerCode.ContainerCode '容器码',
--                ZR_ContainerCodeDetails.CodeStatus '当前状态',
--                ZR_ContainerCodeDetails.num '数量',
--                ZR_ContainerCodeDetails.remark '备注',
--                SysUser.UserDescription '操作人',
--                ZR_ContainerCodeDetails.createDate '创建时间'
--                from ZR_ContainerCodeDetails
--             left join ZR_ToFac_ContainerCode on ZR_ContainerCodeDetails.ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ToFac_ContainerCodeID
--                     left join Tofac on Tofac.ToFacId = ZR_ToFac_ContainerCode.ToFacId
--                     left join ZR_ContainerCode on ZR_ToFac_ContainerCode.ZR_ContainerCodeID = ZR_ContainerCode.ZR_ContainerCodeID
--                     left join product on product.productid = tofac.ProductID
--                     left join SysUser on SysUser.UserId = ZR_ContainerCodeDetails.I_OrBitUserId
--                left join mo on mo.MOName = tofac.ProudctionLotSN
--             WHERE
--                 ( -- 如果 @ProudctionLotSN 为空，则不进行筛选
--                     @ProudctionLotSN = ''
--                     -- 检查是否匹配 tofac 表的 ProudctionLotSN
--                     OR ToFac.ProudctionLotSN = @ProudctionLotSN
--                     -- 检查是否匹配 mo 表的 soname
--                     OR mo.soname = @ProudctionLotSN
--                 )
--                 AND (@ContainerCode = '' OR ZR_ContainerCode.ContainerCode = @ContainerCode)
--                 AND (@TProductName = '' OR product.TProductName = @TProductName)
--                 AND (@ProductDescription = '' OR product.ProductDescription like '%' + @ProductDescription + '%')
--                 AND ToFac.ProudctionLotSN IS NOT NULL AND ToFac.ProudctionLotSN <> ''
--                 -- 开始日期条件
--                 AND (@BeginCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate >= CONVERT(DATETIME, @BeginCreateDate, 120))
--                 -- 结束日期条件，修改为小于第二天的开始时间
--                 AND (@EndCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate < DATEADD(DAY, 1, CONVERT(DATETIME, @EndCreateDate, 120)))
--             ;
            -- 分支1：匹配 ToFac.ProudctionLotSN
            SELECT 
                product.TProductName AS '产品名称',
                product.ProductDescription AS '产品描述',
                Tofac.PrintDate AS '打印日期',
                mo.soname AS '销售单号',
                ToFac.ProudctionLotSN AS '批次号',
                WorkcenterName AS '库位',
                Tofac.Barrelage AS '桶数',
                ZR_ContainerCode.ContainerCode AS '容器码',
                ZR_ContainerCodeDetails.CodeStatus AS '当前状态',
                ZR_ContainerCodeDetails.num AS '数量',
                ZR_ContainerCodeDetails.remark AS '备注',
                SysUser.UserDescription AS '操作人',
                ZR_ContainerCodeDetails.createDate AS '创建时间'
            FROM ZR_ContainerCodeDetails
            LEFT JOIN ZR_ToFac_ContainerCode 
                ON ZR_ContainerCodeDetails.ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ToFac_ContainerCodeID
            LEFT JOIN Tofac 
                ON Tofac.ToFacId = ZR_ToFac_ContainerCode.ToFacId
            LEFT JOIN ZR_ContainerCode 
                ON ZR_ToFac_ContainerCode.ZR_ContainerCodeID = ZR_ContainerCode.ZR_ContainerCodeID
            LEFT JOIN product 
                ON product.productid = tofac.ProductID
            LEFT JOIN SysUser 
                ON SysUser.UserId = ZR_ContainerCodeDetails.I_OrBitUserId
            LEFT JOIN mo 
                ON mo.MOName = tofac.ProudctionLotSN
            LEFT JOIN
                WW_RMInventory ON ZR_ToFac_ContainerCode.BoxLotSn = WW_RMInventory.lotsn
            LEFT JOIN
                Workcenter on Workcenter.WorkcenterId=WW_RMInventory.WorkcenterId
            WHERE
                (@ProudctionLotSN = '' OR ToFac.ProudctionLotSN = @ProudctionLotSN)
                AND (@ContainerCode = '' OR ZR_ContainerCode.ContainerCode = @ContainerCode)
                AND (@TProductName = '' OR product.TProductName = @TProductName)
                AND (@ProductDescription = '' OR product.ProductDescription LIKE '%' + @ProductDescription + '%')
                AND ToFac.ProudctionLotSN IS NOT NULL AND ToFac.ProudctionLotSN <> ''
                AND (@BeginCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate >= @BeginCreateDate)
                AND (@EndCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate < @EndDateExclusive)

            UNION ALL
            
            -- 分支2：匹配 mo.soname（排除已在分支1查出的数据，避免重复）
            SELECT 
                product.TProductName AS '产品名称',
                product.ProductDescription AS '产品描述',
                Tofac.PrintDate AS '打印日期',
                mo.soname AS '销售单号',
                ToFac.ProudctionLotSN AS '批次号',
                WorkcenterName AS '库位',
                Tofac.Barrelage AS '桶数',
                ZR_ContainerCode.ContainerCode AS '容器码',
                ZR_ContainerCodeDetails.CodeStatus AS '当前状态',
                ZR_ContainerCodeDetails.num AS '数量',
                ZR_ContainerCodeDetails.remark AS '备注',
                SysUser.UserDescription AS '操作人',
                ZR_ContainerCodeDetails.createDate AS '创建时间'
            FROM ZR_ContainerCodeDetails
            LEFT JOIN ZR_ToFac_ContainerCode 
                ON ZR_ContainerCodeDetails.ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ToFac_ContainerCodeID
            LEFT JOIN Tofac 
                ON Tofac.ToFacId = ZR_ToFac_ContainerCode.ToFacId
            LEFT JOIN ZR_ContainerCode 
                ON ZR_ToFac_ContainerCode.ZR_ContainerCodeID = ZR_ContainerCode.ZR_ContainerCodeID
            LEFT JOIN product 
                ON product.productid = tofac.ProductID
            LEFT JOIN SysUser 
                ON SysUser.UserId = ZR_ContainerCodeDetails.I_OrBitUserId
            LEFT JOIN mo 
                ON mo.MOName = tofac.ProudctionLotSN
            LEFT JOIN
                WW_RMInventory ON ZR_ToFac_ContainerCode.BoxLotSn = WW_RMInventory.lotsn
            LEFT JOIN
                Workcenter on Workcenter.WorkcenterId=WW_RMInventory.WorkcenterId
            WHERE
                @ProudctionLotSN <> '' -- 仅参数有值时走此分支
                AND mo.soname = @ProudctionLotSN
                AND (ToFac.ProudctionLotSN <> @ProudctionLotSN OR ToFac.ProudctionLotSN IS NULL) -- 去重
                AND (@ContainerCode = '' OR ZR_ContainerCode.ContainerCode = @ContainerCode)
                AND (@TProductName = '' OR product.TProductName = @TProductName)
                AND (@ProductDescription = '' OR product.ProductDescription LIKE '%' + @ProductDescription + '%')
                AND ToFac.ProudctionLotSN IS NOT NULL AND ToFac.ProudctionLotSN <> ''
                AND (@BeginCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate >= @BeginCreateDate)
                AND (@EndCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate < @EndDateExclusive)
            OPTION (RECOMPILE); -- 按实际参数值编译：空参数时编译期剪枝冗余分支/条件，避免参数嗅探产生劣质计划
        end
        
        -- 外购po
        if @I_Sender = 'TofacQuery_PO'
        begin
            SELECT
                [产品名称],
                [产品描述],
                [PO],
                [生产日期],
                [创建时间],
                [库位],
                [箱号],
                [原始箱号重量],
                [箱批次号],
                [容器码],
                [当前状态],
                [数量],
                [备注],
                [操作人],
                [扫码时间],
                [来源]
            FROM (
                     SELECT *,
                            ROW_NUMBER() OVER (
                                PARTITION BY [箱号]
                                ORDER BY Priority ASC, [扫码时间] DESC
                                ) AS FinalRn
                     FROM (
                              -- =====================================================
                              -- 第一部分：查询 VendorDeliveryItemLot 的数据（优先级 1）
                              -- =====================================================
                              SELECT
                                  ProductRoot.ProductName AS '产品名称',
                                  Product.ProductDescription AS '产品描述',
                                  PO.POName AS 'PO',
                                  VendorDeliveryItemLot.ProductionDate AS '生产日期',
                                  VendorDeliveryItemLot.createDate AS '创建时间',
                                  Workcentername AS '库位',
                                  ZR_ToFac_ContainerCode.BoxLotSn AS '箱号',
                                  VendorDeliveryItemLot.qty AS '原始箱号重量',
                                  VendorDeliveryItemLot.ProductionLotNO AS '箱批次号',
                                  ZR_ContainerCode.ContainerCode AS '容器码',
                                  ZR_ContainerCodeDetails.CodeStatus AS '当前状态',
                                  ZR_ContainerCodeDetails.num AS '数量',
                                  ZR_ContainerCodeDetails.remark AS '备注',
                                  SysUser.UserDescription AS '操作人',
                                  ZR_ContainerCodeDetails.CreateDate AS '扫码时间',
                                  '送货' AS '来源',
                                  1 AS Priority
                              FROM
                                  ZR_ContainerCodeDetails
                                      LEFT JOIN
                                  ZR_ToFac_ContainerCode ON ZR_ContainerCodeDetails.ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ToFac_ContainerCodeID
                                      LEFT JOIN
                                  ZR_ContainerCode ON ZR_ToFac_ContainerCode.ZR_ContainerCodeID = ZR_ContainerCode.ZR_ContainerCodeID
                                      LEFT JOIN
                                  SysUser ON SysUser.UserId = ZR_ContainerCodeDetails.I_OrBitUserId
                                      LEFT JOIN
                                  VendorDeliveryItemLot ON ZR_ToFac_ContainerCode.BoxLotSn = VendorDeliveryItemLot.lotsn
                                      LEFT JOIN
                                  Product ON VendorDeliveryItemLot.ProductId = Product.ProductId
                                      LEFT JOIN
                                  ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId
                                      LEFT JOIN
                                  VendorDeliveryItem ON VendorDeliveryItemLot.VendorDeliveryItemId = VendorDeliveryItem.VendorDeliveryItemId
                                      LEFT JOIN
                                  PO ON VendorDeliveryItem.POId = PO.POId
                                      LEFT JOIN
                                  Vendor ON PO.VendorId = Vendor.VendorId
                                      LEFT JOIN
                                  WW_RMInventory ON ZR_ToFac_ContainerCode.BoxLotSn = WW_RMInventory.lotsn
                                      LEFT JOIN
                                  Workcenter on Workcenter.WorkcenterId=WW_RMInventory.WorkcenterId
                              WHERE
                                  ZR_ToFac_ContainerCode.boxlotsn != ''
                                AND VendorDeliveryItemLot.lotsn IS NOT NULL
                                -- 日期条件下推到内层：在 JOIN/窗口函数之前先过滤，减少参与计算的数据量
                                AND (@BeginCreateDate IS NULL OR ZR_ContainerCodeDetails.CreateDate >= @BeginCreateDate)
                                AND (@EndCreateDate IS NULL OR ZR_ContainerCodeDetails.CreateDate < @EndDateExclusive)

                              UNION ALL

                              -- =====================================================
                              -- 第二部分：查询 WW_RMInventory 的数据（优先级 2）
                              -- =====================================================
                              SELECT
                                  ProductRoot.ProductName AS '产品名称',
                                  Product.ProductDescription AS '产品描述',
                                  NULL AS 'PO',
                                  NULL AS '生产日期',
                                  WW_RMInventory.CreateDate AS '创建时间',
                                  Workcentername AS '库位',
                                  ZR_ToFac_ContainerCode.BoxLotSn AS '箱号',
                                  WW_RMInventory.Qty AS '原始箱号重量',
                                  WW_RMInventory.ProductionLotNO AS '箱批次号',
                                  ZR_ContainerCode.ContainerCode AS '容器码',
                                  ZR_ContainerCodeDetails.CodeStatus AS '当前状态',
                                  ZR_ContainerCodeDetails.num AS '数量',
                                  ZR_ContainerCodeDetails.remark AS '备注',
                                  SysUser.UserDescription AS '操作人',
                                  ZR_ContainerCodeDetails.CreateDate AS '扫码时间',
                                  '拆分/打印' AS '来源',
                                  2 AS Priority
                              FROM
                                  ZR_ContainerCodeDetails
                                      LEFT JOIN
                                  ZR_ToFac_ContainerCode ON ZR_ContainerCodeDetails.ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ToFac_ContainerCodeID
                                      LEFT JOIN
                                  ZR_ContainerCode ON ZR_ToFac_ContainerCode.ZR_ContainerCodeID = ZR_ContainerCode.ZR_ContainerCodeID
                                      LEFT JOIN
                                  SysUser ON SysUser.UserId = ZR_ContainerCodeDetails.I_OrBitUserId
                                      LEFT JOIN
                                  WW_RMInventory ON ZR_ToFac_ContainerCode.BoxLotSn = WW_RMInventory.lotsn
                                      LEFT JOIN
                                  Product ON WW_RMInventory.ProductId = Product.ProductId
                                      LEFT JOIN
                                  ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId
                                      LEFT JOIN
                                  Vendor ON WW_RMInventory.VendorId = Vendor.VendorId
                                      LEFT JOIN
                                  Workcenter on Workcenter.WorkcenterId=WW_RMInventory.WorkcenterId
                              WHERE
                                  ZR_ToFac_ContainerCode.boxlotsn != ''
                                AND WW_RMInventory.lotsn IS NOT NULL
                                -- 日期条件下推到内层：在 JOIN/窗口函数之前先过滤，减少参与计算的数据量
                                AND (@BeginCreateDate IS NULL OR ZR_ContainerCodeDetails.CreateDate >= @BeginCreateDate)
                                AND (@EndCreateDate IS NULL OR ZR_ContainerCodeDetails.CreateDate < @EndDateExclusive)
                          ) AS CombinedSource
                 ) AS Ranked
            WHERE FinalRn = 1
              AND (@ProudctionLotSN = ''
                OR [箱批次号] = @ProudctionLotSN
                OR [PO] = @ProudctionLotSN)
              AND (@ContainerCode = '' OR [容器码] = @ContainerCode)
              AND (@TProductName = '' OR [产品名称] = @TProductName)
              AND (@ProductDescription = '' OR [产品描述] LIKE '%' + @ProductDescription + '%')
            ORDER BY [扫码时间] DESC
            OPTION (RECOMPILE); -- 按实际参数值编译：空参数时编译期剪枝冗余条件，避免参数嗅探；日期过滤已下推至内层
--             SELECT
--                 -- 从新的连接表中选取的列
--                 ProductRoot.ProductName AS '产品名称',
--                 Product.ProductDescription AS '产品描述',
--                 PO.POName AS 'PO',
--                 VendorDeliveryItemLot.ProductionDate AS '生产日期',
--                 VendorDeliveryItemLot.createDate AS '创建时间',
--                 ZR_ToFac_ContainerCode.BoxLotSn as '箱号',
--                 VendorDeliveryItemLot.qty as '原始箱号重量',
--                 VendorDeliveryItemLot.ProductionLotNO as '箱批次号',
--                 -- 原查询中保留的列
--                 ZR_ContainerCode.ContainerCode AS '容器码',
--                 ZR_ContainerCodeDetails.CodeStatus AS '当前状态',
--                 ZR_ContainerCodeDetails.num AS '数量',
--                 ZR_ContainerCodeDetails.remark AS '备注',
--                 SysUser.UserDescription AS '操作人',
--                 ZR_ContainerCodeDetails.CreateDate AS '扫码时间'
--             FROM
--                 ZR_ContainerCodeDetails
--             -- 原有的连接关系
--             LEFT JOIN
--                 ZR_ToFac_ContainerCode ON ZR_ContainerCodeDetails.ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ToFac_ContainerCodeID
--             LEFT JOIN
--                 ZR_ContainerCode ON ZR_ToFac_ContainerCode.ZR_ContainerCodeID = ZR_ContainerCode.ZR_ContainerCodeID
--             LEFT JOIN
--                 SysUser ON SysUser.UserId = ZR_ContainerCodeDetails.I_OrBitUserId
--             -- 新添加的连接关系
--             LEFT JOIN
--                 VendorDeliveryItemLot ON ZR_ToFac_ContainerCode.BoxLotSn = VendorDeliveryItemLot.lotsn
--             LEFT JOIN
--                 Product ON VendorDeliveryItemLot.ProductId = Product.ProductId
--             LEFT JOIN
--                 ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId
--             LEFT JOIN
--                 VendorDeliveryItem ON VendorDeliveryItemLot.VendorDeliveryItemId = VendorDeliveryItem.VendorDeliveryItemId
--             LEFT JOIN
--                 PO ON VendorDeliveryItem.POId = PO.POId
--             LEFT JOIN
--                 Vendor ON PO.VendorId = Vendor.VendorId
--             WHERE
--                 ZR_ToFac_ContainerCode.boxlotsn != ''
--                 and (
--                     -- 如果 @ProudctionLotSN 为空，则不进行筛选
--                     @ProudctionLotSN = ''
--                     -- 检查是否匹配 VendorDeliveryItemLot 表的 lotsn
--                     OR VendorDeliveryItemLot.lotsn = @ProudctionLotSN
--                     -- 检查是否匹配 PO 表的 POName
--                     OR PO.POName = @ProudctionLotSN
--                 )
--                 AND (@ContainerCode = '' OR ZR_ContainerCode.ContainerCode = @ContainerCode)
--                 AND (@TProductName = '' OR ProductRoot.ProductName = @TProductName)
--                 AND (@ProductDescription = '' OR product.ProductDescription like '%' + @ProductDescription + '%')
--                 -- 开始日期条件
--                 AND (@BeginCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate >= CONVERT(DATETIME, @BeginCreateDate, 120))
--                 -- 结束日期条件，修改为小于第二天的开始时间
--                 AND (@EndCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate < DATEADD(DAY, 1, CONVERT(DATETIME, @EndCreateDate, 120)));
        end

        if @I_Sender = 'TofacQueryLastTime'
        begin
        WITH RankedRecords AS (
            select
                product.TProductName '产品名称',
                product.ProductDescription '产品描述',
                Tofac.PrintDate '打印日期',
                mo.soname '销售单号',
                ToFac.ProudctionLotSN '批次号',
                WorkcenterName '库位',
                Tofac.Barrelage '桶数',
                ZR_ContainerCode.ContainerCode '容器码',
                CONCAT(ToFac.ProudctionLotSN, '_', ZR_ContainerCode.ContainerCode) '批次容器码标识',
                ZR_ContainerCodeDetails.CodeStatus '当前状态',
                ZR_ContainerCodeDetails.num '数量',
                ZR_ContainerCodeDetails.remark '备注',
                SysUser.UserDescription '操作人',
                ZR_ContainerCodeDetails.createDate '创建时间',
                ROW_NUMBER() OVER (PARTITION BY CONCAT(mo.soname , '_', ToFac.ProudctionLotSN, '_', ZR_ContainerCode.ContainerCode) ORDER BY ZR_ContainerCodeDetails.createDate DESC) as rn
            from
                ZR_ContainerCodeDetails
            left join
                ZR_ToFac_ContainerCode on ZR_ContainerCodeDetails.ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ToFac_ContainerCodeID
            left join
                Tofac on Tofac.ToFacId = ZR_ToFac_ContainerCode.ToFacId
            left join
                ZR_ContainerCode on ZR_ToFac_ContainerCode.ZR_ContainerCodeID = ZR_ContainerCode.ZR_ContainerCodeID
            left join
                product on product.productid = tofac.ProductID
            left join
                SysUser on SysUser.UserId = ZR_ContainerCodeDetails.I_OrBitUserId
            left join
                mo on mo.MOName = tofac.ProudctionLotSN
            LEFT JOIN
                WW_RMInventory ON ZR_ToFac_ContainerCode.BoxLotSn = WW_RMInventory.lotsn
            LEFT JOIN
                Workcenter on Workcenter.WorkcenterId=WW_RMInventory.WorkcenterId
            where
                ( -- 如果 @ProudctionLotSN 为空，则不进行筛选
                    @ProudctionLotSN = '' 
                    -- 检查是否匹配 tofac 表的 ProudctionLotSN
                    OR ToFac.ProudctionLotSN = @ProudctionLotSN 
                    -- 检查是否匹配 mo 表的 soname
                    OR mo.soname = @ProudctionLotSN 
                )                
                AND (@ContainerCode = '' OR ZR_ContainerCode.ContainerCode = @ContainerCode)
                AND (@TProductName = '' OR product.TProductName = @TProductName)
                AND ToFac.ProudctionLotSN IS NOT NULL AND ToFac.ProudctionLotSN <> ''
                AND (@ProductDescription = '' OR product.ProductDescription like '%' + @ProductDescription + '%')
                -- 开始日期条件
                AND (@BeginCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate >= @BeginCreateDate)
                -- 结束日期条件，修改为小于第二天的开始时间
                AND (@EndCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate < @EndDateExclusive)
        )
        SELECT
            产品名称,
            产品描述,
            打印日期,
            销售单号,
            批次号,
            库位,
            桶数,
            容器码,
--             批次容器码标识,
            当前状态,
            数量,
            备注,
            操作人,
            创建时间
        FROM
            RankedRecords
        WHERE
            rn = 1
        OPTION (RECOMPILE);
        end

        if @I_Sender = 'TofacQueryLastTime_PO'
        begin

            WITH CombinedSource AS (
                -- =====================================================
                -- 第一部分：数据来自 VendorDeliveryItemLot（优先级 1）
                -- =====================================================
                SELECT
                    ProductRoot.ProductName AS '产品名称',
                    Product.ProductDescription AS '产品描述',
                    PO.POName AS 'PO',
                    CONVERT(VARCHAR(10), CONVERT(DATE, VendorDeliveryItemLot.ProductionDate, 112), 111) AS '生产日期',
                    VendorDeliveryItemLot.createDate AS '创建时间',
                    ZR_ToFac_ContainerCode.BoxLotSn AS '箱号',
                    VendorDeliveryItemLot.qty AS '原始箱号重量',
                    VendorDeliveryItemLot.ProductionLotNO AS '箱批次号',
                    WorkcenterName AS '库位',
                    ZR_ContainerCode.ContainerCode AS '容器码',
                    ZR_ContainerCodeDetails.CodeStatus AS '当前状态',
                    ZR_ContainerCodeDetails.num AS '数量',
                    ZR_ContainerCodeDetails.remark AS '备注',
                    SysUser.UserDescription AS '操作人',
                    ZR_ContainerCodeDetails.CreateDate AS '扫码时间',
                    'VendorLot' AS DataSource,
                    1 AS Priority  -- 优先级：1 最高，优先取
                FROM
                    ZR_ContainerCodeDetails
                        LEFT JOIN
                    ZR_ToFac_ContainerCode ON ZR_ContainerCodeDetails.ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ToFac_ContainerCodeID
                        LEFT JOIN
                    ZR_ContainerCode ON ZR_ToFac_ContainerCode.ZR_ContainerCodeID = ZR_ContainerCode.ZR_ContainerCodeID
                        LEFT JOIN
                    SysUser ON SysUser.UserId = ZR_ContainerCodeDetails.I_OrBitUserId
                        LEFT JOIN
                    VendorDeliveryItemLot ON ZR_ToFac_ContainerCode.BoxLotSn = VendorDeliveryItemLot.lotsn
                        LEFT JOIN
                    Product ON VendorDeliveryItemLot.ProductId = Product.ProductId
                        LEFT JOIN
                    ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId
                        LEFT JOIN
                    VendorDeliveryItem ON VendorDeliveryItemLot.VendorDeliveryItemId = VendorDeliveryItem.VendorDeliveryItemId
                        LEFT JOIN
                    PO ON VendorDeliveryItem.POId = PO.POId
                        LEFT JOIN
                    Vendor ON PO.VendorId = Vendor.VendorId
                        LEFT JOIN
                    WW_RMInventory ON ZR_ToFac_ContainerCode.BoxLotSn = WW_RMInventory.lotsn
                        LEFT JOIN
                    Workcenter on Workcenter.WorkcenterId=WW_RMInventory.WorkcenterId
                WHERE
                    ZR_ToFac_ContainerCode.boxlotsn != ''
                  AND VendorDeliveryItemLot.lotsn IS NOT NULL  -- 只取能关联到的
                  AND (@ContainerCode = '' OR ZR_ContainerCode.ContainerCode = @ContainerCode)
                  AND (@BeginCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate >= @BeginCreateDate)
                  AND (@EndCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate < @EndDateExclusive)

                UNION ALL

                -- =====================================================
                -- 第二部分：数据来自 WW_RMInventory（优先级 2）
                -- =====================================================
                SELECT
                    ProductRoot.ProductName AS '产品名称',
                    Product.ProductDescription AS '产品描述',
                    NULL AS 'PO',
                    NULL AS '生产日期',
                    WW_RMInventory.CreateDate AS '创建时间',
                    ZR_ToFac_ContainerCode.BoxLotSn AS '箱号',
                    WW_RMInventory.Qty AS '原始箱号重量',
                    WW_RMInventory.ProductionLotNO AS '箱批次号',
                    WorkcenterName AS '库位',
                    ZR_ContainerCode.ContainerCode AS '容器码',
                    ZR_ContainerCodeDetails.CodeStatus AS '当前状态',
                    ZR_ContainerCodeDetails.num AS '数量',
                    ZR_ContainerCodeDetails.remark AS '备注',
                    SysUser.UserDescription AS '操作人',
                    ZR_ContainerCodeDetails.CreateDate AS '扫码时间',
                    'WWInventory' AS DataSource,
                    2 AS Priority  -- 优先级：2，次选
                FROM
                    ZR_ContainerCodeDetails
                        LEFT JOIN
                    ZR_ToFac_ContainerCode ON ZR_ContainerCodeDetails.ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ToFac_ContainerCodeID
                        LEFT JOIN
                    ZR_ContainerCode ON ZR_ToFac_ContainerCode.ZR_ContainerCodeID = ZR_ContainerCode.ZR_ContainerCodeID
                        LEFT JOIN
                    SysUser ON SysUser.UserId = ZR_ContainerCodeDetails.I_OrBitUserId
                        LEFT JOIN
                    WW_RMInventory ON ZR_ToFac_ContainerCode.BoxLotSn = WW_RMInventory.lotsn
                        LEFT JOIN
                    Product ON WW_RMInventory.ProductId = Product.ProductId
                        LEFT JOIN
                    ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId
                        LEFT JOIN
                    Vendor ON WW_RMInventory.VendorId = Vendor.VendorId
                        LEFT JOIN
                    Workcenter on Workcenter.WorkcenterId=WW_RMInventory.WorkcenterId
                WHERE
                    ZR_ToFac_ContainerCode.boxlotsn != ''
                  AND WW_RMInventory.lotsn IS NOT NULL  -- 只取能关联到的
                  AND (@ContainerCode = '' OR ZR_ContainerCode.ContainerCode = @ContainerCode)
                  AND (@BeginCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate >= @BeginCreateDate)
                  AND (@EndCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate < @EndDateExclusive)
            ),
-- =====================================================
-- 按箱号分组，按优先级取最小（优先取 VendorLot），同一个数据源内按扫码时间取最新
-- =====================================================
                 Ranked AS (
                     SELECT *,
                            ROW_NUMBER() OVER (
                                PARTITION BY [箱号]
                                ORDER BY Priority ASC, [扫码时间] DESC
                                ) AS FinalRn
                     FROM CombinedSource
                 )
            -- =====================================================
-- 最终结果：每个箱号只取一条
-- =====================================================
            SELECT
                [产品名称],
                [产品描述],
                [PO],
                [生产日期],
                [创建时间],
                [箱号],
                [原始箱号重量],
                [箱批次号],
                [库位],
                [容器码],
                [当前状态],
                [数量],
                [备注],
                [操作人],
                [扫码时间],
                CASE
                    WHEN DataSource = 'VendorLot' THEN '供应商批次'
                    WHEN DataSource = 'WWInventory' THEN '仓库库存'
                    ELSE '未知来源'
                    END AS '数据来源'
            FROM Ranked
            WHERE
                FinalRn = 1
              AND (@ProudctionLotSN = ''
                OR [箱批次号] = @ProudctionLotSN
                OR [PO] = @ProudctionLotSN)
              AND (@TProductName = '' OR [产品名称] = @TProductName)
              AND (@ProductDescription = '' OR [产品描述] LIKE '%' + @ProductDescription + '%')
            ORDER BY [扫码时间] DESC
            OPTION (RECOMPILE); -- 按实际参数值编译：空参数时编译期剪枝冗余条件，避免参数嗅探产生劣质计划
--             -- 使用 CTE（公共表表达式）来进行初步查询
--             -- 使用 CTE 来进行初步查询并添加行号
--             WITH RankedRecords AS (
--                 SELECT
--                     ProductRoot.ProductName AS '产品名称',
--                     Product.ProductDescription AS '产品描述',
--                     PO.POName AS 'PO',
--                     -- 格式化生产日期
--                     CONVERT(VARCHAR(10), CONVERT(DATE, VendorDeliveryItemLot.ProductionDate, 112), 111) AS '生产日期',
--                     VendorDeliveryItemLot.createDate AS '创建时间',
--                     ZR_ToFac_ContainerCode.BoxLotSn AS '箱号',
--                     VendorDeliveryItemLot.qty as '原始箱号重量',
--                     VendorDeliveryItemLot.ProductionLotNO as '箱批次号',
--                     ZR_ContainerCode.ContainerCode AS '容器码',
--                     ZR_ContainerCodeDetails.CodeStatus AS '当前状态',
--                     ZR_ContainerCodeDetails.num AS '数量',
--                     ZR_ContainerCodeDetails.remark AS '备注',
--                     SysUser.UserDescription AS '操作人',
--                     ZR_ContainerCodeDetails.CreateDate AS '扫码时间',
--                     -- 使用 ROW_NUMBER 函数按箱号分组并按创建时间降序排列
--                     ROW_NUMBER() OVER (PARTITION BY ZR_ToFac_ContainerCode.BoxLotSn ORDER BY ZR_ContainerCodeDetails.CreateDate DESC) AS rn
--                 FROM
--                     ZR_ContainerCodeDetails
--                 -- 原有的连接关系
--                 LEFT JOIN
--                     ZR_ToFac_ContainerCode ON ZR_ContainerCodeDetails.ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCode.ZR_ToFac_ContainerCodeID
--                 LEFT JOIN
--                     ZR_ContainerCode ON ZR_ToFac_ContainerCode.ZR_ContainerCodeID = ZR_ContainerCode.ZR_ContainerCodeID
--                 LEFT JOIN
--                     SysUser ON SysUser.UserId = ZR_ContainerCodeDetails.I_OrBitUserId
--                 -- 新添加的连接关系
--                 LEFT JOIN
--                     VendorDeliveryItemLot ON ZR_ToFac_ContainerCode.BoxLotSn = VendorDeliveryItemLot.lotsn
--                 LEFT JOIN
--                     Product ON VendorDeliveryItemLot.ProductId = Product.ProductId
--                 LEFT JOIN
--                     ProductRoot ON Product.ProductRootId = ProductRoot.ProductRootId
--                 LEFT JOIN
--                     VendorDeliveryItem ON VendorDeliveryItemLot.VendorDeliveryItemId = VendorDeliveryItem.VendorDeliveryItemId
--                 LEFT JOIN
--                     PO ON VendorDeliveryItem.POId = PO.POId
--                 LEFT JOIN
--                     Vendor ON PO.VendorId = Vendor.VendorId
--                 WHERE
--                     ZR_ToFac_ContainerCode.boxlotsn != ''
--                     AND (
--                         -- 如果 @ProudctionLotSN 为空，则不进行筛选
--                         @ProudctionLotSN = ''
--                         -- 检查是否匹配 VendorDeliveryItemLot 表的 lotsn
--                         OR VendorDeliveryItemLot.lotsn = @ProudctionLotSN
--                         -- 检查是否匹配 PO 表的 POName
--                         OR PO.POName = @ProudctionLotSN
--                     )
--                     AND (@ContainerCode = '' OR ZR_ContainerCode.ContainerCode = @ContainerCode)
--                     AND (@TProductName = '' OR ProductRoot.ProductName = @TProductName)
--                     AND (@ProductDescription = '' OR product.ProductDescription like '%' + @ProductDescription + '%')
--                     -- 开始日期条件
--                     AND (@BeginCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate >= CONVERT(DATETIME, @BeginCreateDate, 120))
--                     -- 结束日期条件，修改为小于第二天的开始时间
--                     AND (@EndCreateDate IS NULL OR ZR_ContainerCodeDetails.createDate < DATEADD(DAY, 1, CONVERT(DATETIME, @EndCreateDate, 120)))
--             )
--             -- 从 RankedRecords 中选择 rn 为 1 的记录，即每个箱号对应的最后一条记录
--             SELECT
--                 [产品名称],
--                 [产品描述],
--                 [PO],
--                 [生产日期],
--                 [创建时间],
--                 [箱号],
--                 [原始箱号重量],
--                 [箱批次号],
--                 [容器码],
--                 [当前状态],
--                 [数量],
--                 [备注],
--                 [操作人],
--                 [扫码时间]
--             FROM
--                 RankedRecords
--             WHERE
--                 rn = 1;
        end
      RETURN 0

END
GO
