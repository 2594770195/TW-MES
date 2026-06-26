create table LoadingItemLotDetail
(
    LoadingItemLotDetailId IDType not null
        constraint PK_LoadingItemLotDetail
            primary key,
    LoadingItemLotId       IDType,
    MOItemId               IDType,
    ItemQtyRequired        SysNumberType
        constraint DF_LoadingItemLotDetail_ItemQtyRequired default 0,
    ActualQty              SysNumberType
        constraint DF_LoadingItemLotDetail_ActualQty default 0,
    LastMakingDate         datetime,
    CreateDate             datetime
        constraint DF_LoadingItemLotDetail_CreateDate default getdate()
)
go

