create table UserLogin
(
    UserLoginId     char(12)
        constraint DF_UserLogin_UserLoginId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_UserLogin
            primary key,
    UserName        nvarchar(50),
    ApplicationName nvarchar(50),
    Times           int
        constraint DF_UserLogin_Times default 1,
    CreateDate      datetime
        constraint DF_UserLogin_CreateDate default getdate()
)
go

