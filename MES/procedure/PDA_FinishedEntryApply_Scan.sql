SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2021/05/26 17:10:22:6269>
-- Description:   <入库申请。扫描>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[PDA_FinishedEntryApply_Scan]
@I_Sender NVARCHAR(200)='',						--	客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,		--	返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT,	--	向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',						--	客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',					--	插件命令
@I_OrBitUserId CHAR(12)='',						--	用户ID
@I_OrBitUserName NVARCHAR(100)='',				--	用户名
@I_ResourceId CHAR(12)='',						--	资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',				--	资源名
@I_PKid CHAR(12) ='',							--	主键
@I_ParentPKId CHAR(12)='',						--	父级主键
@I_Parameter NVARCHAR(MAX)='',  				--	插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@WhCategoryCode VARCHAR(5)='',                  -- 入库类别
@WhCategory NVARCHAR(50) = '' ,				    --	入库类别
@WareHouseId CHAR(12)='',                       --	仓库ID
@WareHouseName NVARCHAR(50)='',                 -- 仓库
@ScanSN NVARCHAR(50) = '' ,
@EntryQty DECIMAL(18,8) = 0

AS
BEGIN
	-- set NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	/*
		Content1:由于PDA版本是完全按照PC版本Copy的，所有直接调用MES事务对应的存储过程,以便修改后完全同步
		Content2:所以修改时，直接修改电脑版就行，PDA版本界面的关键参数与PC保持一致就行
	*/
	

	--公共信息变量
	DECLARE @return_value INT=-1
	DECLARE @Enter VARCHAR(2)=CHAR(13)+CHAR(10)
	

	EXEC @return_value=dbo.Txn_FinishedEntryApply_Scan
	    @I_Sender=@I_Sender,
	    @I_ReturnMessage=@I_ReturnMessage OUTPUT, -- nvarchar(max)
	    @I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT, -- nvarchar(100)
	    @I_LanguageId=@I_LanguageId,
	    @I_PlugInCommand=@I_PlugInCommand,
	    @I_OrBitUserId=@I_OrBitUserId,
	    @I_OrBitUserName=@I_OrBitUserName,
	    @I_ResourceId=@I_ResourceId,
	    @I_ResourceName=@I_ResourceName,
	    @I_PKid=@I_PKid,
	    @I_ParentPKId=@I_ParentPKId,
	    @I_Parameter=@I_Parameter,
	    @WhCategoryCode=@WhCategoryCode,
	    @WhCategory=@WhCategory,
	    @WareHouseId=@WareHouseId,
	    @WareHouseName=@WareHouseName,
	    @ScanSN=@ScanSN,
		@EntryQty=@EntryQty


	SET @I_ReturnMessage=@I_ReturnMessage+@Enter
	RETURN @return_value
END

GO
