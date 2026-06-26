create table ProductEntryItem
(
    ProductEntryItemId   char(12)
        constraint DF_ProductEntryItem_ProductEntryItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_ProductEntryItem
            primary key,
    ProductEntryId       char(12),
    ItemSequence         varchar(20),
    ItemStates           varchar(20),
    ProductId            char(12),
    ItemQtyEntry         decimal(18, 3)
        constraint DF_ProductEntryItem_ItemQty default 0,
    UOMId                char(12),
    POId                 char(12),
    POItemId             char(12),
    VendorDeliveryItemId char(12),
    WorkcenterId         char(12),
    ModifyDate           datetime
        constraint DF_ProductEntryItem_ModifyDate default getdate(),
    CreateDate           datetime
        constraint DF_ProductEntryItem_CreateDate default getdate(),
    CostCenterId         char(12),
    ToSAPStates          nvarchar(20),
    SAPInfor             nvarchar(max) collate Chinese_PRC_CI_AS_KS,
    OrderName            nvarchar(50)
)
go

