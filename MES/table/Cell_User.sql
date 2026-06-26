create table Cell_User
(
    Cell_UserId char(12)
        constraint DF_Cell_User_Cell_UserId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Cell_User
            primary key,
    CellId      char(12),
    UserId      char(12),
    ModifyDate  datetime
        constraint DF_Cell_User_ModifyDate default getdate(),
    CreateDate  datetime
        constraint DF_Cell_User_CreateDate default getdate()
)
go

