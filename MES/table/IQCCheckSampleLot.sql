create table IQCCheckSampleLot
(
    IQCCheckSampleLotId char(12) not null
        constraint PK_IQCCheckSampleLot
            primary key,
    IQCCheckId          char(12),
    LotSN               nvarchar(50),
    SpotSampleQty       decimal(18, 6),
    UserId              char(12),
    CreateDate          datetime
        constraint DF_IQCCheckSampleLot_CreateDate default getdate(),
    UOMId               char(12)
)
go

