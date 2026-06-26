create table Vendor_Product
(
    Vendor_ProductId    char(12)
        constraint DF_Vendor_Product_Vendor_ProductId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Vendor_Product
            primary key,
    VendorId            char(12),
    ProductId           char(12),
    RefPrice            float
        constraint DF_Vendor_Product_RefPrice default 0,
    PriceUOMId          char(12),
    StandardQtyOfLot    decimal(18, 4)
        constraint DF_Vendor_Product_StandardQtyOfLot default 0,
    StandardLotQtyOfBox int
        constraint DF_Vendor_Product_StandardLotQtyOfBox default 1,
    IQCType             char
        constraint DF_Vendor_Product_IQCType default 1,
    InspectionType      char
        constraint DF_Vendor_Product_InspectionType default '1',
    RuleShiftTakeEffect datetime
        constraint DF_Vendor_Product_RuleShiftTakeEffect default getdate(),
    ReceiveMode         char
        constraint DF_Vendor_Product_ReceiveMode default '0',
    VendorPN            nvarchar(50),
    IsAppDelivery       bit
        constraint DF_Vendor_Product_IsAppDelivery default 0,
    ModifyDate          datetime
        constraint DF_Vendor_Product_ModifyDate default getdate(),
    CreateDate          datetime
        constraint DF_Vendor_Product_CreateDate default getdate()
)
go

