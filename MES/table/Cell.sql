create table Cell
(
    CellId          char(12)
        constraint DF_Cell_CellId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Cell
            primary key,
    WorkcenterId    char(12),
    ShelfId         char(12),
    CellName        nvarchar(30),
    CellDescription nvarchar(50),
    DisposeObjectId char(12),
    MaxInventory    decimal(18, 6),
    FloorSalverQty  int,
    IsActivity      bit
        constraint DF_Cell_IsActivity default 1,
    IsAllProduct    bit
        constraint DF_Cell_IsAllProduct default 1,
    IsAllLot        bit
        constraint DF_Cell_IsAllLot default 1,
    IsDefaultCell   bit
        constraint DF_Cell_IsDefaultCell default 0,
    IsFIFO          bit
        constraint DF_Cell_IsFIFO default 0,
    IsSeparatedMFO  bit
        constraint DF_Cell_IsSeparatedMFO default 0,
    LongLimit       decimal(18, 2)
        constraint DF_Cell_LongLimit default 0,
    WideLimit       decimal(18, 2)
        constraint DF_Cell_WideLimit default 0,
    HeightLimit     decimal(18, 2)
        constraint DF_Cell_LimitHeight default 0,
    WeightLimit     decimal(18, 2)
        constraint DF_Cell_WeightLimit default 0,
    MaxVolume       decimal(18, 2)
        constraint DF_Cell_MaxVolume default 0,
    RouteOrder      nvarchar(50),
    TierLevel       int,
    X_Coordinate    decimal(18, 6),
    Y_Coordinate    decimal(18, 6),
    Z_Coordinate    decimal(18, 6),
    Orientation     nvarchar(50),
    StorageBags     int
        constraint DF_Cell_StorageBags default 0,
    ModifyDate      datetime
        constraint DF_Cell_ModifyDate default getdate(),
    CreateDate      datetime
        constraint DF_Cell_CreateDate default getdate()
)
go

