create table ProjectFile
(
    ProjectFileID   char(12) not null
        constraint PK_ProjectFile
            primary key,
    ProjectFileNo   int,
    ProjectFileName nchar(50),
    ProjectFileDes  nchar(50),
    PIC             nchar(50),
    Status          nchar(10),
    ProjectID       char(12)
)
go

