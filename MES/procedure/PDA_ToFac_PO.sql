SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Irving>
-- Create date: <2025.01.25>
-- Description:	转厂记录
-- =============================================
CREATE PROCEDURE  [dbo].[PDA_ToFac_PO]
@I_Sender nvarchar(200)='', --客户端执行按钮
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_ExceptionFieldName nvarchar(100)='' output, --向客户端报告引起冲突的字段
@I_LanguageId char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKid char(12) ='',				--主键
@I_ParentPKId char(12)='',			--父级主键
@I_Parameter nvarchar(max)='',  		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.

@ProudctionLotSN nvarchar(50) = '', --批号
@ContainerCode nvarchar(50) = '', --容器码
@CodeStatus nvarchar(50) = '', --明细记录
@num float = 0,             --重量
@remark nvarchar(max) = '',
@TProductName nvarchar(max) = '',
@ProductDescription nvarchar(max) = ''
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

-- 	declare @ToJWBarrelage nvarchar(50)
-- 	declare @Barrelage nvarchar(50)
-- 	declare @ProudctionLotNO nvarchar(50) --其实是工单号
-- 	declare @ProductDescription nvarchar(50)
 	declare @ToFacId char(12) =''
 	declare @ZR_ContainerCodeId char(12) ='' -- 容器码ID
	DECLARE @ZR_ToFac_ContainerCodeID CHAR(12) = '' -- 批号容器中间表ID

	DECLARE @CurrentProudctionLotSN NVARCHAR(255) -- 容器当前的批号
        
   -- ============================ 2026年1月16日 15:14:25  截取箱号（防止录错）      ==============================================----
    IF NOT EXISTS( SELECT 1 FROM Equipment WHERE EquipmentNumber=@ProudctionLotSN )--排除设备，设备会有+号的
    BEGIN
        SET @ProudctionLotSN = LEFT(@ProudctionLotSN, CHARINDEX('+', @ProudctionLotSN + '+') - 1)
    END
    -- ============================ 2026年1月16日 15:14:29  截取箱号（防止录错）      ==============================================----

        
        
 --==========================回车判断，回显批号 begin=====================================================================

    select @CodeStatus as CodeStatus

    --==========================回车判断，回显批号 end=====================================================================
        
    --========================== 2025年12月1日 增加容载器码非空判断 =====================================================================
    if @ContainerCode is null or @ContainerCode = ''
    BEGIN
        --20260602改为随机
        EXEC SysGetObjectPKId '', 'ContainerCode', @ContainerCode OUTPUT;
    END
     --========================== 2025年12月1日 增加容载器码非空判断 begin=====================================================================
         
	--==========================确认按钮 begin=====================================================================
    if @I_Sender='confirm'
        begin
            DECLARE @Flag nvarchar(10) = ''  --判断标志，判断该批号是采购单中已存在的或是通过期初打出来的库存
            -- 0、判断批号
            --校验箱号，不存在
            -- 检查 VendorDeliveryItemLot 表中是否存在指定 lotsn 的记录
            IF EXISTS (
                SELECT 1
                FROM VendorDeliveryItemLot
                WHERE lotsn = @ProudctionLotSN
            )
            BEGIN
                set @Flag = 'Vendor'  --采购送货单
                -- 如果不存在，返回错误信息
--         set @I_ReturnMessage = '箱号不存在'
--         return -1
            END
            ELSE IF EXISTS (
                SELECT 1
                FROM WW_RMInventory
                WHERE lotsn = @ProudctionLotSN and IsStorage = 1
            )
            BEGIN
                set @Flag = 'RMI'   --库存
            END

            -- 1.1、添加容器码(输入容器码)
            -- 检查是否存在指定 ContainerCode 的记录
            IF NOT EXISTS (SELECT 1 FROM ZR_ContainerCode WHERE ContainerCode = @ContainerCode)
            BEGIN
                -- 声明变量用于存储生成的 ZR_ContainerCodeID
                -- DECLARE @ZR_ContainerCodeID CHAR(12) = '';
                -- 调用存储过程生成 ID
                EXEC SysGetObjectPKId '', 'ZR_ContainerCode', @ZR_ContainerCodeID OUTPUT;

                 -- 插入新记录
                INSERT INTO ZR_ContainerCode (
                    ZR_ContainerCodeID,
                    ContainerCode,
                    UpdateDate,
                    ToFacId,
                    CurrentProudctionLotSN
                )
                VALUES (
                    @ZR_ContainerCodeID,
                    @ContainerCode,
                    GETDATE(),
                        @ToFacId,
                    @CurrentProudctionLotSN
                 );
                set @I_ReturnMessage='ServerMessage:添加：'+@ContainerCode+' 新容器成功 '
            END
            
            
            -- 1.2、插入容器,先检查容器是否已绑定过 当前批号
            -- 容器当前批号
