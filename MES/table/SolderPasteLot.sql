create table SolderPasteLot
(
    SolderPasteLotId char(12)
        constraint DF_AccessoryLot_AccessoryLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_SolderPasteLot
            primary key,
    LotId            char(12),
    LotSN            nvarchar(50),
    LotQty           decimal(18, 6)
        constraint DF_AccessoryLot_LotQty default 0,
    UOMId            char(12),
    OrgSN            nvarchar(50),
    DataStatus       char(2)
        constraint DF_AccessoryLot_DataStatus default '00',
    ProductId        char(12),
    VendorId         char(12),
    ValidityDate     date
        constraint DF_SolderPasteLot_ValidityDate default NULL,
    ProductionDate   nvarchar(50),
    ProductionLotNO  nvarchar(50),
    StandardWeight   decimal(18, 2),
    IsUsed           char
        constraint DF_AccessoryLot_IsUsed default 'N',
    IsEmpty          char
        constraint DF_AccessoryLot_IsEmpty default 'N',
    IsCancel         bit
        constraint DF_AccessoryLot_IsCancel default 0,
    ThawDate         datetime,
    UnsealDate       datetime,
    TxnDate          datetime,
    CreateUserId     char(12),
    CreateDate       datetime
        constraint DF_AccessoryLot_CreateDate default getdate()
)
go

