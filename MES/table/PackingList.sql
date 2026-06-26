create table PackingList
(
    PackingListId char(12) not null
        constraint PK_PackingList
            primary key,
    PackingName   nvarchar(50),
    SOId          char(12),
    FactoryId     char(12),
    SaleSide      nvarchar(20),
    ShippingDate  datetime,
    DeliveryName  nvarchar(20),
    POId          char(12),
    CustomerId    char(12),
    UOMId         char(12),
    Address       nvarchar(80),
    Phone         nvarchar(30),
    Consignee     nvarchar(30),
    CreateDate    datetime
        constraint DF_PackingList_CreateDate default getdate(),
    CustomPO      nvarchar(80),
    CustomName    nvarchar(80),
    SOName        nvarchar(30),
    ReceiveUnit   nvarchar(100)
)
go

