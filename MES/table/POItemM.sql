create table POItemM
(
    POItemMId       char(12) not null
        constraint PK_POItemM
            primary key,
    POItemId        char(12),
    ProductId       char(12),
    ItemQtyRequired decimal(18, 6)
        constraint DF_POItemM_ItemQtyRequired default 0,
    ItemQtyIssued   decimal(18, 8)
        constraint DF_POItemM_ItemQtyIssued default 0,
    ItemQtyBack     decimal(18, 8)
        constraint DF_POItemM_ItemQtyBack default 0,
    ItemBasicQty    decimal(18, 8)
        constraint DF_POItemM_ItemQtyBack1 default 0,
    UOMId           char(12),
    ERPItemMId      varchar(30),
    ModifyDate      datetime,
    CreateDate      datetime
        constraint DF_POItemM_CreateDate default getdate()
)
go

