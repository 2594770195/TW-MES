CREATE TABLE [dbo].[SAP_PRODUCT_INVENTORY](
	[Id] [nvarchar](100) NOT NULL,
	[FactoryName] [nvarchar](10) NULL,
	[ProductName] [nvarchar](18) NOT NULL,
	[WorkcenterName] [nvarchar](4) NOT NULL,
	[LotSN] [nvarchar](10) NOT NULL,
	[ProductInventoryNum] [decimal](18, 6) NULL,
	[CheckNum] [decimal](18, 6) NULL,
	[UomName] [nvarchar](3) NULL,
	[LockQty] [decimal](18, 6) NULL,
	[StorageDate] [nvarchar](30) NULL,
	[Note] [nvarchar](30) NULL,
	[SoName] [nvarchar](10) NULL,
	[ItemSequence] [nvarchar](6) NULL,
	[isChange] [nvarchar](50) NULL,
PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]