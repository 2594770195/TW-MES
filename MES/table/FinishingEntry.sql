create table FinishingEntry
(
    FinishingEntryId          char(12)
        constraint DF_FinishingEntry_FinishingEntryId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_FinishingEntry
            primary key,
    FinishingEntryName        nvarchar(50),
    FinishingEntryDescription nvarchar(100),
    FinishingEntryStates      varchar(20)
        constraint DF_FinishingEntry_ProductEntryStates default 10,
    FinishingEntryType        varchar(20),
    FinishingEntryWay         char,
    FactoryId                 char(12),
    DivisionId                char(12),
    ConfirmUserId             char(12),
    ConfirmDate               datetime,
    ApproveUserId             char(12),
    ApproveDate               datetime,
    ToErpLock                 bit
        constraint DF_FinishingEntry_ToErpLock default 0,
    ISUpload                  bit,
    CreateUserId              char(12),
    CreateDate                datetime
        constraint DF_FinishingEntry_CreateDate default getdate(),
    ModifyDate                datetime
        constraint DF_FinishingEntry_ModifyDate default getdate()
)
go

