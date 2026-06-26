create table Cell_Product
(
    Cell_ProductId char(12)
        constraint DF_Cell_Product_Cell_ProductId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Cell_Product
            primary key,
    CellId         char(12),
    ProductId      char(12),
    ModifyDate     datetime
        constraint DF_Cell_Product_ModifyDate default getdate(),
    CreateDate     datetime
        constraint DF_Cell_Product_CreateDate default getdate()
)
go

