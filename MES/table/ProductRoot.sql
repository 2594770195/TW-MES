create table ProductRoot
(
    ProductRootId    char(12)
        constraint DF_ProductRoot_ProductRootId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_ProductRoot
            primary key,
    ProductName      nvarchar(50)
        constraint IX_ProductRoot_ProductName
            unique,
    DefaultProductId char(12),
    ProductFamilyId  char(12),
    CreateDate       datetime
        constraint DF_ProductRoot_CreateDate default getdate()
)
go