--             select @CurrentProudctionLotSN = CurrentProudctionLotSN,@ZR_ContainerCodeId = ZR_ContainerCodeId from ZR_ContainerCode where ContainerCode = @ContainerCode

            -- 不是空表示有绑定
            --IF @CurrentProudctionLotSN IS NOT NULL OR @CurrentProudctionLotSN <> ''
--             IF ISNULL(@CurrentProudctionLotSN,'')!=''
--             BEGIN
--                 -- 检查是否 未解绑 重新使用
--                 IF @CurrentProudctionLotSN != @ProudctionLotSN
--                 BEGIN
--                     -- 提示解绑
--                     set @I_ReturnMessage='ServerMessage:'+ '容器码：' +@ContainerCode + ' 已经绑定批号：' + @CurrentProudctionLotSN + '，请先解绑再进行确认'
--                     RETURN -1
--                 END
--             END

            select @ZR_ContainerCodeId = ZR_ContainerCodeId from ZR_ContainerCode where ContainerCode = @ContainerCode

            -- 2.1 、第一次绑定
            IF NOT EXISTS ( SELECT 1 FROM ZR_ToFac_ContainerCode WHERE BoxLotSn = @ProudctionLotSN and ZR_ContainerCodeId = @ZR_ContainerCodeId )
                BEGIN
                    -- 2.2、当前容器没有绑定 批号，插入中间表绑定ZR_ToFac_ContainerCode
                    -- 声明变量用于存储生成的 ZR_ToFac_ContainerCodeID
                    -- DECLARE @ZR_ToFac_ContainerCodeID CHAR(12) = '';
                    -- 调用存储过程生成 ID
                    EXEC SysGetObjectPKId '', 'ZR_ToFac_ContainerCode', @ZR_ToFac_ContainerCodeID OUTPUT;
    
                    -- 插入新记录到 ZR_ToFac_ContainerCode 中间表
                    INSERT INTO ZR_ToFac_ContainerCode (
                        ZR_ToFac_ContainerCodeID,
                        BoxLotSn,
                        ZR_ContainerCodeId,
                        CreateData,
                        UpdateData
                    )
                    VALUES (
                        @ZR_ToFac_ContainerCodeID,
                        @ProudctionLotSN,
                        @ZR_ContainerCodeId,
                        GETDATE(),
                        GETDATE()
                    );
    
                    --绑定容器码
                    -- 更新 ZR_ContainerCode 表中的 CurrentProudctionLotSN 字段
                    UPDATE ZR_ContainerCode
                        SET CurrentProudctionLotSN = @ProudctionLotSN
                    WHERE ZR_ContainerCodeID = @ZR_ContainerCodeId
    
                    set @I_ReturnMessage='ServerMessage:容器：'+@ContainerCode+' 绑定 ' + @ProudctionLotSN + ' 成功 '
                END
            else
                BEGIN
                    -- 2.1 、解绑后，又绑定原批号
                    IF ISNULL(@CurrentProudctionLotSN,'')=''
                        BEGIN
                             -- 更新 ZR_ContainerCode 表中的 CurrentProudctionLotSN 字段
                            UPDATE ZR_ContainerCode
                                SET CurrentProudctionLotSN = @ProudctionLotSN
                            WHERE ZR_ContainerCodeID = @ZR_ContainerCodeId
                        END
                end

            -- 3.1 历史记录表
            -- 查询中间表记录
            SELECT @ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCodeID FROM ZR_ToFac_ContainerCode WHERE BoxLotSn = @ProudctionLotSN and ZR_ContainerCodeId = @ZR_ContainerCodeId 

            -- 声明变量用于存储生成的 ZR_ContainerCodeDetailsId
            DECLARE @ZR_ContainerCodeDetailsId CHAR(12) = '';
            -- 调用存储过程生成 ID
            EXEC SysGetObjectPKId '', 'ZR_ContainerCodeDetails', @ZR_ContainerCodeDetailsId OUTPUT;
            -- 插入新记录到 dbo.ZR_ContainerCodeDetails 表
            INSERT INTO dbo.ZR_ContainerCodeDetails (
                ZR_ContainerCodeDetailsId,
                ZR_ToFac_ContainerCodeID,
                CodeStatus,
                num,
                remark,
                I_OrBitUserId,
                UpdateDate
            )
            VALUES (
                @ZR_ContainerCodeDetailsId,
                @ZR_ToFac_ContainerCodeID,
                @CodeStatus,
                @num,
                @remark,
                @I_OrBitUserId,
                GETDATE() -- 创建时间，自动生成
            );
            DECLARE @MaterialName NVARCHAR(100)=''
            IF @Flag = 'Vendor'
            BEGIN
                select @MaterialName=ProductDescription from VendorDeliveryItemLot
                LEFT JOIN Product ON VendorDeliveryItemLot.ProductId = Product.ProductId
                where VendorDeliveryItemLot.lotsn = @ProudctionLotSN
            END
            ELSE IF @Flag = 'RMI'
            BEGIN
                select @MaterialName=ProductDescription from WW_RMInventory
                LEFT JOIN Product ON WW_RMInventory.ProductId = Product.ProductId
                where WW_RMInventory.lotsn = @ProudctionLotSN
            END


            set @I_ReturnMessage='ServerMessage:'+@ProudctionLotSN + ' ' + @MaterialName  + ' 记录成功 '
            SET @I_ExceptionFieldName='ProudctionLotSN'
            select null as ProudctionLotSN, --'' as CodeStatus, 
            0 as num, '' as remark, '' as ContainerCode, '' as TProductName, '' as ProductDescription
        end
	--==========================确认按钮 end=====================================================================

    --==========================撤销按钮 begin=====================================================================
        if @I_Sender='unbind'
            begin
                 -- 1.1、容器码
                -- 检查是否存在指定 ContainerCode 的记录
                IF NOT EXISTS (SELECT 1 FROM ZR_ContainerCode WHERE ContainerCode = @ContainerCode)
                BEGIN
                    set @I_ReturnMessage='ServerMessage:容器：'+@ContainerCode+' 不存在 '
                    RETURN -1
                END
    
                -- 已经解绑
                select @CurrentProudctionLotSN = CurrentProudctionLotSN,@ZR_ContainerCodeId = ZR_ContainerCodeId from ZR_ContainerCode where ContainerCode = @ContainerCode
                IF @CurrentProudctionLotSN IS NULL OR @CurrentProudctionLotSN = ''
                BEGIN
                    set @I_ReturnMessage='ServerMessage:容器：'+@ContainerCode+' 已经解绑,不需要重复操作'
                    RETURN 0
                END

                -- 添加解绑记录

                SELECT @ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCodeID FROM ZR_ToFac_ContainerCode WHERE BoxLotSn = @ProudctionLotSN                -- 声明变量用于存储生成的 ZR_ContainerCodeDetailsId
                DECLARE @ZR_ContainerCodeDetailsIda CHAR(12) = '';
                -- 调用存储过程生成 ID
                EXEC SysGetObjectPKId '', 'ZR_ContainerCodeDetails', @ZR_ContainerCodeDetailsIda OUTPUT;
                -- 插入新记录到 dbo.ZR_ContainerCodeDetails 表
                INSERT INTO dbo.ZR_ContainerCodeDetails (
                    ZR_ContainerCodeDetailsId,
                    ZR_ToFac_ContainerCodeID,
                    CodeStatus,
                    num,
                    remark,
                    I_OrBitUserId,
                    UpdateDate
                )
                VALUES (
                    @ZR_ContainerCodeDetailsIda,
                    @ZR_ToFac_ContainerCodeID,
                    '解绑',
                    @num,
                    @remark,
                    @I_OrBitUserId,
                    GETDATE()
                );

                update ZR_ContainerCode set CurrentProudctionLotSN = '' where ContainerCode = @ContainerCode
                 
                
                set @I_ReturnMessage='ServerMessage:解绑：'+@ContainerCode+' 成功 '
                SET @I_ExceptionFieldName='ProudctionLotSN'
                select null as ProudctionLotSN,-- '' as CodeStatus, 
                0 as num, '' as remark, '' as ContainerCode, '' as TProductName, '' as ProductDescription
                RETURN 0
        end
    --===========================撤销按钮 end=====================================================================

	return 0
	
	
END
GO
