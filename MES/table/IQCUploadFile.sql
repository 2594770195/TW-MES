create table IQCUploadFile
(
    IQCUploadFileId char(12) not null
        constraint PK_IQCUploadFile
            primary key,
    FtpFileId       char(12),
    IQCCheckName    nvarchar(50),
    CreateDate      datetime
        constraint DF_IQCUploadFile_CreateDate default getdate()
)
go

