create table UploadIng_Bak_20260130
(
    UploadIngId       char(12) not null,
    UploadInterfaceId char(12),
    UploadDateId      char(12),
    ISUpload          bit,
    UserId            char(12),
    BillsMark         nvarchar(50),
    MatDoc            nvarchar(500),
    CreateDate        datetime,
    Line              nvarchar(50),
    OtherInfor        nvarchar(255),
    InputParams       nvarchar(max),
    OutputParams      nvarchar(max)
)
go

