create table ProductBack
(
    ProductBackId          char(12)
        constraint DF_ProductBack_ProductBackId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_ProductBack
            primary key,
    ProductBackName        nvarchar(50)                                                                   not null,
    ProductBackDescription nvarchar(100),
    ProductBackClass       varchar(2),
    ProductBackType        varchar(20),
    ProductBackStates      varchar(20),
    ErpBillStates          varchar(20),
    PickingListId          char(12),
    DivisionId             char(12),
    FactoryId              char(12),
    VendorId               char(12)
        constraint DF_ProductBack_VendorId default '',
    WorkcenterId           char(12),
    ApproveUserId          char(12),
    ApproveDate            datetime,
    ConfirmUserId          char(12),
    ConfirmDate            datetime,
    ToErpLock              bit
        constraint DF_ProductBack_ToErpLock default 0,
    IsBackApplyScan        bit
        constraint DF_ProductBack_IsBackApplyScan default 0,
    CreateUserId           char(12),
    CreateDate             datetime
        constraint DF_ProductBack_CreateDate default getdate(),
    ModifyDate             datetime
        constraint DF_ProductBack_ModifyDate default getdate(),
    SAPInfor               nvarchar(max) collate Chinese_PRC_CI_AS_KS
)
go

