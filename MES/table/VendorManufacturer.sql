create table VendorManufacturer
(
    VendorManufacturerId char(12) not null
        constraint PK_VendorManufacturer
            primary key,
    VendorId             char(12),
    EquipmentId          char(12),
    CreateDate           datetime
        constraint DF_VendorManufacturer_CreateDate default getdate()
)
go

