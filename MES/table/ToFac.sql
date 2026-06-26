create table ToFac
(
    ToFacID            char(12) not null,
    ProductID          char(12),
    ProudctionLotSN    nvarchar(50),
    PrintDate          datetime,
    Barrelage          int,
    ToBSDate           datetime,
    ToBSBarrelage      int,
    ToJWDate           datetime,
    ToJWBarrelage      int,
    JWDate             datetime,
    JWBarrelage        int,
    IsStorage          bit,
    CellName           nvarchar(50),
    OutBarrelage       int,
    OutBarrelageDate   datetime,
    LeaveBSDate        datetime,
    LeaveBSBarrelage   int,
    LeaveJWDate        datetime,
    LeaveJWBarrelage   int,
    ZR_ContainerCodeId char(12),
    soname             nvarchar(50),
    createData         datetime default getdate()
)
go

