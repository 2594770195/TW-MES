-- =============================================
-- 盘点导入暂存表：Web 导入程序写入，存储过程 Batch_StocktakeUpdateRMInventory 读取
-- =============================================
create table TempStocktakeData
(
    TempStocktakeDataId bigint identity
        constraint PK_TempStocktakeData
            primary key,
    RowNo               int            not null, -- Excel 行号，便于定位错误数据
    FactoryName         nvarchar(100)  not null, -- 工厂名称
    WarehouseName       nvarchar(100)  not null, -- 仓库名称
    ProductNo           nvarchar(100)  not null, -- 物料号
    StockQty            decimal(18, 8) not null, -- 实盘库存数量
    FrozenQty           decimal(18, 8)
        constraint DF_TempStocktakeData_FrozenQty default 0, -- 冻结数量，不为0时将同一SAP批次的库存LotStatus置为0（冻结）
    UOMName             nvarchar(50)   not null, -- 单位名称或单位编码
    SAPBatchNo          nvarchar(100)  not null, -- SAP批号，匹配 ProductionLotNO
    LotSN               nvarchar(100),           -- MES内部批号，非必填，不参与主匹配
    CreateUserId        char(12),                -- 导入操作人
    CreateDate          datetime
        constraint DF_TempStocktakeData_CreateDate default getdate() -- 导入时间
)
go

-- 按工厂、仓库、物料、SAP批号查询时加速重复校验
create index IX_TempStocktakeData_StocktakeKey
    on TempStocktakeData (FactoryName, WarehouseName, ProductNo, SAPBatchNo)
go
