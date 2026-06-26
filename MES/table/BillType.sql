create table BillType
(
    BillTypeId          char(12)
        constraint DF_BillType_BillTypeId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_BillType
            primary key,
    BillId              char(12),
    BillTypeName        nvarchar(30),
    BillTypeDescription nvarchar(50),
    IsDefaultType       bit
        constraint DF_BillType_IsDefaultType default 0,
    IsERP               bit
        constraint DF_BillType_IsERP default 0,
    ModifyDate          datetime
        constraint DF_BillType_ModifyDate default getdate(),
    CreateDate          datetime
        constraint DF_BillType_CreateDate default getdate()
)
go

