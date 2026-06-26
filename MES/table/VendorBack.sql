create table VendorBack
(
    VendorBackId          char(12)
        constraint DF_VendorBack_VendorBackId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_VendorBack
            primary key,
    VendorBackName        nvarchar(50),
    VendorBackDescription nvarchar(100),
    VendorBackClass       varchar(20),
    VendorBackType        varchar(20),
    VendorBackStates      varchar(20)
        constraint DF_VendorBack_VendorBackStates default 10,
    ErpBillStates         varchar(20),
    VendorId              char(12),
    BackDate              datetime
        constraint DF_VendorBack_BackDate default getdate(),
    FactoryId             char(12),
    ConfirmUserId         char(12),
    ConfirmDate           datetime,
    ApproveUserId         char(12),
    ApproveDate           datetime,
    ToErpLock             bit
        constraint DF_VendorBack_ToErpLock default 0,
    ModifyDate            datetime
        constraint DF_VendorBack_ModidyDate default getdate(),
    CreateUserID          char(12),
    CreateDate            datetime
        constraint DF_VendorBack_CreateDate default getdate(),
    DeleteFlag            char(2),
    Ratify                nchar(2),
    ToSAPStates           nvarchar(20),
    SAPInfor              nvarchar(max) collate Chinese_PRC_CI_AS_KS
)
go

