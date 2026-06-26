create table MOItemReprintLot
(
    MOItemReprintLotId char(12)
        constraint DF_MOItemReprintLot_MOItemReprintLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_MOItemReprintLot
            primary key,
    MOItemId           char(12),
    MOId               char(12),
    MOItemTaskId       char(12),
    LotId              char(12),
    LotSN              nvarchar(50),
    LotQty             decimal(18, 4),
    ProductId          char(12),
    IsReprint          bit
        constraint DF_MOItemReprintLot_IsReprint default 0,
    CreateDate         datetime
        constraint DF_MOItemReprintLot_CreateDate default getdate()
)
go

