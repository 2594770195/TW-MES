SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[WW_RMInventory](
	[WWId] [char](12) NOT NULL,
	[LotId] [char](12) NULL,
	[LotSN] [nvarchar](100) NULL,
	[LotStatus] [char](1) NULL,
	[QCStatus] [char](1) NULL,
	[IsolateStatus] [char](1) NULL,
	[Qty] [decimal](18, 8) NULL,
	[OrgQty] [decimal](18, 8) NULL,
	[IsSM] [bit] NULL,
	[UOMId] [char](12) NULL,
	[OrgLotSN] [nvarchar](100) NULL,
	[BoxSN] [nvarchar](100) NULL,
	[MBoxSN] [nvarchar](100) NULL,
	[OBoxSN] [nvarchar](100) NULL,
	[TurnoverBoxSN] [nvarchar](100) NULL,
	[PalletSN] [nvarchar](100) NULL,
	[ProductId] [char](12) NULL,
	[POId] [char](12) NULL,
	[VendorId] [char](12) NULL,
	[DeliveryBatch] [varchar](50) NULL,
	[ProductionDate] [varchar](50) NULL,
	[ProductionLotNO] [varchar](50) NULL,
	[ReceiveDate] [datetime] NULL,
	[MOId] [char](12) NULL,
	[sMOName] [nvarchar](20) NULL,
	[sSOItemSequence] [char](10) NULL,
	[sSOName] [nvarchar](20) NULL,
	[MOItemId] [char](12) NULL,
	[MOItemTaskId] [char](12) NULL,
	[CustomerId] [char](12) NULL,
	[EntryDate] [datetime] NULL,
	[ValidityEndDate] [date] NULL,
	[FactoryId] [char](12) NULL,
	[WorkcenterId] [char](12) NULL,
	[CellId] [char](12) NULL,
	[IsStorage] [bit] NULL,
	[IsInternalLot] [bit] NULL,
	[LastestTxnCode] [nvarchar](50) NULL,
	[LotSType] [varchar](2) NULL,
	[Operator] [nvarchar](50) NULL,
	[IsHS] [bit] NULL,
	[SAPRemark] [nvarchar](50) NULL,
	[ModifyDate] [datetime] NULL,
	[CreateDate] [datetime] NULL,
	[HoldResult] [nvarchar](255) NULL,
	[IsExceedPicking] [bit] NULL,
	[SoToMo] [nvarchar](20) NULL,
	[isInDCSJar] [nvarchar](50) NULL,
 CONSTRAINT [PK_WW_RMInventory] PRIMARY KEY CLUSTERED 
(
	[WWId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_BoxSN] ON [dbo].[WW_RMInventory]
(
	[BoxSN] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_CellId] ON [dbo].[WW_RMInventory]
(
	[CellId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_FactoryId] ON [dbo].[WW_RMInventory]
(
	[FactoryId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_LotId] ON [dbo].[WW_RMInventory]
(
	[LotId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_LotSN] ON [dbo].[WW_RMInventory]
(
	[LotSN] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_LotSType] ON [dbo].[WW_RMInventory]
(
	[LotSType] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_MBoxSN] ON [dbo].[WW_RMInventory]
(
	[MBoxSN] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_OBoxSN] ON [dbo].[WW_RMInventory]
(
	[OBoxSN] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_PalletSN] ON [dbo].[WW_RMInventory]
(
	[PalletSN] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_ProductId] ON [dbo].[WW_RMInventory]
(
	[ProductId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_ProductionLotNO] ON [dbo].[WW_RMInventory]
(
	[ProductionLotNO] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_ReceiveDate] ON [dbo].[WW_RMInventory]
(
	[ReceiveDate] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_TurnoverBoxSN] ON [dbo].[WW_RMInventory]
(
	[TurnoverBoxSN] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_ValidityEndDate] ON [dbo].[WW_RMInventory]
(
	[ValidityEndDate] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_WW_RMInventory_WorkcenterId] ON [dbo].[WW_RMInventory]
(
	[WorkcenterId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [missing_index_584] ON [dbo].[WW_RMInventory]
(
	[OrgLotSN] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [WW_RMInventory__OrgLotSN] ON [dbo].[WW_RMInventory]
(
	[OrgLotSN] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_LotQCStatus]  DEFAULT ('0') FOR [QCStatus]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_IsIsolation]  DEFAULT ('0') FOR [IsolateStatus]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_Qty]  DEFAULT ((0)) FOR [Qty]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_OrgQty]  DEFAULT ((0)) FOR [OrgQty]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_Isd]  DEFAULT ((0)) FOR [IsSM]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_EntryDate]  DEFAULT (getdate()) FOR [EntryDate]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_ValidityEndDate]  DEFAULT (NULL) FOR [ValidityEndDate]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_IsStorage]  DEFAULT ((1)) FOR [IsStorage]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_IsInternalLot]  DEFAULT ((0)) FOR [IsInternalLot]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_LotSType]  DEFAULT ((0)) FOR [LotSType]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_IsMSD]  DEFAULT ((0)) FOR [IsHS]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_ModifyDate]  DEFAULT (getdate()) FOR [ModifyDate]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_CreateDate]  DEFAULT (getdate()) FOR [CreateDate]
