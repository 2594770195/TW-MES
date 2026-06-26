create table IQCCheckItem
(
    IQCCheckItemId         char(12)
        constraint DF_Table_1_QCItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_IQCCheckItem
            primary key,
    IQCCheckId             char(12)                                                              not null,
    QCMode                 varchar(10),
    ItemType               nvarchar(50),
    ItemName               nvarchar(50),
    ItemDescription        nvarchar(100),
    ItemResult             char
        constraint DF_IQCCheckItem_ItemResult default '',
    PQTY                   decimal(18, 8)
        constraint DF_IQCCheckItem_PQTY default 0,
    FQTY                   decimal(18, 8)
        constraint DF_IQCCheckItem_FQTY default 0,
    ItemResultType         char
        constraint DF_IQCCheckItem_ItemResultType default '0',
    CheckLevelCode         varchar(10),
    AQLQualityStandard     varchar(10),
    SampleSize             decimal(18, 8)
        constraint DF_IQCCheckItem_SampleSize default 0,
    AC                     decimal(18, 8)
        constraint DF_IQCCheckItem_AC default 0,
    RE                     decimal(18, 8)
        constraint DF_IQCCheckItem_RE default 0,
    ItemSTDValue           decimal(18, 8),
    ItemMaxValue           decimal(18, 8),
    ItemMinValue           decimal(18, 8),
    ItemUOMId              char(12),
    IsAllowArtificialJudge bit
        constraint DF_IQCCheckItem_IsAllowArtificialJudge default 0,
    DrawDocument           nvarchar(50),
    ReferDocument          nvarchar(50),
    ModifyDate             datetime
        constraint DF_IQCCheckItem_ModifyDate default getdate(),
    CreateDate             datetime
        constraint DF_IQCCheckItem_CreateDate default getdate()
)
go

