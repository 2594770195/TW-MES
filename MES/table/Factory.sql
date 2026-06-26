create table Factory
(
    FactoryId          char(12)
        constraint DF_Factory_FactoryId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Factory
            primary key,
    FactoryName        nvarchar(50)
        constraint IX_Factory_1
            unique,
    FactoryDescription nvarchar(100),
    FactoryAddress     nvarchar(100),
    EnterpriseId       char(12),
    ModifyDate         datetime
        constraint DF_Factory_ModifyDate default getdate(),
    CreateDate         datetime
        constraint DF_Factory_CreateDate default getdate()
)
go

