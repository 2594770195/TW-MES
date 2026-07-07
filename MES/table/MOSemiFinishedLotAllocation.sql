-- =============================================
-- 成品工单半成品批次预分配记录表
-- 仅记录预分配关系，不直接扣减 WW_RMInventory 库存数量
-- =============================================
create table [dbo].[MOSemiFinishedLotAllocation]
(
    MOSemiFinishedLotAllocationId char(12)
        constraint DF_MOSemiFinishedLotAllocation_Id default substring(CONVERT([char](36), newid(), 0), 1, 12) not null
        constraint PK_MOSemiFinishedLotAllocation
            primary key,                                  -- 主键
    MOId                          char(12)       null,     -- 成品工单 ID
    MOName                        nvarchar(50)   null,     -- 成品工单号快照
    MOItemId                      char(12)       null,     -- 工单半成品物料行 ID
    ProductId                     char(12)       null,     -- 半成品物料 ID
    WWId                          char(12)       null,     -- 库存记录 ID，对应 WW_RMInventory.WWId
    LotSN                         nvarchar(100)  null,     -- MES 批次号，对应 WW_RMInventory.LotSN
    ProductionLotNO               varchar(50)    null,     -- SAP/生产批次
    FactoryId                     char(12)       null,     -- 库存所在工厂
    WorkcenterId                  char(12)       null,     -- 库存所在仓库
    CellId                        char(12)       null,     -- 库存储位
    UOMId                         char(12)       null,     -- 单位
    Qty                           decimal(18, 8)
        constraint DF_MOSemiFinishedLotAllocation_Qty default 0 not null, -- 分配数量
    IsOccupyAllocatedQty          bit
        constraint DF_MOSemiFinishedLotAllocation_IsOccupyAllocatedQty default 1 not null, -- 是否占用已分配数量
    DeleteFlag                    char(1)
        constraint DF_MOSemiFinishedLotAllocation_DeleteFlag default '0' not null, -- 逻辑删除：0=有效，1=删除
    CreateUserId                  char(12)       null,     -- 创建人 ID
    CreateUserName                nvarchar(100)  null,     -- 创建人名称
    CreateDate                    datetime
        constraint DF_MOSemiFinishedLotAllocation_CreateDate default getdate() not null, -- 创建时间
    ModifyDate                    datetime
        constraint DF_MOSemiFinishedLotAllocation_ModifyDate default getdate() not null  -- 修改时间
)
go

create index IX_MOSemiFinishedLotAllocation_MOItem
    on [dbo].[MOSemiFinishedLotAllocation] (MOId, MOItemId, ProductId, DeleteFlag, IsOccupyAllocatedQty)
go

create index IX_MOSemiFinishedLotAllocation_LotSN
    on [dbo].[MOSemiFinishedLotAllocation] (LotSN, DeleteFlag, IsOccupyAllocatedQty)
go

create index IX_MOSemiFinishedLotAllocation_Product
    on [dbo].[MOSemiFinishedLotAllocation] (ProductId, DeleteFlag, IsOccupyAllocatedQty)
go

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'成品工单半成品批次预分配记录表，仅记录预分配关系，不直接扣减库存数量' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'主键' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'MOSemiFinishedLotAllocationId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'成品工单 ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'MOId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'成品工单号快照' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'MOName'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'工单半成品物料行 ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'MOItemId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'半成品物料 ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'ProductId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'库存记录 ID，对应 WW_RMInventory.WWId' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'WWId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'MES 批次号，对应 WW_RMInventory.LotSN；LotSN 唯一性仅约束库存表，分配表允许多条记录' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'LotSN'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'SAP/生产批次号，对应库存 ProductionLotNO' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'ProductionLotNO'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'库存所在工厂 ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'FactoryId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'库存所在仓库 ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'WorkcenterId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'库存储位 ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'CellId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'单位 ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'UOMId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'本次预分配数量' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'Qty'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'是否占用已分配数量，1=占用，0=不占用；新增记录默认 1' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'IsOccupyAllocatedQty'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'逻辑删除标记，0=有效，1=删除；查询和库存扣减只统计 0' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'DeleteFlag'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'创建人 ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'CreateUserId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'创建人名称' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'CreateUserName'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'创建时间' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'CreateDate'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'修改时间' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'ModifyDate'
GO
