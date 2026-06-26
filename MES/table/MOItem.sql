create table MOItem
(
    MOItemId           IDType
        constraint DF_MOItem_MOItemId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_MOItem
            primary key,
    MOId               IDType,
    LineSequence       varchar(20),
    ProductId          IDType,
    ParentProductId    IDType,
    ParentMOItemId     IDType,
    ItemQtyRequired    SysNumberType
        constraint DF_MOItem_ItemQtyRequired default 0,
    ItemQtyIssued      SysNumberType
        constraint DF_MOItem_ItemQtyIssued default 0,
    ItemQtyBack        SysNumberType
        constraint DF_MOItem_ItemQtyBack default 0,
    ItemQtyDone        SysNumberType
        constraint DF_MOItem_ItemQtyDone default 0,
    UOMId              IDType,
    BOMLevel           int,
    BOMItemId          IDType,
    BOMQtyRequired     SysNumberType,
    ParentBOMId        IDType,
    SpecificationId    IDType,
    ReplaceGroup       nvarchar(20),
    ItemLocation       nvarchar(2000)
        constraint DF_MOItem_ItemLocation default '',
    IsAllowReplace     bit
        constraint DF_MOItem_IsAllowReplace default 0,
    IsDone             bit
        constraint DF_MOItem_IsDone default 0,
    IsStartLot         bit
        constraint DF_MOItem_IsStartLot default 0,
    SiteId             IDType,
    LabelId            IDType,
    isReplace          bit
        constraint DF_MOItem_isReplace default 0                                                not null,
    OrgReplaceProd     nvarchar(50),
    isENUseReplace     bit
        constraint DF_MOItem_isENUseReplace default 0                                           not null,
    PurchaseUOMId      IDType,
    ConvertQty         float
        constraint DF_MOItem_ConvertQty default 0                                               not null,
    ERPItemId          varchar(30),
    DeleteFlag         varchar(10)
        constraint DF_MOItem_DeleteFlag default ''                                              not null,
    ModifyDate         datetime
        constraint DF_MOItem_ModifyDate default getdate(),
    CreateDate         datetime
        constraint DF_MOItem_CreateDate default getdate(),
    ProductionLotNO    varchar(500),
    PercenTages        SysNumberType,
    ProductionQty      SysNumberType,
    RequiredAdjustment nvarchar(256),
    OrgItemQtyRequired SysNumberType,
    MoItemLotSN        nvarchar(50),
    ReserveRow         varchar(50),
    ReserveOrder       varchar(50),
    IsNewItem          bit
        constraint DF_MOItem_IsNewItem default 0,
    IsProduction       bit
        constraint DF_MOItem_IsProduction default 0,
    RecordType         nvarchar(10),
    ChangeType         nvarchar(5)
)
go

