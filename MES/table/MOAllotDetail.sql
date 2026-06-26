create table MOAllotDetail
(
    MOAllotDetailId  IDType not null
        constraint PK_MOAllotDetail
            primary key,
    MOAllotRequestId IDType,
    ProductId        IDType,
    ItemQtyRequired  SysNumberType,
    AllotQty         SysNumberType,
    FromFactoryId    IDType,
    FromWareHouseId  IDType,
    ToFactoryId      IDType,
    ToWareHouseId    IDType,
    IsMergeMO        bit,
    CreateDate       datetime
        constraint DF_MOAllotDetail_CreateDate default getdate()
)
go

