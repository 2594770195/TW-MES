create table SOItem
(
    SOItemId        char(12)
        constraint DF_SOItem_SOItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_SOItem
            primary key,
    SOId            char(12),
    ItemSequence    varchar(20),
    ItemStates      varchar(20),
    ProductId       char(12),
    CustomerPN      nvarchar(50),
    SaleQty         decimal(18, 8)
        constraint DF_SOItem_SaleQty default 0,
    UOMId           char(12),
    RequiredDate    datetime,
    DeliveryLockQty decimal(18, 8)
        constraint DF_SOItem_SaleDeliveryLQty default 0,
    DeliveryRealQty decimal(18, 8)
        constraint DF_SOItem_SaleDeliveryRQty default 0,
    BackLockQty     decimal(18, 8)
        constraint DF_SOItem_SaleBackLockQty default 0,
    BackRealQty     decimal(18, 8)
        constraint DF_SOItem_RealSaleBackQty default 0,
    ERPItemId       varchar(30),
    DeleteFlag      varchar(5)
        constraint DF_SOItem_IsCancel default '',
    CreateDate      datetime
        constraint DF_SOItem_CreateDate default getdate(),
    ModifyDate      datetime
        constraint DF_SOItem_ModifyDate default getdate(),
    FactoryId       char(12),
    WareHouseId     char(12),
    OldQty          decimal(18, 8),
    OldUOMId        char(12)
)
go

