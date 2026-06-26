create table PGrindParams
(
    PGrindParamsId    IDType not null
        constraint PK_PGrindParams
            primary key,
    ProductionGrindId IDType,
    GapSampFlag       int,
    CurrentCount      int,
    ParamsType        varchar(50),
    ParamsValue       SysNumberType,
    CreateUserId      IDType,
    CreateDate        datetime
        constraint DF_PGrindParams_CreateDate default getdate(),
    ParamsValueChar   varchar(1000)
)
go

