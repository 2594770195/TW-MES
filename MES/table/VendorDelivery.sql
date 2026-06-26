create table VendorDelivery
(
    VendorDeliveryId          char(12)
        constraint DF_DO_DOId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_DO
            primary key,
    VendorDeliveryName        nvarchar(50),
    VendorDeliveryDescription nvarchar(100),
    VendorDeliveryType        varchar(20),
    VendorDeliveryStates      varchar(20)
        constraint DF_VendorDelivery_VendorDeliveryStatus default 10,
    VendorId                  char(12),
    DeliveryPlanDate          datetime,
    DeliveryTrueDate          datetime,
    ArrivalPlanDate           datetime,
    ArrivalTrueDate           datetime,
    Driver                    nvarchar(30),
    Truck                     nvarchar(30),
    FactoryId                 char(12),
    ASNId                     char(12),
    ApproveUserId             char(12),
    ApproveDate               datetime,
    ModifyDate                datetime
        constraint DF_VendorDelivery_ModifyDate default getdate(),
    LotStartWay               char,
    IsFromLotCPrint           bit
        constraint DF_VendorDelivery_IsLotCPrint default 0,
    CreateUserId              char(12),
    CreateDate                datetime
        constraint DF_VendorDelivery_CreateDate default getdate(),
    DriverPhone               nvarchar(30),
    Attachment                char(12),
    Recipient                 nvarchar(50),
    RecipientPhone            nvarchar(50),
    GrossWeightSum            decimal(18, 6)
)
go

