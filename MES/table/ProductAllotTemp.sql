create table ProductAllotTemp
(
    ProductAllotTempId int identity
        constraint PK_ProductAllotTemp
            primary key,
    FromWareHouseId    char(12),
    FromWareHouseName  nvarchar(50),
    FromCellId         char(12),
    ToWareHouseId      char(12),
    ToWareHouseName    nvarchar(50),
    ToCellName         nvarchar(50),
    ProductId          char(12),
    ProductName        nvarchar(50),
    LotSn              nvarchar(50),
    BoxSN              nvarchar(50),
    ProductClassify    char(10),
    AllotType          char,
    Qty                decimal(18, 3),
    UserId             char(12),
    MetadataName       nvarchar(50)
)
go

