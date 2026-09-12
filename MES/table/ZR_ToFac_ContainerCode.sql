SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[ZR_ToFac_ContainerCode](
	[ZR_ToFac_ContainerCodeID] [char](12) NOT NULL,
	[ToFacId] [char](12) NULL,
	[ZR_ContainerCodeId] [char](12) NULL,
	[CreateData] [datetime] NULL,
	[UpdateData] [datetime] NULL,
	[BoxLotSn] [varchar](255) NULL,
 CONSTRAINT [PK_ZR_ToFac_ContainerCode] PRIMARY KEY CLUSTERED 
(
	[ZR_ToFac_ContainerCodeID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
CREATE NONCLUSTERED INDEX [IX_ZR_ToFac_Code_Rel] ON [dbo].[ZR_ToFac_ContainerCode]
(
	[ZR_ToFac_ContainerCodeID] ASC
)
INCLUDE([ZR_ContainerCodeId],[ToFacId]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
GO
ALTER TABLE [dbo].[ZR_ToFac_ContainerCode] ADD  CONSTRAINT [DF__ZR_ToFac___Creat__50689B1D]  DEFAULT (getdate()) FOR [CreateData]
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'主键id' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'ZR_ToFac_ContainerCode', @level2type=N'COLUMN',@level2name=N'ZR_ToFac_ContainerCodeID'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'转厂id' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'ZR_ToFac_ContainerCode', @level2type=N'COLUMN',@level2name=N'ToFacId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'容器id' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'ZR_ToFac_ContainerCode', @level2type=N'COLUMN',@level2name=N'ZR_ContainerCodeId'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'创建时间' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'ZR_ToFac_ContainerCode', @level2type=N'COLUMN',@level2name=N'CreateData'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'修改时间' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'ZR_ToFac_ContainerCode', @level2type=N'COLUMN',@level2name=N'UpdateData'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'箱号lotsn' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'ZR_ToFac_ContainerCode', @level2type=N'COLUMN',@level2name=N'BoxLotSn'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'转厂-容器中间表' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'ZR_ToFac_ContainerCode'
GO
