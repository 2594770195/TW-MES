create table [Order]
(
    OrderName        nvarchar(50),
    OrderDescription nvarchar(255),
    OrderId          char(12) default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Order
            primary key,
    CreateDate       datetime default getdate(),
    del_flag         int      default 0
)
go

