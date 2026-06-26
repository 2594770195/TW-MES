create table UserM
(
    UserMId         char(12)                   not null
        constraint PK_UserM
            primary key,
    UserName        nvarchar(50)               not null,
    UserDescription nvarchar(500),
    CreateDate      datetime default getdate() not null
)
go

