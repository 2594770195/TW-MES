SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<OrBit Team>
-- Create date: <2026-11-17>
-- Description:	成品工单半成品理货 SAP 同步（按工单号列表循环调用）
--               1) 传入工单号列表 @MONames，解析为工单清单后逐单处理；
--               2) 仅处理存在未同步记录（ConfirmStatus='1' AND SAPSyncFlag='0'）的 MO，
--                  跳过无未同步记录的工单；
--               3) 每个工单生成一条 UploadIng 上传记录（UploadDateId=MOId、BillsMark=MOName），
--                  调用 dbo.RfcSAPSync 上传 SAP 接口 U_MOSemiFinishedLotSpecify；
--               4) 接口返回成功时，将该工单全部待同步记录置 SAPSyncFlag='1'（已同步），
--                  失败保持 '0'，等待下次调用补偿；
--               5) 逐工单独立处理，单个工单失败不影响其他工单，结果汇总到 @I_ReturnMessage。
-- 调用示例：
--   DECLARE @Msg NVARCHAR(MAX)=''
--   EXEC dbo.APISyncU_MOSemiFinishedLotSpecifyByMONames
--        @MONames = N'2000018575,2000018576',
--        @I_ReturnMessage = @Msg OUTPUT
-- =============================================
CREATE PROCEDURE [dbo].[APISyncU_MOSemiFinishedLotSpecifyByMONames]
@MONames NVARCHAR(MAX) = '',                     -- 工单号列表，逗号/分号/空格/换行分隔，单个工单号固定 10 位
@I_ReturnMessage NVARCHAR(MAX) = '' OUTPUT,      -- 返回的信息，支持多语言，汇总各工单同步结果
@I_ExceptionFieldName NVARCHAR(100) = '' OUTPUT, -- 向客户端报告引起冲突的字段
@I_OrBitUserId CHAR(12) = '',                    -- 用户 ID
@I_OrBitUserName NVARCHAR(100) = ''              -- 用户名
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

	-- 初始化输出参数
	SET @I_ReturnMessage = ''

	-- 【准备】变量声明（首次声明时备注用途）
	DECLARE @InterfaceItemId NVARCHAR(20) = ''      -- 接口项 ID，对应 dbo.InterfaceItem.ItemName='U_MOSemiFinishedLotSpecify'
	DECLARE @UploadIngId NVARCHAR(20) = ''          -- 上传记录 ID，每次上传生成一条 dbo.UploadIng
	DECLARE @CurSeq INT = 1                         -- 循环当前顺序号
	DECLARE @CurMOId NVARCHAR(20) = ''              -- 当前工单 ID
	DECLARE @CurMOName NVARCHAR(50) = ''            -- 当前工单号
	DECLARE @CurPendingCount INT = 0                -- 当前工单待同步记录数
	DECLARE @API_ReturnMessage NVARCHAR(MAX) = ''   -- RfcSAPSync 接口返回信息
	DECLARE @SuccessList NVARCHAR(MAX) = ''         -- 同步成功的工单号清单
	DECLARE @FailList NVARCHAR(MAX) = ''            -- 同步失败的工单号清单
	DECLARE @SkipList NVARCHAR(MAX) = ''            -- 无未同步记录被跳过的工单号清单
	DECLARE @InvalidList NVARCHAR(MAX) = ''         -- 解析不到有效工单的工单号清单
	DECLARE @SyncCount INT = 0                      -- 本次实际调用 SAP 的工单数

	-- 【校验】工单号列表不能为空
	IF ISNULL(@MONames, '') = ''
	BEGIN
		SET @I_ReturnMessage = N'ServerMessage:[工单号列表]不能为空!'
		RETURN -1
	END

	-- 【准备】#MONameList：把 @MONames 按分隔符解析为工单号清单（与批量分配主流程解析方式一致）
	-- 存放解析结果(去空格、去空段、去重)，供后续循环同步使用
	CREATE TABLE #MONameList (
		Seq int NOT NULL,				-- 输入顺序号
		MOName nvarchar(50) NOT NULL	-- 工单号
	)

	DECLARE @NameSeq INT = 0						-- 已解析的工单号计数器
	DECLARE @pos INT = 1, @len INT = 0				-- 字符串切分位置与总长度
	DECLARE @segment NVARCHAR(50)					-- 当前切分出的工单号

	-- 去除所有空格、逗号、分号、制表符、换行符、回车符
	SET @MONames = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@MONames, ' ', ''), ',', ''), ';', ''), CHAR(9), ''), CHAR(10), ''), CHAR(13), '')
	SET @len = LEN(@MONames)
	WHILE @pos <= @len
	BEGIN
		SET @segment = SUBSTRING(@MONames, @pos, 10)
		IF LEN(@segment) = 10
		BEGIN
			SET @NameSeq = @NameSeq + 1
			-- 同一工单号只保留首次出现的顺序，避免重复同步
			IF NOT EXISTS (SELECT 1 FROM #MONameList WHERE MOName = @segment)
				INSERT INTO #MONameList (Seq, MOName) VALUES (@NameSeq, @segment)
		END
		SET @pos = @pos + 10
	END

	-- 【校验】解析后无有效工单号时直接返回
	IF NOT EXISTS (SELECT 1 FROM #MONameList)
	BEGIN
		SET @I_ReturnMessage = N'ServerMessage:[工单号列表]未解析到有效工单号，请检查输入格式!'
		RETURN -1
	END

	-- 【校验】接口项必须已配置（dbo.InterfaceItem.ItemName='U_MOSemiFinishedLotSpecify'）
	SELECT @InterfaceItemId = InterfaceItemId
	FROM dbo.InterfaceItem
	WHERE ItemName = 'U_MOSemiFinishedLotSpecify'

	IF ISNULL(@InterfaceItemId, '') = ''
	BEGIN
		SET @I_ReturnMessage = N'ServerMessage:[接口项][U_MOSemiFinishedLotSpecify]未配置，请联系IT维护接口定义!'
		RETURN -1
	END

	-- 【准备】#SyncMOList：解析工单号对应的工单 ID，并统计各工单待同步记录数
	-- 待同步口径：ConfirmStatus='1'（已确认）AND SAPSyncFlag='0'（未同步），含已取消(DeleteFlag='1')与已扣数的记录
	IF OBJECT_ID('tempdb..#SyncMOList') IS NOT NULL
		DROP TABLE #SyncMOList
	SELECT
		l.Seq,
		l.MOName,
		MIN(mo.MOId) AS MOId,
		ISNULL((
			SELECT COUNT(1)
			FROM dbo.MOSemiFinishedLotAllocation a
			WHERE a.MOId = MIN(mo.MOId)
				AND a.ConfirmStatus = '1'
				AND a.SAPSyncFlag = '0'
		), 0) AS PendingCount
	INTO #SyncMOList
	FROM #MONameList l
	INNER JOIN dbo.MO mo ON mo.MOName = l.MOName
	GROUP BY l.Seq, l.MOName

	-- 【收集】解析不到有效工单的工单号，仅提示不阻断其他工单同步
	SELECT @InvalidList = ISNULL(@InvalidList + ',', '') + l.MOName
	FROM #MONameList l
	WHERE NOT EXISTS (SELECT 1 FROM #SyncMOList m WHERE m.MOName = l.MOName)

	-- 【校验】传入工单全部无效时直接返回
	IF NOT EXISTS (SELECT 1 FROM #SyncMOList)
	BEGIN
		SET @I_ReturnMessage = N'ServerMessage:[工单号][' + ISNULL(@InvalidList, '') + ']不存在，请检查!'
		RETURN -1
	END

	-- =============================================
	-- 【循环】逐工单同步：只处理存在未同步记录(PendingCount>0)的工单
	-- =============================================
	SELECT @CurSeq = MIN(Seq) FROM #SyncMOList

	WHILE @CurSeq IS NOT NULL
	BEGIN
		-- 【初始化】清空当前工单变量，避免读取不到行时沿用上一轮值
		SET @CurMOId = ''
		SET @CurMOName = ''
		SET @CurPendingCount = 0
		SET @API_ReturnMessage = ''

		SELECT
			@CurMOId = MOId,
			@CurMOName = MOName,
			@CurPendingCount = PendingCount
		FROM #SyncMOList
		WHERE Seq = @CurSeq

		SET @CurSeq = @CurSeq + 1

		-- 【跳过】无未同步记录的工单不做调用，仅记录提示
		IF ISNULL(@CurPendingCount, 0) = 0
		BEGIN
			SET @SkipList = ISNULL(@SkipList + ',', '') + @CurMOName
			CONTINUE
		End

		-- 【写入】生成上传记录：UploadDateId 存 MOId、BillsMark 存工单号，与现有 SAP 上传模式一致
		SET @UploadIngId = ''
		EXEC dbo.SysGetObjectPKId '', 'UploadIng', @UploadIngId OUTPUT

		INSERT INTO dbo.UploadIng
		(
			UploadIngId,
			UploadInterfaceId,
			UploadDateId,
			ISUpload,
			UserId,
			BillsMark,
			MatDoc,
			CreateDate
		)
		VALUES
		(	@UploadIngId,          -- UploadIngId - char(12)
			@InterfaceItemId,      -- UploadInterfaceId - char(12)
			@CurMOId,              -- UploadDateId - char(12)：工单 ID
			'true',                -- ISUpload - bit
			@I_OrBitUserId,        -- UserId - char(12)
			@CurMOName,            -- BillsMark - nvarchar(50)：工单号
			N'',                   -- MatDoc - nvarchar(50)
			GETDATE()              -- CreateDate - datetime
		)

		-- 【调用】上传 SAP：接口 U_MOSemiFinishedLotSpecify，按 UploadIngId 定位上传数据
		EXEC dbo.RfcSAPSync @I_ReturnMessage = @API_ReturnMessage OUTPUT,
			@ItemName = N'U_MOSemiFinishedLotSpecify',
			@UploadIngId = @UploadIngId

		SET @SyncCount = @SyncCount + 1

		IF @API_ReturnMessage LIKE '%成功%'
		BEGIN
			-- 【状态】同步成功：该工单全部待同步记录置为已同步
			-- 说明：判定依据沿用现有上传过程惯例(返回消息包含"成功")，
			--       如 U_MOSemiFinishedLotSpecify 接口返回文本不同，需同步调整此处判断
			UPDATE dbo.MOSemiFinishedLotAllocation
			SET SAPSyncFlag = '1',
				ModifyDate = GETDATE()
			WHERE MOId = @CurMOId
				AND ConfirmStatus = '1'
				AND SAPSyncFlag = '0'

			SET @SuccessList = ISNULL(@SuccessList + ',', '') + @CurMOName
		END
		ELSE
		BEGIN
			-- 【状态】同步失败：SAPSyncFlag 保持 '0'，等待下次调用补偿，不影响其他工单
			SET @FailList = ISNULL(@FailList + ',', '') + @CurMOName
			SET @I_ReturnMessage = ISNULL(@I_ReturnMessage, '')
				+ N'ServerMessage:[工单号][' + @CurMOName + N']同步失败：'
				+ ISNULL(REPLACE(@API_ReturnMessage, 'ServerMessage:', ''), N'接口无返回') + CHAR(13) + CHAR(10)
		END
	END

	-- 【汇总】整理返回信息：成功/跳过/无效清单 + 失败明细

	IF ISNULL(@InvalidList, '') <> ''
		SET @I_ReturnMessage = ISNULL(@I_ReturnMessage, '')
			+ N'ServerMessage:以下工单号不存在，请检查[' + @InvalidList + N']!' + CHAR(13) + CHAR(10)

	IF ISNULL(@FailList, '') <> ''
		SET @I_ReturnMessage = ISNULL(@I_ReturnMessage, '')
			+ N'ServerMessage:同步失败工单[' + @FailList + N']，失败记录保持未同步状态，请修复后重新调用!' + CHAR(13) + CHAR(10)

	IF ISNULL(@I_ReturnMessage, '') = ''
		SET @I_ReturnMessage = N'ServerMessage:未找到需要同步的工单!'

	RETURN 0
END
GO
