create table PickingListItemLot
(
    PickingListItemLotId char(12)
        constraint DF_PickingListItemLot_PickingListItemLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_PickingListItemLot
            primary key,
    PickingListItemId    char(12)
        constraint DF_PickingListItemLot_PickingListItemId default substring(CONVERT([char](36), newid(), 0), 1, 12)    not null,
    ProductId            char(12),
    LotSN                nvarchar(50),
    Qty                  decimal(18, 8)
        constraint DF_PickingListItemLot_Qty default 0,
    PickType             char,
    CellId               char(12),
    CreateUserId         char(12),
    CreateDate           datetime
        constraint DF_PickingListItemLot_CreateDate default getdate()                                                   not null,
    IsPicking            bit default 1,
    ActualPickQty        decimal(18, 8),
    OrgLotSN             nvarchar(50),
    ProductionLotNO      nvarchar(50)
)
go

