create table PickingListOtherTemp
(
    PickingListOtherTempId int identity
        constraint PK_PickingListOtherTemp
            primary key,
    FromWareHouseId        char(12),
    FromWareHouseName      nvarchar(50),
    ProductId              char(12),
    ProductName            nvarchar(50),
    LotSn                  nvarchar(50),
    BoxSN                  nvarchar(50),
    ProductClassify        char(10),
    AllotType              char,
    Qty                    decimal(18, 3),
    UserId                 char(12),
    MetadataName           nvarchar(50),
    CostCenterId           nvarchar(50),
    PickingUser            nvarchar(50)
)
go

