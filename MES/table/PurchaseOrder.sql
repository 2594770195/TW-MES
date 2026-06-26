create table PurchaseOrder
(
    PurchaseOrderId    char(12)
        constraint DF_PurchaseOrder_PurchaseOrderId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_PurchaseOrder
            primary key,
    PurchaseOrderName  nvarchar(30),
    PurchaseOrderDes   nvarchar(200),
    PurchaseOrderState char(3),
    FactoryId          char(12),
    VendorId           char(12),
    AppDivisionId      char(12),
    AppReason          nvarchar(100),
    ContractDocumentId char(12),
    ContractDocumentNO nvarchar(30),
    BasisId            char(12),
    KaiXiangFinish     bit
        constraint DF_PurchaseOrder_KaiXiangFinish default 0,
    YanSHouFinish      bit
        constraint DF_PurchaseOrder_YanSHouFinish default 0,
    AuditUser          char(10),
    AuditResult        char(2),
    AuditDate          datetime,
    AuditRemark        nvarchar(100),
    Remarks            nvarchar(200),
    CreateUserId       char(12),
    CreateDate         datetime
        constraint DF_PurchaseOrder_CreateDate default getdate()
)
go

