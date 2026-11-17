---
name: mes-sql-query
description: "根据 MES 数据库表结构快速生成满足查询需求的 SQL Server SELECT 语句。当用户提出数据查询需求（如查库存、统计领料、追溯批次）时调用；找不到数据来源表时向用户提问确认，并将查询结果与表映射结论记录到历史文件。"
---
# MES 查询 SQL 生成器

根据用户的查询需求，基于 `MES/table/` 中的表结构生成可直接执行的 SQL Server 查询语句（仅 SELECT）。

## 触发场景

用户提出类似以下需求时使用本 skill：

- "帮我查一下……" / "写个 SQL 统计……" / "查某个批次/工单/领料单的数据"
- "看看 xxx 的库存 / 流水 / 记录"
- 需要从 MES 数据库（**OrBitMOMTestBack** 开发库 / **OrBitMOM** 生产库，其他库不看）取数但没有现成查询

## 工作流程

### 1. 理解查询需求

从用户描述中提取：查询对象（工单/批次/物料/单据）、筛选条件、需要的字段、是否需要汇总统计。

### 2. 查历史记录

先读取本 skill 目录下的 `query-history.md`：

- 若存在相同或高度相似的历史查询，直接复用并按需调整；
- 若历史中有"表映射确认"记录，直接采用已确认的表，不再重复提问。

### 3. 定位数据表

按以下顺序查找，**禁止凭记忆猜表名、猜字段**：

1. 根据业务关键词匹配 `MES/table/` 下的文件名（如 领料→PickingList*、工单→MO*、库存→WW_RMInventory/ProductInventory/StockList、批次→Lot/MOItemLot、供应商→Vendor*）。
2. 用 Grep 在表文件的字段注释中搜索业务字段名（如 LotSN、MOName、ProductLotNO），确认字段真实存在后再使用。
3. 参考 `MES/procedure/` 中同类业务的现有写法，确认表间关联关系（主键/外键字段）。

### 4. 找不到表时必须提问

若经过第 3 步仍无法确定数据来源（多个候选表无法取舍、或完全没有匹配），**停止生成，向用户提问**，例如：

- "库存数据应该从 WW_RMInventory（原材料）还是 ProductInventory（成品）取？"
- "您说的'流转记录'是指 MOItemLot_History 还是 LoadingItemLotRecord？"

用户回答后：

1. 将【问题 + 用户确认的表 + 业务含义】追加到 `query-history.md` 的"表映射确认"章节，下次遇到同类需求不再提问；
2. 继续执行第 5 步生成 SQL。

### 5. 生成 SQL

规范要求：

- 仅生成 SELECT 查询，禁止生成 DML/DDL。
- SQL Server T-SQL 语法；数据库范围 **OrBitMOMTestBack**（开发库）/ **OrBitMOM**（生产库），**其他库不看**；表名带 `dbo.` 前缀。
- 字段名以 `MES/table/` 中的表结构文件为准，禁止凭记忆书写。
- 关键 JOIN、WHERE 条件加中文注释，复杂查询分段注释（准备数据 / 关联 / 过滤 / 输出）。
- `WW_RMInventory` 查在库库存必须加 `IsStorage = 1`（仅历史追溯/冲销场景例外）。
- 数量字段用 DECIMAL(18,6) 口径处理，聚合时注意 `ISNULL(x, 0)`。
- 输出时向用户说明：涉及哪些表、核心过滤条件、可选的调整参数（如时间范围）。
- **生成的 SQL 必须在对话页面完整显示**（markdown 代码块），供用户直接复制执行，不能只保存到文件。
- SysUser 表中 UserName 是工号，UserDescription 才是中文姓名；按中文名（如"罗年"）查人时用 `UserDescription = N'姓名'`。

### 6. 记录结果

每次成功生成 SQL 后，**追加**记录到本 skill 目录下的 `query-history.md`，格式：

```markdown
## YYYY-MM-DD <需求一句话摘要>
- 表：WW_RMInventory, Product
- 关键规则：在库库存 IsStorage=1
- SQL：
  SELECT ...
```

同时满足以下条件之一时，将 SQL 保存为独立文件 `MES/query/Q_<摘要拼音或英文>_<YYYYMMDD>.sql`，并在历史记录中注明文件路径：

- SQL 超过 30 行；
- 用户明确要求保存；
- 属于可能反复使用的常用查询。

## 常用表速查（仅作起点，仍需打开表文件核对字段）

| 业务         | 表                                                                                   |
| ------------ | ------------------------------------------------------------------------------------ |
| 原材料库存   | WW_RMInventory                                                                       |
| 成品库存     | ProductInventory / SAP_PRODUCT_INVENTORY                                             |
| 工单         | MO / MOItem / MOItemTask                                                             |
| 工单批次投料 | MOItemLot / MOItemLot_History                                                        |
| 批次主数据   | Lot                                                                                  |
| 领料单       | PickingList / PickingListItem / PickingListItemLot / PickingList_MO / PickingList_PO |
| 采购单       | PO / POItem / POItemLot / PurchaseOrder                                              |
| 入库         | ProductEntry / FinishingEntry                                                        |
| 退料/退货    | ProductBack / VendorBack                                                             |
| 供应商送货   | VendorDelivery / VendorDeliveryItem / VendorDeliveryItemLot                          |
| IQC 质检     | IQCCheck / IQCCheckItem / IQCCheckLot                                                |
| 调拨         | ProductAllot / ProductAllotItem                                                      |
| 半成品分配   | MOSemiFinishedLotAllocation / MOAllotRequest                                         |
| 用户         | SysUser / UserM / UserLogin                                                          |
| 产品         | Product / ProductRoot / ProductBarcode                                               |
| 栈板/装箱    | PalletInfo / PackingList                                                             |

## 与 mes-sqlserver skill 的关系

- 本 skill 只负责**查询（SELECT）**生成；
- 涉及存储过程、表结构修改、DML 脚本时，切换到 mes-sqlserver skill 的规范执行。
