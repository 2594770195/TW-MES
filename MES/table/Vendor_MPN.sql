create table Vendor_MPN
(
    Vendor_MPNId     char(12)
        constraint DF_Table_1_MPNId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Vendor_MPN
            primary key,
    Vendor_ProductId char(12),
    MPN              nvarchar(50),
    MPNAddress       nvarchar(100),
    CreateUserId     char(12),
    CreateDate       datetime
        constraint DF_Vendor_MPN_CreateDate default getdate(),
    ModifyUserId     char(12),
    ModifyDate       datetime
)
go

