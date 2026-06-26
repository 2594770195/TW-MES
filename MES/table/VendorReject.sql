create table VendorReject
(
    VendorRejectId          char(12)
        constraint DF_Table_1_VendorBackId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_VendorReject
            primary key,
    VendorRejectName        nvarchar(50),
    VendorRejectDescription nvarchar(100),
    VendorRejectClass       varchar(20),
    VendorRejectType        varchar(20),
    VendorRejectStates      varchar(20),
    VendorId                char(12),
    VendorDeliveryId        char(12),
    RejectDate              datetime
        constraint DF_VendorReject_RejectDate default getdate(),
    FactoryId               char(12),
    ApproveUserId           char(12),
    ApproveDate             datetime,
    ToErpLock               bit
        constraint DF_VendorReject_ToErpLock default 0,
    IsArrivalReject         bit
        constraint DF_VendorReject_IsArrivalReject default 0                                         not null,
    ConfirmUserId           char(12)
        constraint DF_VendorReject_ConfirmUserId default '',
    ConfirmDate             datetime,
    ModifyDate              datetime
        constraint DF_VendorReject_ModifyDate default getdate(),
    CreateUserId            char(12),
    CreateDate              datetime
        constraint DF_VendorReject_CreateDate default getdate()
)
go

