create table WorkCenter_Factory
(
    WorkCenter_FactoryID char(12)
        constraint DF_WorkCenter_Factory_WorkCenter_FactoryID default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_WorkCenter_Factory
            primary key,
    WorkCenterID         char(12),
    FactoryID            char(12)
)
go

