create table PGFilter
(
    PGFilterId        IDType not null
        constraint PK_PGFilter
            primary key,
    ProductionGrindId IDType
        constraint FK_PGFilter_ProductionGrind
            references ProductionGrind,
    StartTime         datetime,
    StopTime          datetime,
    FilterTime        SysNumberType,
    CreateDate        datetime
        constraint DF_PGFilter_CreateDate default getdate(),
    FilterType        nvarchar(16),
    FilterQty         SysNumberType
)
go

