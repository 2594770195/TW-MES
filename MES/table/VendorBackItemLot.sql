create table VendorBackItemLot
(
    VendorBackItemLotId char(12)
        constraint DF_VendorBackItemLot_VendorBackItemLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_VendorBackItemLot
            primary key,
    VendorBackItemId    char(12),
    LotSN               nvarchar(50),
    BoxSN               nvarchar(50),
    CellId              char(12),
    Qty                 decimal(18, 8)
        constraint DF_VendorBackItemLot_Qty default 0,
    ProductionLotNO     nvarchar(50),
    CreateDate          datetime
        constraint DF_VendorBackItemLot_CreateDate default getdate()
)
go

