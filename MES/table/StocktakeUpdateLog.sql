-- =============================================
-- 盘点库存更新日志表：Batch_StocktakeUpdateRMInventory 更新 WW_RMInventory 数量时写入
-- =============================================
create table StocktakeUpdateLog
(
    StocktakeUpdateLogId bigint identity
        constraint PK_StocktakeUpdateLog
            primary key,
    BatchNo               nvarchar(30)   not null, -- 盘点批次号，与存储过程 @BatchNo 一致
    ProductNo             nvarchar(100)  not null, -- 物料号
    LotSN                 nvarchar(100)  null,     -- MES 内部批号
    SAPBatchNo            nvarchar(100)  not null, -- SAP 批号，对应 ProductionLotNO
    BeforeQty             decimal(18, 8) not null, -- 修改前数量
    AfterQty              decimal(18, 8) not null, -- 修改后数量
    WWId                  char(12)       null,     -- 库存主键，便于追溯
    FactoryId             char(12)       null,
    WorkcenterId          char(12)       null,
    UpdateType            nvarchar(20)   not null, -- adjust=按累计保留调整, semi_add=半成品差额追加
    CreateUserId          char(12)       null,     -- 操作人
    CreateDate            datetime
        constraint DF_StocktakeUpdateLog_CreateDate default getdate() -- 记录时间
)
go

create index IX_StocktakeUpdateLog_BatchNo
    on StocktakeUpdateLog (BatchNo)
go

create index IX_StocktakeUpdateLog_ProductSAP
    on StocktakeUpdateLog (ProductNo, SAPBatchNo)
go
