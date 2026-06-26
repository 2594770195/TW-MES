create table PGrindTimeRef
(
    PGrindTimeRefId  IDType not null
        constraint PK_PGrindTimeRef
            primary key,
    ProductId        IDType,
    Weight           SysNumberType,
    SpecificationId  IDType,
    Eam_EquipModelId IDType,
    GrindTime        SysNumberType,
    GZType           SysNumberType,
    FillQty          SysNumberType,
    Remark           nvarchar(256),
    CreateDate       datetime
)
go

