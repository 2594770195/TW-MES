create table StockList_MO
(
    StockList_MOId char(12)
        constraint DF_StockList_MO_StockList_MOId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_StockList_MO
            primary key,
    StockListId    char(12),
    MOId           char(12),
    CreateUserId   char(12),
    CreateDate     datetime
        constraint DF_StockList_MO_CreateDate default getdate()
)
go

