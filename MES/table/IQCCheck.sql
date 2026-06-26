create table IQCCheck
(
    IQCCheckId        char(12)
        constraint DF_IQCCheck_IQCCheckId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_IQCCheck
            primary key,
    IQCCheckName      nvarchar(50),
    IQCCheckStates    varchar(20)
        constraint DF_IQCCheck_IQCCheckStates default 10,
    SendTimes         int
        constraint DF_IQCCheck_IQCCheckType default 1,
    FromIQCCheckId    char(12)
        constraint DF_IQCCheck_FromIQCCheckId default '',
    ProductId         char(12),
    SendQty           decimal(18, 8)
        constraint DF_IQCCheck_IQCSendQty default 0,
    SendDate          datetime,
    UOMId             char(12),
    CheckResult       char(2)
        constraint DF_IQCCheck_CheckResult default '',
    CheckDate         datetime,
    CheckUserId       char(12),
    CheckResultType   char
        constraint DF_IQCCheck_CheckResultType default '0',
    JudgeResult       varchar(20)
        constraint DF_IQCCheck_ConfirmResult1 default '',
    JudgeUserId       char(12),
    JudgeDate         datetime,
    JudgeComment      nvarchar(100),
    ConfirmResult     varchar(20)
        constraint DF_IQCCheck_ConfirmResult default '',
    ConfirmUserId     char(12),
    ConfirmDate       datetime,
    ConfirmComment    nvarchar(100),
    RejectedQty       decimal(18, 8)
        constraint DF_IQCCheck_RejectedQty default 0,
    InspectionType    char
        constraint DF_IQCCheck_InspectionType default 1,
    IQCType           char
        constraint DF_IQCCheck_IQCType default 1,
    FactoryId         char(12),
    VendorDeliveryId  char(12),
    DeliveryArrivalId char(12),
    WorkflowStepId    char(12),
    WorkflowStatus    char,
    IsEntry           bit
        constraint DF_IQCCheck_IsCreateEntry default 0,
    EntryDate         datetime,
    EntryUserId       char(12),
    IsReject          bit
        constraint DF_IQCCheck_IsToReject default 0,
    RejectDate        datetime,
    RejectUserId      char(12),
    Operator          nvarchar(50),
    ModifyDate        datetime
        constraint DF_IQCCheck_ModifyDate default getdate(),
    CreateUserId      char(12),
    CreateDate        datetime
        constraint DF_IQCCheck_CreateDate default getdate(),
    InventoryComment  nvarchar(100)
)
go

