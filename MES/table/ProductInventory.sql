create table ProductInventory
(
    ProductInventoryId  char(12) not null
        constraint PK_ProductInventory
            primary key,
    FactoryId           char(12),
    ProductId           char(12),
    WorkcenterId        char(12),
    ToWorkcenterId      char(12),
    LotSN               nvarchar(50)
        constraint DF__ProductIn__LotSN__750522EF default NULL,
    ProductInventoryNum decimal(18, 4),
    UOMId               char(12),
    DeleteFlag          varchar(10),
    CheckNum            decimal(18, 4),
    LockQty             decimal(18, 4),
    Note                nvarchar(200),
    StorageDate         nvarchar(200),
    SOName              nvarchar(50),
    ItemSequence        nvarchar(20),
    CreateDate          datetime
        constraint DF_ProductInventory_CreateDate default getdate()
)
go

