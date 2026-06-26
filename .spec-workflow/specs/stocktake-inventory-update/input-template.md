# 库存盘点 Excel 输入模板

## 1. 模板用途

本模板用于库存盘点更新存储过程 `dbo.Batch_StocktakeUpdateRMInventory` 的输入数据准备。外部程序或人工导入工具需要先将 Excel 数据清洗后写入临时表 `#StocktakeData`，再调用存储过程进行预览或正式更新。

## 2. 固定字段

| Excel列名 | 临时表字段 | 是否必填 | 示例 | 说明 |
|---|---|---|---|---|
| 工厂 | `FactoryName` | 是 | 一厂 | 用于解析 `FactoryId` |
| 仓库 | `WarehouseName` | 是 | 原材料仓 | 用于解析 `WorkcenterId` |
| 物料号 | `ProductNo` | 是 | RM001 | 用于解析 `ProductId` |
| 库存数量 | `StockQty` | 是 | 100.00000000 | 用于更新或新增库存数量，不能小于 0 |
| 冻结数量 | `FrozenQty` | 否 | 0.00000000 | 缺省为 0；不为 0 时存储过程将同一 SAP 批次的在库记录 `LotStatus` 置为 0（冻结） |
| 单位 | `UOMName` | 是 | KG | 用于解析 `UOMId` |
| SAP批号 | `SAPBatchNo` | 是 | SAPBATCH001 | 写入并匹配 `WW_RMInventory.ProductionLotNO` |

## 3. 可选字段

| Excel列名 | 临时表字段 | 是否必填 | 示例 | 说明 |
|---|---|---|---|---|
| 批号 / MES批号 | `LotSN` | 否 | LOT20260618001 | 盘点来源通常不提供，不作为必填字段，也不参与主匹配 |

> 说明：`冻结数量` 为可选列，旧版 Excel 模板不含该列时按 0 处理。

## 4. 导入临时表结构

```sql
-- 【输入】盘点 Excel 数据导入后的临时表结构，供存储过程统一读取
CREATE TABLE #StocktakeData
(
    RowNo INT NOT NULL,                    -- Excel 行号，便于定位错误数据
    FactoryName NVARCHAR(100) NOT NULL,    -- 工厂名称
    WarehouseName NVARCHAR(100) NOT NULL,  -- 仓库名称
    ProductNo NVARCHAR(100) NOT NULL,      -- 物料号
    StockQty DECIMAL(18, 8) NOT NULL,      -- 实盘库存数量
    FrozenQty DECIMAL(18, 8) NOT NULL       DEFAULT 0, -- 冻结数量，不为 0 时冻结同一 SAP 批次
    UOMName NVARCHAR(50) NOT NULL,         -- 单位名称或单位编码
    SAPBatchNo NVARCHAR(100) NOT NULL,     -- SAP批号，匹配 ProductionLotNO
    LotSN NVARCHAR(100) NULL               -- MES内部批号，非必填，不参与主匹配
);
```

## 5. 已确认规则

- Excel 固定必填字段为：工厂、仓库、物料号、库存数量、单位、SAP批号。
- 盘点来源默认不提供 MES 内部批号 `LotSN`。
- `SAP批号` 必填，并作为匹配 `WW_RMInventory.ProductionLotNO` 的唯一外部批次字段。
- `LotSN` 不作为必填字段，不参与库存主匹配。
- 同一批导入数据中，`工厂 + 仓库 + 物料号 + SAP批号` 不允许重复；发现重复时阻断本次处理并返回清晰错误。
- 所有文本字段导入前后需要去除首尾空格，避免主数据匹配失败。

## 6. 示例数据

| RowNo | 工厂 | 仓库 | 物料号 | 库存数量 | 冻结数量 | 单位 | SAP批号 | 批号 / MES批号 |
|---:|---|---|---|---:|---:|---|---|---|
| 2 | 一厂 | 原材料仓 | RM001 | 100.00000000 | 0.00000000 | KG | SAPBATCH001 | |
| 3 | 一厂 | 原材料仓 | RM002 | 50.50000000 | 10.00000000 | PCS | SAPBATCH002 | |

## 7. 后续开发影响

- 任务 2 需要继续确认 `Factory`、`Product`、`Workcenter`、`UOM` 的真实表名和匹配字段。
- 任务 3 需要继续确认新增库存时 `LotSN` 留空还是按系统规则生成。
- 后续存储过程的全局校验逻辑必须按本模板字段和规则实现。
