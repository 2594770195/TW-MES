create table Logs
(
    id       int identity
        constraint PK_Logs
            primary key,
    Machine  varchar(32),
    [User]   varchar(32),
    Time     datetime,
    Source   varchar(32),
    Severity smallint,
    Data     varchar(255),
    area     int
)
go

