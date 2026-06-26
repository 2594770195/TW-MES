create table Cell_ProductFamily
(
    Cell_ProductFamilyId char(12)
        constraint DF_Cell_ProductFamily_Cell_ProductFamilyId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Cell_ProductFamily
            primary key,
    CellId               char(12),
    ProductFamilyId      char(12),
    ModifyDate           datetime
        constraint DF_Cell_ProductFamily_ModifyDate default getdate(),
    CreateDate           datetime
        constraint DF_Cell_ProductFamily_CreateDate default getdate()
)
go

