---
name: mes-sqlserver
description: MES 制造执行系统 SQL Server 数据库开发规范。编写或修改表结构、存储过程、批处理脚本时使用。适用于 MES、OrBitMOMTestBack、库存、领料、质检、WMS 同步等 SQL Server 开发场景。
---

# MES SQL Server 开发

## 开发前必读

1. 阅读 `readme.md` 了解当前功能背景与目录说明。
2. 阅读 `.spec-workflow/steering/tech.md` 了解技术约束与安全规范。
3. 若功能有 spec 文档，先读 `.spec-workflow/specs/<功能名>/` 下的 requirements、design、tasks。

## 目录约定

| 类型 | 路径 | 说明 |
|---|---|---|
| 表结构 | `MES/table/` | 每个表一个 `.sql` 文件，文件名与表名一致 |
| 存储过程 | `MES/procedure/` | 每个过程一个 `.sql` 文件 |
| 规格文档 | `.spec-workflow/specs/` | 需求、设计、任务 |
| 技术约束 | `.spec-workflow/steering/` | 架构与开发原则 |

**查找表字段**：先在 `MES/table/` 搜索对应表名，确认字段名、类型、主键后再写 SQL，禁止凭记忆猜字段。

**参考现有写法**：在 `MES/procedure/` 搜索同类业务（Picking、Txn_、PDA_、APISync、WebAPI_ 等前缀），保持命名与结构一致。

## 数据库约束

- 数据库：**OrBitMOMTestBack**（仅此库，禁止跨库访问）。
- 方言：**SQL Server**（T-SQL）。
- 除 SELECT 外，INSERT/UPDATE/DELETE/DDL 脚本仅供提交审批，不直接在生产执行。
- 禁止 SQL 字符串拼接；存储过程参数、应用层调用均使用参数化。

## 存储过程编写规范

### 文件头

```sql
-- =============================================
-- Author:		<作者>
-- Create date: <创建日期>
-- Description:	<中文功能说明>
-- Revision: 1.00
-- =============================================
CREATE PROCEDURE [dbo].[ProcedureName]
```

### OrBit 平台 Save/DoMethod 类过程

若过程属于 OrBit-MetaObject 引擎生成或 SaveData/DoMethod 模式，必须保留标准接口参数：

- `@I_ReturnMessage`、`@I_IsNewRow`、`@I_ExceptionFieldName`
- `@I_LanguageId`、`@I_OrBitUserId`、`@I_OrBitUserName`
- `@I_ResourceId`、`@I_ResourceName`、`@I_PKId` 等

参考：`MES/procedure/PickingCategorySaveData.sql`

### 过程体惯例

```sql
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

    -- 初始化输出参数
    SET @I_ReturnMessage = ''

    -- 【业务校验】中文说明本段用途
    IF ...
    BEGIN
        SET @I_ReturnMessage = '错误码或提示'
        RETURN -1
    END

    -- 【核心逻辑】中文说明本段用途
    ...

END
```

### 注释要求

- 每段核心逻辑块前加**中文注释**，说明业务目的（如 `-- 按仓库分组处理盘点数据`）。
- 复杂 JOIN、事务边界、批量更新规则必须注释。
- 参数含义用行尾 `--` 中文说明（与现有过程保持一致）。
- 使用临时表（`#表名` 或 `INTO #表名`）时，在**创建或首次写入前**用中文注释写明该临时表的作用、存放内容及后续用途。
- 临时变量（`DECLARE @变量名`）**第一次出现（声明）时**，必须用行尾 `--` 或上一行注释写明中文名称或用途；后续赋值/使用处可不重复备注。

```sql
-- 【准备】#ResolvedStocktakeData：将 Excel 文本解析为 MES 主数据 ID，并保留行级错误原因
SELECT ...
INTO #ResolvedStocktakeData
FROM dbo.TempStocktakeData s
...

-- 【准备】#WarehouseList：本次盘点涉及的仓库清单，供按仓库独立事务循环处理
CREATE TABLE #WarehouseList ( ... );

-- ✅ 临时变量首次声明时备注用途
DECLARE @RemainQty DECIMAL(18, 6)   -- 剩余待分配数量
DECLARE @LotSN NVARCHAR(50)        -- 当前处理的批次条码
DECLARE @i INT                     -- 循环计数器

-- ❌ 不推荐：声明时无备注，读者无法快速理解用途
DECLARE @RemainQty DECIMAL(18, 6)
DECLARE @x INT
```
### 事务与错误

- 多表写操作使用 `BEGIN TRAN` / `COMMIT` / `ROLLBACK`，按仓库或业务单元划分事务时注意注释范围。
- 失败时设置 `@I_ReturnMessage` 并 `RETURN -1`（OrBit 风格）或 `RAISERROR`/`THROW`（批处理脚本）。
- 不向前端或调用方暴露内部堆栈；错误信息应可理解、可定位。

### 锁定策略

