create table Bill
(
    BillId          char(12)
        constraint DF_Bill_BillId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Bill
            primary key,
    BillName        nvarchar(50),
    BillDescription nvarchar(100),
    BillHeader      char(3),
    BillCounter     bigint
        constraint DF_Bill_BillCounter default 0,
    CurCounterDate  varchar(30)
        constraint DF_Bill_CurCounterDate default '',
    CreateDate      datetime
        constraint DF_Bill_CreateDate default getdate()
)
go

