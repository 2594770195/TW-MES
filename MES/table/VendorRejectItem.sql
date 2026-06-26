create table VendorRejectItem
(
    VendorRejectItemId   char(12)
        constraint DF_Table_1_VendorBackItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_VendorRejectItem
            primary key,
    VendorRejectId       char(12),
    ItemSequence         varchar(20),
    POId                 char(12),
    POItemId             char(12),
    ProductId            char(12),
    ItemQtyRejected      decimal(18, 8)
        constraint DF_Table_1_ItemBackQty default 0,
    ItemUOMId            char(12),
    VendorDeliveryItemId char(12),
    ModifyDate           datetime
        constraint DF_VendorRejectItem_ModifyDate default getdate(),
    CreateDate           datetime
        constraint DF_VendorRejectItem_CreateDate default getdate(),
    WorkcenterId         char(12)
)
go

