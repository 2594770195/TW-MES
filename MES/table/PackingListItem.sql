create table PackingListItem
(
    PackingListItemId char(12) not null
        constraint PK_PackingListItem
            primary key,
    PackingListId     char(12),
    ItemSequence      nvarchar(10),
    Ctnno             nvarchar(30),
    CustomerProduct   nvarchar(40),
    ProductId         char(12),
    SOUOMId           char(12),
    UOMId             char(12),
    CaseNumber        numeric(13, 6),
    ItemNumber        numeric(13, 6),
    TotalQty          numeric(13, 6),
    GrossWeight       numeric(13, 6),
    NetWeight         numeric(13, 6),
    CreateDate        datetime
        constraint DF_PackingListItem_CreateDate default getdate(),
    PackNumber        numeric(13, 6)
)
go

