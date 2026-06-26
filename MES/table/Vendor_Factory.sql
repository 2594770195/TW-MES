create table Vendor_Factory
(
    Vendor_FactoryId char(12)
        constraint DF_Table_1_Vendor_UserId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Vendor_Factory
            primary key,
    VendorId         char(12),
    FactoryId        char(12),
    ModifyDate       datetime
        constraint DF_Vendor_Factory_ModifyDate default getdate(),
    CreateDate       datetime
        constraint DF_Vendor_Factory_CreateDate default getdate()
)
go

