create table PGUseParts
(
    PGUsePartsId      IDType not null
        constraint PK_PGUseParts
            primary key,
    ProductionGrindId IDType,
    PartsId           IDType,
    PartsType         varchar(16),
    CreateDate        datetime
        constraint DF_PGUseParts_CreateDate default getdate(),
    PartsQty          int
        constraint DF_PGUseParts_PartsQty default 1,
    PartsCategory     varchar(16)
)
go

