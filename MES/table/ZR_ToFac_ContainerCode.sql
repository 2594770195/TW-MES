create table ZR_ToFac_ContainerCode
(
    ZR_ToFac_ContainerCodeID char(12),
    ToFacId                  char(12),
    ZR_ContainerCodeId       char(12),
    CreateData               datetime default getdate(),
    UpdateData               datetime,
    BoxLotSn                 varchar(255)
)
go

