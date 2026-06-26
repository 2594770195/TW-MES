create table PO
(
    POId          char(12)
        constraint DF_PO_POId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_PO
            primary key,
    POName        nvarchar(50),
    PODescription nvarchar(100),
    POType        varchar(20)
        constraint DF_PO_POType default 0                                               not null,
    POStates      varchar(20)
        constraint DF_PO_POStates default 10,
    FactoryId     char(12),
    VendorId      char(12),
    ReleaseDate   datetime
        constraint DF_PO_ReleaseDate default getdate(),
    DeliveryDate  datetime,
    DeleteFlag    varchar(5),
    ModifyDate    datetime
        constraint DF_PO_ModifyDate default getdate(),
    CreateUserId  char(12),
    CreateDate    datetime
        constraint DF_PO_CreateDate default getdate(),
    Ratify        nchar(4)
)
go

