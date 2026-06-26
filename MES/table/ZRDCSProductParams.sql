create table ZRDCSProductParams
(
    ZRDCSProductParamsId   nvarchar(255) not null,
    ProductID              nvarchar(200),
    TProductName           nvarchar(200),
    ProductDescription     nvarchar(255),
    ProductParam           nvarchar(255),
    MesProductDescription  nvarchar(200),
    procedureId            nvarchar(255),
    procedureName          nvarchar(255),
    procedureVersion       nvarchar(100),
    ProductLine            nvarchar(50),
    ProductParamCorrespond nvarchar(255)
)
go

