create table ProductAllot
(
    ProductAllotId          char(12)
        constraint DF_ProductAllot_ProductAllotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_ProductAllot
            primary key,
    ProductAllotName        nvarchar(50)                                                                    not null,
    ProductAllotDescription nvarchar(100),
    ProductAllotStates      varchar(20),
    ProductAllotType        varchar(20),
    ErpBillStates           varchar(20),
    FactoryId               char(12),
    ToFactoryId             char(12),
    WorkcenterId            char(12),
    ToWorkcenterId          char(12),
    ConfirmUserId           char(12),
    ConfirmDate             datetime,
    ApproveUserId           char(12),
    ApproveDate             datetime,
    PickingListId           char(12),
    ProductBackId           char(12),
    CreateWay               char
        constraint DF_ProductAllot_CreateWay default '0',
    ToErpLock               bit
        constraint DF_ProductAllot_ToErpLock default 0,
    OperateWay              char
        constraint DF_ProductAllot_OperateType default '0',
    CreateUserId            char(12),
    CreateDate              datetime
        constraint DF_ProductAllot_CreateDate default getdate(),
    ModifyDate              datetime
        constraint DF_ProductAllot_ModifyDate default getdate(),
    MOAllotRequestId        char(12),
    RequiredDate            datetime,
    SAPInfor                nvarchar(max) collate Chinese_PRC_CI_AS_KS
)
go

