create table ProductBarcodeDC
(
    ProductBarcodeDCId      char(12) not null
        constraint PK_ProductBarcodeDC
            primary key,
    ProductBarcodeId        char(12),
    IsMoveInDC              bit,
    SpecificationId         char(12),
    MESTxnObjectParameterId char(12),
    ScanSequence            char(2),
    CheckRuleSP             nvarchar(50)
)
go

