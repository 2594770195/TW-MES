create table Customer_Factory
(
    Customer_FactoryId char(12)
        constraint DF_Table_1_Customer_UserId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Customer_Factory
            primary key,
    CustomerId         char(12),
    FactoryId          char(12),
    CreateDate         datetime
        constraint DF_Customer_Factory_CreateDate default getdate(),
    ModifyDate         datetime
        constraint DF_Customer_Factory_ModifyDate default getdate()
)
go

