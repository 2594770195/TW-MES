# MES-Cursor 项目说明

## 项目用途

本项目用于维护 MES 相关数据库对象、开发文档和规格工作流。当前仓库主要包含 SQL Server 表结构、存储过程以及 `.spec-workflow` 规格文档。

## 目录说明

| 目录 | 说明 |
|---|---|
| `MES/table/` | SQL Server 表结构脚本 |
| `MES/procedure/` | SQL Server 存储过程脚本 |
| `.spec-workflow/steering/` | 项目方向、技术约束、目录规范说明 |
| `.spec-workflow/specs/` | 各功能的需求、设计、任务文档 |

## 功能规格文档

每个业务功能的详细说明（需求、设计、任务）放在 `.spec-workflow/specs/<功能名>/` 下，例如：

- `stocktake-inventory-update/` — 库存盘点更新
- `api-tester/` — 接口测试工具

## Web 应用

| 应用 | 路径 | 说明 |
|---|---|---|
| MES 工具箱 | `web/stocktake-import/` | 统一前端入口；当前含「库存盘点导入」模块（`/stocktake`） |

启动说明见 [`web/stocktake-import/README.md`](web/stocktake-import/README.md)。

### 近期规格进展

- `stocktake-inventory-update/` 已确认任务 1：库存盘点 Excel 输入模板。模板说明见 `.spec-workflow/specs/stocktake-inventory-update/input-template.md`，后续开发可从任务 2「复核主数据字段映射」继续。
- `stocktake-inventory-update/` 已确认任务 2：主数据字段映射。工厂匹配 `Factory.FactoryName`，仓库匹配 `Workcenter.WorkcenterName` 且限定工厂，物料号匹配 `ProductRoot.ProductName` 后关联 `Product.ProductRootId` 获取 `ProductId`，单位匹配 `UOM.UOMName` 或 `UOM.ERPUnitcode`。
- `stocktake-inventory-update/` 已确认任务 3：SAP 批号仅写入 `WW_RMInventory.ProductionLotNO`，本期不同步 `SAPRemark`；新增库存的 `LotSN` 使用系统批号规则 `WW_MP_LotSN` 生成。
- `stocktake-inventory-update/` 已完成任务 4-14：新增存储过程脚本 `MES/procedure/Batch_StocktakeUpdateRMInventory.sql`，实现按仓库独立事务、DryRun 预览、已有库存累计保留更新、缺失库存新增、缺失物料或 SAP 批次置出库和 JSON 结果返回。
- `stocktake-import/` Excel 导入已支持「冻结数量」列：解析后写入 `TempStocktakeData.FrozenQty`，存储过程在冻结数量不为 0 时将同一 SAP 批次的在库记录 `LotStatus` 置为 0。

## 开发注意事项

- 所有 SQL 均按 SQL Server 语法编写，目标数据库为 OrBitMOMTestBack。
- 表结构到 `MES/table/` 查找，存储过程到 `MES/procedure/` 查找。
- 存储过程每段核心逻辑需要添加中文注释。
- 除 SELECT 外，其余 SQL 变更需经审批后再执行。
- 禁止 SQL 字符串拼接，统一使用参数化查询。

## Cursor AI 辅助开发

本项目已配置 MES SQL Server 专用 Skill 与 Rule，在 Cursor 中编写 `MES/**/*.sql` 时会自动应用规范。

| 类型 | 路径 | 作用 |
|---|---|---|
| Skill | `.cursor/skills/mes-sqlserver/SKILL.md` | MES 开发流程、目录约定、OrBit 存储过程规范 |
| Rule | `.cursor/rules/mes-sqlserver.mdc` | 编辑 SQL 文件时的注释、安全、事务约束 |

使用方式：在对话中描述需求即可（如「写一个领料确认存储过程」）；也可显式说「使用 mes-sqlserver skill」。
