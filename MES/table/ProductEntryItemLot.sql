create table ProductEntryItemLot
(
    ProductEntryItemLotId char(12)
        constraint DF_ProductEntryItemLot_ProductEntryItemLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_ProductEntryItemLot
            primary key,
    ProductEntryItemId    char(12),
    CellId                char(12),
    LotSN                 nvarchar(50),
    Qty                   decimal(18, 8)
        constraint DF_ProductEntryItemLot_Qty default 0,
    ProductionLotNO       nvarchar(50),
    ModifyDate            datetime
        constraint DF_ProductEntryItemLot_ModifyDate default getdate(),
    CreateDate            datetime
        constraint DF_ProductEntryItemLot_CreateDate default getdate()
)
go

