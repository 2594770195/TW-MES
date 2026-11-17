SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OBit Team HK0313>
-- Create date: <2021.08.02>
-- Description:	<工单配方调整>
-- Rev: 10.00
-- =============================================
CREATE PROCEDURE  [dbo].[Txn_MOItemQtyRequiredEdit]
@I_Sender nvarchar(200)='', --客户端执行按钮
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_ExceptionFieldName nvarchar(100)='' output, --向客户端报告引起冲突的字段
@I_LanguageId char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)='',			--用户ID
@I_OrBitUserName nvarchar(100)='',	--用户名
@I_ResourceId	char(12)='',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)='',	--资源名
@I_PKId char(12) = '',				--主键
@I_SourcePKId char(12)='',			--执行拷贝时传入的源主键  
@I_ParentPKId char(12)='',			--父级主键
@I_Parameter nvarchar(100)='',		--插件参数	

@Operator VARCHAR(32) = '',--当前扫描员工号
@LotSN LotSN = '',--当前扫描批号
@ROperator VARCHAR(32) = '',--为防止误操作传入的已扫员工号
@RLotSN LotSN = '',--为防止误操作传入的已扫批号
@ProductId IDType='',
@AdjustmentRemark NVARCHAR(200)='',
@AddItemQty SysNumberType=0,
@ProductLine CHAR(5)='',
@QProductDescription NVARCHAR(100)=''

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
		
	DECLARE @LoadingItemLotId IDType
	DECLARE @IsComplete BIT=0
	DECLARE @LoadingItemLotDetailId IDType
	DECLARE @MOId IDType
	DECLARE @MOName VARCHAR(32)

	--求和项统计
	DECLARE @TotalItemQtyRequired SysNumberType
	DECLARE @TotalOrgItemQtyRequired SysNumberType
	DECLARE @TotalItemQtyIncrement SysNumberType

	DECLARE @LotProductDescription NVARCHAR(100)

	DECLARE @SpecificationId IDType
	DECLARE @WorkflowId CHAR(12)
	DECLARE @SpecificationCode VARCHAR(16)

	IF @I_Sender='PageLoad'
	BEGIN
		SELECT @Operator=EmployeeNo FROM SysUser WHERE UserId=@I_OrBitUserId
		SET @I_ExceptionFieldName='LotSN'
				
		--获取待调单列表
		SELECT ROW_NUMBER() OVER(ORDER BY A.CreateDate) AS RN,A.LotSN,A.Qty,C.MOName,C.MOQtyRequired,D.ProductDescription,C.AdjustmentRemark FROM MOItemLot A
		INNER JOIN MOItem B ON A.MOItemId=B.MOItemId
		INNER JOIN MO C ON B.MOId=C.MOId
		INNER JOIN Product D ON B.ProductId=D.ProductId 
		INNER JOIN Lot E ON A.LotSN=E.LotSN
		INNER JOIN Specification F ON E.SpecificationId=F.SpecificationId
		INNER JOIN SpecificationRoot G ON F.SpecificationRootId=G.SpecificationRootId
		WHERE C.IsAdjustment=1 AND D.ProductClassify='2' AND C.MOStates='20' 
		AND ISNULL(C.DeleteFlag,'') IN('','0') AND ISNULL(A.DeleteFlag,'') IN('','0') AND ISNULL(B.DeleteFlag,'') IN('','0')
		AND E.WorkflowId NOT IN('WKF1000000Z2','WKF1000000YW','WKF1000000YS')
		AND ((E.WorkflowId IN('WKF1000000YT','WKF1000000YV') AND G.SpecificationCode IN('DPQC','IPQC','FNINKJ')) OR E.WorkflowId NOT IN('WKF1000000YT','WKF1000000YV'))

		SELECT @Operator AS Operator
		SET @I_ReturnMessage='ServerMessage:请扫描批号条码.'
		RETURN 0
	END

	IF @I_Sender='QueryMO'
	BEGIN
		--获取待调单列表
		SELECT ROW_NUMBER() OVER(ORDER BY A.CreateDate) AS RN,A.LotSN,A.Qty,C.MOName,C.MOQtyRequired,D.ProductDescription,C.AdjustmentRemark FROM MOItemLot A
		INNER JOIN MOItem B ON A.MOItemId=B.MOItemId
		INNER JOIN MO C ON B.MOId=C.MOId
		INNER JOIN Product D ON B.ProductId=D.ProductId 
		INNER JOIN Lot E ON A.LotSN=E.LotSN
		INNER JOIN Specification F ON E.SpecificationId=F.SpecificationId
		INNER JOIN SpecificationRoot G ON F.SpecificationRootId=G.SpecificationRootId
		WHERE C.IsAdjustment=1 AND D.ProductClassify='2' AND C.MOStates='20' 
		AND ISNULL(C.DeleteFlag,'') IN('','0') AND ISNULL(A.DeleteFlag,'') IN('','0') AND ISNULL(B.DeleteFlag,'') IN('','0')
		AND (ISNULL(@ProductLine,'')='' OR C.ProductLine=@ProductLine)
		AND (ISNULL(@QProductDescription,'')='' OR D.ProductDescription LIKE '%'+@QProductDescription+'%')
		AND E.WorkflowId NOT IN('WKF1000000Z2','WKF1000000YW','WKF1000000YS')
		AND ((E.WorkflowId IN('WKF1000000YT','WKF1000000YV') AND G.SpecificationCode IN('DPQC','IPQC','FNINKJ')) OR E.WorkflowId NOT IN('WKF1000000YT','WKF1000000YV'))

		RETURN 0
	END

	IF @I_Sender='SaveAdjustmentRemark'
	BEGIN
		IF EXISTS(SELECT 1 FROM Lot WHERE LotSN=@RLotSN)
		BEGIN
			SELECT @MOId=MOId FROM Lot WHERE LotSN=@RLotSN
			UPDATE MO SET AdjustmentRemark=@AdjustmentRemark WHERE MOId=@MOId

			SELECT ROW_NUMBER() OVER(ORDER BY A.CreateDate) AS RN,A.LotSN,A.Qty,C.MOName,C.MOQtyRequired,D.ProductDescription,C.AdjustmentRemark FROM MOItemLot A
			INNER JOIN MOItem B ON A.MOItemId=B.MOItemId
			INNER JOIN MO C ON B.MOId=C.MOId
			INNER JOIN Product D ON B.ProductId=D.ProductId 
			WHERE C.IsAdjustment=1 AND D.ProductClassify='2' AND C.MOStates='20' 
			AND ISNULL(C.DeleteFlag,'') IN('','0') AND ISNULL(A.DeleteFlag,'') IN('','0') AND ISNULL(B.DeleteFlag,'') IN('','0')


			SELECT @Operator AS Operator,@RLotSN AS RLotSN,@LotSN AS LotSN,@ROperator AS ROperator,@AdjustmentRemark AS AdjustmentRemark
			SET @I_ReturnMessage='ServerMessage:保存成功.'
			RETURN 0
		END
		ELSE
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请先扫描批号.'
			RETURN -1
		END
	END


	IF @I_Sender IN('GetMOItemList','QueryAdjustmentMO')
	BEGIN
		SET @I_ExceptionFieldName='LotSN'
		
		--判断工单是否是已下达状态
		SELECT @SpecificationCode=SR.SpecificationCode,@MOId=L.MOId,@ProductId=L.ProductId,@WorkflowId=L.WorkflowId FROM Lot L INNER JOIN Specification S ON L.SpecificationId=S.SpecificationId
		INNER JOIN SpecificationRoot SR ON S.SpecificationRootId=SR.SpecificationRootId
		WHERE L.LotSN=@LotSN AND L.LotStatus='1'
		IF ISNULL(@MOId,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:工单批号['+@LotSN+']未启动或不存在'
			RETURN -1
		END

		IF @I_Sender='GetMOItemList'
		BEGIN
			--判断员工工号
			IF NOT EXISTS(SELECT 1 FROM SysUser WHERE EmployeeNo=@Operator AND IsActivity=1)
			BEGIN
				SET @I_ReturnMessage='ServerMessage:员工工号['+@Operator+']不存在.'
				RETURN -1
			END

			IF NOT EXISTS(SELECT 1 FROM MO WHERE MOId=@MOId AND MOStates='20')
			BEGIN
				SET @I_ReturnMessage='ServerMessage:工单当前不是已下达状态，不允许调整用量.'
				RETURN -1
			END

			--IF @WorkflowId IN('WKF1000000YT','WKF1000000YV') AND @SpecificationCode NOT IN ('DPQC','IPQC','FNINKJ')
			--BEGIN
			--	SET @I_ReturnMessage='ServerMessage:当前未到更改配方节点，不允许调单'
			--	RETURN -1
			--END

			----判断是否已经开始生产跳单
			--IF EXISTS(SELECT 1 FROM LoadingItemLot WHERE MOId=@MOId AND IsComplete=0)
			--BEGIN
			--	SET @I_ReturnMessage='ServerMessage:工单正在生产上料，不允许调整用量.'
			--	RETURN -1
			--END

			SELECT @MOName=MOName FROM MO WHERE MOId=@MOId

			--重新从SAP抓取工单信息
			EXEC [dbo].[RefreshMOForSAPDoMethod]
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_LanguageId=@I_LanguageId,
				@I_PlugInCommand=@I_PlugInCommand,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_OrBitUserName=@I_OrBitUserName,
				@I_ResourceId=@I_ResourceId,
				@I_ResourceName=@I_ResourceName,
				@I_PKid=@I_PKid,
				@I_ParentPKId=@I_ParentPKId,
				@I_Parameter=@I_Parameter,
				@MOName=@MOName,
				@SOName=''

			SELECT @LotProductDescription=ProductDescription FROM Product WHERE ProductId=@ProductId

			IF NOT EXISTS(SELECT 1 FROM MOItemAdjustment A INNER JOIN MOItem B ON A.MOItemId=B.MOItemId WHERE B.MOId=@MOId)
			BEGIN
				IF EXISTS(SELECT 1 FROM MOItem WHERE MOId=@MOId AND OrgItemQtyRequired IS NULL)
				BEGIN
					UPDATE MOItem SET OrgItemQtyRequired=ItemQtyRequired WHERE MOId=@MOId AND OrgItemQtyRequired IS NULL
				END
			END

			SELECT @AdjustmentRemark=AdjustmentRemark FROM MO WHERE MOId=@MOId
		END
		

		SELECT TOP 1 @LoadingItemLotId=LoadingItemLotId,@IsComplete=IsComplete FROM LoadingItemLot WHERE MOId=@MOId AND IsComplete=1 ORDER BY CompleteDate DESC

		SELECT @TotalOrgItemQtyRequired=SUM(MOI.OrgItemQtyRequired),@TotalItemQtyRequired=SUM(MOI.ItemQtyRequired),@TotalItemQtyIncrement=SUM((MOI.ItemQtyRequired-ISNULL(LD.ItemQtyRequired,0))) FROM MOItem MOI
		LEFT JOIN LoadingItemLotDetail LD ON MOI.MOItemId=LD.MOItemId AND LD.LoadingItemLotId=@LoadingItemLotId
		WHERE MOI.MOId=@MOId AND MOI.LineSequence<>'000' AND ISNULL(MOI.DeleteFlag,'') IN('','0')

		--查询工单配方
		SELECT MOI.MOItemId,MOI.LineSequence,MOI.ProductId,PR.ProductName,P.ProductDescription,MOI.OrgItemQtyRequired AS OrgBOMQty,MOI.ItemQtyRequired AS BOMQty,
		(MOI.ItemQtyRequired-ISNULL(LD.ItemQtyRequired,0)) AS ItemQtyIncrement,
		MOA.C1,MOA.C2,MOA.C3,MOA.C4,MOA.C5,MOA.C6,MOA.C7,MOA.C8,MOA.C9 FROM MOItem MOI
		INNER JOIN Product P ON MOI.ProductId=P.ProductId
		INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
		LEFT JOIN LoadingItemLotDetail LD ON MOI.MOItemId=LD.MOItemId AND LD.LoadingItemLotId=@LoadingItemLotId
		LEFT JOIN (SELECT MOItemId,SUM(CASE WHEN AdjustmentNumber=1 THEN AddItemQty ELSE 0 END) AS C1
		,SUM(CASE WHEN AdjustmentNumber=2 THEN AddItemQty ELSE 0 END) AS C2
		,SUM(CASE WHEN AdjustmentNumber=3 THEN AddItemQty ELSE 0 END) AS C3
		,SUM(CASE WHEN AdjustmentNumber=4 THEN AddItemQty ELSE 0 END) AS C4
		,SUM(CASE WHEN AdjustmentNumber=5 THEN AddItemQty ELSE 0 END) AS C5
		,SUM(CASE WHEN AdjustmentNumber=6 THEN AddItemQty ELSE 0 END) AS C6
		,SUM(CASE WHEN AdjustmentNumber=7 THEN AddItemQty ELSE 0 END) AS C7
		,SUM(CASE WHEN AdjustmentNumber=8 THEN AddItemQty ELSE 0 END) AS C8
		,SUM(CASE WHEN AdjustmentNumber=9 THEN AddItemQty ELSE 0 END) AS C9 FROM 
		(SELECT MOItemId,(NewItemQtyRequired-OldItemQtyRequired) AS AddItemQty,AdjustmentNumber FROM MOItemAdjustment)
		 AS Adjustment GROUP BY MOItemId) MOA ON MOI.MOItemId=MOA.MOItemId
		WHERE MOI.MOId=@MOId AND CAST(MOI.LineSequence AS INT)<>0 AND ISNULL(MOI.DeleteFlag,'') IN('','0')
		UNION ALL 
		SELECT '' AS MOItemId,'' AS LineSequence,'' AS ProductId,'' AS ProductName,'总计' AS ProductDescription,@TotalOrgItemQtyRequired AS OrgBOMQty,
		@TotalItemQtyRequired AS BOMQty,@TotalItemQtyIncrement AS ItemQtyIncrement,NULL AS C1,NULL AS C2,NULL AS C3,NULL AS C4,NULL AS C5,NULL AS C6,NULL AS C7,NULL AS C8,NULL AS C9
		
		SELECT @Operator AS ROperator,@LotSN AS RLotSN,@AdjustmentRemark AS AdjustmentRemark,@LotProductDescription AS LotProductDescription
		RETURN 0
	END

	IF @I_Sender='SaveMOItem'
	BEGIN
		IF ISNULL(@ROperator,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请先扫描人员工号.'
			RETURN -1
		END
		IF ISNULL(@RLotSN,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请先扫描批号.'
			RETURN -1
		END

		IF ISNULL(@ProductId,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请选择产品.'
			RETURN -1
		END

		DECLARE @MOItemId IDType
		DECLARE @MAXLineSequence CHAR(3)
		DECLARE @LineSequence CHAR(3)
		DECLARE @ParentProductId IDType
		DECLARE @ParentMOItemId IDType
		DECLARE @UOMId IDType
		DECLARE @RequiredAdjustment NVARCHAR(256)
		DECLARE @MOItemQtyRequired SysNumberType
		DECLARE @MOItemAdjustmentId IDType
		DECLARE @AdjustmentNumber INT=0
		DECLARE @NewItemNumber INT=0
        DECLARE @LogMOName VARCHAR(32)
        DECLARE @LogProductDescription NVARCHAR(100)
        DECLARE @LogChangeType NVARCHAR(5)
        DECLARE @LogOldQty SysNumberType
        DECLARE @LogNewQty SysNumberType

		SELECT @SpecificationCode=SR.SpecificationCode,@SpecificationId=L.SpecificationId,@MOId=L.MOId,@WorkflowId=L.WorkflowId FROM Lot L INNER JOIN Specification S ON L.SpecificationId=S.SpecificationId
		INNER JOIN SpecificationRoot SR ON S.SpecificationRootId=SR.SpecificationRootId
		WHERE L.LotSN=@RLotSN AND L.LotStatus='1'
		--判断工单是否是已下达状态
		--SELECT @MOId=MOId FROM Lot WHERE LotSN=@LOTSN

		SELECT @AdjustmentNumber=ISNULL(AdjustmentNumber,1) FROM MO WHERE MOId=@MOId

        -- 流水所需基础信息
        SELECT @LogMOName=MOName FROM MO WHERE MOId=@MOId
        SELECT @LogProductDescription=ProductDescription FROM Product WHERE ProductId=@ProductId

        IF NOT EXISTS(SELECT 1 FROM MO WHERE MOId=@MOId AND MOStates='20')
		BEGIN
			SET @I_ReturnMessage='ServerMessage:工单当前不是已下达状态，不允许调整用量.'
			RETURN -1
		END

		--IF @WorkflowId IN('WKF1000000YT','WKF1000000YV') AND @SpecificationCode NOT IN ('DPQC','IPQC','FNINKJ')
		--BEGIN
		--	SET @I_ReturnMessage='ServerMessage:当前未到更改配方节点，不允许调单'
		--	RETURN -1
		--END
		--判断是否已经开始生产
		SELECT TOP 1 @LoadingItemLotId=LoadingItemLotId,@IsComplete=IsComplete FROM LoadingItemLot WHERE MOId=@MOId ORDER BY CreateDate DESC
		--IF ISNULL(@LoadingItemLotId,'')<>''
		--BEGIN
		--	--判断是否正在生产中，正在生产中不允许调整
		--	IF ISNULL(@IsComplete,0)=0
		--	BEGIN
		--		SET @I_ReturnMessage='ServerMessage:工单正在生产上料，不允许调整用量.'
		--		RETURN -1
		--	END
		--END
		IF ISNULL(@AddItemQty,0)=0
		BEGIN
			SET @I_ReturnMessage='ServerMessage:调整数量不能为零.'
			RETURN -1
		END
		
		--检查添加项是否已添加
		SELECT @LineSequence=LineSequence,@MOItemId=MOItemId,@RequiredAdjustment=RequiredAdjustment,@MOItemQtyRequired=ItemQtyRequired FROM MOItem WHERE MOId=@MOId AND ProductId=@ProductId AND ISNULL(DeleteFlag,'') IN('','0') AND LineSequence<>'000'
		IF ISNULL(@MOItemId,'')<>''
		BEGIN
			IF @MOItemQtyRequired+@AddItemQty<0
			BEGIN
				SET @I_ReturnMessage='ServerMessage:工单物料用量不能小于零.'
				RETURN -1
			END

			IF @LineSequence='000'
			BEGIN
				SET @I_ReturnMessage='ServerMessage:工单成品需求不可修改.'
				RETURN -1
			END
			--未生产时才可减少工单用量
			--IF EXISTS(SELECT 1 FROM LoadingItemLotDetail WHERE LoadingItemLotId=@LoadingItemLotId AND MOItemId=@MOItemId AND ActualQty>@AddItemQty+@MOItemQtyRequired)
			--BEGIN
			--	SET @I_ReturnMessage='ServerMessage:工单已经开始了上料，无法再减少工单用量.'
			--	RETURN -1
			--END

			IF ISNULL(@RequiredAdjustment,'')<>''
				SET @RequiredAdjustment=@RequiredAdjustment+' --> '+CAST(@AddItemQty AS VARCHAR(19))
			ELSE
				SET @RequiredAdjustment=CAST(@MOItemQtyRequired AS VARCHAR(19))+' --> '+CAST(@AddItemQty AS VARCHAR(19))

			IF EXISTS(SELECT 1 FROM [dbo].[MOItemAdjustment] WHERE MOItemId=@MOItemId AND ISNULL(AdjustmentNumber,1)=@AdjustmentNumber)
			BEGIN
				UPDATE [dbo].[MOItemAdjustment] SET NewItemQtyRequired=@MOItemQtyRequired+@AddItemQty WHERE MOItemId=@MOItemId AND ISNULL(AdjustmentNumber,1)=@AdjustmentNumber
			END
			ELSE
			BEGIN
				--SELECT @AdjustmentNumber=COUNT(1) FROM MOItemAdjustment WHERE MOItemId=@MOItemId
				--SET @AdjustmentNumber+=1
				EXEC SysGetObjectPKId '','MOItemAdjustment',@MOItemAdjustmentId OUTPUT
				INSERT INTO [dbo].[MOItemAdjustment]
						   ([MOItemAdjustmentId]
						   ,[MOItemId]
						   ,[OldItemQtyRequired]
						   ,[NewItemQtyRequired]
						   ,[Operator]
						   ,[LotSN]
						   ,[SpecificationId]
						   ,[AdjustmentNumber])
					 VALUES
						   (@MOItemAdjustmentId
						   ,@MOItemId
						   ,@MOItemQtyRequired
						   ,@MOItemQtyRequired+@AddItemQty
						   ,@ROperator
						   ,@RLotSN
						   ,@SpecificationId
						   ,@AdjustmentNumber)
			END

			

			IF @MOItemQtyRequired+@AddItemQty<=0
			BEGIN
				UPDATE MOItem SET RequiredAdjustment=@RequiredAdjustment,ItemQtyRequired=@MOItemQtyRequired+@AddItemQty,DeleteFlag='1'
				 WHERE MOItemId=@MOItemId

				EXEC dbo.MOChangeDoMethod @I_ReturnMessage = @I_ReturnMessage OUTPUT,          
                                @MOItemID = @MOItemId,
                                @ChangeType = N'D'   --工单修改类型I（增加），U（更改），D（删除）

				IF @LoadingItemLotId<>''
				BEGIN
					DELETE FROM LoadingItemLotDetail WHERE LoadingItemLotId=@LoadingItemLotId AND MOItemId=@MOItemId
				END
                -- 流水：删除物料
                SET @LogChangeType='D'
                SET @LogOldQty=@MOItemQtyRequired
                SET @LogNewQty=0

			END
			ELSE
			BEGIN
				UPDATE MOItem SET RequiredAdjustment=@RequiredAdjustment,ItemQtyRequired=@MOItemQtyRequired+@AddItemQty
				 WHERE MOItemId=@MOItemId

				EXEC dbo.MOChangeDoMethod @I_ReturnMessage = @I_ReturnMessage OUTPUT,          
                                @MOItemID = @MOItemId,
                                @ChangeType = N'U'   --工单修改类型I（增加），U（更改），D（删除）
			END
            -- 流水：调整已有物料
            -- 流水：调整已有物料
            SET @LogChangeType='U'
            SET @LogOldQty=@MOItemQtyRequired
            SET @LogNewQty=@MOItemQtyRequired+@AddItemQty
			 
		END
		ELSE
		BEGIN
			IF @AddItemQty<0
			BEGIN
				SET @I_ReturnMessage='ServerMessage:工单物料用量不能小于零.'
				RETURN -1
			END

			IF NOT EXISTS(SELECT 1 FROM TZProduct WHERE ProductId=@ProductId)
			BEGIN
				SELECT @LotProductDescription=ProductDescription FROM Product WHERE ProductId=@ProductId
				SET @I_ReturnMessage='ServerMessage:所添加产品['+@LotProductDescription+']未在已上线产品清单中，无法添加.'
				RETURN -1
			END
			--生成行号
			--SELECT @NewItemNumber=COUNT(1) FROM MOItem WHERE MOId=@MOId AND LEFT(LineSequence,1)='9'
			--SET @LineSequence=CAST((901+@NewItemNumber) AS CHAR(3))

			SELECT @MAXLineSequence=MAX(LineSequence) FROM MOItem WHERE MOId=@MOId AND LEFT(LineSequence,1)<>'9'
			SET @LineSequence=SUBSTRING('000',0,4-LEN(CAST((CAST(@MAXLineSequence AS INT)+10) AS CHAR(3))))+CAST((CAST(@MAXLineSequence AS INT)+10) AS CHAR(3))
		
			SELECT @ParentProductId=ProductId FROM MO WHERE MOId=@MOID

			SELECT @ParentMOItemId=MOItemId FROM MOItem WHERE MOId=@MOId AND ProductId=@ParentProductId

			SELECT @UOMId=UsageUOMId FROM Product WHERE ProductId=@ProductId

			SET @RequiredAdjustment='0 --> '+CAST(@AddItemQty AS VARCHAR(19))
			--添加工单明细
			EXEC SysGetObjectPKId '','MOItem',@MOItemId OUTPUT
			INSERT INTO [dbo].[MOItem]
					   ([MOItemId]
					   ,[MOId]
					   ,[LineSequence]
					   ,[ProductId]
					   ,[ParentProductId]
					   ,[ParentMOItemId]
					   ,[OrgItemQtyRequired]
					   ,[ItemQtyRequired]
					   ,[ItemQtyIssued]
					   ,[ItemQtyBack]
					   ,[ItemQtyDone]
					   ,[UOMId]
					   ,[BOMLevel]
					   ,[BOMItemId]
					   ,[BOMQtyRequired]
					   ,[ParentBOMId]
					   ,[RequiredAdjustment]
					   ,[IsNewItem])
				 VALUES
					   (@MOItemId
					   ,@MOId
					   ,@LineSequence
					   ,@ProductId
					   ,@ParentProductId
					   ,@ParentMOItemId
					   ,0
					   ,@AddItemQty
					   ,0
					   ,0
					   ,0
					   ,@UOMId
					   ,0
					   ,''
					   ,0
					   ,''
					   ,@RequiredAdjustment
					   ,1)

				EXEC SysGetObjectPKId '','MOItemAdjustment',@MOItemAdjustmentId OUTPUT
				INSERT INTO [dbo].[MOItemAdjustment]
						   ([MOItemAdjustmentId]
						   ,[MOItemId]
						   ,[OldItemQtyRequired]
						   ,[NewItemQtyRequired]
						   ,[Operator]
						   ,[LotSN]
						   ,[SpecificationId]
						   ,[AdjustmentNumber])
					 VALUES
						   (@MOItemAdjustmentId
						   ,@MOItemId
						   ,0
						   ,@AddItemQty
						   ,@ROperator
						   ,@RLotSN
						   ,@SpecificationId
						   ,@AdjustmentNumber)

			IF ISNULL(@LoadingItemLotId,'')<>''
			BEGIN
				EXEC SysGetObjectPKId '','LoadingItemLotDetail',@LoadingItemLotDetailId OUTPUT
				INSERT INTO [dbo].[LoadingItemLotDetail]
						   ([LoadingItemLotDetailId]
						   ,[LoadingItemLotId]
						   ,[MOItemId]
						   ,[ItemQtyRequired]
						   ,[ActualQty]
						   ,[LastMakingDate])
					 VALUES
						   (@LoadingItemLotDetailId
						   ,@LoadingItemLotId
						   ,@MOItemId
						   ,0
						   ,0
						   ,getdate())
			END

			EXEC dbo.MOChangeDoMethod @I_ReturnMessage = @I_ReturnMessage OUTPUT,          
                                @MOItemID = @MOItemId,
                                @ChangeType = N'I'   --工单修改类型I（增加），U（更改），D（删除）

            -- 流水：新增物料
            SET @LogChangeType='I'
            SET @LogOldQty=0
            SET @LogNewQty=@AddItemQty
		END

        -- =====================================  调单流水（每次保存一条）  =====================================
        IF ISNULL(@LogChangeType,'')<>''
            BEGIN
                INSERT INTO [dbo].[MOItemAdjustmentLog]
                ([MOItemId]
                ,[MOId]
                ,[MOName]
                ,[ProductId]
                ,[ProductDescription]
                ,[LotSN]
                ,[AdjustmentNumber]
                ,[ChangeType]
                ,[OldQty]
                ,[AddQty]
                ,[NewQty]
                ,[IsNewItem]
                ,[Operator])
                VALUES
                    (@MOItemId
                    ,@MOId
                    ,@LogMOName
                    ,@ProductId
                    ,@LogProductDescription
                    ,@RLotSN
                    ,@AdjustmentNumber
                    ,@LogChangeType
                    ,@LogOldQty
                    ,@AddItemQty
                    ,@LogNewQty
                    ,CASE WHEN @LogChangeType='I' THEN 1 ELSE 0 END
                    ,@ROperator)
            END
        -- =====================================  调单流水 END  =====================================

        --如果正在投料过程中，则及时更改当前要求投料物料
		IF ISNULL(@LoadingItemLotId,'')<>'' AND @IsComplete=0
		BEGIN
			DECLARE @WaterProductId CHAR(12)
			DECLARE @DiluentProductId CHAR(12)
			SELECT @WaterProductId=P.ProductId FROM ProductRoot PR INNER JOIN Product P ON PR.ProductRootId=P.ProductRootId WHERE PR.ProductName='9999999999'
			SELECT @DiluentProductId=P.ProductId FROM ProductRoot PR INNER JOIN Product P ON PR.ProductRootId=P.ProductRootId WHERE PR.ProductName='1023450105'

			SET @MOItemId=''

			--重新设定当前要求投料物料
			SELECT TOP 1 @MOItemId=A.MOItemId FROM LoadingItemLotDetail L
			INNER JOIN MOItem A ON L.MOItemId=A.MOItemId
			WHERE L.LoadingItemLotId=@LoadingItemLotId
			AND ISNULL(A.DeleteFlag,'') IN('','0') AND L.ActualQty=0
			AND A.ProductId IN (@WaterProductId,@DiluentProductId) 

			IF ISNULL(@MOItemId,'')=''
			BEGIN
				SELECT TOP 1 @MOItemId=A.MOItemId FROM LoadingItemLotDetail L
				INNER JOIN MOItem A ON L.MOItemId=A.MOItemId
				WHERE L.LoadingItemLotId=@LoadingItemLotId
				AND ISNULL(A.DeleteFlag,'') IN('','0') AND A.ItemQtyRequired>L.ActualQty
				AND A.ProductId NOT IN (@WaterProductId,@DiluentProductId) 
				ORDER BY A.LineSequence
			END

			IF ISNULL(@MOItemId,'')=''
			BEGIN
				SELECT TOP 1 @MOItemId=A.MOItemId FROM LoadingItemLotDetail L
				INNER JOIN MOItem A ON L.MOItemId=A.MOItemId
				WHERE L.LoadingItemLotId=@LoadingItemLotId
				AND ISNULL(A.DeleteFlag,'') IN('','0') AND L.ActualQty<A.ItemQtyRequired
				AND A.ProductId IN (@WaterProductId,@DiluentProductId) 
			END
				
			UPDATE LoadingItemLot SET MOItemId=@MOItemId WHERE LoadingItemLotId=@LoadingItemLotId
		END

		--重新从SAP抓取工单信息
			EXEC [dbo].[RefreshMOForSAPDoMethod]
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_LanguageId=@I_LanguageId,
				@I_PlugInCommand=@I_PlugInCommand,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_OrBitUserName=@I_OrBitUserName,
				@I_ResourceId=@I_ResourceId,
				@I_ResourceName=@I_ResourceName,
				@I_PKid=@I_PKid,
				@I_ParentPKId=@I_ParentPKId,
				@I_Parameter=@I_Parameter,
				@MOName=@MOName,
				@SOName=''

		SET @I_ReturnMessage='ServerMessage:工单项已调整.'
		
		SELECT @TotalOrgItemQtyRequired=SUM(MOI.OrgItemQtyRequired),@TotalItemQtyRequired=SUM(MOI.ItemQtyRequired),@TotalItemQtyIncrement=SUM((MOI.ItemQtyRequired-ISNULL(LD.ItemQtyRequired,0))) FROM MOItem MOI
		LEFT JOIN LoadingItemLotDetail LD ON MOI.MOItemId=LD.MOItemId AND LD.LoadingItemLotId=@LoadingItemLotId
		WHERE MOI.MOId=@MOId AND MOI.LineSequence<>'000' AND ISNULL(MOI.DeleteFlag,'') IN('','0')

		UPDATE MOItem SET ItemQtyRequired=@TotalItemQtyRequired WHERE MOId=@MOId AND LineSequence='000'

		--查询工单配方
		SELECT MOI.MOItemId,MOI.LineSequence,MOI.ProductId,PR.ProductName,P.ProductDescription,MOI.OrgItemQtyRequired AS OrgBOMQty,MOI.ItemQtyRequired AS BOMQty,
		(MOI.ItemQtyRequired-ISNULL(LD.ItemQtyRequired,0)) AS ItemQtyIncrement,
		MOA.C1,MOA.C2,MOA.C3,MOA.C4,MOA.C5,MOA.C6,MOA.C7,MOA.C8,MOA.C9 FROM MOItem MOI
		INNER JOIN Product P ON MOI.ProductId=P.ProductId
		INNER JOIN ProductRoot PR ON P.ProductRootId=PR.ProductRootId
		LEFT JOIN LoadingItemLotDetail LD ON MOI.MOItemId=LD.MOItemId AND LD.LoadingItemLotId=@LoadingItemLotId
		LEFT JOIN (SELECT MOItemId,SUM(CASE WHEN AdjustmentNumber=1 THEN AddItemQty ELSE 0 END) AS C1
		,SUM(CASE WHEN AdjustmentNumber=2 THEN AddItemQty ELSE 0 END) AS C2
		,SUM(CASE WHEN AdjustmentNumber=3 THEN AddItemQty ELSE 0 END) AS C3
		,SUM(CASE WHEN AdjustmentNumber=4 THEN AddItemQty ELSE 0 END) AS C4
		,SUM(CASE WHEN AdjustmentNumber=5 THEN AddItemQty ELSE 0 END) AS C5
		,SUM(CASE WHEN AdjustmentNumber=6 THEN AddItemQty ELSE 0 END) AS C6
		,SUM(CASE WHEN AdjustmentNumber=7 THEN AddItemQty ELSE 0 END) AS C7
		,SUM(CASE WHEN AdjustmentNumber=8 THEN AddItemQty ELSE 0 END) AS C8
		,SUM(CASE WHEN AdjustmentNumber=9 THEN AddItemQty ELSE 0 END) AS C9 FROM 
		(SELECT MOItemId,(NewItemQtyRequired-OldItemQtyRequired) AS AddItemQty,AdjustmentNumber FROM MOItemAdjustment)
		 AS Adjustment GROUP BY MOItemId) MOA ON MOI.MOItemId=MOA.MOItemId
		WHERE MOI.MOId=@MOId AND CAST(MOI.LineSequence AS INT)<>0 AND ISNULL(MOI.DeleteFlag,'') IN('','0')
		UNION ALL 
		SELECT '' AS MOItemId,'' AS LineSequence,'' AS ProductId,'' AS ProductName,'总计' AS ProductDescription,@TotalOrgItemQtyRequired AS OrgBOMQty,
		@TotalItemQtyRequired AS BOMQty,@TotalItemQtyIncrement AS ItemQtyIncrement,NULL AS C1,NULL AS C2,NULL AS C3,NULL AS C4,NULL AS C5,NULL AS C6,NULL AS C7,NULL AS C8,NULL AS C9
		
		--返回页面数据
		SELECT @ProductId AS ProductId,0 AS AddItemQty
	END

	IF @I_Sender='AdjustmentComplete'
	BEGIN
		IF ISNULL(@RLotSN,'')=''
		BEGIN
			SET @I_ReturnMessage='ServerMessage:请先扫描批号.'
			RETURN -1
		END
		IF NOT EXISTS(SELECT 1 FROM Lot WHERE LotSN=@RLotSN)
		BEGIN
			SET @I_ReturnMessage='ServerMessage:工单批号['+@RLotSN+']不存在.'
			RETURN -1
		END

		SELECT @SpecificationCode=SR.SpecificationCode,@MOId=L.MOId,@WorkflowId=L.WorkflowId FROM Lot L INNER JOIN Specification S ON L.SpecificationId=S.SpecificationId
		INNER JOIN SpecificationRoot SR ON S.SpecificationRootId=SR.SpecificationRootId
		WHERE L.LotSN=@RLotSN AND L.LotStatus='1'

		IF NOT EXISTS(SELECT 1 FROM MO WHERE MOId=@MOId AND IsAdjustment=1)
		BEGIN
			SET @I_ReturnMessage='ServerMessage:调单已完成，请勿重复点击.'
			RETURN -1
		END

		IF @WorkflowId IN('WKF1000000YT','WKF1000000YV') AND @SpecificationCode NOT IN ('DPQC','IPQC','FNINKJ')
		BEGIN
			SET @I_ReturnMessage='ServerMessage:当前未到更改配方节点，不需要点击调单完成'
			RETURN -1
		END

		--调单完成，进行工序移送
		DECLARE @QC_ProcessInsId IDType
		-- 获取批号获取送检单数据
		SELECT
			TOP 1 @QC_ProcessInsId = dbo.QC_ProcessIns_SubLot.QC_ProcessInsId
		FROM 
			QC_ProcessIns_SubLot
			INNER JOIN dbo.QC_ProcessIns ON QC_ProcessIns.QC_ProcessInsId = QC_ProcessIns_SubLot.QC_ProcessInsId
		WHERE 
			QC_ProcessIns_SubLot.LotSN = @RLotSN
		AND QC_ProcessIns.InsStates = '20' AND QC_ProcessIns.SubmissCategory='IPQC'
		ORDER BY QC_ProcessIns.ConfirmDate DESC

		--较之前是否有调整
		--SELECT TOP 1 @LoadingItemLotId=LoadingItemLotId FROM LoadingItemLot WHERE MOId=@MOId AND ISNULL(MOItemId,'')='' ORDER BY CompleteDate DESC
		----先判定有没有调整工单增量，如果没有，提示调整
		--IF ISNULL(@LoadingItemLotId,'')<>'' AND NOT EXISTS(SELECT 1 FROM LoadingItemLotDetail L INNER JOIN MOItem M ON L.MOItemId=M.MOItemId WHERE L.LoadingItemLotId=@LoadingItemLotId AND L.ItemQtyRequired<>M.ItemQtyRequired)
		--BEGIN
		--	SET @I_ReturnMessage='ServerMessage:工单较之前没有调整，请调整工单用量后继续操作.'
		--	RETURN -1
		--END

		--SELECT @SpecificationCode=SR.SpecificationCode FROM Lot L INNER JOIN Specification S ON L.SpecificationId=S.SpecificationId
		--INNER JOIN SpecificationRoot SR ON S.SpecificationRootId=SR.SpecificationRootId
		--WHERE L.LotSN=@RLotSN

		IF ISNULL(@QC_ProcessInsId,'')<>''
		BEGIN
			select ROW_NUMBER() OVER(ORDER BY QCP.LotSN) AS ROWKEY,QCP.LotId,QCP.LotSN,L.MOId,L.ProductId,L.WorkcenterId,L.SpecificationId,L.WorkflowStepId INTO #TEMP from QC_ProcessIns_SubLot QCP
			inner join Lot L ON QCP.LotId=L.LotId where QCP.QC_ProcessInsId=@QC_ProcessInsId AND (@SpecificationCode IN('IPQC') OR QCP.LotSN=@RLotSN)

			DECLARE @ROWNUMBER INT=0
			DECLARE @ROWKEY INT=1
			DECLARE @LotId IDType
			DECLARE @WorkcenterId IDType
		
			DECLARE @WorkflowStepId IDType
			DECLARE @CurDate DATETIME=GETDATE()

			SELECT @ROWNUMBER=COUNT(1) FROM #TEMP

			WHILE @ROWKEY<=@ROWNUMBER
			BEGIN
				SELECT 
					@LotId=LotId,
					@ProductId=ProductId,
					@WorkcenterId=WorkcenterId,
					@SpecificationId=SpecificationId,
					@WorkflowStepId=WorkflowStepId,
					@LotSN=LotSN
				FROM #TEMP WHERE ROWKEY=@ROWKEY

				--移送到下一道工序
				EXEC [dbo].[TxnBase_LotMove] 
				@I_ReturnMessage=@I_ReturnMessage OUTPUT,
				@I_OrBitUserId=@I_OrBitUserId,
				@I_ResourceId=@I_ResourceId,
				@LotSN=@LotSN,
				@LotInDate=@CurDate	

				SET @ROWKEY+=1
			END
		END
		ELSE IF @SpecificationCode IN('DPQC','FNINKJ','BGPF') --Irving 2024/12/20 添加变更配方节点 'BGPF' 用户水性、活性 调单
		BEGIN
			--移送到下一道工序
			EXEC [dbo].[TxnBase_LotMove] 
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@I_OrBitUserId=@I_OrBitUserId,
			@I_ResourceId=@I_ResourceId,
			@LotSN=@RLotSN,
			@LotInDate=@CurDate	
		END

		--停止调单
		UPDATE MO SET IsAdjustment=0 WHERE MOId=@MOId

-- =====================================       发送调单信息到DCS          ========================================== -----

        DECLARE @AdjustmentNumberDCS INT=0
		SELECT @MOId=MOId FROM Lot WHERE LotSN=@RLotSN
		SELECT @MoName = MOName from mo where moid=@MOId
		select @AdjustmentNumberDCS = adjustmentNumber from mo where mo.MOName = @MoName
        -- 判断当前操作有没有进行调单
		IF EXISTS(
		   select * from MOItemAdjustment
           LEFT JOIN MOItem ON MOItemAdjustment.MOItemId = MOItem.MOItemId
           LEFT JOIN MO ON MoItem.MOId = MO.MOId
		   INNER JOIN ZR_DCS_ORDER ON MO.MOId = ZR_DCS_ORDER.MOId
           where mo.MOName = @MoName
           and MO.AdjustmentNumber = @AdjustmentNumberDCS

        )
		BEGIN
            --第一步 发送调单的物料信息
            --组装格式
            DECLARE @jsonObj nvarchar(max);
            DECLARE @instanceRootId nvarchar(255); --程序头id
            DECLARE @moid_dcs nvarchar(max);
            DECLARE @RESULT_DCS_INFO nvarchar(max);

            --获取MOId
            select @moid_dcs=moid from mo where mo.MOName = @MoName

            --获取程序头id
            select @instanceRootId=dcsProcedureId from ZR_DCS_ORDER where MOId=@moid_dcs

            -- 调试用：查看ZR_DCS_INSTANCE表数据（按需保留）
    --         SELECT * FROM ZR_DCS_INSTANCE WHERE moName = @MoName

            -- 核心逻辑：生成JSON并直接赋值给@jsonObj（移除所有ZR_DCS_INSTANCE_INFO关联）
            SET @jsonObj = (
                SELECT
                    @instanceRootId AS instanceRootId,
                    -- 核心：JSON_QUERY包裹instanceParams内层JSON，避免外层转义为字符串
                    JSON_QUERY((
                        SELECT
                            -- 固定替换：instanceId使用@instanceRootId（移除ZR_DCS_INSTANCE_INFO关联）
                            @instanceRootId AS instanceId,
                            -- JSON_QUERY包裹targetValues，避免转义
                            JSON_QUERY((
                                SELECT
                                    -- 拼接BU_01/BU_02，强制转NVARCHAR避免拼接报错
                                    N'BU_0' + CAST(ROW_NUMBER() OVER (ORDER BY mia.CreateDate) AS NVARCHAR(10)) AS [param.name],
                                    5 AS [param.dataType], -- 固定替换：dataType改为固定值5
                                    CAST(1 AS BIT) AS [param.isEditable], -- 固定输出true
                                    -- 生成runtimeValue的JSON字符串（带转义符）
                                    (
                                        SELECT
                                            N'0' AS actualWeight,
                                            JSON_QUERY(N'{"xx":"0"}') AS additionalFields, -- 避免内部转义
                                            N'' AS batch,
                                            p.TProductName AS code,
                                            N' ' AS equipment,
                                            -- 计算差值并转字符串（匹配示例格式）
                                            CAST((mia.NewItemQtyRequired - mia.OldItemQtyRequired) AS NVARCHAR(20)) AS expectedWeight,
                                            ISNULL(p.ProductDescription, N'') AS name, -- 空值兜底
                                            N'' AS package,
                                            N'0' AS skipCheck
                                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER -- 生成单个JSON对象
                                    ) AS runtimeValue,
                                    @instanceRootId AS instanceId -- 固定替换：instanceId使用@instanceRootId
                                FROM (
                                    -- 子查询：取目标MO单的最新调单数据（最大AdjustmentNumber）
                                    SELECT
                                        mia.*,
                                        mi.ProductId
                                    FROM MOItemAdjustment mia
                                    LEFT JOIN MOItem mi ON mia.MOItemId = mi.MOItemId
                                    LEFT JOIN MO ON mi.MOId = MO.MOId
                                    WHERE MO.MOId = @moid_dcs
                                      AND mia.AdjustmentNumber = (
                                          SELECT MAX(mia2.AdjustmentNumber)
                                          FROM MOItemAdjustment mia2
                                          LEFT JOIN MOItem mi2 ON mia2.MOItemId = mi2.MOItemId
                                          LEFT JOIN MO ON mi2.MOId = MO.MOId
                                          WHERE MO.MOId = @moid_dcs
                                      )
                                ) mia
                                -- 关联Product表取产品描述（保留业务必要关联）
                                LEFT JOIN Product p ON mia.ProductId = p.ProductId
                                ORDER BY mia.CreateDate -- 固定排序，保证BU_01/BU_02顺序
                                FOR JSON PATH -- 生成targetValues数组
                            )) AS targetValues
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER -- 生成instanceParams单个对象
                    )) AS instanceParams
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
            );

             EXEC @RESULT_DCS_INFO=[dbo].[MESUpdateDCSDoMethod]
                    @I_Sender=@I_Sender,
                    @I_ReturnMessage=@I_ReturnMessage output, --返回的信息,支持多语言
                    @I_ExceptionFieldName=@I_ExceptionFieldName output, --向客户端报告引起冲突的字段
                    @I_LanguageId=@I_LanguageId, --客户端传入的语言ID
                    @I_PlugInCommand=@I_PlugInCommand, --插件命令
                    @I_OrBitUserId=@I_OrBitUserId, --用户ID
                    @I_OrBitUserName=@I_OrBitUserName, --用户名
                    @I_ResourceId=@I_ResourceId, --资源ID(如果资源不在资源清单中，那么它将是空的)
                    @I_ResourceName=@I_ResourceName, --资源名
                    @I_PKid=@I_PKid, --主键
                    @I_ParentPKId=@I_ParentPKId,
                    @I_Parameter=@I_Parameter,
                    @jsonObj=@jsonObj
            -- 调试用：打印生成的JSON（按需保留）
            -- SELECT @jsonObj AS GeneratedJson;

            --第二步 发送需要调单的信号

            -- ===================== 新增：延迟2秒 =====================
                WAITFOR DELAY '00:00:01'; -- 格式：时:分:秒，精准延迟2秒，不阻塞其他会话
            -- ========================================================

            DECLARE @jsonObj_Signal nvarchar(max); -- 调单信号JSON变量（与第一步区分）

            -- 核心：生成调单信号JSON，动态取instanceId和dataType
            SET @jsonObj_Signal = (
                SELECT
                    @instanceRootId AS instanceRootId,
                    -- instanceParams输出为单个对象（WITHOUT_ARRAY_WRAPPER）
                    JSON_QUERY((
                        SELECT
                            @instanceRootId AS instanceId, -- instanceParams下的instanceId
                            -- targetValues保留数组格式，内部字段严格匹配目标结构
                            JSON_QUERY((
                                SELECT
                                    -- param嵌套对象：仅包含name/dataType/isEditable
                                    N'BACK_QA' AS [param.name],
                                    3 AS [param.dataType],
                                    CAST(1 AS BIT) AS [param.isEditable], -- 生成true布尔值
                                    -- runtimeValue为字符串"1"（目标格式要求）
                                    N'1' AS runtimeValue,
                                    -- targetValues数组项内的instanceId
                                    @instanceRootId AS instanceId
                                FOR JSON PATH -- 保留数组格式
                            )) AS targetValues
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER -- 关键：instanceParams是单个对象，非数组
                    )) AS instanceParams
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
            );

            -- 调试用：打印调单信号JSON（按需保留）
            -- SELECT @jsonObj_Signal AS Signal_GeneratedJson;

            -- 调用DCS接口发送调单信号（复用第一步的接口存储过程）
            DECLARE @RESULT_DCS_SIGNAL nvarchar(max);
            EXEC @RESULT_DCS_SIGNAL=[dbo].[MESUpdateDCSDoMethod]
                @I_Sender=@I_Sender,
                @I_ReturnMessage=@I_ReturnMessage output,
                @I_ExceptionFieldName=@I_ExceptionFieldName output,
                @I_LanguageId=@I_LanguageId,
                @I_PlugInCommand=@I_PlugInCommand,
                @I_OrBitUserId=@I_OrBitUserId,
                @I_OrBitUserName=@I_OrBitUserName,
                @I_ResourceId=@I_ResourceId,
                @I_ResourceName=@I_ResourceName,
                @I_PKid=@I_PKid,
                @I_ParentPKId=@I_ParentPKId,
                @I_Parameter=@I_Parameter,
                @jsonObj=@jsonObj_Signal; -- 传入调单信号JSON
        END



-- =====================================       发送调单信息到DCS          ========================================== -----

		SET @I_ReturnMessage='ServerMessage:工单调整已完成提交.'
	END


	IF @I_Sender='QueryAdjustmentDetail'
	BEGIN
		SELECT B.LineSequence,C.TProductName AS ProductName,C.ProductDescription,A.OldItemQtyRequired,A.NewItemQtyRequired,
		A.AdjustmentNumber,A.Operator,D.UserDescription,CONVERT(varchar, A.CreateDate, 120 ) AS AdjustmentTime FROM MOItemAdjustment A
		INNER JOIN MOItem B ON A.MOItemId=B.MOItemId
		INNER JOIN Product C ON B.ProductId=C.ProductId
		INNER JOIN SysUser D ON A.Operator=D.UserName
		WHERE A.LotSN=@LotSN
		ORDER BY A.CreateDate
		RETURN 0
	END

	return 0
	
	
END
GO
