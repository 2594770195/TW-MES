create table POItemLot
(
    POItemLotId         char(12)
        constraint DF_Table_1_Vendor_ProductLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_POItemLot_1
            primary key,
    POItemId            char(12),
    LotSN               nvarchar(50),
    BoxSN               nvarchar(50),
    Qty                 decimal(18, 6),
    ProductId           char(12),
    ProductionDate      varchar(20),
    ProductionLotNO     varchar(20),
    StandardQtyOfLot    decimal(18, 6),
    StandardLotQtyOfBox decimal(18, 6),
    MPN                 nvarchar(50),
    PrintCount          int
        constraint DF_POItemLot_PrintCount_1 default 0,
    IsReceiveScan       bit
        constraint DF_POItemLot_IsReceiveScan_1 default 0,
    ReceiveDate         datetime,
    IsSpareLot          bit
        constraint DF_POItemLot_IsReceiveScan default 0,
    DeleteFlag          char
        constraint DF_POItemLot_DeleteFlag default ''                                                       not null,
    ModifyDate          datetime
        constraint DF_POItemLot_ModifyDate default getdate(),
    CreateUserId        char(12),
    CreateDate          datetime
        constraint DF_POItemLot_CreateDate_1 default getdate()
)
go

