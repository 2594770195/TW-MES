create table LockRecord
(
    LockRecordId     char(12)
        constraint DF_Table_1_MaterialLockId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_LockRecord
            primary key,
    LockType         varchar(5)
        constraint DF_LockRecord_LockType default '0',
    WarehouseId      char(12),
    CellId           char(12),
    ProductId        char(12),
    MOItemTaskId     char(12),
    MOId             char(12),
    LotSN            nvarchar(100),
    VendorId         char(12),
    IsLock           bit
        constraint DF_LockRecord_IsLock default 0,
    LockReason       nvarchar(200),
    LockDate         datetime,
    LockPersNumber   nvarchar(30),
    UnLockReason     nvarchar(200),
    UnLockDate       datetime,
    UnLockPersNumber nvarchar(30),
    CreateUserId     char(12),
    CreateDate       datetime
        constraint DF_LockRecord_CreateDate default getdate()
)
go

