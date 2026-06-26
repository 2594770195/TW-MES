create table ProductAPSPara
(
    ProductAPSParaId   char(12) not null
        constraint PK_ProductAPSPara
            primary key,
    ProductId          char(12),
    WorkcenterId       char(12),
    WorkcenterCapacity int
        constraint DF_ProductAPSPara_WorkcenterCapacity default 0,
    PrepareCycleTime   int
        constraint DF_ProductAPSPara_PrepareCycleTime default 0,
    CreateDate         datetime
        constraint DF_ProductAPSPara_CreateDate default getdate()
)
go

