create table DateType
(
    DateTypeId   char(12) not null
        constraint PK_DateType
            primary key,
    DateTypeName nvarchar(50),
    DateTypeDesc nvarchar(200),
    DateLength   int,
    IsProtected  bit
        constraint DF_DateType_IsProtected default 1,
    ModifyUserId char(12),
    ModifyDate   datetime,
    CreateUserId char(12),
    CreateDate   datetime
)
go

