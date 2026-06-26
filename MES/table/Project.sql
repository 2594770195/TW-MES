create table Project
(
    ProjectID      char(12) not null
        constraint PK_Project
            primary key,
    ProjectRootId  char(12),
    ProjectPhase   nchar(50),
    ProjectStatus  nchar(10),
    ProjectDes     nchar(100),
    IsDefaultPhase bit,
    CreatePerson   nchar(10),
    CreateDate     datetime
        constraint DF_Project_CreateDate default getdate(),
    ModifyPerson   nchar(10),
    ModifyDate     datetime
)
go

