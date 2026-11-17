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
        constraint DF_MOSemiFinishedLotAllocation_IsOccupyAllocatedQty default 1 not null, -- 是否占用已分配数量：1=占用(确认或未确认)，删除时置 0 释放
    ConfirmStatus                 char(1)
        constraint DF_MOSemiFinishedLotAllocation_ConfirmStatus default '0' not null, -- 确认状态：0=未确认(仅当前单号分配时占用库存)，1=已确认(永久占用库存)
    allow_batch                  bit
        constraint DF_MOSemiFinishedLotAllocation_allow_batch default 0 not null, -- 是否分批分配：0=不分批(确认时需足量)，1=分批(可部分分配)
    DeleteFlag                    char(1)
        constraint DF_MOSemiFinishedLotAllocation_DeleteFlag default '0' not null, -- 逻辑删除：0=有效，1=删除
    SAPSyncFlag                   char(1)
        constraint DF_MOSemiFinishedLotAllocation_SAPSyncFlag default '0' not null, -- SAP同步状态：0=未同步(待同步)，1=已同步；任何ConfirmStatus='1'的修改都置回'0'，由统一同步逻辑循环调用未同步记录的MO上报
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
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'是否占用已分配数量，1=占用，0=不占用；新增记录默认 1，删除时置 0 释放占用' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'IsOccupyAllocatedQty'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'确认状态，0=未确认(仅当前单号分配时占用库存)，1=已确认(永久占用库存)' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'ConfirmStatus'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'是否分批分配，0=不分批(确认时需足量)，1=分批(可部分分配)' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'allow_batch'
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

-- =============================================
-- 已存在表的升级脚本（新库执行上方 create table 即可忽略此段）
-- 为既有表补充 ConfirmStatus 确认状态字段 / allow_batch 是否分批字段
-- =============================================
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.MOSemiFinishedLotAllocation')
        AND name = N'ConfirmStatus'
)
BEGIN
    ALTER TABLE dbo.MOSemiFinishedLotAllocation
        ADD ConfirmStatus char(1) NOT NULL
        CONSTRAINT DF_MOSemiFinishedLotAllocation_ConfirmStatus DEFAULT '0'

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'确认状态，0=未确认(仅当前单号分配时占用库存)，1=已确认(永久占用库存)' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'ConfirmStatus'
END
GO

-- 为既有表补充 allow_batch 是否分批分配字段
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.MOSemiFinishedLotAllocation')
        AND name = N'allow_batch'
)
BEGIN
    ALTER TABLE dbo.MOSemiFinishedLotAllocation
        ADD allow_batch bit NOT NULL
        CONSTRAINT DF_MOSemiFinishedLotAllocation_allow_batch DEFAULT 0

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'是否分批分配，0=不分批(确认时需足量)，1=分批(可部分分配)' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'allow_batch'
END
GO

-- 为既有表补充 SAPSyncFlag SAP同步状态字段
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.MOSemiFinishedLotAllocation')
        AND name = N'SAPSyncFlag'
)
BEGIN
    ALTER TABLE dbo.MOSemiFinishedLotAllocation
        ADD SAPSyncFlag char(1) NOT NULL
        CONSTRAINT DF_MOSemiFinishedLotAllocation_SAPSyncFlag DEFAULT '0'

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'SAP同步状态，0=未同步(待同步)，1=已同步；任何ConfirmStatus=1的记录被修改/取消/扣数后都置回0，操作完成后由统一同步逻辑循环调用存在未同步记录的MO上报SAP，同步成功置1' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'MOSemiFinishedLotAllocation', @level2type=N'COLUMN',@level2name=N'SAPSyncFlag'
END
GO
