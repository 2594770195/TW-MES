create table Customer_User
(
    Customer_UserId char(12)
        constraint DF_Customer_User_Customer_UserId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Customer_User
            primary key,
    CustomerId      char(12),
    UserId          char(12),
    CreateDate      datetime
        constraint DF_Customer_User_CreateDate default getdate(),
    ModifyDate      datetime
        constraint DF_Customer_User_ModifyDate default getdate()
)
go

