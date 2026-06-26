create table ProductBarcode
(
    ProductBarcodeId          char(12) not null
        constraint PK_ProductBarcodeItem
            primary key,
    ProductBarcode            nvarchar(50),
    ProductBarcodeDescription nvarchar(200),
    CreateDate                datetime
        constraint DF_ProductBarcodeItem_CreateDate default getdate()
)
go

