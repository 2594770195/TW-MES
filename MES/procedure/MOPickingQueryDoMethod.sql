-- =============================================
-- Author:		<OrBit Team HK0313 >
-- Create date: <2022.03.31>
-- Description:	工单领料查询
-- =============================================
CREATE PROCEDURE  [dbo].[MOPickingQueryDoMethod]
@I_Sender nvarchar(200)='', --客户端执行按钮
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_ExceptionFieldName nvarchar(100)='' output, --向客户端报告引起冲突的字段
@I_LanguageId char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKid char(12) ='',				--主键
@I_ParentPKId char(12)='',			--父级主键
@I_Parameter nvarchar(100)='',		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@MOName NVARCHAR(50)=''      --工单号

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	DECLARE @RESULT INT =0

	EXEC @RESULT=[dbo].[PDA_MOPickingQuery]
	@I_Sender=@I_Sender,
	@I_ReturnMessage=@I_ReturnMessage OUTPUT,
	@I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
	@MOName=@MOName

	RETURN @RESULT

END













go

