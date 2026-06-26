create table CostCenter
(
    CostCenterId          char(12) not null
        constraint PK_CostCenter
            primary key,
    CostCenterName        nvarchar(50),
    CostCenterDescription nvarchar(100)
)
go

