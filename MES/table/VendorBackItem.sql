create table VendorBackItem
(
    VendorBackItemId char(12)
        constraint DF_Table_1_ProductEntryItemId_1 default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_VendorBackItem
            primary key,
    VendorBackId     char(12),
    ItemSequence     varchar(20),
    WorkcenterId     char(12),
    POId             char(12),
    POItemId         char(12),
    ProductId        char(12),
    BackQty          decimal(18, 8)
        constraint DF_VendorBackItem_BackQty default 0,
    RealBackQty      decimal(18, 8)
        constraint DF_VendorBackItem_RealBackQty default 0,
    UOMId            char(12),
    DeleteFlag       varchar(5)
        constraint DF_VendorBackItem_DeleteFlag default ''                                                   not null,
    ERPItemId        varchar(30),
    ModifyDate       datetime
        constraint DF_VendorBackItem_ModifyDate default getdate(),
    CreateDate       datetime
        constraint DF_VendorBackItem_CreateDate default getdate(),
    DateRequired     datetime,
    FactoryId        char(12)
)
go

