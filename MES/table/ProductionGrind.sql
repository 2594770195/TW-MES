create table ProductionGrind
(
    ProductionGrindId  IDType not null
        constraint PK_ProductionGrind
            primary key,
    FilterTechnologyId IDType,
    EquipmentId        IDType,
    Equipment2Id       IDType,
    SpecificationId    IDType,
    LotSN              LotSN,
    StartTime          datetime,
    EndTime            datetime,
    AgeingTime         decimal(18, 3),
    CurrentTime        datetime,
    StartQty           SysNumberType,
    EndQty             SysNumberType,
    CreateDate         datetime
        constraint DF_ProductionGrind_CreateDate default getdate(),
    CreateUserId       IDType,
    OperationTips      nvarchar(50),
    CurrentCount       int
        constraint DF_ProductionGrind_CurrentCount default 0,
    SampFlag           bit
        constraint DF_ProductionGrind_SampFlag default 0,
    MaxSampFlag        bit
        constraint DF_ProductionGrind_MaxSampFlag default 0,
    IsComplete         bit
        constraint DF_ProductionGrind_IsComplete default 0,
    MoveFlag           varchar(16),
    DataChainId        IDType,
    ToSpecificationId  IDType,
    FilterType         nvarchar(10),
    FilterE1           int
        constraint DF_ProductionGrind_FilterE1 default 0,
    FilterE2           int
        constraint DF_ProductionGrind_FilterE2 default 0,
    FilterE3           int
        constraint DF_ProductionGrind_FilterE3 default 0,
    GZUsedTime         int
        constraint DF_ProductionGrind_GZUsedTime default 0
)
go

