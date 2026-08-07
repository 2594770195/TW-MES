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
- `finished-mo-semifinished-lot-allocation/` — 成品工单半成品批次预分配
- `finished-ink-allocation-picking/` — 成品灌墨指定批次与完工领料

### 半成品批次分配（MOSemiFinishedLotAllocationDoMethod）

| `@I_Sender` | 说明 |
|---|---|
| `GetMOProduct` | 查工单半成品需求/已分配/未分配 |
| `GetInventory` | 查可分配批次库存（按 `EntryDate` 排序） |
| `GetAllocatedLots` | 查已分配批次 |
| `AssignLot` | 扫 `LotSN` 单批分配 |
| `AutoAssign` | 按入库时间 FIFO 自动填满剩余需求（入参 `@MOItemId`） |
| `DeleteLot` | 逻辑删除分配记录 |

`AutoAssign` 规则：库存过滤同 `GetInventory`；按 `EntryDate`、`LotSN` 升序逐批取 `MIN(剩余需求, 批次可用量)`；库存不足时部分分配并返回剩余量。

### 成品灌墨指定批次衔接（PDA_FPInkCheckInput）

完整规格见 `.spec-workflow/specs/finished-ink-allocation-picking/`（requirements / design / tasks）。

- 灌墨扫描以 `MOSemiFinishedLotAllocation` 的有效占用记录作为准入条件，不再要求该批次已生成领料记录。
- 实际使用数量可超过分配数量，但批次必须为当前工单仍占用的已分配批次；批次可用量直接取当前库存 `WW_RMInventory.Qty`，且不得超过工单物料剩余需求。每次写入 `LoadingItemLotRecord` 时同步扣减对应库存，因此不再按当前会话已用数量重复扣减。
- 上料写入在同一事务内完成库存扣减、`LoadingItemLotDetail` / `LoadingItemLotRecord`、`TxnBase_MLotTrack` 批次追溯和 `DataChainAssyIssue` 数据链记录，参考 `PDA_ProductionMaking_LotSNScan` 的 `UsedQtyScan` 分支。
- 扫描工单时，当前已分配批次的库存总量必须覆盖分配数量；不足时阻断并提示仓库重新分配。
- 批次可用量大于剩余需求时，PDA 先返回建议数量，操作员在 `InputNumberDefocus` 确认后才写入使用记录。
- 自动完工或批次下线前，仅为当前上料会话的未领料记录生成生产领料单；过站报工成功后，将实际使用批次的分配记录设为不再占用已分配数量，历史记录保留。
- `PDA_FPInkCheckInput.sql` 已完成 spec 任务 5–10 的脚本改造，尚待按任务 12–16 进行数据库回归测试及 DBA 审批部署。

## Web 应用

| 应用 | 路径 | 说明 |
|---|---|---|
| MES 工具箱 | `web/stocktake-import/` | 统一前端入口；当前含「库存盘点导入」「索引碎片查询」等模块 |

启动说明见 [`web/stocktake-import/README.md`](web/stocktake-import/README.md)。

### 近期规格进展

- `stocktake-inventory-update/` 已确认任务 1：库存盘点 Excel 输入模板。模板说明见 `.spec-workflow/specs/stocktake-inventory-update/input-template.md`，后续开发可从任务 2「复核主数据字段映射」继续。
- `stocktake-inventory-update/` 已确认任务 2：主数据字段映射。工厂匹配 `Factory.FactoryName`，仓库匹配 `Workcenter.WorkcenterName` 且限定工厂，物料号匹配 `ProductRoot.ProductName` 后关联 `Product.ProductRootId` 获取 `ProductId`，单位匹配 `UOM.UOMName` 或 `UOM.ERPUnitcode`。
- `stocktake-inventory-update/` 已确认任务 3：SAP 批号仅写入 `WW_RMInventory.ProductionLotNO`，本期不同步 `SAPRemark`；新增库存的 `LotSN` 使用系统批号规则 `WW_MP_LotSN` 生成。
- `stocktake-inventory-update/` 已完成任务 4-14：新增存储过程脚本 `MES/procedure/Batch_StocktakeUpdateRMInventory.sql`，实现按仓库独立事务、DryRun 预览、已有库存累计保留更新、缺失库存新增、缺失物料或 SAP 批次置出库和 JSON 结果返回。
- `stocktake-import/` Excel 导入已支持「冻结数量」列：解析后写入 `TempStocktakeData.FrozenQty`，存储过程在冻结数量不为 0 时将同一 SAP 批次的在库记录 `LotStatus` 置为 0。同一工厂、仓库、物料号、SAP批号的多行会在导入时自动合并 `StockQty` 与 `FrozenQty`。
- `Batch_StocktakeUpdateRMInventory` v1.08 起，正式更新（DryRun=0）时数量变更写入 `StocktakeUpdateLog`（物料号、LotSN、SAP 批次、修改前/后数量），表结构见 `MES/table/StocktakeUpdateLog.sql`。

### 盘点存储过程待办（2026-07-06）

| 项 | 状态 | 说明 |
|---|---|---|
| v1.08 StocktakeUpdateLog | **未测试** | 数量变更日志写入逻辑待验证 |
| v1.09 半成品 OrgLotSN | **未测试** | 非 SAP批次+001 时 OrgLotSN 规则待验证 |
| 大文件 Excel 导入 | **待修改** | 约 30 万行盘点 Excel 导入失败，涉及 `web/stocktake-import/` 与本存储过程，修改前须先修复并回归 |

## 开发注意事项

- 所有 SQL 均按 SQL Server 语法编写，目标数据库为 OrBitMOMTestBack。
- 表结构到 `MES/table/` 查找，存储过程到 `MES/procedure/` 查找。
- 存储过程每段核心逻辑需要添加中文注释；临时变量首次声明时需备注中文名称或用途。
- 除 SELECT 外，其余 SQL 变更需经审批后再执行。
- 禁止 SQL 字符串拼接，统一使用参数化查询。

## Cursor AI 辅助开发

本项目已配置 MES SQL Server 专用 Skill 与 Rule，在 Cursor 中编写 `MES/**/*.sql` 时会自动应用规范。

| 类型 | 路径 | 作用 |
|---|---|---|
| Skill | `.cursor/skills/mes-sqlserver/SKILL.md` | MES 开发流程、目录约定、OrBit 存储过程规范 |
| Rule | `.cursor/rules/mes-sqlserver.mdc` | 编辑 SQL 文件时的注释、安全、事务约束 |

使用方式：在对话中描述需求即可（如「写一个领料确认存储过程」）；也可显式说「使用 mes-sqlserver skill」。
