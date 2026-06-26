create table Customer_Product
(
    Customer_ProductId char(12)
        constraint DF_Customer_Product_Customer_ProductId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Customer_Product
            primary key,
    CustomerId         char(12),
    ProductId          char(12),
    CustomerPN         nvarchar(50),
    ModifyDate         datetime
        constraint DF_Customer_Product_ModifyDate default getdate(),
    CreateDate         datetime
        constraint DF_Customer_Product_CreateDate default getdate()
)
go

