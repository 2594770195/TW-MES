create table UOM
(
    UOMId          char(12)
        constraint DF_UOM_UOMId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_UOM
            primary key,
    UOMName        nvarchar(50),
    UOMDescription nvarchar(100),
    CreateDate     datetime
        constraint DF_UOM_CreateDate default getdate(),
    ERPUnitcode    nvarchar(35)
)
go

