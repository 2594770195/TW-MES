create table VendorDeliveryItemLot
(
    VendorDeliveryItemLotId char(12)
        constraint DF_POItemLot_POItemLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_VendorDeliveryItemLot
            primary key,
    VendorDeliveryItemId    char(12),
    LotSN                   nvarchar(50),
    BoxSN                   nvarchar(50),
    Qty                     decimal(18, 6)
        constraint DF_VendorDeliveryItemLot_Qty default 0,
    DefectQty               decimal(18, 6)
        constraint DF_VendorDeliveryItemLot_PassQty default 0,
    ProductId               char(12),
    ProductionDate          varchar(20),
    ProductionLotNO         nvarchar(50),
    DeliveryBatch           nvarchar(50),
    StandardQtyOfLot        decimal(18, 6)
        constraint DF_VendorDeliveryItemLot_StandardQtyOfLot default 0,
    StandardLotQtyOfBox     decimal(18, 6)
        constraint DF_VendorDeliveryItemLot_StandardLotQtyOfBox default 0,
    MPN                     nvarchar(50),
    IsSpareLot              bit
        constraint DF_VendorDeliveryItemLot_IsSpare default 0,
    PrintCount              int
        constraint DF_POItemLot_PrintCount default 0,
    IsArrivalReject         bit
        constraint DF_VendorDeliveryItemLot_IsArrivalRejected default 0                               not null,
    ArrivalRejectDate       datetime,
    IsReceiveScan           bit
        constraint DF_POItemLot_IsScan default 0,
    ReceiveDate             datetime,
    IsReceiveAck            bit
        constraint DF_VendorDeliveryItemLot_IsReceiveAffirm default 0                                 not null,
    ReceiveAckDate          datetime,
    IsChecked               bit
        constraint DF_VendorDeliveryItemLot_IsChecked default 0                                       not null,
    CheckDate               datetime,
    IsPutaway               bit
        constraint DF_VendorDeliveryItemLot_IsPutaway default 0                                       not null,
    PutawayDate             datetime,
    IsEntry                 bit
        constraint DF_VendorDeliveryItemLot_IsEntry default 0                                         not null,
    EntryDate               datetime,
    StagAreaId              char(12),
    WorkcenterId            char(12),
    CellId                  char(12),
    IQCCheckId              char(12),
    DeleteFlag              char
        constraint DF_VendorDeliveryItemLot_DeleteFlag default ''                                     not null,
    ModifyDate              datetime
        constraint DF_VendorDeliveryItemLot_ModifyDate default getdate(),
    CreateUserId            char(12),
    CreateDate              datetime
        constraint DF_POItemLot_CreateDate default getdate()                                          not null,
    IsPicking               bit
        constraint DF_VendorDeliveryItemLot_IsPicking default 0
)
go

