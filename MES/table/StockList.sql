create table StockList
(
    StockListId          char(12)
        constraint DF_StockList_StockListId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_StockList
            primary key,
    StockListName        nvarchar(50),
    StockListDescription nvarchar(100),
    StockListStates      char(2),
    FactoryId            char(12),
    CreateUserId         char(12),
    CreateDate           datetime
        constraint DF_StockList_CreateDate default getdate()
)
go

