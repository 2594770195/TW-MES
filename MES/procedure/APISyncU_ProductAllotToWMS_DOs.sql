SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OrBit Team Orbchay>
-- Create date: <2026.01.17>
-- Description:	<获取 调拨申请 数据，并传给WMS> 原仓库和目标仓库都必须有
-- Rev: 1.00
-- =============================================
CREATE PROCEDURE [dbo].[APISyncU_ProductAllotToWMS_DOs]
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@ItemName NVARCHAR(50)='',                 --项目名称
--- 以上为标准字段-------------------------
@ProductAllotName NVARCHAR(50)='',--生产调拨单
@UserId CHAR(12)='' --用户ID
    
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

	--委外退货ProductAllot
	DECLARE @ProductAllotId CHAR(12)=''
	DECLARE @BillStates VARCHAR(20)=''
	DECLARE @BillStatesDesc NVARCHAR(50)=''
	DECLARE @BillClass VARCHAR(20)=''

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

		--IF ISNULL(@UserName,'')=''
		--BEGIN
		--	SET @I_ReturnMessage='ServerMessage:[调用WMS] 用户名/用户账号不能为空！'
		--	RETURN -1
		--END

		--IF ISNULL(@UserPwd,'')=''
		--BEGIN
		--	SET @I_ReturnMessage='ServerMessage:[调用WMS] 用户密码不能为空！'
		--	RETURN -1
		--END
	END
	--**************end  1.获取接口信息   end*************************


	--第二：
	--**************begin  2.获取要回传ERP的数据（要检查单据） begin*************************
	BEGIN
		--获取请求数据
		IF ISNULL(@ProductAllotName,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:[调用WMS] 生产调拨单不能为空！';
			RETURN -1
		END

		--获取单据信息
		SELECT @ProductAllotId=ProductAllotId,
			   @BillStates=ProductAllotStates
		FROM dbo.ProductAllot
		WHERE ProductAllotName=@ProductAllotName

		--SELECT * FROM ProductAllot ORDER BY CreateDate desc


		IF ISNULL(@ProductAllotId,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:[调用WMS] 生产调拨单【'+@ProductAllotName+'】不存在！'
			RETURN -1
		END

		--获取单据状态描述
		SELECT @BillStatesDesc=BillStatesDescription
		FROM dbo.Bill
		INNER JOIN dbo.BillStates ON BillStates.BillId = Bill.BillId
		WHERE BillName='ProductAllot' AND BillStatesName=@BillStates
		AND IsERP=0

		--检查单据状态
		IF @BillStates NOT IN('20')--审核状态的单据才需要发送调拨单
		BEGIN
			SET @I_ReturnMessage='ServerMessage:[调用WMS] 生产调拨单【'+@ProductAllotName+'】'
			+'当前状态【'+ISNULL(@BillStatesDesc,'')+'】,不可以过账，请检查！'

			RETURN -1
		END

		--检查是否有调拨需求数量
		IF NOT EXISTS(SELECT 1 FROM dbo.ProductAllotItem
		WHERE ProductAllotId=@ProductAllotId AND AllotQty>0 AND ProductAllotItem.DeleteFlag='')
		BEGIN
			SET @I_ReturnMessage='ServerMessage:[调用WMS] 生产调拨单【'+@ProductAllotName+'】'
			+'无实际生产调拨数据,不可以通知WMS，请检查！'

			RETURN -1
		END

		Declare @FromWareHouseId CHAR(50)=''
        Declare @ToWareHouseId CHAR(50)=''
        select @FromWareHouseId=WorkcenterId,@ToWareHouseId=ToWorkcenterId from dbo.ProductAllot WHERE ProductAllotId=@ProductAllotId
		
		--单据头  使用WMS发货单接口
		IF OBJECT_ID('tempdb..#Head') IS NOT NULL DROP TABLE #Head
		CREATE TABLE #Head(
			dlvNo NVARCHAR(50),
			dlvDate DATETIME,
			dlvMode INT,
			whCode NVARCHAR(50),
			fromAddr NVARCHAR(200),
			priority INT,
			partnerCode NVARCHAR(50),
			workshopCode NVARCHAR(50),
			toWhCode NVARCHAR(50),
			deliverAddr NVARCHAR(200),
			recipientName NVARCHAR(50),
			ladingMode INT,
			voucherID NVARCHAR(50),
			refKey CHAR(12)
		)

		INSERT INTO #Head
		SELECT ProductAllotName AS dlvNo,
			   ProductAllot.CreateDate AS dlvDate,
			   7 AS dlvMode,--调拨出库
			   p2.WMSWarehouseCode AS whCode,
               f2.FactoryName + '.' +wc2.WorkcenterName AS fromAddr,
			   0 AS priority,
			   '0000000' AS partnerCode,
			   '' AS workshopCode,
			   p1.WMSWarehouseCode AS toWhCode,
			   f.FactoryName + '.' +wc.WorkcenterName AS deliverAddr,
			   SysUser.UserDescription AS recipientName,
			   3 AS ladingMode,
			   '' AS voucherID,
			   ProductAllot.ProductAllotId AS refKey
		FROM dbo.ProductAllot
		LEFT JOIN dbo.SysUser ON SysUser.CreateUserId = ProductAllot.CreateUserId
        left join ProductlineWH p1 on p1.warehouseid=ProductAllot.ToWorkcenterId
        left join ProductlineWH p2 on p2.warehouseid=ProductAllot.WorkcenterId
		LEFT JOIN dbo.Workcenter wc ON wc.WorkcenterId = ProductAllot.ToWorkcenterId
        LEFT JOIN dbo.Workcenter wc2 ON wc2.WorkcenterId = ProductAllot.WorkcenterId
        left join Factory f on f.FactoryId=ProductAllot.ToFactoryId
        left join Factory f2 on f2.FactoryId=ProductAllot.FactoryId
		WHERE ProductAllotId=@ProductAllotId

--         SELECT ProductAllotName AS adviceNo,
-- 			   ProductAllot.CreateDate AS adviceDate,
-- 			   7 AS adviceType,--调拨出库
--                '' AS cargoOwnerCode,
--                ProductAllot.CreateDate AS deadline,
-- 			   0 AS priority,
-- 			   '0000000' AS partnerCode,
-- 			   '' AS workshopCode,
-- 			   --'TW02' AS toWhCode,--先使用WMS仓库
-- 			   --'C101' AS toWhCode,
-- 			   p.WMSWarehouseCode AS toWhCode,
-- 			   wc.WorkcenterName AS deliverAddr,
-- 			   SysUser.UserDescription AS recipientName,
--                SysUser.UserName AS requesterCode,
-- 			   ProductAllot.ProductAllotId AS refKey
--  			   INTO #Head
-- 		FROM dbo.ProductAllot
-- 		LEFT JOIN dbo.SysUser ON SysUser.CreateUserId = ProductAllot.CreateUserId
-- 		LEFT JOIN dbo.Workcenter ON Workcenter.WorkcenterId = ProductAllot.WorkcenterId
-- 		LEFT JOIN dbo.Workcenter wc ON wc.WorkcenterId = ProductAllot.ToWorkcenterId
-- 		left join ProductlineWH p on p.warehouseid=ProductAllot.ToWorkcenterId
-- 		WHERE ProductAllotId=@ProductAllotId


		--单据明细
		IF OBJECT_ID('tempdb..#Item') IS NOT NULL DROP TABLE #Item
		CREATE TABLE #Item(
			itemID INT,
			materialCode NVARCHAR(200),
			deadline DATETIME,
			quantity DECIMAL(18,2),
			qaStatus INT,
			batchNo NVARCHAR(100),
			manufacturerCode NVARCHAR(100),
			licPlateNo NVARCHAR(100),
			rfPartnerCode NVARCHAR(50),
			rfOrderNo NVARCHAR(50),
			excessRatio INT,
			refName NVARCHAR(50),
			refID NVARCHAR(50),
			refNo NVARCHAR(50),
			refItemID INT,
			refItemKey CHAR(12),
			remark NVARCHAR(500)
		)

		INSERT INTO #Item
		SELECT TRY_CONVERT(INT, ProductAllotItem.ItemSequence) AS itemID,
			   ProductName AS materialCode,
               ProductAllotItem.CreateDate AS deadline,
			   AllotQty AS quantity,
			   1 AS qaStatus,
			   ProductAllotTemp.ProductionLotNO AS batchNo,
			   Factory.FactoryName AS manufacturerCode,
			   '' AS licPlateNo,
			   '' AS rfPartnerCode,
			   '' AS rfOrderNo,
			   1 AS excessRatio,
			   '' AS refName,
			   '' AS refID,
			   @ProductAllotName AS refNo,
			   ItemSequence AS refItemID,
			   ProductAllotItem.ProductAllotItemId AS refItemKey,
			   '' AS remark
		FROM dbo.ProductAllotItem
		LEFT JOIN dbo.ProductAllot ON ProductAllot.ProductAllotId = ProductAllotItem.ProductAllotId
		LEFT JOIN dbo.Product ON Product.ProductId = ProductAllotItem.ProductId
		LEFT JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
		LEFT JOIN dbo.Factory ON Factory.FactoryId = ProductAllot.FactoryId
		LEFT JOIN (select WW_RMInventory.ProductionLotNO,ProductAllotTemp.ProductId from dbo.ProductAllotTemp 
		        LEFT JOIN WW_RMInventory ON WW_RMInventory.LotSN = ProductAllotTemp.LotSn
		        where FromWareHouseId = @FromWareHouseId
				AND ToWareHouseId = @ToWareHouseId
				AND UserId = @UserId ) as ProductAllotTemp ON ProductAllotTemp.ProductId = ProductAllotItem.ProductAllotId
		WHERE ProductAllotItem.ProductAllotId=@ProductAllotId  AND ProductAllotItem.DeleteFlag=''
	END
	--**************end  2.获取要回传ERP的数据（要检查单据）  end*************************
	IF NOT EXISTS (SELECT 1 FROM #Head)
	BEGIN
		SET @I_ReturnMessage='单据【'+@ProductAllotName+'】生产调拨通知WMS失败！调拨单据信息不存在，请确认！'
		RETURN -1
	END;
	IF NOT EXISTS (SELECT 1 FROM #Item)
	BEGIN
		SET @I_ReturnMessage='单据【'+@ProductAllotName+'】生产调拨通知WMS失败！调拨明细不存在，请确认！'
		RETURN -1
	END;

	--第三：
	--**************begin  3.回传ERP，获取接口返回的数据，并解析，更新MES单据    begin*************************
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
			SET @I_ReturnMessage='单据【'+@ProductAllotName+'】生产调拨通知WMS失败！'+'WMS返回：'+@I_ReturnMessage
			--SET @E_TYPE='mes-1'
			RETURN -1
		END;

		--制作请求头
		DECLARE @RequestHeaders NVARCHAR(MAX) = N'Authorization<|=|>Bearer ' + @I_ReturnOAuth;


		-- Head（核心修改：去掉ROOT('Head') + 新增WITHOUT_ARRAY_WRAPPER + AUTO→PATH，平铺表头字段）
		SELECT @RequestData=(SELECT *
		FROM #Head FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER) -- 改动1：删ROOT('Head')、AUTO→PATH、加WITHOUT_ARRAY_WRAPPER

        -- Item（核心修改：路径从'$.Item'→'$.items'，匹配接口规范）
		SET @RequestData=JSON_MODIFY(@RequestData,
									 '$.items', -- 改动2：Item→items（小写+s，匹配DOItem[]规范）
									 (SELECT * FROM #Item FOR JSON AUTO,INCLUDE_NULL_VALUES)
									 )

		--组合数据
		SET @Api_PostDataStr=REPLACE(@Api_PostDataStr,'@@RequestData',@RequestData)

		-- 1. 截取掉"RequestData":之前的所有内容（删除SysInfo外层）
		SET @Api_PostDataStr = SUBSTRING(@Api_PostDataStr, CHARINDEX('"RequestData":', @Api_PostDataStr) + LEN('"RequestData":'), LEN(@Api_PostDataStr))
		-- 2. 去掉最后一个多余的}（删除RequestData外层的闭合符）
		SET @Api_PostDataStr = LEFT(@Api_PostDataStr, LEN(@Api_PostDataStr) - 1)
		--*************** end 获取最终的请求数据 end*************************************

		--todo
		--SET @I_ReturnMessage='122334564564'
		--select @Api_PostDataStr
		--RETURN -1


		--删除临时表
		DROP TABLE #Head
		DROP TABLE #Item

		--记录日志信息
		EXEC dbo.SysGetObjectPKId '','InterfaceLog',@InterfaceLogId OUTPUT
		INSERT INTO dbo.InterfaceLog
			 (
				 InterfaceLogId,
				 InterfaceItemId,
				 LogContent,
				 OS_Data,
				 CS_Data,
				 CreateDate,
				 BillTName,
				 BillId
			 )
		VALUES
			 (
				 @InterfaceLogId, -- InterfaceLogId - char(12)
				 @ItemId, -- InterfaceItemId - char(12)
				 N'', -- LogContent - nvarchar(100)
				 '', -- OS_Data - nvarchar(max)
				 @Api_PostDataStr, -- CS_Data - nvarchar(max)
				 GETDATE() ,-- CreateDate - datetime
				 'ProductAllot',
				 @ProductAllotId
			 )

		--调用接口前锁定
		UPDATE dbo.ProductAllot SET ToErpLock=1
		WHERE ProductAllotId=@ProductAllotId

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
                       @IsPost=1, --POST/GET
                       @WebAPIUrl=@Url,--WMS接口地址
                       @UserName=N'',--基本认证：用户。（可选，根据接口调用要求）
                       @UserPassword=N'', --基本认证：密码。（可选，根据接口调用要求）
                       @TimeOutS=5, --超时时间。（可选）
                       @ContentType=N'application/json',--内容类型。（可选，根据接口调用要求）
                       @Headers=@RequestHeaders,--请求头。（可选，根据接口调用要求）
                       @PostFormParams=N'',--POST 请求，表单，键值对。（可选，根据接口调用要求）--POST请求二选1
                       @PostRawParams=@Api_PostDataStr, -- @jsonObj,--POST 请求，Raw（可以上传支持的任意格式的文本）。（可选，根据接口调用要求）--POST请求二选1
                       @GetParams=N'currentPage<|=|>1<|&|>pageSize<|=|>100' --GET 请求，表单，键值对。（可选，根据接口调用要求）


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
			SET @LogContent='单据【'+@ProductAllotName+'】过账失败!'+@Api_ReturnData
			SET @E_TYPE='mes-1'
		END
		ELSE
		BEGIN
			--是否Json
			IF ISJSON(@Api_ReturnData)<=0
			BEGIN
				SET @LogContent='单据【'+@ProductAllotName+'】过账失败！接口返回的数据不是Json格式，请检查接口格式！WMS返回：'+@Api_ReturnData
				SET @E_TYPE='mes-1'
			END
			ELSE
			BEGIN
				--解析新格式的JSON
				BEGIN TRY
					--解析返回的状态信息（新JSON格式：顶层的result、error等字段）
					INSERT INTO @Deal_Result
							(
								E_TYPE,
								E_MSG
							)
					SELECT
						JSON_VALUE(@Api_ReturnData, '$.ok') AS E_TYPE,  -- 解析顶层的result字段
						JSON_VALUE(@Api_ReturnData, '$.error') AS E_MSG    -- 解析顶层的error字段
					WHERE
						JSON_VALUE(@Api_ReturnData, '$.ok') IS NOT NULL  -- 过滤空值

					--删除无用数据
					DELETE @Deal_Result WHERE ISNULL(E_TYPE,'')=''

					-- 如果解析到了错误类型，更新@E_TYPE变量（可选，根据业务需求）
					--IF EXISTS(SELECT 1 FROM @Deal_Result)
					--BEGIN
					--	SELECT TOP 1 @E_TYPE = E_TYPE FROM @Deal_Result
					--END
				END TRY
				BEGIN CATCH
					SET @LogContent='单据【'+@ProductAllotName+'】生产调拨通知WMS失败！解析Json格式异常，异常信息：'+ERROR_MESSAGE() +'WMS返回：'+@Api_ReturnData
					SET @E_TYPE='mes-1'
				END CATCH
			END
		END

		--SELECT @E_TYPE
		--获取接口处理结果的类型
		IF @E_TYPE=''
		BEGIN
			SELECT @E_TYPE=E_TYPE,
				   @E_MSG=E_MSG
			FROM @Deal_Result

			SET @E_TYPE=ISNULL(@E_TYPE,'')

			--如果成功
			IF @E_TYPE='true'
			BEGIN
				SET @LogContent='单据【'+@ProductAllotName+'】生产调拨通知WMS成功！'
			END
			ELSE
            BEGIN
				SET @LogContent='单据【'+@ProductAllotName+'】生产调拨通知WMS失败！WMS返回结果：'+@E_MSG
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


		--更新MES单据状态 --更新为已确认状态
		UPDATE dbo.ProductAllot SET
			       ProductAllotStates='20',
				   ToErpLock=0
			WHERE ProductAllotId=@ProductAllotId

		IF @E_TYPE='true' RETURN 0
		ELSE RETURN -1

	END
	--**************end  3.回传ERP，获取接口返回的数据，并解析，更新MES单据    end*************************

END
GO
