create table LoadingItemLotPS
(
    LoadingItemLotPSId     IDType not null
        constraint PK_LoadingItemLotPS
            primary key,
    LoadingItemLotDetailId IDType,
    LotSN                  LotSN,
    ProductId              IDType,
    SupplyQty              SysNumberType,
    SupplyWareHouseId      IDType,
    IsRequest              bit,
    IsApporved             bit
        constraint DF_LoadingItemLotPS_IsApporved default 0,
    CreateUserId           IDType,
    CreateDate             datetime
        constraint DF_LoadingItemLotPS_CreateDate default getdate()
)
go

