create table ProductBackItemLot
(
    ProductBackItemLotId char(12)
        constraint DF_ProductBackItemLot_ProductBackItemLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_ProductBackItemLot
            primary key,
    ProductBackItemId    char(12)                                                                                       not null,
    LotSN                nvarchar(50)                                                                                   not null,
    CellId               char(12),
    Qty                  decimal(18, 8)
        constraint DF_ProductBackItemLot_Qty default 0,
    MLotType             char
        constraint DF_ProductBackItemLot_LotType default '0',
    IsBackPutaway        bit
        constraint DF_ProductBackItemLot_IsScaned default 0,
    PrintCount           int
        constraint DF_ProductBackItemLot_PrintCount default 0,
    CreateUserId         char(12),
    CreateDate           datetime
        constraint DF_ProductBackItemLot_CreateDate default getdate()
)
go