- 所有 SQL 操作默认**不添加锁提示**，包括 `UPDLOCK`、`HOLDLOCK`、`XLOCK`、`ROWLOCK`、`TABLOCK` 等。
- 只有确认不加锁会带来重大数据风险（如超分配、重复扣减、数据损坏）时，先向用户说明风险、锁范围与并发影响，获得明确同意后才可增加锁提示或提升隔离级别。
- 未获用户明确同意时，不得以"防并发"为由自行添加锁提示。

### @I_ReturnMessage 错误提示规范

OrBit Save/DoMethod 类过程的业务校验失败时，**必须**设置 `@I_ReturnMessage` 并以 `ServerMessage:` 前缀返回；涉及**具体输入参数**的异常，**必须**在提示中拼接该参数的实际值，便于前端/操作员定位问题。

**格式**：`ServerMessage:[参数中文名][参数值]错误描述`

- 参数中文名用方括号 `[]` 包裹，表示字段/参数含义。
- 参数值紧跟其后，同样用方括号 `[]` 包裹，通过字符串拼接写入变量值。
- OrBit 过程若需换行，末尾加 `+ @Enter`（与现有过程保持一致）。

```sql
-- ❌ 不推荐：未带出具体参数值，操作员无法判断扫了什么
SET @I_ReturnMessage = 'ServerMessage:[批次条码]不存在，请重新扫描' + @Enter;

-- ✅ 推荐：带出具体参数值
SET @I_ReturnMessage = 'ServerMessage:[批次条码][' + @LotSN + ']不存在，请重新扫描' + @Enter;

-- ✅ 其他示例
SET @I_ReturnMessage = 'ServerMessage:[工单号][' + @MOName + ']不存在，请检查!' + @Enter;
SET @I_ReturnMessage = 'ServerMessage:[领料单号][' + @PickingListName + ']不存在，请检查!' + @Enter;
```

**适用场景**（必须带出参数值）：

- 扫描/输入的单号、条码、批次号不存在或无效
- 根据传入 ID/编码查不到主数据或业务单据
- 参数格式正确但业务校验失败，且失败原因与传入值直接相关

**可不拼接参数值**的场景：

- 未选择行、未选有效记录等**无具体入参值**的操作提示（如 `请选择有效工单!`）
- 系统内部错误、并发冲突等与单一输入值无关的异常

## 表结构脚本规范

- 文件放在 `MES/table/<TableName>.sql`。
- 修改前对照现有表脚本，保持字段命名风格（如 `char(12)` 主键、`nvarchar` 名称字段）。
- 新增字段在脚本中用中文注释说明业务含义。
- 新增表时必须使用 `sys.sp_addextendedproperty @name=N'MS_Description'` 写入表说明和每个字段说明，确保 SQL Server 表设计器的"说明"字段可见。
- 历史表不需要修改，仅为备份

## 常见业务规则

### WW_RMInventory 库存表

- `IsStorage=1` 表示**在库**；`IsStorage=0` 表示已出库/不在库。
- 查询、匹配、分配、校验可用库存时，**默认必须加** `IsStorage=1`（可再配合 `Qty>0` 等条件）。
- 仅在明确需要包含已出库记录的场景（如盘点冲销、历史追溯、专门把批次置为不在库）才可省略或使用 `IsStorage=0`。

```sql
-- ✅ 推荐：查可用在库库存
SELECT ...
FROM dbo.WW_RMInventory
WHERE ... AND IsStorage = 1 AND Qty > 0

-- ❌ 易错：漏加 IsStorage，会把已出库批次算进可用量
SELECT ...
FROM dbo.WW_RMInventory
WHERE ...
```

## 常见业务模块前缀

| 前缀 | 典型用途 |
|---|---|
| `Picking*` / `PickingList*` | 领料单 |
| `Txn_*` | 事务类操作 |
| `PDA_*` | PDA 端查询/提交 |
| `APISync*` / `WebAPI_*` | 与 WMS/外部系统同步 |
| `Vendor_*` | 供应商相关 |
| `Txn_QC_*` | 质检 |

## 工作流程

编写新功能 SQL 时按顺序执行：

1. **查表** — 在 `MES/table/` 确认所有涉及表的字段。
2. **查参考** — 在 `MES/procedure/` 找同类过程作模板。
3. **读 spec** — 有规格文档则严格按 requirements/design 实现。
4. **写脚本** — 遵循本节规范，分段中文注释。
5. **自检** — 字段名、主键类型、事务范围、参数化、错误返回（参数异常时 `@I_ReturnMessage` 是否带出具体参数值）、临时表注释是否说明用途、临时变量首次声明是否已备注名称/用途；新增表是否已写入表级和字段级 `MS_Description` 说明；涉及 `WW_RMInventory` 时是否已按需加 `IsStorage=1`。

## 输出要求

向用户交付 SQL 时说明：

- 涉及哪些表与存储过程
- 核心业务规则（更新/新增/软删除等）
- 是否需先跑预览或备份
- 部署前需 DBA/审批的注意事项