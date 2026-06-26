create table Product
(
    ProductId             char(12)
        constraint DF_Product_ProductId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Product
            primary key,
    ProductRootId         char(12)
        constraint DF_Product_ProductRootId default substring(CONVERT([char](36), newid(), 0), 1, 12),
    ProductRevision       nvarchar(20)
        constraint DF_Product_ProductRevision default N'1.0',
    ProductDescription    nvarchar(1000),
    ProductDescription_1  nvarchar(200),
    ProductDescription_2  nvarchar(200),
    ManufacturerInfor     nvarchar(50),
    ProductTypeId         char(12),
    ProductClassify       char(10),
    PurchaseUOMId         char(12),
    InventoryUOMId        char(12),
    UsageUOMId            char(12),
    UOMConversion         float
        constraint DF_Product_UOMConversion default 1                                             not null,
    IsActivity            bit
        constraint DF_Product_IsActivity default 1,
    IsDefaultProduct      bit
        constraint DF_Product_IsDefaultProduct default 1,
    IsLCR                 bit
        constraint DF_Product_IsLCR default 0,
    IsRoHS                varchar(50),
    BOMId                 char(12),
    ProductBarcodeId      char(12),
    CustomerId            char(12),
    CustomerPN            varchar(50),
    StandardQtyOfBox      decimal(18, 4)
        constraint DF_Product_StandardBoxQty default 0,
    STCheckBoxQty         int
        constraint DF_Product_STCheckBoxQty default 0,
    WorkflowId            char(12),
    StandardCost          decimal(18, 6)
        constraint DF_Product_StandardCost default 0,
    StandardCapacity      decimal(18, 6)
        constraint DF_Product_StandCapacity default 0,
    USL                   decimal(18, 6)
        constraint DF_Product_USL default 0,
    LSL                   decimal(18, 6)
        constraint DF_Product_LSL default 0,
    CurrentCost           decimal(18, 6)
        constraint DF_Product_CurrentCost default 0,
    GrossWeight           decimal(18, 6)
        constraint DF_Product_Weight default 0,
    NetWeight             decimal(18, 6)
        constraint DF_Product_NetWeight default 0,
    Volume                decimal(18, 6)
        constraint DF_Product_Volume default 0,
    AgingTimeM            decimal(18, 6)
        constraint DF_Product_AgingTime default 0,
    IsFIFO                bit
        constraint DF_Product_ProductFIFO default 0,
    IsSeparatedMFO        bit
        constraint DF_Product_IsSeparatedMFO default 0,
    IsExceedPicking       bit
        constraint DF_Product_IsExceedPicking default 1,
    PMax                  float
        constraint DF_Product_PMax default 0,
    PMin                  float
        constraint DF_Product_PMin default 0,
    SafeStorageTime       int
        constraint DF_Product_SafeStorageTime default 0,
    SafeExtendTime1       int
        constraint DF_Product_SafeExtendTime default 0,
    SafeExtendTime2       int
        constraint DF_Product_SafeExtendTime11 default 0,
    SafeExtendTime3       int
        constraint DF_Product_SafeExtendTime12 default 0,
    ExpDateSPL            int,
    IsConNumberPack       bit
        constraint DF_Product_ConNumberPack default 0,
    IsConNumberPallet     bit
        constraint DF_Product_ConNumberPallet default 0,
    IskeyMat              bit
        constraint DF_Product_IskeyMat_SN default 0,
    IskeyParts            bit
        constraint DF_Product_IskeyParts default 0,
    SafetyInventory       decimal(18, 8)
        constraint DF_Product_SafetyInventory default 0,
    MaxiInventory         decimal(18, 8)
        constraint DF_Product_MaxiInventory default 0,
    IsHS                  bit
        constraint DF_Product_IsHumidity default 0,
    HSLevel               nvarchar(10),
    TempBoxLabelId        char(12),
    TempPalletLabelId     char(12),
    IsHybridPack          bit
        constraint DF_Product_IsHybridPack default 0,
    MThickness            decimal(18, 2)
        constraint DF_Product_MThickness default 0,
    DeleteFlag            varchar(50)
        constraint DF_Product_DeleteFlag default '',
    DPPM                  decimal(18, 2)
        constraint DF_Product_DPPM default 0,
    PPM                   decimal(18, 2)
        constraint DF_Product_PPM default 0,
    ModifyDate            datetime,
    CreateDate            datetime
        constraint DF_Product_CreateDate default getdate(),
    BoardFaceCode         nvarchar(50),
    IsNOutBox             bit
        constraint DF__Product__IsNOutB__7465391A default 0,
    TProductName          nvarchar(50)
        constraint DF__Product__Product__75595D53 default NULL,
    TPS_ProductWorkflowId char(12)
        constraint DF__Product__TPS_Pro__764D818C default NULL,
    TPS_BomId             char(12),
    ProductColor          nvarchar(50),
    FiltrationProcess     nvarchar(50),
    FiltrationProcess1    nvarchar(50),
    OverdueTime           decimal(13, 6),
    ExpirationDate        decimal(13, 6),
    SealingType           nvarchar(50)
)
go

