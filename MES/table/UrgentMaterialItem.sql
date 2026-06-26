create table UrgentMaterialItem
(
    UrgentMaterialItemId char(12)
        constraint DF_UrgentMaterialItem_UrgentMaterialItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_UrgentMaterialItem
            primary key,
    UrgentMaterialId     char(12),
    ProductId            char(12),
    CreateDate           datetime
        constraint DF_UrgentMaterialItem_CreateDate default getdate()
)
go

