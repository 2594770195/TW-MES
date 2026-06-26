create table LoadingItemLot
(
    LoadingItemLotId IDType not null
        constraint PK_LoadingItemLot
            primary key,
    IsComplete       bit
        constraint DF_LoadingItemLot_IsComplete default 0,
    EquipmentId      IDType,
    EmployeeId       IDType,
    SpecificationId  nvarchar(50),
    MOId             IDType,
    MOItemId         IDType,
    WorkCenterId     IDType,
    MOItemTaskId     IDType,
    LastMakingDate   datetime,
    CreateUserId     IDType,
    CreateDate       datetime
        constraint DF_LoadingItemLot_CreateDate default getdate(),
    CompleteDate     datetime,
    PickingListId    IDType,
    StirTime         SysNumberType
        constraint DF_LoadingItemLot_StirTime default 0,
    StirState        bit
        constraint DF_LoadingItemLot_StirState default 1,
    StirCurrDate     datetime
        constraint DF_LoadingItemLot_StirStartDate default getdate(),
    LotSN            varchar(100),
    UVFirst          bit
)
go

