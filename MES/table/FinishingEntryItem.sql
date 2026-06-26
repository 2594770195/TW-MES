create table FinishingEntryItem
(
    FinishingEntryItemId char(12)
        constraint DF_Table_1_ProductEntryItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_FinishingEntryItem
            primary key,
    FinishingEntryId     char(12),
    ItemSequence         varchar(20),
    ProductId            char(12),
    ItemQtyEntry         decimal(18, 3)
        constraint DF_FinishingEntryItem_ItemQtyEntry default 0,
    MOId                 char(12),
    MOItemId             char(12),
    ItemUOMId            char(12),
    WorkcenterId         char(12),
    ModifyDate           datetime
        constraint DF_FinishingEntryItem_ModifyDate default getdate(),
    CreateDate           datetime
        constraint DF_FinishingEntryItem_CreateDate default getdate(),
    ToSAPStates          nvarchar(20),
    SAPInfor             nvarchar(max) collate Chinese_PRC_CI_AS_KS
)
go

