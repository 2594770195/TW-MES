create table Vendor_ProductLot
(
    Vendor_ProductLotId  char(12)
        constraint DF_Table_1_POVendorProductId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_POVendorProductLot
            primary key,
    Vendor_ProductId     char(12),
    PKGSN                nvarchar(50),
    PKGQty               int,
    BoxSN                nvarchar(50),
    LotStatus            char(2)
        constraint DF_Vendor_ProductLot_LotStatus default 10,
    ProductionDateCode   nvarchar(20),
    ProductionDate       datetime,
    StandardQtyOfLot     decimal(18, 4),
    StandardLotQtyOfBox  int,
    ResourceId           char(12),
    PrintCount           int
        constraint DF_Vendor_ProductLot_PrintCount default 0,
    ReceiveUserId        char(12),
    IsReceiveScan        bit
        constraint DF_Vendor_ProductLot_IsReceiveScan default 0,
    ReceiveResourceId    char(12),
    ReceiveDate          datetime,
    IQCDefectCodeId      char(12),
    IQCUserId            char(12),
    IQCResourceId        char(12),
    IQCAcceptCode        char
        constraint DF_Vendor_ProductLot_IQCAcceptCode default 0,
    StartDate            datetime,
    POId                 char(12),
    POItemId             char(12),
    VendorDeliveryItemId char(12),
    CreateUserId         char(12),
    CreateDate           datetime
        constraint DF_POVendorProductLot_CreateDate default getdate()
)
go

