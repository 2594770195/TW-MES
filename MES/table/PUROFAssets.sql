create table PUROFAssets
(
    PUROFAssetsId           char(12)                                 not null
        constraint PK_EquipmentApplication
            primary key,
    ApplySN                 nvarchar(30),
    ApplyEquipmentId        char(12),
    UseInfo                 nvarchar(500),
    ApplyQty                int,
    UserId                  char(12),
    UserName                nvarchar(20),
    Division                nvarchar(100),
    ApplyType               char,
    ApplicationContent      nvarchar(1000),
    ITManagerId             char(12),
    ITManager               nvarchar(30),
    ITManagerContent        nvarchar(1000),
    LeadId                  char(12),
    Lead                    nvarchar(30),
    LeadContent             nvarchar(1000),
    EquipmentManagerId      char(12),
    EquipmentManager        nvarchar(30),
    EquipmentManagerContent nvarchar(1000),
    DivisionManagerId       char(12),
    DivisionManager         nvarchar(30),
    DivisionManagerContent  nvarchar(1000),
    DivisionCondition       nvarchar(100)
        constraint DF_PUROFAssets_DivisionCondition default space(0) not null,
    ExecutiveManagerId      char(12),
    ExecutiveManager        nvarchar(30),
    ExecutiveManagerContent nvarchar(1000),
    AboutPrice              decimal(18, 2),
    WorkflowStepId          char(12),
    WorkflowStatus          char,
    IsDelete                bit
        constraint DF_PUROFAssets_IsDelete default 0                 not null,
    IsUse                   bit
        constraint DF_PUROFAssets_isuse default 0                    not null,
    CreateDate              datetime
        constraint DF_PUROFAssets_CreateDate default getdate()
)
go

