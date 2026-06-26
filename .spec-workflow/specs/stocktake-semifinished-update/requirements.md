# Requirements: 半成品盘点导入

## 状态
- **状态**：草稿 Draft
- **创建日期**：2026-06-26
- **范围**：在 MES 工具箱（`web/stocktake-import`）新增「半成品盘点」模块
- **核心存储过程**：`dbo.UpdateInventoryBySAP_BCP`（已存在）

---

## 1. 目标
新增两个简单功能：

1. **Excel 导入**：上传 Excel，将半成品库存数据写入 `SAP_PRODUCT_INVENTORY` 表。
2. **执行盘点**：页面选择/填写「工厂 + 仓库」，调用存储过程 `dbo.UpdateInventoryBySAP_BCP` 更新 `WW_RMInventory`。

不做复杂封装，不改存储过程逻辑，仅提供导入 + 触发执行的界面与接口。

---

## 2. 功能需求

### F-001 Excel 导入到 SAP_PRODUCT_INVENTORY
- 提供下载标准 Excel 模板。
- 上传 Excel，按列名解析并写入 `SAP_PRODUCT_INVENTORY`。
- 每行 `Id` 由程序生成（GUID），`isChange` 默认 `0`。
- 导入前按「工厂 + 仓库」清空对应旧数据，再写入本次数据。
- 删除必须按本次 Excel 中去重后的「工厂 + 仓库」集合先执行一次，再批量插入，禁止逐行“先删后插”。
- 返回导入行数与解析错误（缺列、空必填）。

### F-002 选择工厂仓库执行盘点
- 页面填写/选择「工厂」「仓库」。
- 点击执行调用 `EXEC dbo.UpdateInventoryBySAP_BCP @WarehouseName, @FactoryName`。
- 返回执行结果提示（成功 / 找不到仓库 / 无可处理数据 / 异常信息）。
- 因存储过程对“找不到仓库”仅 `select` 提示，应用层需先做工厂仓库存在性校验，校验失败时不调用存储过程。

---

## 3. Excel 模板列

| Excel 列名 | 必填 | 对应字段 | 说明 |
|---|---|---|---|
| 工厂 | 是 | `FactoryName` | 与执行时填写的工厂一致 |
| 仓库 | 是 | `WorkcenterName` | 与执行时填写的仓库一致 |
| 物料 | 是 | `ProductName` | 半成品物料名称 |
| 批号 | 是 | `LotSN` | SAP 批号 |
| 在库数量 | 否 | `ProductInventoryNum` | 可用库存数量 |
| 质检数量 | 否 | `CheckNum` | 质检中数量 |
| 锁定数量 | 否 | `LockQty` | 锁定/冻结数量 |
| 单位 | 否 | `UomName` | 单位名称 |
| 入库日期 | 否 | `StorageDate` | 用于计算有效期 |
| 备注 | 否 | `Note` | 写入 `SAPRemark` |

> 三个数量列至少应有一列有值；取值与状态规则由存储过程内部处理（`ProductInventoryNum → CheckNum → LockQty`）。
> 字段长度需在导入前校验：`FactoryName<=10`、`ProductName<=18`、`WorkcenterName<=4`、`LotSN<=10`、`UomName<=3`、`StorageDate<=30`、`Note<=30`，超长直接报错并返回行号。

---

## 4. 异常与提示

| 场景 | 处理 |
|---|---|
| 文件为空 / 非 xlsx | 提示重新上传 |
| 缺少必填列 | 提示缺少的列名 |
| 必填字段为空 | 提示行号 |
| 找不到仓库 | 应用层预检失败并提示「找不到仓库」，不调用存储过程 |
| 数据为空（该工厂仓库） | 存储过程 `RETURN 0`，提示无可处理数据 |
| 执行异常 | 透传错误信息，库存整体回滚 |

---

## 5. 非功能要求
- 复用现有 MES 工具箱前后端（React + ASP.NET Core）与数据库连接配置。
- 数据库写入参数化，不拼接 SQL。
- 数据库：`OrBitMOMTestBack`（测试）/ 生产库按环境切换。
- 新增接口响应格式统一沿用 `ApiResponse<T>`，与现有 `stocktake` 模块保持一致。

---

## 6. 开放问题
- [ ] 工厂、仓库是下拉选择（查主数据）还是手工填写？默认手工填写，与 Excel 一致。
- [ ] 导入是按「工厂+仓库」清空重写，还是全表清空重写？默认按「工厂+仓库」。
- [ ] 是否允许同一工厂仓库多次导入叠加？默认覆盖。
