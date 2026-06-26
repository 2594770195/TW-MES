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

### 事务与错误

- 多表写操作使用 `BEGIN TRAN` / `COMMIT` / `ROLLBACK`，按仓库或业务单元划分事务时注意注释范围。
- 失败时设置 `@I_ReturnMessage` 并 `RETURN -1`（OrBit 风格）或 `RAISERROR`/`THROW`（批处理脚本）。
- 不向前端或调用方暴露内部堆栈；错误信息应可理解、可定位。

## 表结构脚本规范

- 文件放在 `MES/table/<TableName>.sql`。
- 修改前对照现有表脚本，保持字段命名风格（如 `char(12)` 主键、`nvarchar` 名称字段）。
- 新增字段在脚本中用中文注释说明业务含义。
- 历史表不需要修改，仅为备份

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
5. **自检** — 字段名、主键类型、事务范围、参数化、错误返回。

## 输出要求

向用户交付 SQL 时说明：

- 涉及哪些表与存储过程
- 核心业务规则（更新/新增/软删除等）
- 是否需先跑预览或备份
- 部署前需 DBA/审批的注意事项
