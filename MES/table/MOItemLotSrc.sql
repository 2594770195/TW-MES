create table MOItemLotSrc
(
    MOItemLotSrcId char(12) not null
        constraint PK_MOItemLotSrc
            primary key,
    MOItemLotId    char(12),
    IsTaskStart    bit,
    IsPrint        bit,
    LotSn          nvarchar(50),
    MLotSn         nvarchar(50),
    NetWeight      decimal(18, 4),
    GrossWeight    decimal(18, 4),
    DeleteFlag     char,
    CreateDate     datetime,
    CreateUserId   char(12)
)
go

