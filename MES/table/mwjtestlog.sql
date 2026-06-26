create table mwjtestlog
(
    log1       nvarchar(max),
    log3       nvarchar(max),
    createdate datetime
        constraint DF_mwjtestlog_createdate default getdate(),
    log4       nvarchar(max),
    src        nchar(200)
)
go