GO
ALTER TABLE [dbo].[WW_RMInventory] ADD  CONSTRAINT [DF_WW_RMInventory_IsExceedPicking]  DEFAULT ((0)) FOR [IsExceedPicking]
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'材料、半成品、成品库存表主键' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'WWId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'LotId' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'LotId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'批次号' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'LotSN'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'批号状态 （状态不能随便加，以免影响WES的功能，计算库存时状态取1或0）：
0（锁定）；
1（正常）
2（删除-比如盘亏删除）
9（预留-系统中，所有单据，扫描变成9，单据确认后变成1）

在用户编码UserCode表里有维护，方便获取状态描述' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'LotStatus'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'QC状态：0无操作；1待检；2合格；3不合格' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'QCStatus'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'隔离状态：0无隔离；1已隔离。已被隔离的物料有些业务不允许使用（比如：生产领料、上料）' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'IsolateStatus'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Lot内数量' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'Qty'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'原始数量' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'OrgQty'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'是否是散货。用途（比如：发料时，散货先出）' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'IsSM'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'单位ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'UOMId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'来源批号' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'OrgLotSN'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'箱号' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'BoxSN'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'中箱' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'MBoxSN'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'外箱' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'OBoxSN'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'周转箱号，每次按周转箱入库时，把之前按周转箱入库的这个字段置空（即保存周转箱最新的数据），方便发料' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'TurnoverBoxSN'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'栈板号' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'PalletSN'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'产品ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'ProductId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'采购订单ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'POId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'供应商ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'VendorId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'送货批次。一天一个供应商就是一批' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'DeliveryBatch'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'生产日期 DateCode' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'ProductionDate'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'生产批次 LotNO' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'ProductionLotNO'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'来料日期' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'ReceiveDate'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'工单ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'MOId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'工单明细MOItemId' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'MOItemId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'工单任务单ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'MOItemTaskId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'客户ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'CustomerId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'入库日期' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'EntryDate'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'有效日期。NUll代表没有有效期' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'ValidityEndDate'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'工厂ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'FactoryId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'工作中心ID。对于IsStorage=1，那么就是仓库；对于IsStorag=0，可以存在普通工作中心或线体' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'WorkcenterId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'储位ID' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'CellId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'是否在库 1 是 0 否' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'IsStorage'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'是否自制件 1 是 0 否' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'IsInternalLot'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'最新执行的事务代码，用于物料管理。执行Txn_LotTrack存储过程会更新' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'LastestTxnCode'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'批次来源类型：
0（默认类型：不代表具体的来源）；
1（物料：来料上架，采购送货等）；
2（物料：库存物料批次打印，一般期初使用）；
3（物料：生产退料单，启动的批次）；
4（物料：超期复检单，在超期复检单进行物料拆批）；
5（物料：物料批次拆分，包括库存物料批次拆分、产线物料批次拆分、物料合并）；
6（物料：工单明细，直接启动物料批次，插入库存表）；
7（取样上架）；
8（无码补印 ，非库存物料）；
29（周转箱的库存批，即不按单片管理，汇总的批次数）；
30（成品、半成品：完工入库时插入库存表）；
31（成品、半成品：销售退库时，在销售退库单启动的LotSN）

' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'LotSType'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'作业员工号' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'Operator'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'是否湿敏材料 1/0' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'IsHS'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'SAP备注' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'SAPRemark'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'修改日期' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'ModifyDate'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'创建日期' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'CreateDate'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'锁定原因' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'HoldResult'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'是否是超领料' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'IsExceedPicking'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'转呆滞' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'SoToMo'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'是否在DCS原料罐里' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'WW_RMInventory', @level2type=N'COLUMN',@level2name=N'isInDCSJar'
GO
