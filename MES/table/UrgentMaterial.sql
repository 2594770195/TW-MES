create table UrgentMaterial
(
    UrgentMaterialId char(12)
        constraint DF_UrgentMaterial_UrgentMaterialId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_UrgentMaterial
            primary key,
    StartDate        date,
    EndDate          date,
    ModifyDate       datetime
        constraint DF_UrgentMaterial_ModifyDate default getdate(),
    CreateDate       datetime
        constraint DF_UrgentMaterial_CreateDate default getdate()
)
go

