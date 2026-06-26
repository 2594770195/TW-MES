create table MOItemTaskInfinite
(
    MOItemTaskId               char(12)
        constraint DF_MOItemTaskInfinite_MOItemTaskId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_MOItemTaskInfinite
            primary key,
    MOItemTaskName             nvarchar(50),
    Sequence                   char(5)
        constraint DF_MOItemTaskInfinite_Sequence default 0                                                     not null,
    ProcessCapacityID          char(12),
    SpecificationGroupID       char(12),
    SpecificationGroupSequence int
        constraint DF_MOItemTaskInfinite_SpecificationGroupSequence default 0,
    PickingListId              char(12),
    MOId                       char(12),
    MOItemLotID                char(12),
    MOItemId                   char(12),
    ProductId                  char(12),
    ExecuteDateFrom            datetime,
    ExecuteDateTo              datetime,
    ResourceDateFrom           datetime,
    ResourceDateTo             datetime,
    LateStart                  datetime,
    LateEnd                    datetime,
    MainResourceID             char(12),
    WorkcenterId               char(12),
    ShiftId                    char(12),
    InitialTaskPlannedQty      decimal(18, 4),
    TaskPlannedQty             decimal(18, 4)
        constraint DF_MOItemTaskInfinite_TaskPlannedQty default 0,
    WorkPlannedQty             decimal(18, 4)
        constraint DF_MOItemTaskInfinite_WorkPlannedQty default 0,
    TaskCompeleteQty           decimal(18, 4)
        constraint DF_MOItemTaskInfinite_TaskCompeleteQty default 0,
    TaskStatus                 char
        constraint DF_MOItemTaskInfinite_TaskStatus default '0',
    TaskPriorityLevel          int,
    Completion                 int
        constraint DF_MOItemTaskInfinite_Completion default 0,
    PrepareDuration            int,
    Duration                   int
        constraint DF_MOItemTaskInfinite_Duration default 0,
    EndDuration                int,
    PostDuration               int sparse,
    ProcessInterval            int
        constraint DF_MOItemTaskInfinite_ProcessInterval default 0,
    TotalDuration              int,
    ResourceUnitCapability     decimal(18, 4),
    IsMain                     bit
        constraint DF_MOItemTaskInfinite_IsMain default 0,
    IsCompelete                bit
        constraint DF_MOItemTaskInfinite_IsCompelete default 0,
    IsProcess                  bit
        constraint DF_MOItemTaskInfinite_IsProcess default 0,
    IsDelete                   bit
        constraint DF_MOItemTaskInfinite_IsDelete default 0,
    Islock                     bit
        constraint DF_MOItemTaskInfinite_Islock default 0,
    IsNoSum                    bit
        constraint DF_MOItemTaskInfinite_IsNoSum default 0,
    CreateDate                 datetime
        constraint DF_MOItemTaskInfinite_CreateDate default getdate(),
    ResultProcessingTime       int,
    ResultStartTime            datetime,
    ResultEndTime              datetime,
    PubDate                    datetime,
    TaskId                     char(12)
)
go

