SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		<OrBit Team Orbchay>
-- Create date: <2026.01.17>
-- Description:	<查询WMS库存信息>
-- Rev: 1.00
-- =============================================
CREATE PROCEDURE [dbo].[APISyncD_WMSInventory]
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@ItemName NVARCHAR(50)='D_WMSInventory',                 --项目名称
--- 以上为标准字段-------------------------
@LicPlateNo NVARCHAR(50)='', --WMS存货组即MES批次号
@Status BIT =0, --0;正常在库|4;已发走或无存量
@BatchNo    Nvarchar(50)='', --SAP批次
@MaterialCode    Nvarchar(50)='' ,
@FactoryName	NVARCHAR(50)='',
@WorkcenterName  NVARCHAR(50)=''
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	--通用变量
	DECLARE @Return_int INT=-1
	DECLARE @CurDate DATETIME=GETDATE()
	DECLARE @timestamp VARCHAR(30)=REPLACE(REPLACE(REPLACE(CONVERT(VARCHAR(100), GETDATE(), 120),'-',''),' ',''),':','')
	DECLARE @InterfaceLogId CHAR(12)='' --日志信息
	DECLARE @LogContent NVARCHAR(max)=''--日志信息
	DECLARE @E_TYPE VARCHAR(20)='' --返回状态类型
	DECLARE @E_MSG NVARCHAR(max)='' --返回状态信息

	--接口配置信息
	DECLARE @ItemId CHAR(12)='' --项目名称Id
	DECLARE @Url NVARCHAR(200)=''
	DECLARE @UserName NVARCHAR(50)=''
	DECLARE @UserPwd NVARCHAR(50)=''
	DECLARE @TimeOutS INT=0
	DECLARE @IsExe BIT=0

	--请求与返回信息
	DECLARE @RequestData NVARCHAR(MAX)=''
	DECLARE @Api_PostDataStr NVARCHAR(MAX)=''
	DECLARE @Api_ReturnData NVARCHAR(MAX)='' --返回的数据

    DECLARE @GetParams NVARCHAR(max)=''
    --查询结果
    DECLARE @InvItem TABLE (
    RecQuantity   DECIMAL(18,3),
    BatchNo       NVARCHAR(50),
    LicPlateNo    NVARCHAR(50),
    MaterialCode  NVARCHAR(50),
	warehouseName NVARCHAR(50),
	FactoryName   NVARCHAR(50)
    -- 以后要加字段，在这里加一列
    );



	--调用接口返回的标准提示信息,解析@Api_ReturnData得到
	DECLARE @Deal_Result TABLE(
		E_TYPE VARCHAR(20),
		E_MSG NVARCHAR(max)
	)


	
	--ERP接口请求json
	-- 请求数据初始化。
	--例子：
	SET @Api_PostDataStr='{
    "SysInfo": {
      "SysId": "0004",
	  "SysName": "ERP",
      "APICode": "S0064",
      "SendTime": "@@timestamp",
      "UserName": "Orbchay"
    },
    "RequestData": 
	 @@RequestData
}'
	--去掉回车、制表、换行、空格
	SET @Api_PostDataStr=REPLACE(REPLACE(REPLACE(REPLACE(@Api_PostDataStr,CHAR(13),''),CHAR(10),''),CHAR(9),''),' ','')


	--替换时间戳
	SET @Api_PostDataStr=REPLACE(@Api_PostDataStr,'@@timestamp',@timestamp)


	--第一：
	--**************begin  1.获取接口信息   begin*************************
	BEGIN
		IF ISNULL(@ItemName,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:[调用WMS] 项目名称不能为空！'
			RETURN -1
		END 
		SELECT @Url=WebUrl,
			   @UserName=UserName,
			   @UserPwd=UserPwd,
			   @TimeOutS=ISNULL(TimeOutS,0)*1000,
			   @ItemId=InterfaceItemId,
			   @IsExe=ISNULL(IsExe,0)
		FROM dbo.InterfaceItem 
		WHERE ItemName=@ItemName

		IF ISNULL(@ItemId,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:[调用WMS] 接口【'+@ItemName+'】不存在！'
			RETURN -1
		END

		IF @IsExe=0
		BEGIN
			SET @I_ReturnMessage='ServerMessage:[调用WMS] 接口【'+@ItemName+'】已关闭！'
			RETURN -1
		END

		IF ISNULL(@Url,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:[调用WMS] Web地址不能为空！'
			RETURN -1
		END 

	END 

	--**************end  1.获取接口信息   end*************************	
    --**************start  2.构造查询参数   start*************************	
    BEGIN

        IF ISNULL(@LicPlateNo,'')='' AND ISNULL(@MaterialCode,'')='' AND ISNULL(@BatchNo,'')=''
        BEGIN
            SET @I_ReturnMessage='ServerMessage:[调用WMS] 查询参数不足！'
			RETURN -1
        END
        IF ISNULL(@MaterialCode,'')<>'' AND  NOT EXISTS(select 1 from Product where TProductName=@MaterialCode)
        BEGIN
            SET @I_ReturnMessage='ServerMessage:[调用WMS] 物料编码不存在！'
			RETURN -1
        END

        Set @GetParams=N'condition<|=|>t.status=0' 
        IF ISNULL(@LicPlateNo,'')<>''
            Set @GetParams += ' AND t.licPlateNo=''' + REPLACE(@LicPlateNo, '''', '''''') + ''''
        IF ISNULL(@MaterialCode,'')<>''
            Set @GetParams += ' AND material.materialCode=''' + REPLACE(@MaterialCode, '''', '''''') + ''''
        IF ISNULL(@BatchNo,'')<>''
            Set @GetParams += ' AND t.BatchNo=''' + REPLACE(@BatchNo, '''', '''''') + ''''
		IF ISNULL(@FactoryName,'')<>'' AND ISNULL(@WorkcenterName,'')<>''
            Set @GetParams += ' AND binLoc.binlocCode=''' + REPLACE(@FactoryName+'.'+@WorkcenterName, '''', '''''') + ''''

        Set @GetParams += '<|&|>includeRelation<|=|>True<|&|>page<|=|>1<|&|>pageSize<|=|>10'
                insert into mwjtestlog(src,log1) VALUES('查询WMS库存',@GetParams)

    END


    --**************end  2.构造查询参数   end*************************	

	--**************begin  3.回传WMS，获取接口返回的数据，并解析    begin*************************
	BEGIN 
		--*************** begin 获取最终的请求数据 begin********************************
		--转Json
		--Token
		DECLARE @I_ReturnOAuth NVARCHAR(MAX),@Return_ints INT = -1
		EXEC @Return_ints=dbo.Com_GetWMSOAuthForUserCode 
		                                    @I_ReturnOAuth = @I_ReturnOAuth OUTPUT,    -- nvarchar(4000)
		                                    @I_ReturnMessage = @I_ReturnMessage OUTPUT -- nvarchar(max)

		IF @Return_ints<>0
		BEGIN
			SET @I_ReturnMessage='获取WMS库存失败！'+'WMS返回：'+@I_ReturnMessage
			--SET @E_TYPE='mes-1'
			RETURN -1
		END;

		--制作请求头
		DECLARE @RequestHeaders NVARCHAR(MAX) = N'Authorization<|=|>Bearer ' + @I_ReturnOAuth;

        --记录日志信息
		EXEC dbo.SysGetObjectPKId '','InterfaceLog',@InterfaceLogId OUTPUT
		INSERT INTO dbo.InterfaceLog
			 (
				 InterfaceLogId,
				 InterfaceItemId,
				 LogContent,
				 OS_Data,
				 CS_Data,
				 CreateDate
			 )
		VALUES
			 (
				 @InterfaceLogId, -- InterfaceLogId - char(12)
				 @ItemId, -- InterfaceItemId - char(12)
				 N'', -- LogContent - nvarchar(100)
				 '', -- OS_Data - nvarchar(max)
				 @Api_PostDataStr, -- CS_Data - nvarchar(max)
				 GETDATE() -- CreateDate - datetime
			 )

		--*************调用接口***************************
		BEGIN TRY 
			--EXEC @Return_int=dbo.CLR_CallWebAPI
			--	 @ReceiveData = @Api_ReturnData OUTPUT, -- nvarchar(max)
			--	 @LocalWCFUrl = N'', -- nvarchar(4000)
			--	 @IsPost = 1, -- bit
			--	 @WebAPIUrl = @Url, -- nvarchar(max)
			--	 @JsonPost =@Api_PostDataStr -- nvarchar(max)
			--SELECT @RequestHeaders
			--使用新的CLR
			EXEC @Return_int=dbo.CLR_CallWebAPIEx
                       @ReceiveData=@Api_ReturnData OUTPUT,
                       @LocalWCFUrl=N'',--WCF地址
                       @IsPost=0, --POST/GET
                       @WebAPIUrl=@Url,--WMS接口地址
                       @UserName=N'',--基本认证：用户。（可选，根据接口调用要求）
                       @UserPassword=N'', --基本认证：密码。（可选，根据接口调用要求）
                       @TimeOutS=5, --超时时间。（可选）
                       @ContentType=N'application/json',--内容类型。（可选，根据接口调用要求）
                       @Headers=@RequestHeaders,--请求头。（可选，根据接口调用要求）
                       @PostFormParams=N'',--POST 请求，表单，键值对。（可选，根据接口调用要求）--POST请求二选1
                       @PostRawParams=@Api_PostDataStr, -- @jsonObj,--POST 请求，Raw（可以上传支持的任意格式的文本）。（可选，根据接口调用要求）--POST请求二选1
                       @GetParams=@GetParams --GET 请求，表单，键值对。（可选，根据接口调用要求）


		END TRY
		BEGIN CATCH
			SET @Return_int=-1
			SET @Api_ReturnData=ERROR_MESSAGE()

		END CATCH

		--*************调用接口***************************
		--更新日志
		UPDATE dbo.InterfaceLog SET OS_Data=@Api_ReturnData
		WHERE InterfaceLogId=@InterfaceLogId

		--调用接口的结果
		IF @Return_int=-1
		BEGIN
			SET @LogContent='获取库存信息失败!'+@Api_ReturnData
			SET @E_TYPE='mes-1'
		END 
		ELSE 
		BEGIN 
			--是否Json
			IF ISJSON(@Api_ReturnData)<=0
			BEGIN
				SET @LogContent='获取库存信息失败！接口返回的数据不是Json格式，请检查接口格式！WMS返回：'+@Api_ReturnData
				SET @E_TYPE='mes-1'
			END 
			ELSE
			BEGIN
				--解析新格式的JSON
				BEGIN TRY
					--解析返回的状态信息（新JSON格式：顶层的result、error等字段）
					INSERT INTO @InvItem (RecQuantity, BatchNo, LicPlateNo, MaterialCode,warehouseName,FactoryName)
                    SELECT
                        RecQuantity,
                        BatchNo,
                        LicPlateNo,
                        MaterialCode,
						warehouseName,
						FactoryName
                    FROM OPENJSON(@Api_ReturnData)   -- 根就是数组，路径写 '$' 或不写第二参数都行
                    WITH (
                        RecQuantity   DECIMAL(18,3) '$.recQuantity',
                        BatchNo       NVARCHAR(50)  '$.batchNo',
                        LicPlateNo    NVARCHAR(50)  '$.licPlateNo',
                        MaterialCode  NVARCHAR(50)  '$.material.materialCode',  -- 嵌套对象直接用点路径
						warehouseName    NVARCHAR(50)  '$.binLoc.lgort',
						FactoryName    NVARCHAR(50)  '$.binLoc.werks'
                    );
                    SET @LogContent='获取库存信息成功'
				END TRY
				BEGIN CATCH
					SET @LogContent='获取库存信息失败！解析Json格式异常，异常信息：'+ERROR_MESSAGE() +'WMS返回：'+@Api_ReturnData
					SET @E_TYPE='mes-1'
				END CATCH
			END
		END


		--更新接口日志
		UPDATE dbo.InterfaceLog SET
			   LogContent=@LogContent,
			   StatusCode=@E_TYPE,
			   StatusDesc=@E_MSG
		WHERE InterfaceLogId=@InterfaceLogId

		--更新接口执行时间
		UPDATE dbo.InterfaceItem SET LastDate=@CurDate
		WHERE InterfaceItemId=@ItemId

		--提示信息
		SET @I_ReturnMessage='ServerMessage:[调用WMS] '+@LogContent

        select * from @InvItem
		IF @E_TYPE='true' RETURN 0	
		ELSE RETURN -1     

	END 
	--**************end  3.回传ERP，获取接口返回的数据，并解析，更新MES单据    end*************************	

END

GO
