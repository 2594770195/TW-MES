create table ZR_Document
(
    ZR_DocumentID      char(12) default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint ZR_Document_pk
            primary key
        constraint ZR_Document_pk_2
            unique,
    ProductName        nvarchar(255),
    ProductDescription nvarchar(255),
    ProudctionLotSN    nvarchar(255),
    ContainerCode      nvarchar(255),
    CodeStatus         nvarchar(255),
    Num                float,
    Remark             nvarchar(max),
    UserName           nvarchar(255),
    createDate         datetime,
    updateDate         datetime
)
go

