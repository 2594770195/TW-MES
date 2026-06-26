create table UOMConversion
(
    UOMConversionId char(12)
        constraint DF_UOMConversion_UOMConversionId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_UOMConversion
            primary key
        constraint FK_UOMConversion_UOMConversion
            references UOMConversion,
    UOMId           char(12),
    TargetUOMId     char(12),
    ConversionRate  float,
    ProductId       char(12),
    CreateTime      datetime
        constraint DF_UOMConversion_CreateTime default getdate(),
    ModifyTime      datetime
)
go

