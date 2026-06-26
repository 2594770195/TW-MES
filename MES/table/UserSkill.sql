create table UserSkill
(
    UserSkillId char(12)
        constraint DF_UserSkill_UserSkillId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_UserSkill
            primary key,
    UserId      char(12),
    SkillId     char(12),
    SkillStatus nvarchar(50),
    SkillDesc   nvarchar(200),
    CreateBy    char(12),
    CreateDate  datetime
)
go

