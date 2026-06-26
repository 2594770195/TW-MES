create table Vendor
(
    VendorId          char(12)
        constraint DF_Vendor_VendorId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Vendor
            primary key,
    VendorName        nvarchar(50),
    VendorShortName   nvarchar(50),
    VendorDescription nvarchar(100),
    VendorAddress     nvarchar(100),
    BarcodeHeader     char(4)
        constraint DF_Vendor_ObjectPKHeader default space(0),
    VendorTypeId      char(12),
    IsOften           bit
        constraint DF_Vendor_IsOften default 0,
    Industry          nvarchar(50),
    VendorNature      varchar(20),
    VendorGrade       varchar(10),
    DeleteFlag        varchar(20)
        constraint DF_Vendor_DeleteFlag default '',
    ModifyDate        datetime
        constraint DF_Vendor_ModifyDate default getdate(),
    CreateDate        datetime
        constraint DF_Vendor_CreateDate default getdate()
)
go

