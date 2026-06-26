create table Lot
(
    LotId                  char(12)
        constraint DF_Lot_LotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Lot
            primary key,
    LotSN                  varchar(100)
        constraint IX_Lot_LotSN
            unique,
    ProductId              char(12),
    LotStatus              char
        constraint DF_Lot_LotStatus default 1,
    Qty                    decimal(18, 6),
    OriginalQty            decimal(18, 6),
    PriorityLevel          char(2),
    UOMId                  char(12),
    ShiftId                char(12),
    WorkcenterId           char(12),
    ResourceId             char(12),
    VendorId               char(12),
    CustomerId             char(12),
    MOId                   char(12),
    MOItemId               char(12),
    MOItemTaskId           char(12),
    CellId                 char(12),
    WorkflowId             char(12),
    WorkflowStepId         char(12),
    SpecificationId        char(12),
    IsMoveIn               bit
        constraint DF_Lot_IsMoveIn default 0,
    NextWorkflowStepId     char(12),
    PreviousWorkflowStepId char(12),
    LatestTxnCode          varchar(20),
    LatestUserId           char(12),
    LatestMoveDate         datetime,
    LatestActivityDate     datetime,
    ParentLotId            char(12),
    CreateDate             datetime
        constraint DF_Lot_CreateDate default getdate(),
    QualityMark            varchar(16),
    MixingEndTime          datetime,
    MOBackResult           varchar(16)
)
go

