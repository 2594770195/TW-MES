
-- =============================================
-- Author:		<OrBit Team HK0325>
-- Create date: <2021.08.04>
-- Description:	PDA插件-生产已领料工单查询
--  
-- =============================================
CREATE PROCEDURE  [dbo].[PDA_ProductMOPickingQuery]
@I_Sender NVARCHAR(200)='', --客户端执行按钮
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@I_ExceptionFieldName NVARCHAR(100)='' OUTPUT, --向客户端报告引起冲突的字段
@I_LanguageId CHAR(1)='1',				--客户端传入的语言ID
@I_PlugInCommand VARCHAR(5)='',		--插件命令
@I_OrBitUserId CHAR(12)='',			--用户ID
@I_OrBitUserName NVARCHAR(100)='',	--用户名
@I_ResourceId	CHAR(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName NVARCHAR(100)='',	--资源名
@I_PKid CHAR(12) ='',				--主键
@I_ParentPKId CHAR(12)='',			--父级主键
@I_Parameter NVARCHAR(MAX)='',  		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@IsSwitchTab BIT=0,--是否是切换页签。为0时，不是切换页签，而是第一次打开插件
@StartDate DATETIME=NULL,
@EndDate DATETIME=NULL,
@EquipmentNo NVARCHAR(50)=''
 
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	
	--通用
	DECLARE @return_value INT=-1
	DECLARE @Enter NVARCHAR(100)=CHAR(13)+CHAR(10)

	--************begin 查询界面 begin*******************
	--页面加载方法，即第一次打开插件
	IF @I_Sender='PageLoad'
	BEGIN
	    IF ISNULL(@IsSwitchTab,0)=0
		BEGIN
			--SET @I_ExceptionFieldName='MOName'

			--1.第一次打开插件，初始化界面参数
			SET @StartDate=GETDATE()-1 --开始时间往前多少天
			SET @EndDate=GETDATE()
			--只精确到天，比如：2020-05-07 00:00:00.000
			SET @StartDate=CAST(CONVERT(VARCHAR, @StartDate, 23) AS DATETIME)
			SET @EndDate=CAST(CONVERT(VARCHAR, @EndDate, 23)+' 23:59:59' AS DATETIME)

			--初始化界面参数
			SELECT @StartDate AS StartDate,@EndDate AS EndDate,1 as IsSwitchTab
		END
		
		RETURN 0
	END

	IF @I_Sender='GetProductionMOList'
	BEGIN
	    --根据设备号筛选工单号
		IF ISNULL(@EquipmentNo,'')<>''
		BEGIN
			SELECT MO.MOId,MO.MOName,PR.ProductName,MO.MOQtyRequired,MO.EquipmentId,ISNULL(E.EquipmentNumber,'') AS EquipmentNo FROM MO 
			LEFT JOIN Equipment E ON MO.EquipmentId=E.EquipmentId
			INNER JOIN Product P ON MO.ProductId=P.ProductId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId 
			LEFT JOIN FrontProcessLot FPL ON MO.MOId=FPL.MOId
			WHERE MO.MOStates IN('20','30') AND ISNULL(MO.DeleteFlag,'')<>'X'
			AND MO.PlannedDateFrom>=@StartDate AND MO.PlannedDateTo<=@EndDate
			AND E.EquipmentNumber=@EquipmentNo
		END
		ELSE
		BEGIN
			SELECT MO.MOId,MO.MOName,PR.ProductName,MO.MOQtyRequired,MO.EquipmentId,ISNULL(E.EquipmentNumber,'') AS EquipmentNo FROM MO 
			LEFT JOIN Equipment E ON MO.EquipmentId=E.EquipmentId
			INNER JOIN Product P ON MO.ProductId=P.ProductId
			INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
			LEFT JOIN FrontProcessLot FPL  ON MO.MOId=FPL.MOId
			WHERE MO.MOStates IN('20','30') AND ISNULL(MO.DeleteFlag,'')<>'X' AND MO.PlannedDateFrom>=@StartDate 
			AND MO.PlannedDateTo<=@EndDate AND ISNULL(MO.EquipmentId,'')<>''
		END

		RETURN 0
	END

	RETURN 0
END
go

