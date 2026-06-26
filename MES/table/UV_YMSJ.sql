create table UV_YMSJ
(
    UV_YMSJID         char(12) not null,
    CmdSpeed          int,
    CmdXnOne          float,
    CmdXnTwo          float,
    CmdXnThree        float,
    CmdQY             float,
    StartDate         datetime,
    CreateDate        datetime
        constraint DF__UV_YMSJ__CreateD__52A5E94A default getdate(),
    EndDate           datetime,
    ModifyDate        datetime
        constraint DF__UV_YMSJ__ModifyD__539A0D83 default getdate(),
    YMSJTime          decimal(18, 3),
    LotID             char(12),
    EmployeeNo        nvarchar(50),
    EquipmentNo       nvarchar(50),
    JudgingDepartment int,
    JudgingIsStorage  int,
    ProductionGrindId char(12)
)
go

