create table LoadingItemLotRecord
(
    LoadingItemLotRecordId IDType not null
        constraint PK_LoadingItemLotRecord
            primary key,
    LoadingItemLotDetailId IDType,
    LotSN                  LotSN,
    Qty                    SysNumberType,
    EmployeeId             IDType,
    CreateUserId           IDType,
    CreateDate             datetime
        constraint DF_LoadingItemLotRecord_CreateDate default getdate(),
    IsPicking              bit
        constraint DF_LoadingItemLotRecord_IsPicking default 0,
    RealQty                decimal(18, 3)
)
go

