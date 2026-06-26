create table MO
(
    MOId                  IDType
        constraint DF_MO_MOId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_MO
            primary key,
    MOName                nvarchar(50)
        constraint IX_MO_MOName
            unique,
    MODescription         nvarchar(100),
    MOType                varchar(20),
    MOStates              varchar(20)
        constraint DF_MO_MOStatus default 10,
    ProductId             IDType,
    PlannedDateFrom       datetime,
    PlannedDateTo         datetime,
    IsPlanned             bit,
    NoteMessage           nvarchar(200),
    ExecuteDateFrom       datetime,
    ExecuteDateTo         datetime,
    MOQtyRequired         SysNumberType,
    MOQtyDone             SysNumberType,
    UOMId                 IDType,
    BOMName               nvarchar(50),
    PickStatus            char(2),
    SOName                nvarchar(50),
    CustomerId            IDType,
    ParentMOId            IDType,
    FactoryId             IDType,
    DivisionId            IDType,
    WorkflowId            IDType,
    ERPId                 varchar(30),
    TempBoxLabelId        IDType,
    TempPalletLabelId     IDType,
    DeleteFlag            varchar(5),
    ApproveDate           datetime,
    ApproveUserId         IDType,
    ModifyDate            datetime
        constraint DF_MO_ModifyDate default getdate(),
    CreateUserId          IDType,
    CreateDate            datetime
        constraint DF_MO_CreateDate default getdate(),
    ScheduleModel         char(2)
        constraint DF_MO_ScheduleModel default 5,
    TaskMaxNum            SysNumberType
        constraint DF_MO_TaskMaxNum default 0,
    TaskMinNum            SysNumberType
        constraint DF_MO_TaskMinNum default 0,
    IsAllowSplitMo        bit
        constraint DF_MO_IsAllowSplitMo default 1,
    PriorityLevel         char(5),
    ProductionStages      nvarchar(50),
    TPS_ProductWorkflowId IDType
        constraint DF__MO__TPS_ProductW__3A389785 default NULL,
    WorkcenterId          IDType,
    ProductLine           char(20),
    IsLock                bit
        constraint DF__MO__IsLock__44E10E81 default 0,
    EquipmentId           IDType,
    IsAdjustment          bit
        constraint DF_MO_IsAdjustment default 1,
    UpdateStart           datetime,
    UpdateEnd             datetime,
    IsOnline              bit,
    HeadComment           nvarchar(800),
    BoxHoe                nvarchar(800),
    MoText                nvarchar(800),
    SoText                nvarchar(800),
    AdjustmentNumber      int
        constraint DF_MO_AdjustmentNumber default 1,
    AdjustmentRemark      nvarchar(800),
    SapCreateDate         datetime
        constraint DF__MO__SapCreateDat__6F6C452A default getdate(),
    CustomerProduct       nvarchar(800),
    Models                nvarchar(800) collate Chinese_PRC_CI_AS_WS,
    ProductTxt            nvarchar(800),
    MOQtySAPDone          SysNumberType,
    Remark                nvarchar(255),
    FromLineBody          nvarchar(20),
    SoItemSequence        nvarchar(20)
)
go

