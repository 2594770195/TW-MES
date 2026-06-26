create table UVPreGrindList
(
    UVPreGrindListId   char(12) not null
        constraint PK_UVPreGrindList
            primary key,
    CreateDate         datetime
        constraint DF_UVPreGrindList_CreateDate default getdate(),
    ProductName        nvarchar(50),
    ProductId          char(12),
    ProductDescription nvarchar(100),
    CreateUserId       char(12),
    isJM               int
)
go

