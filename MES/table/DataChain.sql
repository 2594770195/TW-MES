create table DataChain
(
    DataChainId     char(12)
        constraint DF_DataChain_DataChainId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_DataChain
            primary key,
    LotId           char(12),
    Qty             decimal(18, 4),
    MOId            char(12),
    MOItemId        char(12),
    ProductId       char(12),
    TxnCode         varchar(10),
    WorkcenterId    char(12),
    ShiftId         char(12),
    SpecificationId char(12),
    WorkflowStepId  char(12),
    PluginId        char(12),
    UserId          char(12),
    ResourceId      char(12),
    CreateDate      datetime
        constraint DF_DataChain_CreateDate default getdate()
)
go

