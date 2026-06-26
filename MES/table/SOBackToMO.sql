create table SOBackToMO
(
    SOBackToMOId     char(12) not null
        constraint PK_SOBackToMO
            primary key,
    SOId             char(12),
    SOItemId         char(12),
    ProcesseOpinion  nvarchar(200),
    FileId           char(12),
    MOId             char(12),
    CreateDate       datetime
        constraint DF_SOBackToMO_CreateDate default getdate(),
    CreateUserId     char(12),
    UpdateDate       datetime,
    UpdateUserId     char(12),
    SOBackToMOStatue nvarchar(50),
    SOBackToMOName   nvarchar(50)
)
go

