SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		
-- Create date: <2026.09.30>
-- Modify date: 
-- Description:	<成品工单半成品批次批量分配>
-- 批次预留批量修改：对账本次提交的选中批次 与 已存在的预分配记录
-- 约束：本次 XML 只能包含唯一一个 MOItemId(单物料行)，多个物料行直接判定异常
-- 处理方式：先将该物料行所有有效预分配记录全部逻辑删除(全部取消)，
--           再从本次选中批次按FIFO重新分配(全部走新增)
-- 数量校验：事务前先做预检(净需求 vs 选中批次可分配总量)，不足则整体失败，
--           不开启事务、不改动任何现有分配记录；事务尾再做兜底校验
-- 参考实现：MOSemiFinishedLotAllocationBatchDoMethod 的 AutoAssign 与 DeleteLot
-- Rev: 1.10
-- =============================================
CREATE PROCEDURE  [dbo].[MOLotSpecify_AssignReserveLot_DoMethod]
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
@I_Parameter NVARCHAR(MAX)='', 		--插件参数
--以上变量为系统服务固定接口参数，必须在每一个DoEvent过程中实现.
@MONames nvarchar(max) = ''
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	insert into mwjtestlog(src,log1,log2) VALUES('MOLotSpecify_AssignReserveLot_DoMethod',@I_Sender,@I_Parameter)

	DECLARE @xml NVARCHAR(MAX)=@I_Parameter --xml文本
	DECLARE @idoc INT --xml句柄
	DECLARE @xmlFileName NVARCHAR(100)='/NewDataSet/SQLDataSet' --解析路径

    DECLARE @CurrQty FLOAT=0

	--本次要保存的明细
	DECLARE @Temp TABLE(
		IsRowSelect bit,
		MOItemId CHAR(12),
		WWId    CHAR(12),
        Qty     float
	)

	BEGIN TRY
		--获取XML句柄
		EXEC sys.sp_xml_preparedocument @idoc OUTPUT, @xml

		--解析数据：openxml(idoc,rowpattern,flags)
		INSERT INTO @Temp
		(
			IsRowSelect,
		    MOItemId,
		    WWId,
            Qty
		)
		SELECT *
		FROM  OPENXML(@idoc,@xmlFileName,2)
		--与XML的列名一致
		WITH (
			IsRowSelect bit,
		    MOItemId CHAR(12),
		    WWId    CHAR(12),
            Qty     float
		)

		--释放句柄	
		EXEC sys.sp_xml_removedocument @idoc
	END TRY
	BEGIN CATCH
		SET @I_ReturnMessage='ServerMessage:数据解析失败，请联系IT人员！'+ERROR_MESSAGE()
		RETURN -1
	END CATCH

	IF NOT EXISTS(SELECT 1 FROM @Temp WHERE IsRowSelect=1)
	BEGIN
		SET @I_ReturnMessage='ServerMessage:没有选择生产批次！'
		RETURN -1
	END


	CREATE TABLE #MONameList (
		Seq int NOT NULL,				-- 输入顺序号
		MOName nvarchar(50) NOT NULL	-- 工单号
	)
    DECLARE @NameSeq int = 0

    IF @MONames IS NOT NULL AND @MONames <> ''
    BEGIN
        -- 去除所有空格、逗号、制表符、换行符、回车符
        SET @MONames = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@MONames, ' ', ''), ',', ''), CHAR(9), ''), CHAR(10), ''), CHAR(13), '');
        DECLARE @pos INT = 1, @len INT = LEN(@MONames), @segment NVARCHAR(50);
        WHILE @pos <= @len
            BEGIN
                SET @segment = SUBSTRING(@MONames, @pos, 10);
                IF LEN(@segment) = 10
                    SET @NameSeq = @NameSeq + 1
                    INSERT INTO #MONameList(Seq,MOName) VALUES (@NameSeq,@segment);
                SET @pos = @pos + 10;
            END
    END
    -- 【准备】#MOList：把工单号解析为有效工单 ID 清单，供各分支按输入顺序引用
	SELECT
		l.Seq,
		l.MOName,
		MIN(mo.MOId) AS MOId
	INTO #MOList
	FROM #MONameList l
	INNER JOIN dbo.MO mo ON mo.MOName = l.MOName
		AND mo.MOName LIKE '2%'
	GROUP BY l.Seq, l.MOName


	-- =========================================================
	-- 批次预留批量修改(单物料行)：先全部取消该物料所有有效预分配，
	-- 再从事务前预检验证数量足够(不足则整体失败、不改动数据)，通过后事务内按FIFO重新新增分配
	-- =========================================================
	DECLARE @SelMOItemId CHAR(12)               -- 当前处理的选中物料行ID
	DECLARE @SelMOId CHAR(12)                   -- 当前物料行所属工单ID
	DECLARE @SelMOName NVARCHAR(50)             -- 当前工单号快照
	DECLARE @SelProductId CHAR(12)              -- 当前物料ID
	DECLARE @SelUOMId CHAR(12)                  -- 当前物料单位ID
	DECLARE @SelRequiredQty DECIMAL(18,8)       -- 当前物料净需求
	DECLARE @SelAllocatedQty DECIMAL(18,8)      -- 当前物料已分配(保留)数量
	DECLARE @SelRemainQty DECIMAL(18,8)         -- 当前物料剩余需求
	DECLARE @SelAssignQty DECIMAL(18,8)         -- 单批次分配数量
	DECLARE @SelWWId CHAR(12)                   -- 当前批次库存记录ID
	DECLARE @SelLotSN NVARCHAR(100)             -- 当前批次号
	DECLARE @SelProductionLotNO VARCHAR(50)     -- 当前SAP/生产批次
	DECLARE @SelFactoryId CHAR(12)              -- 工厂ID
	DECLARE @SelWorkcenterId CHAR(12)           -- 仓库ID
	DECLARE @SelCellId CHAR(12)                 -- 储位ID
	DECLARE @SelAvailableQty DECIMAL(18,8)      -- 当前批次可用量
	DECLARE @SelNewId CHAR(12)                  -- 新增分配记录ID
	DECLARE @SelLotRowId INT                    -- 批次循环当前行号
	DECLARE @SelLotCount INT                    -- 批次循环行数

    CREATE TABLE #TempSelected (
		WWId    CHAR(12),
        MOItemId CHAR(12),
        Qty     float
	)

	-- 【准备】本次选中的期望批次集合
    IF (select sum(qty) from @Temp)>0
    BEGIN
        insert INTO #TempSelected SELECT WWId,MOItemId,Qty FROM @Temp WHERE Qty>0
    END
    ELSE
    BEGIN
        insert INTO #TempSelected SELECT WWId,MOItemId,Qty FROM @Temp WHERE IsRowSelect = 1
    END
	

	-- 【校验】选中批次必须唯一归属一个物料行(仅允许单个物料行操作)
	IF (SELECT COUNT(DISTINCT MOItemId) FROM #TempSelected) <> 1
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:选择工单明细异常！'
		RETURN -1
	END

	-- 【取值】取唯一物料行主键
	SELECT TOP 1 @SelMOItemId = MOItemId FROM #TempSelected

	-- 【取值+校验】取该物料行的工单/物料/净需求信息，并校验有效性
	SELECT
		@SelMOItemId = mi.MOItemId,
		@SelMOId = mo.MOId,
		@SelMOName = mo.MOName,
		@SelProductId = mi.ProductId,
		@SelUOMId = mi.UOMId,
		@SelRequiredQty = CONVERT(decimal(18, 8), ISNULL(mi.ItemQtyRequired, 0) - ISNULL(mi.ItemQtyIssued, 0) + ISNULL(mi.ItemQtyBack, 0))
	FROM dbo.MOItem mi
	INNER JOIN dbo.MO mo ON mo.MOId = mi.MOId
	INNER JOIN dbo.Product p ON p.ProductId = mi.ProductId
	WHERE mi.MOItemId = @SelMOItemId
		AND ISNULL(mi.DeleteFlag, '') = '0'
		AND mi.LineSequence <> '000'
		AND p.ProductClassify = '2'

	-- 【校验】物料行必须有效解析，否则直接失败
	IF ISNULL(@SelMOItemId, '') = ''
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:工单半成品物料行不存在或已失效，请检查！'
		RETURN -1
	END

	-- =========================================================
	-- 0️⃣ 数量预检（在事务前执行，不足则整体失败，不改动任何现有分配记录）
	--    可分配总量 = Σ 选中批次 [ 库存Qty - 该批次除本物料行外的有效占用 ]
	--    （本物料保留量已含在可分配量内，等价于前端“本行已分配 + 可分配”）
	--    过滤口径与下方FIFO分配完全一致，确保预检结果与最终分配一致
	-- =========================================================
    --人工指定数量的不需要检验，允许部分指定
    IF (select sum(Qty) from #TempSelected) =0 AND (
		SELECT SUM(CASE WHEN PreQty > 0 THEN PreQty ELSE 0 END)
		FROM (
			SELECT
				CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0)) - ISNULL(other.AllocOtherQty, 0) AS PreQty
			FROM dbo.WW_RMInventory wri
			INNER JOIN #TempSelected ts ON ts.WWId = wri.WWId
			CROSS APPLY (
				-- 该批次上除本物料行以外的有效占用数量
				SELECT SUM(ISNULL(a.Qty, 0)) AS AllocOtherQty
				FROM dbo.MOSemiFinishedLotAllocation a
				WHERE a.WWId = wri.WWId
					AND a.DeleteFlag = '0'
					AND a.IsOccupyAllocatedQty = 1
                    AND (a.ConfirmStatus = '1' OR (a.ConfirmStatus = '0' AND a.MOId IN (SELECT MOId FROM #MOList)))
					AND a.MOItemId <> @SelMOItemId
			) other
			WHERE wri.ProductId = @SelProductId
				AND wri.LotStatus = '1'
				AND wri.IsStorage = 1
				AND ISNULL(wri.Qty, 0) > 0
				AND ISNULL(wri.LotSN, '') <> ''
				-- 库存表同一LotSN多行记录视为异常，不参与判定
				AND (
					SELECT COUNT(1)
					FROM dbo.WW_RMInventory wriCnt
					WHERE wriCnt.LotSN = wri.LotSN
				) = 1
		) t
	) < @SelRequiredQty
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage:预留批次数量不足，无法完成分配！'
		RETURN -1
	END

	-- 【事务】开启对账事务，保证取消/累加/新增整体原子性
	BEGIN TRANSACTION ResvLotReconcile

	-- =========================================================
	-- ① 全部取消：将该物料行所有有效预分配记录全部逻辑删除，
	--    释放的占用量回流到批次可用量，随后从选中批次重新分配
	-- =========================================================
	UPDATE dbo.MOSemiFinishedLotAllocation
	SET DeleteFlag = '1',
		ModifyDate = GETDATE(),
        IsOccupyAllocatedQty = 0,
        ConfirmStatus = '0' 
	WHERE MOItemId = @SelMOItemId
		AND DeleteFlag = '0'
		AND IsOccupyAllocatedQty = 1

	-- 【计算】取消后该物料当前已分配数量(保留的有效占用)
	SELECT @SelAllocatedQty = CONVERT(decimal(18, 8), ISNULL(SUM(ISNULL(Qty, 0)), 0))
	FROM dbo.MOSemiFinishedLotAllocation
	WHERE MOItemId = @SelMOItemId
		AND DeleteFlag = '0'
		AND IsOccupyAllocatedQty = 1
        AND (ConfirmStatus = '1' OR (ConfirmStatus = '0' AND MOId IN (SELECT MOId FROM #MOList)))

	SET @SelRemainQty = @SelRequiredQty - ISNULL(@SelAllocatedQty, 0)

	-- ② 该物料分配数量已足够时不再分配(预检已保证可配满，仅当仍有剩余需求时才分配)
	IF ISNULL(@SelRemainQty, 0) > 0
	BEGIN
		-- 【准备】选中批次FIFO清单(按生产日期→入库日期→批次号)
		-- 可用量=库存-该批次全部有效占用，实时反映事务内已累加/新增的占用
		-- HasAlloc/AllocId 用于区分累加或新增
		SELECT
			ROW_NUMBER() OVER (
				ORDER BY
					ISNULL(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(wri.ProductionDate)), '')), '99991231'),
					wri.EntryDate,
					wri.LotSN
			) AS RowId,
			wri.WWId,
			wri.LotSN,
			wri.ProductionLotNO,
			wri.FactoryId,
			wri.WorkcenterId,
			wri.CellId,
			CONVERT(decimal(18, 8), ISNULL(wri.Qty, 0) - ISNULL(alloc.AllocatedQty, 0)) AS AvailableQty
		INTO #CurLots
		FROM dbo.WW_RMInventory wri
		INNER JOIN #TempSelected ts ON ts.WWId = wri.WWId
		LEFT JOIN (
			-- 该批次被其他工单物料占用的有效数量(本物料已全部取消，不计入)
			SELECT WWId, SUM(ISNULL(Qty, 0)) AS AllocatedQty
			FROM dbo.MOSemiFinishedLotAllocation
			WHERE DeleteFlag = '0'
				AND IsOccupyAllocatedQty = 1
                AND (ConfirmStatus = '1' OR (ConfirmStatus = '0' AND MOId IN (SELECT MOId FROM #MOList)))
				AND ISNULL(LotSN, '') <> ''
			GROUP BY WWId
		) alloc ON alloc.WWId = wri.WWId
		WHERE wri.ProductId = @SelProductId
			-- 只取正常在库、数量>0、批次号非空的批次
			AND wri.LotStatus = '1'
			AND wri.IsStorage = 1
			AND ISNULL(wri.Qty, 0) > 0
			AND ISNULL(wri.LotSN, '') <> ''
			-- 库存表同一LotSN多行记录视为异常，不参与分配
			AND (
				SELECT COUNT(1)
				FROM dbo.WW_RMInventory wriCnt
				WHERE wriCnt.LotSN = wri.LotSN
			) = 1
		ORDER BY wri.EntryDate, wri.LotSN

		SELECT @SelLotCount = COUNT(1) FROM #CurLots
		SET @SelLotRowId = 1

		-- ④ 逐批FIFO分配(全部取消后重新分配)：全部走新增记录
		WHILE @SelLotRowId <= @SelLotCount AND ISNULL(@SelRemainQty, 0) > 0
		BEGIN
			SELECT
				@SelWWId = WWId,
				@SelLotSN = LotSN,
				@SelProductionLotNO = ProductionLotNO,
				@SelFactoryId = FactoryId,
				@SelWorkcenterId = WorkcenterId,
				@SelCellId = CellId,
				@SelAvailableQty = AvailableQty
			FROM #CurLots
			WHERE RowId = @SelLotRowId

			SET @SelLotRowId = @SelLotRowId + 1
            
            --检查指定数量是否足够
            SET @CurrQty=0
            select @CurrQty=qty from #TempSelected t where t.WWId=@SelWWId
            IF @CurrQty>@SelAvailableQty
            BEGIN
                ROLLBACK TRANSACTION ResvLotReconcile
				SET @I_ReturnMessage = 'ServerMessage:指定数量大于可用数量，分配失败!'
				RETURN -1
            END

            -- ② 可用量为0的批次不分配
			IF ISNULL(@SelAvailableQty, 0) <= 0
				CONTINUE

			SET @SelAssignQty = CASE
                WHEN @CurrQty>0  THEN @CurrQty
				WHEN @SelRemainQty < @SelAvailableQty THEN @SelRemainQty
				ELSE @SelAvailableQty
			END

			IF ISNULL(@SelAssignQty, 0) <= 0
				CONTINUE

			-- ④ 全部取消后重新分配：生成主键并新增分配记录
			EXEC dbo.SysGetObjectPKId '', 'MOSemiFinishedLotAllocation', @SelNewId OUTPUT

			IF ISNULL(@SelNewId, '') = ''
			BEGIN
				ROLLBACK TRANSACTION ResvLotReconcile
				SET @I_ReturnMessage = 'ServerMessage:生成分配记录失败!'
				RETURN -1
			END

			INSERT INTO dbo.MOSemiFinishedLotAllocation (
				MOSemiFinishedLotAllocationId,
				MOId,
				MOName,
				MOItemId,
				ProductId,
				WWId,
				LotSN,
				ProductionLotNO,
				FactoryId,
				WorkcenterId,
				CellId,
				UOMId,
				Qty,
				IsOccupyAllocatedQty,
                ConfirmStatus,
				DeleteFlag,
				CreateUserId,
				CreateUserName,
				CreateDate,
				ModifyDate
			)
			VALUES (
				@SelNewId,
				@SelMOId,
				@SelMOName,
				@SelMOItemId,
				@SelProductId,
				@SelWWId,
				@SelLotSN,
				@SelProductionLotNO,
				@SelFactoryId,
				@SelWorkcenterId,
				@SelCellId,
				@SelUOMId,
				@SelAssignQty,
				1,
                '0',
				'0',
				@I_OrBitUserId,
				@I_OrBitUserName,
				GETDATE(),
				GETDATE()
			)

			IF @@ROWCOUNT = 0
			BEGIN
				ROLLBACK TRANSACTION ResvLotReconcile
				SET @I_ReturnMessage = 'ServerMessage:生成分配记录失败!'
				RETURN -1
			END

			SET @SelRemainQty = @SelRemainQty - @SelAssignQty
		END

		IF OBJECT_ID('tempdb..#CurLots') IS NOT NULL
			DROP TABLE #CurLots
	END



	-- =========================================================
	-- 【兜底】分配后再次校验该物料最终分配总量是否足够净需求
	--    正常情况下事务前预检已保证数量充足；此兜底用于应对
	--    并发改动/口径差异等异常场景，避免提交不完整分配
	-- =========================================================
	SELECT @SelAllocatedQty = CONVERT(decimal(18, 8), ISNULL(SUM(ISNULL(Qty, 0)), 0))
	FROM dbo.MOSemiFinishedLotAllocation
	WHERE MOItemId = @SelMOItemId
		AND DeleteFlag = '0'
		AND IsOccupyAllocatedQty = 1
        AND (ConfirmStatus = '1' OR (ConfirmStatus = '0' AND MOId IN (SELECT MOId FROM #MOList)))

	IF ISNULL(@SelAllocatedQty, 0) < ISNULL(@SelRequiredQty, 0) AND (select sum(Qty) from #TempSelected) =0
	BEGIN
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION ResvLotReconcile
		SET @I_ReturnMessage = 'ServerMessage:分配数量异常，无法完成分配！'
		RETURN -1
	END
    ELSE IF ISNULL(@SelAllocatedQty, 0) > ISNULL(@SelRequiredQty, 0)
    BEGIN
        IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION ResvLotReconcile
		SET @I_ReturnMessage = 'ServerMessage:分配数量超出需求数量，无法完成分配！'
		RETURN -1
    END

    IF OBJECT_ID('tempdb..#TempSelected') IS NOT NULL
	DROP TABLE #TempSelected

	-- 【提交】数量校验通过(预检+兜底)，取消/累加/新增整体生效
	COMMIT TRANSACTION ResvLotReconcile

	SET @I_ReturnMessage='ServerMessage:工单物料预留批次成功!'

	RETURN 0

END
GO
