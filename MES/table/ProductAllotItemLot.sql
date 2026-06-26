create table ProductAllotItemLot
(
    ProductAllotItemLotId char(12)
        constraint DF_ProductAllotItemLot_ProductAllotItemLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_ProductAllotItemLot
            primary key,
    ProductAllotItemId    char(12),
    LotSN                 nvarchar(50),
    BoxSN                 nvarchar(50),
    Qty                   decimal(18, 6)
        constraint DF_ProductAllotItemLot_Qty default 0,
    CellId                char(12),
    ToCellId              char(12),
    IsAEScan              bit
        constraint DF_ProductAllotItemLot_IsReceiveScan default 1,
    AllotType             char,
    CreateUserId          char(12),
    CreateDate            datetime
        constraint DF_ProductAllotItemLot_CreateDate default getdate(),
    IsAOScan              bit default 1,
    ToLotSN               nvarchar(50),
    MOProductionLotId     char(12)
)
go

