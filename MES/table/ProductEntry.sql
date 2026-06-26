create table ProductEntry
(
    ProductEntryId          char(12)
        constraint DF_ProductEntry_ProductEntryId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_ProductEntry
            primary key,
    ProductEntryName        nvarchar(50),
    ProductEntryDescription nvarchar(100),
    ProductEntryClass       varchar(5),
    ProductEntryStates      varchar(20)
        constraint DF_ProductEntry_ProductEntryStatus default 10,
    ProductEntryType        varchar(20)
        constraint DF_ProductEntry_ProductEntryType default 10,
    VendorId                char(12),
    VendorDeliveryId        char(12),
    FactoryId               char(12),
    TRXTypeId               char(12),
    ApproveUserId           char(12),
    ApproveDate             datetime,
    ConfirmUserId           char(12)
        constraint DF_ProductEntry_ConfirmUserId default '',
    ConfirmDate             datetime,
    ToErpLock               bit
        constraint DF_ProductEntry_ToErpLock default 0,
    ModifyDate              datetime
        constraint DF_ProductEntry_ModifyDate default getdate(),
    CreateUserId            char(12),
    CreateDate              datetime
        constraint DF_ProductEntry_CreateDate default getdate(),
    PrintStates             bit,
    SAPInfor                nvarchar(max) collate Chinese_PRC_CI_AS_KS,
    ShutdownUserId          char(12),
    ShutdownDate            datetime default getdate(),
    ShutdownResult          nvarchar(max)
)
go

