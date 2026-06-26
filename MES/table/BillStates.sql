create table BillStates
(
    BillStatesId          char(12)
        constraint DF_Table_1_BillId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_BillStates
            primary key,
    BillId                char(12)
        constraint DF_BillStates_BillId default substring(CONVERT([char](36), newid(), 0), 1, 12),
    BillStatesName        nvarchar(20)
        constraint DF_Table_1_BillStates default '00',
    BillStatesDescription nvarchar(50),
    IsDefaultStates       bit
        constraint DF_BillStates_IsDefaultStates default 0,
    IsERP                 bit
        constraint DF_BillStates_IsERP default 0,
    ModifyDate            datetime
        constraint DF_BillStates_ModifyDate default getdate(),
    CreateDate            datetime
        constraint DF_BillStates_CreateDate default getdate()
)
go

