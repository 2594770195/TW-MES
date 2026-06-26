create table SOToSO
(
    SOToSoId         char(12) not null
        constraint PK_SOToSO
            primary key,
    FromSOName       nvarchar(50),
    ToSOName         nvarchar(50),
    FromItemSequence nvarchar(50),
    ToItemSequence   nvarchar(50),
    Qty              decimal(18, 3),
    LotSN            nvarchar(50),
    ToSAPStates      nvarchar(20),
    SAPInfor         nvarchar(max) collate Chinese_PRC_CI_AS_KS,
    SOToSOName       nvarchar(30),
    SOToSOStates     nvarchar(30),
    CreateDate       datetime default getdate()
)
go

