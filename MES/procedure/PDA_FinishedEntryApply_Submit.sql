SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:        <OrBit Team Orbchay HH0102 >
-- Create date:   <2020/08/22 13:38:10:5298>
-- Description:   <入库申请：提交>
-- Rev: 15.00
-- Update comment:
-- Update date:
-- =============================================
CREATE PROCEDURE  [dbo].[PDA_FinishedEntryApply_Submit]
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
@FinishingEntryName NVARCHAR(50) = '',			-- 入库单
@NoteMessage NVARCHAR(200)='',
@NoteInfor NVARCHAR(200)='',
@Barrelage NVARCHAR(200)=''
AS

BEGIN
	-- set NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	/*
		Content1:方案说明：
		1.本方案由产线先“入库申请”扫描，入库申请时，生成单据的状态是10（待审核），扫描完之后点击“提交”，状态更新为20（已审核）
		2.仓库有对应的功能“入库接收”
	*/

	--TY
	DECLARE @Enter VARCHAR(2) = CHAR(13)+CHAR(10)
	DECLARE @return_value INT=-1

	EXEC @return_value=dbo.Txn_FinishedEntryApply_Submit
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
	    @FinishingEntryName=@FinishingEntryName,
		@NoteMessage=@NoteMessage,
		@NoteInfor=@NoteInfor,
		@Barrelage=@Barrelage

    IF @return_value=0
        Select '' AS FinishingEntryName,'' AS NoteInfor, '' AS NoteMessage
	

	SET @I_ReturnMessage=@I_ReturnMessage+@Enter
	RETURN @return_value
END

GO
