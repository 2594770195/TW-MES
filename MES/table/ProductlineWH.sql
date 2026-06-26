create table ProductlineWH
(
    ProductlineWHId  char(12) not null
        constraint PK_ProductlineWH
            primary key,
    Productline      nvarchar(20),
    warehouse        nvarchar(20),
    warehouseid      nchar(12),
    factoryid        nchar(12),
    WMSWarehouseCode nvarchar(20),
    factoryname      nvarchar(20)
)
go

