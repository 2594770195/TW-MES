create table PGFault
(
    PGFaultId         IDType not null
        constraint PK_PGFault
            primary key,
    ProductionGrindId IDType,
    FaultCodeId       IDType,
    CreateDate        datetime
        constraint DF_PGFault_CreateDate default getdate()
)
go

