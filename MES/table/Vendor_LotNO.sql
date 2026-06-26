create table Vendor_LotNO
(
    Vendor_LotNOId char(12)
        constraint DF_Vendor_LotNO_Vendor_LotNOId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_Vendor_LotNO
            primary key,
    VendorId       char(12),
    AllBits        int
        constraint DF_Vendor_LotNO_AllBits default 0,
    PrefixBits     varchar(20),
    SuffixBits     varchar(20),
    ContainsChar   varchar(20)
        constraint DF_Vendor_LotNO_ContainsChar default '',
    MinValue       varchar(20),
    MaxValue       varchar(20),
    ModifyDate     datetime
        constraint DF_Vendor_LotNO_ModifyDate default getdate(),
    CreateDate     datetime
        constraint DF_Vendor_LotNO_CreateDate default getdate()
)
go

