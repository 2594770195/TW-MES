SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		<OrBit Team Orbchay>
-- Create date: <2026.01.17>
-- Description:	<获取 杂发单 数据，并回写WMS 使用WMS的发货单（对应MES过站原材料扣料）>
-- Rev: 1.00
-- =============================================
ALTER PROCEDURE [dbo].[APISyncU_PickingOtherToWMS]
@I_ReturnMessage NVARCHAR(MAX)='' OUTPUT,  --返回的信息,支持多语言
@ItemName NVARCHAR(50)='',                 --项目名称
--- 以上为标准字段-------------------------
@PickingListName NVARCHAR(50)=''--线边出库单
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

	--委外退货PickingList
	DECLARE @PickingListId CHAR(12)=''
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
		IF ISNULL(@PickingListName,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:[调用WMS] 线边出库单不能为空！';
			RETURN -1
		END

		--获取单据信息
		SELECT @PickingListId=PickingListId,
			   @BillStates=PickingListStates,
			   @BillClass=PickingListClass
		FROM dbo.PickingList
		WHERE PickingListName=@PickingListName


		IF ISNULL(@PickingListId,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:[调用WMS] 线边出库单【'+@PickingListName+'】不存在！'
			RETURN -1
		END

        --单据头，改为调用存货调整
		-- 创建源数据临时表，用于循环调用WMS托盘查询接口
		SELECT 
			   Product.ProductName AS ProductName,
			   Factory.FactoryName AS FactoryName,
			   wc.WorkcenterName AS WorkcenterName,
			   wri.ProductionLotNO AS ProductionLotNO,
			   wri.OrgLotSN AS OrgLotSN,
			   wri.LotSN AS LotSN,
			   -1 * QtyRequired AS  adjustQuantity, --正数增加库存，负数减少库存
               '杂发'  AS adjustReason,
               'MES杂发单：' + PickingList.PickingListName  AS  Remark
			   INTO #TempSource
		FROM dbo.PickingListItem
		LEFT JOIN dbo.PickingList ON PickingList.PickingListId = PickingListItem.PickingListId
		LEFT JOIN dbo.Product ON Product.ProductId = PickingListItem.ProductId
		LEFT JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
		INNER JOIN dbo.PickingListItemLot ON PickingListItem.PickingListItemId=PickingListItemLot.PickingListItemId
		left  JOIN dbo.WW_RMInventory AS wri ON wri.LotSN = PickingListItemLot.LotSN
        LEFT JOIN dbo.Workcenter wc ON wc.WorkcenterId = wri.WorkcenterId
		LEFT JOIN dbo.Factory ON Factory.FactoryId = wc.FactoryId
        LEFT JOIN CostCenter ON PickingListItem.CostCenterId = CostCenter.CostCenterId 
        LEFT JOIN ProductlineWH on ProductlineWH.warehouseid=wri.WorkcenterId
		WHERE PickingListItem.PickingListId=@PickingListId  AND PickingListItem.DeleteFlag=''

		-- 声明循环变量
		DECLARE @Src_ProductName NVARCHAR(50)=''
		DECLARE @Src_FactoryName NVARCHAR(50)=''
		DECLARE @Src_WorkcenterName NVARCHAR(50)=''
		DECLARE @Src_ProductionLotNO NVARCHAR(50)=''
		DECLARE @Src_OrgLotSN NVARCHAR(100)=''
		DECLARE @Src_LotSN NVARCHAR(100)=''
		DECLARE @Src_adjustQuantity DECIMAL(18,8)=0
		DECLARE @Src_adjustReason NVARCHAR(200)=''
		DECLARE @Src_Remark NVARCHAR(200)=''
		DECLARE @Src_licplateno NVARCHAR(100)=''
		DECLARE @Src_ReturnMessage NVARCHAR(MAX)=''
		DECLARE @Src_RC INT=0

		-- 创建目标临时表#Head
		CREATE TABLE #Head (
			licPlateNo NVARCHAR(100),
			adjustQuantity DECIMAL(18,8),
			adjustReason NVARCHAR(200),
			Remark NVARCHAR(200)
		)

		-- 游标循环遍历源数据，逐行调用APISyncU_WMSLSPRetrieve获取licPlateNo
		DECLARE cur_LSP CURSOR FOR
		SELECT ProductName, FactoryName, WorkcenterName, ProductionLotNO, OrgLotSN, LotSN, adjustQuantity, adjustReason, Remark
		FROM #TempSource

		OPEN cur_LSP
		FETCH NEXT FROM cur_LSP INTO @Src_ProductName, @Src_FactoryName, @Src_WorkcenterName, @Src_ProductionLotNO, @Src_OrgLotSN, @Src_LotSN, @Src_adjustQuantity, @Src_adjustReason, @Src_Remark

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @Src_licplateno=''
			SET @Src_ReturnMessage=''
			SET @Src_RC=0

			-- 当关键参数均不为空时，调用WMS托盘查询接口
			IF ISNULL(@Src_ProductName,'')<>'' AND ISNULL(@Src_FactoryName,'')<>'' AND ISNULL(@Src_WorkcenterName,'')<>'' AND ISNULL(@Src_ProductionLotNO,'')<>''
			BEGIN
				EXECUTE @Src_RC = [dbo].[APISyncU_WMSLSPRetrieve] 
				   @Src_ReturnMessage OUTPUT
				  ,N'U_WMSLSPRetrieve'
				  ,@Src_ProductName
				  ,@Src_FactoryName
				  ,@Src_WorkcenterName
				  ,@Src_ProductionLotNO
				  ,@Src_licplateno OUTPUT
			END

			-- 若接口返回为空，则使用默认批次号
			IF ISNULL(@Src_licplateno,'')=''
			BEGIN
				SET @Src_licplateno = ISNULL(@Src_OrgLotSN, @Src_LotSN)
			END

			-- 写入#Head
			INSERT INTO #Head (licPlateNo, adjustQuantity, adjustReason, Remark)
			VALUES (@Src_licplateno, @Src_adjustQuantity, @Src_adjustReason, @Src_Remark)

			FETCH NEXT FROM cur_LSP INTO @Src_ProductName, @Src_FactoryName, @Src_WorkcenterName, @Src_ProductionLotNO, @Src_OrgLotSN, @Src_LotSN, @Src_adjustQuantity, @Src_adjustReason, @Src_Remark
		END

		CLOSE cur_LSP
		DEALLOCATE cur_LSP

		--单据头
		-- SELECT PickingListName AS dlvNo
 		-- 	   INTO #Head
		-- FROM dbo.PickingList
		-- WHERE PickingListId=@PickingListId

		--单据明细
		-- SELECT 
		-- 	   ProductName AS materialCode,
		-- 	   QtyRequired AS quantity,
		-- 	   CASE WHEN ISNULL((SELECT t.IsLot FROM dbo.Test AS t ),0)='1' THEN wri.ProductionLotNO
		-- 		ELSE 'MES' END AS batchNo,
		-- 	   CostCenter.CostCenterName AS deptCode,--成本中心
		-- 	   ProductlineWH.WMSWarehouseCode AS WhCode,
        --        Factory.FactoryName + '.' +wc.WorkcenterName  AS dlvAddr,
        --        '' refName,
        --     --    0 refID,
        --        OrderName AS refNo,--订单号，用于同步SAP
        --        TRY_CONVERT(INT, PickingListItem.ItemSequence) AS refItemID,
        --        PickingListItem.PickingListItemId AS refItemKey,
        --        PickingList.PickingListDescription AS  remark
		-- 	   INTO #Item
		-- FROM dbo.PickingListItem
		-- LEFT JOIN dbo.PickingList ON PickingList.PickingListId = PickingListItem.PickingListId
		-- LEFT JOIN dbo.Product ON Product.ProductId = PickingListItem.ProductId
		-- LEFT JOIN dbo.ProductRoot ON ProductRoot.ProductRootId = Product.ProductRootId
		-- INNER JOIN dbo.PickingListItemLot ON PickingListItem.PickingListItemId=PickingListItemLot.PickingListItemId
		-- left  JOIN dbo.WW_RMInventory AS wri ON wri.LotSN = PickingListItemLot.LotSN
        -- LEFT JOIN dbo.Workcenter wc ON wc.WorkcenterId = wri.WorkcenterId
		-- LEFT JOIN dbo.Factory ON Factory.FactoryId = wc.FactoryId
        -- LEFT JOIN CostCenter ON PickingListItem.CostCenterId = CostCenter.CostCenterId 
        -- LEFT JOIN ProductlineWH on ProductlineWH.warehouseid=wri.WorkcenterId
		-- WHERE PickingListItem.PickingListId=@PickingListId  AND PickingListItem.DeleteFlag=''
	END 
	--**************end  2.获取要回传ERP的数据（要检查单据）  end*************************	
	IF NOT EXISTS (SELECT 1 FROM #Head)
	BEGIN
		SET @I_ReturnMessage='单据【'+@PickingListName+'】线边出库同步WMS失败！领料单据信息不存在，请确认！'
		RETURN -1
	END;
	-- IF NOT EXISTS (SELECT 1 FROM #Item)
	-- BEGIN
	-- 	SET @I_ReturnMessage='单据【'+@PickingListName+'】线边出库同步WMS失败！领料明细不存在，请确认！'
	-- 	RETURN -1
	-- END;

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
			SET @I_ReturnMessage='单据【'+@PickingListName+'】线边出库同步WMS失败！'+'WMS返回：'+@I_ReturnMessage
			--SET @E_TYPE='mes-1'
			RETURN -1
		END;

		--制作请求头
		DECLARE @RequestHeaders NVARCHAR(MAX) = N'Authorization<|=|>Bearer ' + @I_ReturnOAuth;


		-- Head（核心修改：去掉ROOT('Head') + 新增WITHOUT_ARRAY_WRAPPER + AUTO→PATH，平铺表头字段）
		-- SELECT @RequestData=(SELECT *
		-- FROM #Head FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER) -- 改动1：删ROOT('Head')、AUTO→PATH、加WITHOUT_ARRAY_WRAPPER
		-- Item（核心修改：路径从'$.Item'→'$.items'，匹配接口规范）
		-- SET @RequestData=JSON_MODIFY(@RequestData,
		-- 							 '$.items', -- 改动2：Item→items（小写+s，匹配DOItem[]规范）
		-- 							 (SELECT * FROM #Item FOR JSON AUTO,INCLUDE_NULL_VALUES)
		-- 							 )
        
        --只有列表
        SELECT @RequestData=(SELECT * FROM #Head FOR JSON AUTO,INCLUDE_NULL_VALUES)

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
		-- DROP TABLE #Item

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
				 'PickingListOther',
				 @PickingListId
			 )

		--调用接口前锁定
		UPDATE dbo.PickingList SET ToErpLock=1
		WHERE PickingListId=@PickingListId	
		
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
			SET @LogContent='单据【'+@PickingListName+'】过账失败!'+@Api_ReturnData
			SET @E_TYPE='mes-1'
		END 
		ELSE 
		BEGIN 
			--是否Json
			IF ISJSON(@Api_ReturnData)<=0
			BEGIN
				SET @LogContent='单据【'+@PickingListName+'】过账失败！接口返回的数据不是Json格式，请检查接口格式！WMS返回：'+@Api_ReturnData
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
					SET @LogContent='单据【'+@PickingListName+'】线边出库同步WMS失败！解析Json格式异常，异常信息：'+ERROR_MESSAGE() +'WMS返回：'+@Api_ReturnData
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
				SET @LogContent='单据【'+@PickingListName+'】线边出库同步WMS成功！'
			END
			ELSE
            BEGIN
				SET @LogContent='单据【'+@PickingListName+'】线边出库同步WMS失败！WMS返回结果：'+@E_MSG
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


		IF @E_TYPE='true' RETURN 0	
		ELSE RETURN -1     

	END 
	--**************end  3.回传ERP，获取接口返回的数据，并解析，更新MES单据    end*************************	

END

GO
