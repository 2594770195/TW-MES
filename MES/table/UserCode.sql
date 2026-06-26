create table UserCode
(
    UserCodeId          char(12)
        constraint DF_UserCode_UserCodeId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_UserCode
            primary key,
    UserCodeName        nvarchar(100),
    UserCodeDescription nvarchar(200)
        constraint DF_UserCode_UserCodeDescription default space(0),
    Protected           bit,
    ParentUserCodeId    char(12)
        constraint DF_UserCode_ParentUserCodeId default space(0),
    CreateDate          datetime
        constraint DF_UserCode_CreateDate default getdate()
)
go

