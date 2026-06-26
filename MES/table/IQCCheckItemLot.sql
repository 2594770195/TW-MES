create table IQCCheckItemLot
(
    IQCCheckItemLotId char(12)
        constraint DF_Table_1_IQCCheckItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_IQCCheckItemLot
            primary key,
    IQCCheckItemId    char(12)                                                                         not null,
    LotSN             nvarchar(50),
    CheckQty          decimal(18, 8)
        constraint DF_IQCCheckItemLot_FQTY default 0,
    ItemValue         decimal(18, 8)
        constraint DF_IQCCheckItemLot_ItemValue default 0,
    ItemUOMId         char(12),
    CheckResult       char
        constraint DF_IQCCheckItemLot_CheckResult default '',
    DefectCode        nvarchar(50),
    DefectDescription nvarchar(100),
    CreateUserId      char(12),
    CreateDate        datetime
        constraint DF_IQCCheckItemLot_CreateDate default getdate()
)
go

