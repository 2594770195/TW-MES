create table SO
(
    SOId              char(12)
        constraint DF_SO_SOId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_SO
            primary key,
    SOName            nvarchar(50),
    SODescription     nvarchar(100),
    SOType            varchar(20),
    SOStates          varchar(20),
    CustomerId        char(12),
    FactoryId         char(12),
    DeliveryFactoryId char(12),
    CreateUserId      char(12),
    CreateDate        datetime
        constraint DF_SO_CreateDate default getdate(),
    ModifyDate        datetime
        constraint DF_SO_ModifyDate default getdate(),
    IsBack            bit default 0,
    SOTypeDesc        nvarchar(100),
    CreateUser        nvarchar(100)
)
go

