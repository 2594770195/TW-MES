create table PickingList
(
    PickingListId          char(12)
        constraint DF_Table_1_PickListId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_PickingList
            primary key,
    PickingListName        nvarchar(50),
    PickingListDescription nvarchar(100),
    PickingListClass       varchar(2),
    PickingListType        varchar(20),
    PickingListStates      varchar(20),
    ErpBillStates          varchar(20),
    ToWorkcenterId         char(12),
    DateRequired           datetime default getdate(),
    DivisionId             char(12),
    FactoryId              char(12),
    VendorId               char(12),
    ApproveUserId          char(12),
    ApproveDate            datetime,
    ConfirmUserId          char(12)
        constraint DF_PickingList_ConfirmUserId default '',
    ConfirmDate            datetime,
    ToErpLock              bit
        constraint DF_PickingList_ToErpLock default 0,
    ModifyDate             datetime
        constraint DF_PickingList_ModifyDate default getdate(),
    CreateUserId           char(12),
    CreateDate             datetime
        constraint DF_PickingList_CreateDate default getdate(),
    MOAllotRequestId       char(12),
    SAPInfor               nvarchar(max) collate Chinese_PRC_CI_AS_KS,
    ProductClassify        char(10),
    ProductionLotNO        varchar(50),
    ShutdownUserId         char(12),
    ShutdownDate           datetime default getdate(),
    ShutdownResult         nvarchar(max)
)
go

