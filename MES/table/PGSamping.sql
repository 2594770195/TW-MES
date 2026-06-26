create table PGSamping
(
    PGSampingId       IDType not null
        constraint PK_PGSamping
            primary key,
    ProductionGrindId IDType,
    CurrentCount      int,
    SampingQty        SysNumberType,
    CreateDate        datetime
        constraint DF_PGSamping_CreateDate default getdate(),
    IsInspection      bit
        constraint DF_PGSamping_IsInspection default 0
)
go

