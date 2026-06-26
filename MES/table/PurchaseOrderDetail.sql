create table PurchaseOrderDetail
(
    PurchaseOrderDetailId char(12)
        constraint DF_PurchaseOrderDetail_PurchaseOrderDetailId default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_PurchaseOrderDetail
            primary key,
    PurchaseOrderId       char(12),
    EquipmentId           char(12),
    PurchaseQty           int
        constraint DF_PurchaseOrderDetail_PurchaseQty default 0,
    ItemQtyReceived       int
        constraint DF_PurchaseOrderDetail_ItemQtyReceived default 0,
    ItemQtyRejected       int
        constraint DF_PurchaseOrderDetail_ItemQtyRejected default 0,
    UomId                 char(12),
    UnitPrice             decimal(18, 2),
    Remarks               nvarchar(200),
    purchaseRequisitionId char(12),
    UseDepartment         nvarchar(100),
    CreateUserId          char(12),
    CreateDate            datetime
        constraint DF_PurchaseOrderDetail_CreateDate default getdate()
)
go

