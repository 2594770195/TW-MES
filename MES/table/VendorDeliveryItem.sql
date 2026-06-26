create table VendorDeliveryItem
(
    VendorDeliveryItemId char(12)
        constraint DF_VendorDeliveryItem_VendorDeliveryItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_VendorDeliveryItem
            primary key,
    VendorDeliveryId     char(12),
    ItemSequence         varchar(20),
    ItemStates           varchar(20)
        constraint DF_VendorDeliveryItem_VendorDeliveryItemStatus_1 default 10,
    POId                 char(12),
    POItemId             char(12),
    ProductId            char(12),
    DeliveryUOMId        char(12),
    ItemQtyDelivery      decimal(18, 6)
        constraint DF_VendorDeliveryItem_ItemQtyDelivery default 0,
    ItemQtyStarted       decimal(18, 6)
        constraint DF_VendorDeliveryItem_ItemQtyStarted default 0,
    ItemQtySpare         decimal(18, 6)
        constraint DF_VendorDeliveryItem_ItemSpareQty default 0,
    ItemQtySpareStarted  decimal(18, 6)
        constraint DF_VendorDeliveryItem_ItemQtySpareStarted default 0,
    ItemQtyReceived      decimal(18, 6)
        constraint DF_VendorDeliveryItem_ItemQtyReceived default 0,
    ItemQtyEntry         decimal(18, 6)
        constraint DF_VendorDeliveryItem_ItemQtyEntry default 0,
    ItemQtyRejected      decimal(18, 6)
        constraint DF_VendorDeliveryItem_ItemQtyRejected default 0,
    ItemQtySpareRejected decimal(18, 6)
        constraint DF_VendorDeliveryItem_ItemQtySpareStarted1 default 0,
    IsUrgent             bit
        constraint DF_VendorDeliveryItem_IsUrgent default 0,
    ModifyDate           datetime
        constraint DF_VendorDeliveryItem_ModifyDate default getdate(),
    CreateDate           datetime
        constraint DF_VendorDeliveryItem_CreateDate default getdate(),
    Comments             nvarchar(100),
    GrossWeight          decimal(18, 6),
    GrossWeightSum       decimal(18, 6)
)
go

