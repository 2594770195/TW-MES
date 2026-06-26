create table Customer
(
    CustomerId          char(12)
        constraint DF_Customer_CustomerId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Customer
            primary key,
    CustomerName        nvarchar(50)
        constraint IX_Customer
            unique,
    CustomerShortName   nvarchar(50),
    CustomerDescription nvarchar(100),
    CustomerAddress     nvarchar(100) default '',
    IsOften             bit
        constraint DF_Customer_IsOften default 0,
    DeleteFlag          char,
    ModifyDate          datetime
        constraint DF_Customer_ModifyDate default getdate(),
    CreateDate          datetime
        constraint DF_Customer_CreateDate default getdate(),
    CustomerClass       nvarchar(50),
    ClassDescription    nvarchar(100)
)
go

