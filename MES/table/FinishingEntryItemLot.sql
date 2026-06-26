create table FinishingEntryItemLot
(
    FinishingEntryItemLotId char(12)
        constraint DF_FinishingEntryItemLot_FinishingEntryItemLotId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_FinishingEntryItemLot
            primary key,
    FinishingEntryItemId    char(12),
    LotId                   char(12),
    LotSN                   nvarchar(100),
    Qty                     decimal(18, 8)
        constraint DF_FinishingEntryItemLot_Qty default 0,
    BoxSN                   nvarchar(100),
    MBoxSN                  nvarchar(100),
    OBoxSN                  nvarchar(100),
    PalletSN                nvarchar(100),
    CellId                  char(12),
    EntryUnit               varchar(10),
    IsAccepted              bit
        constraint DF_FinishingEntryItemLot_IsAcceptScan default 0,
    AcceptUserId            char(12),
    AccepteDate             datetime,
    CreateDate              datetime
        constraint DF_FinishingEntryItemLot_CreateDate default getdate(),
    WorkcenterId            char(12),
    ISVerify                varchar(10)
)
go

