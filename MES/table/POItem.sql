create table POItem
(
    POItemId         char(12)
        constraint DF_POItem_POItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_POItem
            primary key,
    POId             char(12),
    ItemSequence     varchar(20),
    ItemStates       varchar(20)
        constraint DF_POItem_POItemStates default 10,
    ProductId        char(12),
    ItemQtyOrgReq    decimal(18, 6),
    ItemQtyRequired  decimal(18, 6)
        constraint DF_POItem_ItemQtyRequired default 0,
    ItemQtyStarted   decimal(18, 6)
        constraint DF_POItem_ItemStartQty default 0,
    ItemQtySpare     decimal(18, 6)
        constraint DF_POItem_AttachedQty default 0,
    ItemQtyReceived  decimal(18, 6)
        constraint DF_POItem_ItemQtyReceived default 0,
    ItemQtyRejected  decimal(18, 6)
        constraint DF_POItem_ItemQtyRejected default 0,
    ItemQtyEntry     decimal(18, 6)
        constraint DF_POItem_ItemQtyREntry default 0,
    ItemQtyBack      decimal(18, 6)
        constraint DF_POItem_ItemQtyBack default 0,
    ItemSQtyDelivery decimal(18, 6)
        constraint DF_POItem_ItemSQtyDelivery default 0,
    PurchaseUOMId    char(12),
    IsBeyondDelivery bit
        constraint DF_POItem_IsBeyondDelivery default 0,
    DateRequired     datetime,
    PlanDeliveryDate datetime,
    ERPItemId        varchar(30),
    DeleteFlag       varchar(5)
        constraint DF_POItem_DeleteFlag default '',
    ModifyDate       datetime
        constraint DF_POItem_ModifyDate default getdate(),
    CreateDate       datetime
        constraint DF_POItem_CreateDate default getdate(),
    WorkcenterId     char(12)
)
go

