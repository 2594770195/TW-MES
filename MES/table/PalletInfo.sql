create table PalletInfo
(
    PalletInfoId char(12)
        constraint DF__PalletInf__Palle__7A96DAA5 default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_PalletInfo
            primary key,
    SType        char
        constraint DF_PalletInfo_SType default 1,
    PalletSN     nvarchar(100)                                                                              not null,
    MOId         char(12)
        constraint DF__PalletInfo__MOId__7B8AFEDE default ''                                                not null,
    ProductId    char(12),
    PrintCount   int
        constraint DF__PalletInf__Print__7C7F2317 default 0,
    IsUsed       bit
        constraint DF__PalletInf__IsUse__7D734750 default 0,
    CreateUserId char(12),
    CreateDate   datetime
        constraint DF__PalletInf__Creat__7F5B8FC2 default getdate(),
    IsCancel     bit default 0
)
go

