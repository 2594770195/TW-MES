create table LoadingItemLotParams
(
    LoadingItemLotParamsId IDType not null
        constraint PK_LoadingItemLotParams
            primary key,
    LoadingItemLotId       IDType,
    MOItemId               IDType,
    ParamsType             varchar(50),
    ParamsValue            SysNumberType,
    CreateUserId           IDType,
    CreateDate             datetime
        constraint DF_LoadingItemLotParams_CreateDate default getdate()
)
go

