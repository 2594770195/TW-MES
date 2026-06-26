create table ZR_Update_Lot_QualityMark
(
    ZR_Update_Lot_QualityMarkId char(12) not null
        constraint ZR_Update_Lot_QualityMark_pk
            primary key,
    LotSn                       nvarchar(50),
    OrgQualityMark              nvarchar(10),
    NewQualityMark              nvarchar(10),
    SysUserId                   nvarchar(20),
    CreateData                  datetime default getdate(),
    remark                      nvarchar(max)
)
go

