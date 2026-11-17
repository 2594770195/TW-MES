SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		
-- Create date: 
-- Description:	转厂记录-半成品-拆批
-- =============================================
CREATE PROCEDURE  [dbo].[PDA_ToFac_Split]
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
@ProductDescription nvarchar(max) = '',
@IsSplitLotSN BIT=0
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

-- 	declare @ToJWBarrelage nvarchar(50)
-- 	declare @Barrelage nvarchar(50)
	declare @ProudctionLotNO nvarchar(50) --其实是工单号
-- 	declare @ProductDescription nvarchar(50)
 	declare @ToFacId char(12) =''
 	declare @ZR_ContainerCodeId char(12) ='' -- 容器码ID
	DECLARE @ZR_ToFac_ContainerCodeID CHAR(12) = '' -- 批号容器中间表ID

	DECLARE @CurrentProudctionLotSN NVARCHAR(255) -- 容器当前的批号
    DECLARE @LotSN NVARCHAR(50)
    DECLARE @WWnum float = 0
    DECLARE @NewLotSN NVARCHAR(50)
    DECLARE @SplitReturn INT=-1
    DECLARE @SplitReturnMessage NVARCHAR(MAX)=''
        
 --==========================回车判断，回显批号 begin=====================================================================
    select top 1 @LotSN=lotsn from WW_RMInventory where lotsn=@ProudctionLotSN
    IF ISNULL(@LotSN,'')<>''
    BEGIN
        select @ProudctionLotSN=ProductionLotNO from WW_RMInventory where LotSN=@LotSN
    END
    ELSE IF (select count(1) from WW_RMInventory where ProductionLotNO=@ProudctionLotSN) =1
    BEGIN
        select @LotSN=lotsn from WW_RMInventory where ProductionLotNO=@ProudctionLotSN
    END
    insert into mwjtestlog(LOG1,log2,log3,log4) VALUES('PDA_ToFac','65','@LotSN'+@LotSN,'@ProudctionLotSN'+@ProudctionLotSN)
	-- 截取工单前10位
    if (@ProudctionLotSN like '%+%')
        BEGIN
            select @ProudctionLotSN=SUBSTRING(  @ProudctionLotSN,1,  CHARINDEX('+',@ProudctionLotSN)-1  )
        end
    else
        begin
            select @ProudctionLotSN=LEFT(@ProudctionLotSN, 10)
        end

    --批号是空的就回显
    if @ProudctionLotSN is null or @ProudctionLotSN = ''
    BEGIN
        -- ZR_ContainerCode 表记录当前批号
        select @CurrentProudctionLotSN = CurrentProudctionLotSN,@ZR_ContainerCodeId = ZR_ContainerCodeId from ZR_ContainerCode where ContainerCode = @ContainerCode
        select @TProductName = Product.TProductName, @ProductDescription = ProductDescription from ToFac join Product on ToFac.ProductID = Product.ProductId WHERE ProudctionLotSN=@CurrentProudctionLotSN
        -- 回显最后一次的数量
        select @ToFacId=ToFacId from ToFac WHERE ProudctionLotSN=@CurrentProudctionLotSN
        SELECT @ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCodeID FROM ZR_ToFac_ContainerCode WHERE ToFacId = @ToFacId and ZR_ContainerCodeId = @ZR_ContainerCodeId
        if @ZR_ToFac_ContainerCodeID is not null or @ZR_ToFac_ContainerCodeID <> ''
            begin
                select top 1 @num = num,@remark = remark --,@CodeStatus = CodeStatus 
                from ZR_ContainerCodeDetails where ZR_ToFac_ContainerCodeID = @ZR_ToFac_ContainerCodeID ORDER BY createdate desc
            end

        -- 检查变量是否为空字符串或者 NULL
        IF ISNULL(@CurrentProudctionLotSN,'')!=''
        BEGIN
            -- 检查是否 未解绑 重新使用
            IF @CurrentProudctionLotSN != @ProudctionLotSN
            BEGIN
                insert into mwjtestlog(LOG1,log2,log3,log4) VALUES('PDA_ToFac','97',@CurrentProudctionLotSN,@ProductDescription)

                select @CurrentProudctionLotSN as ProudctionLotSN,@TProductName as TProductName,@ProductDescription as ProductDescription,@num as num,@remark as remark,@CodeStatus as CodeStatus
            END
        END
        
        set @I_ExceptionFieldName = 'num'
    END

    -- 回显批号对应的产品
    if @ProudctionLotSN is not null and @ProudctionLotSN != ''
    BEGIN
        if not exists (select 1 from ToFac where ProudctionLotSN=@ProudctionLotSN)
        BEGIN
            -- 初始化变量
            DECLARE @ProductId_TOFAC nvarchar(120) = NULL
            DECLARE @CreateDate_TOFAC datetime = NULL
            DECLARE @LotQty_TOFAC decimal(18, 6) = 0
            DECLARE @SoName_TOFAC nvarchar(50) = ''
    
            -- 从工单表查询
            SELECT
                @ProductId_TOFAC = mo.ProductId,
                @CreateDate_TOFAC = ISNULL(lot.CreateDate, GETDATE()),
                @LotQty_TOFAC = ISNULL(lot.qty, 0),
                @SoName_TOFAC = ISNULL(mo.soname, '')
            FROM mo
            LEFT JOIN lot ON mo.moid = lot.moid
            WHERE mo.moname = @ProudctionLotSN;
    
            -- ==============================================
            -- 关键：查不到工单 → 不插入，也不报错
            -- 让后面 confirm 按钮去提示“批号不存在”
            -- ==============================================
            IF @ProductId_TOFAC IS NOT NULL
            BEGIN
                -- 生成ID
                EXEC dbo.SysGetObjectPKId '', 'ToFac', @ToFacId OUTPUT;
    
                INSERT INTO ToFac (
                    ToFacID,
                    ProductID,
                    ProudctionLotSN,
                    PrintDate,
                    Barrelage,
                    ToBSDate,
                    ToBSBarrelage,
                    ToJWDate,
                    ToJWBarrelage,
                    JWDate,
                    JWBarrelage,
                    IsStorage,
                    soname
                )
                VALUES (
                    @ToFacId,
                    @ProductId_TOFAC,
                    @ProudctionLotSN,
                    @CreateDate_TOFAC,
                    (@LotQty_TOFAC / 1000) + 1,
                    NULL,
                    0,
                    NULL,
                    0,
                    NULL,
                    0,
                    1,
                    @SoName_TOFAC
                );
            END
        END
    
        select @TProductName = Product.TProductName, @ProductDescription = ProductDescription
        from ToFac
        join Product on ToFac.ProductID = Product.ProductId
        WHERE ProudctionLotSN=@ProudctionLotSN
        
        set @I_ExceptionFieldName = 'ContainerCode'
        IF @I_Sender='checkParam'
        BEGIN
            select @TProductName as TProductName, @ProductDescription as ProductDescription
        END
        insert into mwjtestlog(LOG1,log2,log3,log4) VALUES('PDA_ToFac','178',@TProductName,@ProductDescription)
    end
    --==========================回车判断，回显批号 end=====================================================================


     --========================== 2025年12月1日 增加容载器码非空判断 =====================================================================
    if @ContainerCode is null or @ContainerCode = ''
    BEGIN
        set @I_ReturnMessage='ServerMessage:请扫描容载器码'
        return -1
    END
     --========================== 2025年12月1日 增加容载器码非空判断 begin=====================================================================

	--==========================确认按钮 begin=====================================================================
    if @I_Sender='confirm'
        begin
            -- 0、判断批号
            select @ToFacId=ToFacId from ToFac WHERE ProudctionLotSN=@ProudctionLotSN
            if @ToFacId is null or @ToFacId = ''
            BEGIN
                set @I_ReturnMessage='ServerMessage:批号：'+ @ProudctionLotSN +'不存在，请扫描正确批号'
                RETURN -1
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
            select @CurrentProudctionLotSN = CurrentProudctionLotSN,@ZR_ContainerCodeId = ZR_ContainerCodeId from ZR_ContainerCode where ContainerCode = @ContainerCode

            -- 不是空表示有绑定
            --IF @CurrentProudctionLotSN IS NOT NULL OR @CurrentProudctionLotSN <> ''
            IF ISNULL(@CurrentProudctionLotSN,'')!=''
            BEGIN
                -- 检查是否 未解绑 重新使用
                IF @CurrentProudctionLotSN != @ProudctionLotSN
                BEGIN
                    -- 提示解绑
                    set @I_ReturnMessage='ServerMessage:'+ '容器码：' +@ContainerCode + ' 已经绑定批号：' + @CurrentProudctionLotSN + '，请先解绑再进行确认'+@ProudctionLotSN
                    RETURN -1
                END
            END

            --拆批
            SET @NewLotSN =@LotSN
            IF @IsSplitLotSN=1
            BEGIN
                --拆批时必须有确定的MES批次
                if ISNULL(@LotSN,'')=''
                BEGIN
                    set @I_ReturnMessage='ServerMessage:批号：'+ @ProudctionLotSN +'不存在，请扫描正确MES批号'
                    RETURN -1
                END
                -- 拆批数量非空及边界校验：必须大于0
                IF ISNULL(@num,0)<=0
                BEGIN
                    set @I_ReturnMessage='ServerMessage:'+ '拆批数量必须大于0'
                    RETURN -1
                END
                -- 校验源批号在库数量（只统计已入库库存）
                SELECT @WWnum=ISNULL(SUM(Qty),0) FROM WW_RMInventory WHERE LotSN=@LotSN AND IsStorage=1
                IF ISNULL(@WWnum,0)<@num
                BEGIN
                    set @I_ReturnMessage='ServerMessage:'+ '拆批数量不能大于库存数量,当前库存数量：'+convert(varchar(20),@WWnum) 
                    RETURN -1
                END
                -- 调用拆批过程：从源批号@LotSN中拆出@num，新批号通过输出参数返回
                EXEC @SplitReturn=dbo.Txn_MaterialLotSplit
                    @I_Sender='PDA_ToFac',
                    @I_ReturnMessage=@SplitReturnMessage OUTPUT,
                    @I_OrBitUserId=@I_OrBitUserId,
                    @I_OrBitUserName=@I_OrBitUserName,
                    @SplitLotSN=@LotSN,
                    @SplitQty=@num,
                    @NewSplitLotSN=@NewLotSN OUTPUT
                -- 拆批失败：直接返回拆批过程的提示信息
                IF ISNULL(@SplitReturn,0)<>0 OR ISNULL(@NewLotSN,'')=''
                BEGIN
                    set @I_ReturnMessage=ISNULL(NULLIF(@SplitReturnMessage,''),'ServerMessage:'+ '拆批失败，请检查源批号与拆批数量')
                    RETURN -1
                END
            END
            ELSE
            BEGIN
                SET @NewLotSN=''--如果不是拆批的则不能证明只有一桶，不能直接绑定MES批次
            END
            

            -- 2.1 、第一次绑定
            IF NOT EXISTS ( SELECT 1 FROM ZR_ToFac_ContainerCode WHERE ToFacId = @ToFacId and ZR_ContainerCodeId = @ZR_ContainerCodeId )
                BEGIN
                        insert into mwjtestlog(LOG1,log2,log3,log4) VALUES('PDA_ToFac','254',@LotSN,@IsSplitLotSN)

                    -- 2.2、当前容器没有绑定 批号，插入中间表绑定ZR_ToFac_ContainerCode
                    -- 声明变量用于存储生成的 ZR_ToFac_ContainerCodeID
                    -- DECLARE @ZR_ToFac_ContainerCodeID CHAR(12) = '';
                    -- 调用存储过程生成 ID
                    EXEC SysGetObjectPKId '', 'ZR_ToFac_ContainerCode', @ZR_ToFac_ContainerCodeID OUTPUT;
    
                    -- 插入新记录到 ZR_ToFac_ContainerCode 中间表
                    INSERT INTO ZR_ToFac_ContainerCode (
                        ZR_ToFac_ContainerCodeID,
                        ToFacId,
                        ZR_ContainerCodeId,
                        CreateData,
                        UpdateData,
                        BoxLotSn
                    )
                    VALUES (
                        @ZR_ToFac_ContainerCodeID,
                        @ToFacId,
                        @ZR_ContainerCodeId,
                        GETDATE(),
                        GETDATE(),
                        @NewLotSN
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

                    -- 2.2、补充 MES 批次绑定
                    -- 场景：容器已随工单绑定（ZR_ToFac_ContainerCode 已存在，BoxLotSn 为空），
                    --       入库接收自动拆批时不会再走 2.1 的新增分支，必须在此把拆出的 MES 批次回写到 BoxLotSn，
                    --       否则拆批成功后容器仍然没有绑定 MES 批次
                    IF ISNULL(@NewLotSN,'')<>''
                    BEGIN
                        -- 已绑定其它 MES 批次时不允许覆盖，避免库存批次与容器关系错乱
                        IF EXISTS (SELECT 1 FROM ZR_ToFac_ContainerCode
                                   WHERE ToFacId = @ToFacId
                                     AND ZR_ContainerCodeId = @ZR_ContainerCodeId
                                     AND ISNULL(BoxLotSn,'')<>''
                                     AND BoxLotSn<>@NewLotSN)
                        BEGIN
                            set @I_ReturnMessage='ServerMessage:容器：'+@ContainerCode+' 已绑定其它MES批次，请先解绑后再操作'
                            RETURN -1
                        END

                        -- 只回写 BoxLotSn 为空的记录，重复调用（同一批次重复确认）不重复覆盖
                        UPDATE ZR_ToFac_ContainerCode
                            SET BoxLotSn=@NewLotSN,
                                UpdateData=GETDATE()
                        WHERE ToFacId = @ToFacId
                          AND ZR_ContainerCodeId = @ZR_ContainerCodeId
                          AND ISNULL(BoxLotSn,'')=''

                        -- 同步容器当前批号（工单号），保证容器与工单关系一致
                        UPDATE ZR_ContainerCode
                            SET CurrentProudctionLotSN = @ProudctionLotSN
                        WHERE ZR_ContainerCodeID = @ZR_ContainerCodeId
                    END
                end

            -- 3.1 历史记录表
            -- 查询中间表记录
            SELECT @ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCodeID FROM ZR_ToFac_ContainerCode WHERE ToFacId = @ToFacId and ZR_ContainerCodeId = @ZR_ContainerCodeId

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
                GETDATE()
            );
            set @I_ReturnMessage='ServerMessage:添加：'+@ContainerCode+ ' ' +@ProudctionLotSN  + ' 记录成功 '
            IF @SplitReturn=0
            BEGIN
                set @I_ReturnMessage =@I_ReturnMessage + @SplitReturnMessage
                --拆批场景：返回容器绑定的MES批次，便于现场确认绑定结果
                IF ISNULL(@NewLotSN,'')<>''
                BEGIN
                    set @I_ReturnMessage =@I_ReturnMessage + 'ServerMessage:容器【'+@ContainerCode+'】已绑定MES批次【'+@NewLotSN+'】'
                END
            END

            select null as ProudctionLotSN,  0 as num, '' as remark, '' as ContainerCode, '' as TProductName, '' as ProductDescription--'' as CodeStatus,
            set @I_ExceptionFieldName = 'ContainerCode'
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
                select @ToFacId=ToFacId from ToFac WHERE ProudctionLotSN=@CurrentProudctionLotSN
                SELECT @ZR_ToFac_ContainerCodeID = ZR_ToFac_ContainerCodeID FROM ZR_ToFac_ContainerCode WHERE ToFacId = @ToFacId and ZR_ContainerCodeId = @ZR_ContainerCodeId
                -- 声明变量用于存储生成的 ZR_ContainerCodeDetailsId
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
                    '解绑',
                    @I_OrBitUserId,
                    GETDATE()
                );

                update ZR_ContainerCode set CurrentProudctionLotSN = '' where ContainerCode = @ContainerCode
                 
                
                set @I_ReturnMessage='ServerMessage:解绑：'+@ContainerCode+' 成功 '
                select null as ProudctionLotSN, '' as CodeStatus, 0 as num, '' as remark, '' as ContainerCode, '' as TProductName, '' as ProductDescription
                RETURN 0
        end
    --===========================撤销按钮 end=====================================================================

	return 0
	
	
END
GO
