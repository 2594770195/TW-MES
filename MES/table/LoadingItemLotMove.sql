create table LoadingItemLotMove
(
    LoadingItemLotMoveId IDType
        constraint DF_LoadingItemLotMove_LoadingItemLotMoveId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_LoadingItemLotMove
            primary key,
    LoadingItemLotId     IDType,
    DataChainId          IDType,
    LotId                IDType,
    LotSN                LotSN,
    InQty                SysNumberType
        constraint DF_LoadingItemLotMove_InQty default 0,
    OutQty               SysNumberType
        constraint DF_LoadingItemLotMove_OutQty default 0,
    MOId                 IDType,
    MOItemId             IDType,
    MOItemTaskId         IDType,
    ProductId            IDType,
    WorkflowId           IDType,
    WorkflowStepId       IDType,
    SpecificationId      IDType,
    Operator             nvarchar(50),
    WorkcenterId         IDType,
    EquipmentId          IDType,
    ResourceId           IDType,
    UserId               IDType,
    CreateDate           datetime
        constraint DF_LoadingItemLotMove_CreateDate default getdate()
)
go

