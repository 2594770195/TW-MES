create table IQCCheckLot
(
    IQCCheckLotId        char(12)
        constraint DF_IQCCheckLot_IQCCheckLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_IQCCheckLot
            primary key,
    IQCCheckId           char(12),
    LotSN                nvarchar(50),
    Qty                  decimal(18, 6)
        constraint DF_IQCCheckLot_Qty default 0,
    DefectQty            decimal(18, 6)
        constraint DF_IQCCheckLot_DefectQty default 0,
    DestroyQty           decimal(18, 6)
        constraint DF_IQCCheckLot_DestroyQty default 0,
    VendorDeliveryItemId char(12),
    CreateDate           datetime
        constraint DF_IQCCheckLot_CreateDate default getdate()
)
go

