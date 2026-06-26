create table Vendor_User
(
    Vendor_UserId char(12)
        constraint DF_Table_1_Vendor_UsertId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Vendor_User
            primary key,
    VendorId      char(12),
    UserId        char(12),
    ModifyDate    datetime
        constraint DF_Vendor_User_ModifyDate default getdate(),
    CreateDate    datetime
        constraint DF_Vendor_User_CreateDate default getdate()
)
go

