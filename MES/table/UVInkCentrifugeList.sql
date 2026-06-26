create table UVInkCentrifugeList
(
    UVInkCentrifugeListId char(12) not null
        constraint PK_UVInkCentrifugeList
            primary key,
    CreateDate            datetime
        constraint DF_UVInkCentrifugeList_CreateDate default getdate(),
    ProductName           nvarchar(50)
        constraint DF_UVInkCentrifugeList_TProductName default NULL,
    ProductId             char(12),
    ProductDescription    nvarchar(100),
    CreateUserId          char(12)
)
go

