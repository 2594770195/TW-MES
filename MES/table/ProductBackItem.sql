create table ProductBackItem
(
    ProductBackItemId char(12)
        constraint DF_ProductBackItem_ProductBackItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_ProductBackItem
            primary key,
    ProductBackId     char(12),
    ItemSequence      varchar(20),
    ItemStates        varchar(20),
    MOId              char(12),
    MOItemId          char(12),
    POId              char(12),
    POItemId          char(12),
    POItemMId         char(12),
    ProductId         char(12),
    BackQty           decimal(18, 3)
        constraint DF_ProductBackItem_ItemQty default 0,
    StartMLotSNQty    decimal(18, 3)
        constraint DF_ProductBackItem_StartMLotSNQty default 0,
    RealBackQty       decimal(18, 3)
        constraint DF_ProductBackItem_RealBackQty default 0,
    HedgeQty          decimal(18, 3)
        constraint DF_ProductBackItem_DepositoryQty default 0,
    ItemUOMId         char(12),
    WorkcenterId      char(12),
    ERPItemId         varchar(30),
    DeleteFlag        varchar(5)
        constraint DF_ProductBackItem_DeleteFlag default '',
    ModifyDate        datetime
        constraint DF_ProductBackItem_ModifyDate default getdate(),
    CreateDate        datetime
        constraint DF_ProductBackItem_CreateDate default getdate()                                                not null,
    CostCenterId      char(12),
    SAPInfor          nvarchar(max) collate Chinese_PRC_CI_AS_KS,
    IsPost            bit default 0,
    ToSAPStates       nvarchar(20)
)
go

