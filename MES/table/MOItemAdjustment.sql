create table MOItemAdjustment
(
    MOItemAdjustmentId IDType not null
        constraint PK_MOItemAdjustment
            primary key,
    MOItemId           IDType,
    OldItemQtyRequired SysNumberType,
    NewItemQtyRequired SysNumberType,
    Operator           nvarchar(50),
    LotSN              LotSN,
    AdjustmentNumber   int
        constraint DF_MOItemAdjustment_AdjustmentNumber default 1,
    CreateDate         datetime
        constraint DF_MOItemAdjustment_CreateDate default getdate(),
    SpecificationId    IDType
)
go

