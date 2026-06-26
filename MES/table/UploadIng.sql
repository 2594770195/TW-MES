create table UploadIng
(
    UploadIngId       char(12)
        constraint DF_UploadIng_UploadIngId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_UploadIng
            primary key,
    UploadInterfaceId char(12),
    UploadDateId      char(12),
    ISUpload          bit,
    UserId            char(12),
    BillsMark         nvarchar(50),
    MatDoc            nvarchar(500),
    CreateDate        datetime
        constraint DF_UploadIng_CreateDate default getdate(),
    Line              nvarchar(50),
    OtherInfor        nvarchar(255),
    InputParams       nvarchar(max),
    OutputParams      nvarchar(max)
)
go

