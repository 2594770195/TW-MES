create table PickingListItem
(
    PickingListItemId char(12)
        constraint DF_PickingListItem_PickingListItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_PickingListItem
            primary key,
    PickingListId     char(12),
    ItemSequence      varchar(20),
    ItemStates        varchar(20),
    MOId              char(12),
    MOItemId          char(12),
    POId              char(12),
    POItemId          char(12),
    POItemMId         char(12),
    ProductId         char(12),
    QtyRequired       decimal(18, 3)
        constraint DF_PickingListItem_QtyRequired default 0,
    QtyIssued         decimal(18, 3)
        constraint DF_PickingListItem_QtyIssued default 0,
    HedgeQty          decimal(18, 3)
        constraint DF_PickingListItem_DepositoryQty default 0,
    UOMId             char(12),
    WorkcenterId      char(12),
    ERPItemId         varchar(30),
    DeleteFlag        varchar(5)
        constraint DF_PickingListItem_DeleteFlag_1 default ''                                                     not null,
    ModifyDate        datetime
        constraint DF_PickingListItem_ModifyDate default getdate(),
    CreateDate        datetime
        constraint DF_PickingListItem_CreateDate default getdate(),
    CostCenterId      char(12),
    ToSAPStates       nvarchar(20),
    SAPInfor          nvarchar(max) collate Chinese_PRC_CI_AS_KS,
    OrderName         nvarchar(50)
)
go

