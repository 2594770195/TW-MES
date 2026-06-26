create table MOItemLot
(
    MOItemLotId  IDType
        constraint DF_MOItemLot_MOItemLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_MOItemLot
            primary key,
    MOItemId     IDType,
    MOItemTaskId IDType,
    LotId        IDType,
    LotSN        LotSN,
    Qty          SysNumberType
        constraint DF_MOItemLot_Qty default 0,
    PrintCount   int
        constraint DF_MOItemLot_PrintCount_1 default 0,
    DeleteFlag   char
        constraint DF_MOItemLot_DeleteFlag_1 default ''                                               not null,
    ModifyDate   datetime
        constraint DF_MOItemLot_ModifyDate default getdate(),
    CreateDate   datetime
        constraint DF_MOItemLot_CreateDate default getdate()
)
go

