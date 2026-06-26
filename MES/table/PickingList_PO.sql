create table PickingList_PO
(
    PickingList_POId char(12) not null
        constraint PK_PickingList_PO
            primary key,
    PickingListId    char(12),
    POId             char(12),
    CreateUserId     char(12),
    CreateDate       datetime
        constraint DF_PickingList_PO_CreateDate default getdate()
)
go

