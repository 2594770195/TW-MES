create table MOAllotMODetail
(
    MOAllotMODetailId IDType not null
        constraint PK_MOAllotMODetail
            primary key,
    MOAllotRequestId  IDType,
    MOId              IDType,
    MOItemId          char(12),
    ProductId         IDType,
    ProductionLotNO   varchar(100),
    AllotQty          SysNumberType
        constraint DF_MOAllotMODetail_AllotQty default 0,
    TempFactoryId     IDType,
    TempWorkcenterId  IDType,
    CreateDate        datetime
        constraint DF_MOAllotMODetail_CreateDate default getdate(),
    AllotQtyCurrent   SysNumberType
        constraint DF_MOAllotMODetail_AllotQtyCurrent default 0,
    ToFactoryId       IDType,
    ToWareHouseId     IDType,
    IsProduction      bit
        constraint DF__MOAllotMO__IsPro__691E6EF7 default 1
)
go

