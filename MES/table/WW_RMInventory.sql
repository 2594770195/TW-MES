create table WW_RMInventory
(
    WWId            char(12) not null
        constraint PK_WW_RMInventory
            primary key,
    LotId           char(12),
    LotSN           nvarchar(100),
    LotStatus       char,
    QCStatus        char
        constraint DF_WW_RMInventory_LotQCStatus default '0',
    IsolateStatus   char
        constraint DF_WW_RMInventory_IsIsolation default '0',
    Qty             decimal(18, 8)
        constraint DF_WW_RMInventory_Qty default 0,
    OrgQty          decimal(18, 8)
        constraint DF_WW_RMInventory_OrgQty default 0,
    IsSM            bit
        constraint DF_WW_RMInventory_Isd default 0,
    UOMId           char(12),
    OrgLotSN        nvarchar(100),
    BoxSN           nvarchar(100),
    MBoxSN          nvarchar(100),
    OBoxSN          nvarchar(100),
    TurnoverBoxSN   nvarchar(100),
    PalletSN        nvarchar(100),
    ProductId       char(12),
    POId            char(12),
    VendorId        char(12),
    DeliveryBatch   varchar(50),
    ProductionDate  varchar(50),
    ProductionLotNO varchar(50),
    ReceiveDate     datetime,
    MOId            char(12),
    sMOName         nvarchar(20),
    sSOItemSequence char(10),
    sSOName         nvarchar(20),
    MOItemId        char(12),
    MOItemTaskId    char(12),
    CustomerId      char(12),
    EntryDate       datetime
        constraint DF_WW_RMInventory_EntryDate default getdate(),
    ValidityEndDate date
        constraint DF_WW_RMInventory_ValidityEndDate default NULL,
    FactoryId       char(12),
    WorkcenterId    char(12),
    CellId          char(12),
    IsStorage       bit
        constraint DF_WW_RMInventory_IsStorage default 1,
    IsInternalLot   bit
        constraint DF_WW_RMInventory_IsInternalLot default 0,
    LastestTxnCode  nvarchar(50),
    LotSType        varchar(2)
        constraint DF_WW_RMInventory_LotSType default 0,
    Operator        nvarchar(50),
    IsHS            bit
        constraint DF_WW_RMInventory_IsMSD default 0,
    SAPRemark       nvarchar(50),
    ModifyDate      datetime
        constraint DF_WW_RMInventory_ModifyDate default getdate(),
    CreateDate      datetime
        constraint DF_WW_RMInventory_CreateDate default getdate(),
    HoldResult      nvarchar(255),
    IsExceedPicking bit
        constraint DF_WW_RMInventory_IsExceedPicking default 0,
    SoToMo          nvarchar(20),
    isInDCSJar      nvarchar(50)
)
go

