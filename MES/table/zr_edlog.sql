create table zr_edlog
(
    Id           char(12) default substring(CONVERT([char](36), newid(), 0), 1, 12),
    Type         nvarchar(max),
    InputParams  nvarchar(max),
    OutputParams nvarchar(max),
    CreateDate   datetime default getdate(),
    UploadIngId  char(12),
    InDate       datetime,
    OutDate      datetime
)
go

