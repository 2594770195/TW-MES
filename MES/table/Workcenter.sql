create table Workcenter
(
    WorkcenterId          char(12)
        constraint DF_Workcenter_WorkcenterId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Workcenter
            primary key,
    WorkcenterName        nvarchar(50),
    WorkcenterDescription nvarchar(100),
    SiteId                char(12),
    WorkcenterTypeId      char(12),
    ProductStoreTypeId    char(12),
    IsVirtualWarehouse    bit
        constraint DF_Workcenter_IsVirtualWarehouse default 0,
    IsOMDepositW          bit
        constraint DF_Workcenter_IsOMWarehouse default 0,
    IsVenueDepositW       bit
        constraint DF_Workcenter_IsVenueWarehouse default 0,
    IsFIFO                bit
        constraint DF_Workcenter_IsFIFO default 0,
    IsSeparatedMFO        bit
        constraint DF_Workcenter_IsSeparatedMFO default 0,
    IsClosed              bit
        constraint DF_Workcenter_IsClosed default 0,
    IsSap                 bit,
    Worktime              numeric(9, 2)
        constraint DF_Workcenter_Worktime default 0,
    Overtime              numeric(9, 2)
        constraint DF_Workcenter_Overtime default 0,
    DeleteFlag            nchar,
    LineLeaderUserId      char(12),
    WorkcenterGroup       nvarchar(50),
    AndonState            char
        constraint DF_Workcenter_AndonState default 0,
    ModifyDate            datetime
        constraint DF_Workcenter_ModifyDate default getdate(),
    CreateDate            datetime
        constraint DF_Workcenter_CreateDate default getdate(),
    FactoryId             char(12)
)
go

