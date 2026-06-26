create table VendorRejectItemLot
(
    VendorRejectItemLotId char(12)
        constraint DF_Table_1_VendorBackItemLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_VendorRejectItemLot
            primary key,
    VendorRejectItemId    char(12),
    LotSN                 nvarchar(40),
    BoxSN                 nvarchar(40),
    Qty                   decimal(18, 8)
        constraint DF_VendorRejectItemLot_Qty default 0,
    ProductionLotNO       nvarchar(50),
    CreateDate            datetime
        constraint DF_VendorRejectItemLot_CreateDate default getdate()
)
go

