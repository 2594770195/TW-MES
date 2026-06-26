create table PGLoss
(
    PGLossId          IDType not null,
    ProductionGrindId IDType,
    CurrentCount      int,
    LossQty           SysNumberType,
    CreateDate        datetime
        constraint DF_PGLoss_CreateDate default getdate(),
    IsInspection      bit
        constraint DF_PGLoss_IsInspection default 0
)
go

