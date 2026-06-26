create table ProductAllotItem
(
    ProductAllotItemId char(12)
        constraint DF_Table_1_ProductAllotItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_ProductAllotItem
            primary key,
    ProductAllotId     char(12),
    ItemSequence       varchar(50),
    ItemStates         varchar(10)
        constraint DF_ProductAllotItem_ItemStates default '10',
    ProductId          char(12),
    AllotQty           decimal(18, 3)
        constraint DF_ProductAllotItem_AllotQty default 0,
    RealAllotQty       decimal(18, 3)
        constraint DF_ProductAllotItem_RealQty default 0,
    ItemUOMId          char(12),
    ERPItemId          varchar(30),
    DeleteFlag         varchar(5)
        constraint DF_ProductAllotItem_DeleteFlag default '',
    CreateDate         datetime
        constraint DF_ProductAllotItem_CreateDate default getdate(),
    ModifyDate         datetime
        constraint DF_ProductAllotItem_ModifyDate default getdate(),
    PickingListItemId  char(12),
    ToProductId        char(12),
    ToSAPStates        nvarchar(20),
    SAPInfor           nvarchar(max) collate Chinese_PRC_CI_AS_KS,
    CostCenterId       char(12),
    OrderName          nvarchar(50)
)
go

