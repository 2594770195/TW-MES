create table PickingList_MO
(
    PickingList_MOId char(12)
        constraint DF_Table_1_StockList_MOId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_PickingList_MO
            primary key,
    PickingListId    char(12),
    MOId             char(12),
    CreateDate       datetime
        constraint DF_PickingListMO_CreateDate default getdate(),
    ModifyDate       datetime
        constraint DF_PickingListMO_ModifyDate default getdate(),
    ToSAPStates      nvarchar(20),
    SAPInfor         nvarchar(max) collate Chinese_PRC_CI_AS_KS,
    IsPost           bit
        constraint DF_PickingList_MO_IsPostSAP default 0
)
go

