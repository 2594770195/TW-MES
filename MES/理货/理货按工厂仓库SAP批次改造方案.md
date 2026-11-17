# 理货维度改造方案：由「SAP 批次」改为「工厂 + 仓库 + SAP 批次」

> 版本：v1.2（2026-11-12）
> 更新说明：
>   1) `MOLotSpecify` 重分配由"覆盖式全量取消后重插"改为 **Upsert**（已扣数行原样保留、已存在行更新、不存在行插入）
>   2) 已扣数触发条件改为**扫码数量严格等于理货量**，不支持人工填写扣数数量，总扫码量 = 总理货量后流程才可结束
>   3) `mmbe.sql` / `zpp12.sql` 报表暂废弃，本次改造不处理
>   4) 新增单元测试用例
>   5) **新增工厂口径：理货只能分配与工单工厂对应的库存工厂**（9502/9304 工单 → 9502 库存；9302 工单 → 9302 库存）
> 状态：**方案待评审，未改代码**
> 涉及过程：
> - `AssignLot_GetLotByProductionLotNo_Script`（理货-指定批次对话框，可分配批次）
> - `MOSemiFinishedLotAllocationBatchByProductionLotNoDoMethod`（理货主流程：查询 / 自动分配 / 确认 / 取消）
> - `MOLotSpecify_AssignReserveLotByProductionLotNo_DoMethod`（手工指定理货批次和数量）
> - `PDA_FPInkCheckInput_PL`（按理货数据灌墨扣数）
> 涉及表：`MOSemiFinishedLotAllocation`、`WW_RMInventory`

---

## 一、改造目标

### 1.1 现状

当前理货（预分配）的业务主键是 `ProductId + ProductionLotNO`（半成品物料 + SAP 批次）：

- 一个 SAP 批次无论分布在几个工厂、几个仓库，在理货里**只汇总成一行**；
- 分配记录 `FactoryId`、`WorkcenterId` 固定写 `NULL`，展示时再由库存表按批次反查"代表行"；
- 可分配数量、占用数量、确认校验、灌墨扣数全部按 `ProductId + ProductionLotNO` 汇总。

### 1.2 目标

理货维度改为 **`ProductId + FactoryId + WorkcenterId + ProductionLotNO`**（物料 + 工厂 + 仓库 + SAP 批次）：

- 同一个 SAP 批次在不同工厂 / 不同仓库时，理货**拆成多行**，各自独立数量、独立占用、独立确认、独立取消；
- 分配记录必须把实际的 `FactoryId`、`WorkcenterId` 写入，不再写 `NULL`；
- 所有"库存数量 / 已分配数量 / 可用数量"的计算都按四字段同维度汇总与匹配。

### 1.3 为什么必须改

1. **SAP 库存是按「工厂 + 库存地点」管理的**。理货后续要向 SAP 同步「已理货 / 取消 / 已扣数」，SAP 侧过账必须明确工厂与库存地点；只按 SAP 批次一个维度无法确定扣哪个库位。
2. **物理库存本身分仓**。同一 SAP 批次在 A 仓 60、B 仓 40，按整批汇总是"100 可用"，但灌墨实际只能从扫描到的那个 MES 批次（属于某一个仓库）扣料，另一个仓库的库存无法参与。
3. **避免跨仓误占用 / 误确认**。按批次汇总时会出现"拿 A 仓库存去校验 B 仓理货"，确认可以通过，但仓库实物不够，SAP 与 MES 数据都会失真。
4. **取消与扣数需要仓库级精度**。仓库要能只取消某一仓库的理货，而不影响其他仓库同批次理货。

---

## 二、维度与口径定义

### 2.1 理货维度（业务主键）

```
ProductId + FactoryId + WorkcenterId + ProductionLotNO
```

| 字段 | 说明 | 是否参与维度 |
|---|---|---|
| `ProductId` | 半成品物料 | 是 |
| `FactoryId` | 库存所在工厂 | 是（本次新增） |
| `WorkcenterId` | 库存所在仓库（`IsStorage=1`） | 是（本次新增） |
| `ProductionLotNO` | SAP / 生产批次 | 是 |
| `CellId` | 储位 | 否，仅展示。储位调整不影响理货占用 |
| `LotSN` / `WWId` | MES 批次 | 否，仍写 `NULL`，由库存表按四字段反查代表子批次 |
| `MOId` / `MOItemId` | 工单 / 工单物料行 | 否，属于需求侧 |

> 说明：储位不进维度的原因——储位在仓库内会因移库变动，理货锁的是"仓库里的这批货"，不是"某个储位上的货"。

### 2.2 数量口径（全部改为四字段同维度）

**库存数量**（某维度可用的在库量）：

```sql
SELECT ProductId, FactoryId, WorkcenterId, ProductionLotNO,
       SUM(ISNULL(Qty, 0)) AS StockQty
FROM dbo.WW_RMInventory
WHERE LotStatus = '1' AND IsStorage = 1 AND ISNULL(Qty, 0) > 0
  AND ISNULL(ProductionLotNO, '') <> ''
GROUP BY ProductId, FactoryId, WorkcenterId, ProductionLotNO
```

**已占用数量**（全局）：`DeleteFlag='0' AND IsOccupyAllocatedQty=1 AND ConfirmStatus='1'`，按四字段汇总。
**本单占用**：再加 `ConfirmStatus='0' AND MOId IN (本次工单清单)`，按四字段汇总。

**可用数量** = 库存数量 − 已占用数量（同维度）。

### 2.3 记录状态（不变）

| 状态 | ConfirmStatus | IsOccupyAllocatedQty | DeleteFlag |
|---|---|---|---|
| 未确认（预分配） | 0 | 1 | 0 |
| 已理货 | 1 | 1 | 0 |
| 已扣数 | 1 | 0 | 0 |
| 取消分配 | 1 | 1 | 1 |

本次改造**不改变状态机**，只改变"一行代表的范围"。

### 2.4 工厂口径（**理货分配的前置约束**）

理货只能分配与工单工厂对应的库存工厂，规则：

| 工单工厂（`MO.FactoryId` → `Factory.FactoryName`） | 允许分配的库存工厂 |
|---|---|
| `9502` | `9502` |
| `9304` | `9502`（受托工厂库存统一在 9502） |
| `9302` | `9302` |
| 其他 | 同名工厂（兜底，与"相同工厂"原则一致） |

实现方式：由 `MOItem → MO → Factory` 取工单工厂名，按上表映射为"允许的库存工厂名"，再换算成 `FactoryId`，
在可分配批次查询（对话框、`GetInventory`、`AutoAssign`）中追加 `AND wri.FactoryId = @StockFactoryId`。

**为什么**：

1. 物理库存按工厂隔离，9302 的货不能拿去满足 9502 工单，反之亦然；
2. SAP 过账按工厂区分，跨厂理货在 SAP 侧无法落账；
3. 受托工厂（9304）的半成品实物统一存放于 9502，所以 9304 工单必须映射到 9502 库存。

**失败处理**：

- 工单未维护工厂、或映射后的库存工厂在 `Factory` 表不存在时：
  - 对话框脚本 / `GetInventory` 直接返回错误，不展示可分配批次；
  - `AutoAssign` 跳过该工单，并在返回信息中提示"未维护工厂或对应库存工厂不存在"。

---

## 三、表与索引

### 3.1 表结构：无需加字段

`MOSemiFinishedLotAllocation` 已有 `FactoryId`、`WorkcenterId`（`char(12)`，可空），本次只是从"固定写 NULL"改为"写入实际工厂/仓库"。

建议把两列的业务含义在扩展属性中补充为"理货维度，必填（主流程写入）"。

### 3.2 新增索引（必须）

现有索引只有 `ProductId`，四字段查询会走不到索引。

```sql
-- 理货维度索引：支撑按 工厂+仓库+SAP批次 汇总库存/占用，以及灌墨扫描时的维度匹配
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_MOSemiFinishedLotAllocation_Dim'
               AND object_id = OBJECT_ID(N'dbo.MOSemiFinishedLotAllocation'))
BEGIN
    CREATE INDEX IX_MOSemiFinishedLotAllocation_Dim
        ON dbo.MOSemiFinishedLotAllocation
           (ProductId, FactoryId, WorkcenterId, ProductionLotNO, DeleteFlag, IsOccupyAllocatedQty)
END
GO
```

### 3.3 存量数据：无需处理

旧理货数据已清理，`MOSemiFinishedLotAllocation` 中不存在 `FactoryId` / `WorkcenterId` 为空的记录，本次**不做存量回填、不做历史空值兼容**：

- `GetAllocatedLots` 的库存代表行反查直接按四字段严格等值匹配，不再"优先匹配、空值回退"；
- 新数据由主流程写入真实工厂/仓库，四字段始终非空。

---

## 四、`AssignLot_GetLotByProductionLotNo_Script`（可分配批次对话框）

### 改动位置：约 L109–L208

| 改动点 | 现状 | 改为 | 为什么 |
|---|---|---|---|
| 汇总分组 | `GROUP BY wri.ProductId, wri.ProductionLotNO` | 增加 `wri.FactoryId, wri.WorkcenterId` | 同一 SAP 批次跨仓库必须拆成多行，否则网格只有一行、无法分仓分配 |
| 工厂/仓库列 | `MIN(f.FactoryName)`、`MIN(pr...)`，`WorkcenterName` 被注释 | 直接输出 `f.FactoryName`、`w.WorkcenterName`，并**新增返回 `FactoryId`、`WorkcenterId`** | 前端需要回传维度，否则保存时无法定位仓库 |
| 行标识 | `MIN(wri.WWId)` | 保留，但改为"该维度内最早入库行"的 WWId | 网格行标识；同批次多仓库时 WWId 必须不同，不能再跨仓库取 MIN |
| 已分配子查询 `alloc` | 按 `ProductId + ProductionLotNO` 汇总并 JOIN | 按四字段 `GROUP BY` 并四字段 JOIN | 否则 A 仓的占用会被扣到 B 仓可用量上 |
| 本行已分配 `moAlloc` | 按 `ProductId + ProductionLotNO` 汇总 | 按四字段汇总并 JOIN | `IsRowSelect` 需按维度判断，已分配的是 A 仓不代表 B 仓也分配过 |
| 排序 | 生产日期 → 入库日期 → 批次号 | 追加 `FactoryId, WorkcenterId` 作为稳定排序尾键 | 同批次多行时排序不确定，会导致网格每次刷新行序变化 |
| 工厂过滤 | 库存不做工厂限制 | 按 §2.4 由 `MOItem → MO → Factory` 解析允许的库存工厂，`InvAgg` / `InvRep` 均追加 `AND wri.FactoryId = @StockFactoryId` | 对话框是分配入口，必须与主流程同一口径，否则会显示并允许选中其他工厂库存 |

### 参考改法（核心片段）

```sql
-- 【汇总】按 物料+工厂+仓库+SAP批次 汇总库存，同一 SAP 批次跨仓库拆多行
;WITH InvAgg AS (
    SELECT wri.ProductId, wri.FactoryId, wri.WorkcenterId, wri.ProductionLotNO,
           SUM(ISNULL(wri.Qty, 0)) AS StockQty,
           COUNT(1) AS LotSNCount,
           MIN(ISNULL(TRY_CONVERT(date, NULLIF(LTRIM(RTRIM(wri.ProductionDate)), '')), '99991231')) AS FirstProductionDate,
           MIN(wri.EntryDate) AS FirstEntryDate
    FROM dbo.WW_RMInventory wri
    WHERE wri.ProductId = @ProductId
      AND wri.LotStatus = '1' AND wri.IsStorage = 1
      AND ISNULL(wri.Qty, 0) > 0
      AND ISNULL(wri.ProductionLotNO, '') <> ''
    GROUP BY wri.ProductId, wri.FactoryId, wri.WorkcenterId, wri.ProductionLotNO
)
-- 【占用】同样按四字段汇总，并与库存四字段对齐
, Alloc AS (
    SELECT a.ProductId, a.FactoryId, a.WorkcenterId, a.ProductionLotNO,
           SUM(ISNULL(a.Qty, 0)) AS AllocatedQty
    FROM dbo.MOSemiFinishedLotAllocation a
    WHERE a.DeleteFlag = '0' AND a.IsOccupyAllocatedQty = 1
      AND (a.ConfirmStatus = '1' OR (a.ConfirmStatus = '0' AND a.MOId IN (SELECT MOId FROM #MOList)))
      AND ISNULL(a.ProductionLotNO, '') <> ''
    GROUP BY a.ProductId, a.FactoryId, a.WorkcenterId, a.ProductionLotNO
)
```

> 前端同步要求：网格必须增加「工厂」「仓库」两列，并在提交 XML 时带上 `FactoryId`、`WorkcenterId`。仅靠 `ProductionLotNO` 已无法唯一确定一行。

---

## 五、`MOSemiFinishedLotAllocationBatchByProductionLotNoDoMethod`（理货主流程）

### 5.1 `GetInventory`（**已废弃，2026-11-12 删除**）

原分支已从过程中删除，可分配批次统一由对话框脚本 `AssignLot_GetLotByProductionLotNo_Script` 返回
（该脚本已按四维度拆行并执行工厂口径过滤）。调用方传 `@I_Sender='GetInventory'` 会被白名单校验拒绝。

> 下方 5.1 原文保留作为历史记录，不再执行。

| 改动点 | 说明 |
|---|---|
| `InvAgg` / `Alloc` | `GROUP BY` 与 JOIN 均改为四字段 |
| `InvRep` | `PARTITION BY wri.ProductId, wri.FactoryId, wri.WorkcenterId, wri.ProductionLotNO`，`rn=1` 取该维度最早入库行作代表 |
| 返回列 | 新增 `FactoryId`、`WorkcenterId`；`FactoryName` / `WorkcenterName` 直接取代表行，不再依赖 `MIN()` |
| `ProductInventory` 关联 | 保持 `ProductId + ProductionLotNO + WorkcenterId`，现在仓库是确定值，不会再出现取错仓库 |
| `ORDER BY` | 生产日期 → 入库日期 → `FactoryId` → `WorkcenterId` → 批次号 |
| 工厂过滤 | 按 §2.4 解析工单允许的库存工厂，`InvAgg` / `InvRep` 追加 `AND wri.FactoryId = @StockFactoryId` |

**为什么**：这是自动分配和前端"可分配批次"的数据源，若此处不拆行，后面 AutoAssign 拿不到仓库信息，仍会跨仓合并。

### 5.2 `GetAllocatedLots`（约 L304–L378）

现状问题：`OUTER APPLY` 只按 `ProductId + ProductionLotNO` 反查代表库存行，同批次多仓库时会取到**别的仓库**的 `LotSN / FactoryId / WorkcenterId`；`StockQty` 子查询也没有仓库条件，展示的"库存数量"是全部仓库合计。

| 改动点 | 改为 |
|---|---|
| 代表行反查 | `WHERE x.ProductId = a.ProductId AND x.FactoryId = a.FactoryId AND x.WorkcenterId = a.WorkcenterId AND x.ProductionLotNO = a.ProductionLotNO` |
| `StockQty` 子查询 | 增加 `y.FactoryId = a.FactoryId AND y.WorkcenterId = a.WorkcenterId` |
| 工厂/仓库列 | 直接取 `a.FactoryId / a.WorkcenterId`（分配时必填，不做空值回退） |
| 排序 | 追加 `a.FactoryId, a.WorkcenterId` |

**为什么**：已分配列表是仓库人员"看哪一行、点哪个取消"的依据，必须显示该行真实所属仓库及其库存。

### 5.3 `AutoAssign`（约 L383–L689）

| 改动点 | 说明 |
|---|---|
| `#AutoLots` 表结构 | 增加 `FactoryId char(12)`、`WorkcenterId char(12)` 两列 |
| 可分配批次装载（约 L510–L548） | `GROUP BY` 改为四字段；`HAVING` 与 `alloc` 子查询同样四字段；`ROW_NUMBER()` 排序追加 `FactoryId, WorkcenterId` |
| 工厂过滤 | 工单循环开始时解析 `@CurStockFactoryId`，装载 `#AutoLots` 时追加 `AND wri.FactoryId = @CurStockFactoryId`；工单无工厂/库存工厂不存在时跳过并记入提示清单 |
| 循环取值 | 新增 `@CurFactoryId`、`@CurWorkcenterId`，每轮先清空再读取 |
| `INSERT` 写记录（约 L596–L639） | `FactoryId`、`WorkcenterId` 由 `NULL` 改为实际值 |
| 分配结果 `#AutoResult` | 可增加"分配仓库数"，便于前端提示（可选） |
| 未分配提示 | 工单内存在 `#AutoResult.RemainQty > 0` 的行（库存不足未分配完）时，记入 `@UnassignedMOList`，结束时提示"半成品库存不足，未分配完成"；与"需求为0""无工厂"提示并列返回 |

参考：

```sql
INSERT INTO dbo.MOSemiFinishedLotAllocation (
    ..., ProductionLotNO, FactoryId, WorkcenterId, CellId, ...
) VALUES (
    ..., @CurProductionLotNO, @CurFactoryId, @CurWorkcenterId, NULL, ...
)
```

**为什么要按四字段写入**：目前单物料行只会写一条 `ProductionLotNO` 记录；改造后同一批次在 A、B 仓会各写一条，后续确认 / 取消 / 扣数都靠这两列定位。

**FIFO 顺序**：仍以生产日期、入库日期为主；仓库只作为同日期下的稳定排序键，不代表按仓库优先。

### 5.4 `ConfirmLot`（约 L694–L914）

| 改动点 | 说明 |
|---|---|
| `#InsufficientLots` 的 `pending` | 按四字段 `GROUP BY` |
| `confirmed` 子查询 | 按四字段 `GROUP BY` |
| `inv` 库存子查询 | 按四字段 `GROUP BY`，并补 `LotStatus='1' AND IsStorage=1`（现状未过滤，会把锁定/非在库库存算进来，导致确认误放行） |
| 三表 JOIN | 由 `ProductId + ProductionLotNO` 改为**四字段全等匹配** |
| 报错信息 | 增加工厂/仓库，便于定位（例：`[批次][xxx][仓库][yyy]库存不足`） |
| SAP 同步明细 | 键由 `(ProductId, ProductionLotNO)` 改为 `(FactoryId, WorkcenterId, ProductId, ProductionLotNO)` |
| `OUTPUT ... INTO #ConfirmedRows` | **顺带修正**：当前 `#ConfirmedRows` 只定义 1 列，`OUTPUT INTO` 却写了 6 列，过程无法编译。应把临时表扩展为 6 列，或只捕获主键后回查 |

**为什么**：确认 = 转为全局永久占用。校验必须落在"这个仓库的这批货"上，否则 A 仓的库存会为 B 仓的理货背书。

### 5.5 `DeleteLot`（约 L919–L1004）

| 改动点 | 说明 |
|---|---|
| 取数 | 增加 `@DelFactoryId`、`@DelWorkcenterId` |
| 报错信息 | `[批次][xxx][工厂][yyy][仓库][zzz]已扣数，不允许取消分配` |
| 三态处理逻辑 | 不变（未确认→释放；已理货→保留占用仅置删除；已扣数→禁止） |
| SAP 同步明细 | 增加 `FactoryId`、`WorkcenterId`，否则 SAP 无法按库位回冲 |

**为什么**：取消是按行操作的，一行现在等于"某仓库的某批次量"，报错和同步都必须带仓库才能对上账。

### 5.6 `AllowBatch` / `GetMOProduct`

无需改动（按工单整体取反 / 仅返回提示）。
注意 `GetMOProduct` 与 `AutoAssign` 共用同一段代码，改动 5.3 后自动生效。

---

## 六、`MOLotSpecify_AssignReserveLotByProductionLotNo_DoMethod`（修改理货批次和数量）

### 改动位置：约 L72–L505

| 改动点 | 现状 | 改为 | 为什么 |
|---|---|---|---|
| XML 解析 `@Temp` | 列：`IsRowSelect, MOItemId, WWId, ProductionLotNO, Qty` | 增加 `FactoryId`、`WorkcenterId` 两列 | 同一批次多行提交时必须知道改的是哪个仓库 |
| `#TempResolved` | 只解析 `ProductionLotNO`；传 `WWId` 时只反查批次号 | 工厂/仓库必须由前端传入，任一为空直接报错；`ProductionLotNO` 未传时仍可由 `WWId` 反查 | 不做缺省维度反查，缺维度说明前端未升级，直接阻断避免写入错误仓库 |
| `#TempSelected` | `GROUP BY ProductionLotNO, MOItemId` | `GROUP BY ProductionLotNO, MOItemId, FactoryId, WorkcenterId` | 否则两仓数量被相加，重分配时无法区分 |
| 预检 `inv` / `other`（约 L278–L313） | 按 `ProductionLotNO` 汇总 | 按四字段汇总；`other` 子查询也按四字段排除本物料行 | 保证预检与后续分配口径一致 |
| `#CurLots`（约 L346–L382） | `GROUP BY inv.ProductionLotNO`；`other` 只按批次汇总 | 四字段分组 + 四字段 JOIN；`AvailableQty` 按四字段计算 | 同上 |
| 人工指定数量取值（约 L406–L413） | `WHERE ProductionLotNO = @SelProductionLotNO` | 增加 `AND FactoryId = @SelFactoryId AND WorkcenterId = @SelWorkcenterId` | 两仓同批次各有指定数量，不能串用 |
| `INSERT` 写记录（约 L445–L488） | `FactoryId`、`WorkcenterId` 写 `NULL` | 写实际值 | 与主流程保持一致 |
| `#CurLots` 排序 | 生产日期 → 入库日期 → 批次号 | 追加 `FactoryId, WorkcenterId` | 稳定排序 |

### 六.1 重分配改造：Upsert 语义（**本次改造必做**）

**现状**：过程按 `MOItemId` 先全量 `UPDATE ... SET DeleteFlag='1', IsOccupyAllocatedQty=0, ConfirmStatus='0'`
把该物料行所有记录（含已扣数、已理货、未确认）都"取消 + 重置"，然后再 `INSERT` 新的理货行。
这条路径存在的问题：

1. **已扣数行被一并取消** —— 已扣数是永久状态（`ConfirmStatus='1', IsOccupyAllocatedQty=0`），
   表示"已理货并已扣完料"。把它重新置成"未确认已释放"（`0/0/1`）会导致：
   - 仓库界面上已扣数行消失，变成一条刚被取消的记录；
   - 后续 SAP 同步若按"取消分配"上报，会让 SAP 误以为这一行从未被理货过。
2. **已理货行被重置状态** —— 按已确认状态机，已理货行（`1/1/0`）取消后应为 `1/1/1`（保留占用仅置删除标记），
   而不是 `0/0/1`。当前写法会把全局永久占用误重置成本次分配占用。
3. **已理货 / 已扣数行对应的 SAP 同步无法正确表达** —— "取消后重插"在 SAP 侧表现为
   "先取消 50 → 再新增 30"，而实际业务意图只是"把理货量从 50 改成 30"。

**改造为 Upsert（MERGE 语义）**：

> 重分配 = 对"原本就存在的同维度行"做**更新**（保留状态、修正数量），
> 对"原本不存在的新维度行"做**插入**；对"这次不再需要的旧行"单独走取消逻辑（`DeleteLot` 三态判定）。

伪代码：

```sql
BEGIN TRANSACTION TallyReassign;

-- Step 1. 把前端选中的行解析进 @TempSelected（已按四字段 GROUP BY）

-- Step 2. 【更新】同维度已存在记录：保留状态、只改数量
UPDATE a
SET a.Qty        = t.SelQty,        -- 用用户指定的新数量替换
    a.ModifyDate = GETDATE()
OUTPUT inserted.MOSemiFinishedLotAllocationId, deleted.Qty, inserted.Qty
    INTO @UpdatedRows (MOSemiFinishedLotAllocationId, OldQty, NewQty)
FROM dbo.MOSemiFinishedLotAllocation a
INNER JOIN @TempSelected t
    ON t.MOItemId         = a.MOItemId
   AND t.FactoryId        = a.FactoryId
   AND t.WorkcenterId     = a.WorkcenterId
   AND t.ProductionLotNO  = a.ProductionLotNO
WHERE a.DeleteFlag = '0';           -- 仅更新未删除行

-- Step 3. 【插入】前端有、库内没有的维度行（即全新理货）
INSERT INTO dbo.MOSemiFinishedLotAllocation (
    MOId, MOItemId, ProductId, FactoryId, WorkcenterId, ProductionLotNO,
    Qty, UOMId, ConfirmStatus, IsOccupyAllocatedQty, DeleteFlag,
    CreateDate, CreateUserId, Allow_batch, ...
)
SELECT ..., t.SelQty, ..., '0', 1, '0', GETDATE(), @I_OrBitUserId, ...
FROM @TempSelected t
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.MOSemiFinishedLotAllocation a
    WHERE a.MOItemId         = t.MOItemId
      AND a.FactoryId        = t.FactoryId
      AND a.WorkcenterId     = t.WorkcenterId
      AND a.ProductionLotNO  = t.ProductionLotNO
      AND a.DeleteFlag = '0'
);

-- Step 4. 【取消】库内有、前端没有的维度行（原本分配过这次不选了）
-- 严格复用 DeleteLot 三态判定，这里只给 UPDATE 逻辑，实际调用 DeleteLot 更稳妥
UPDATE a SET ...
FROM dbo.MOSemiFinishedLotAllocation a
WHERE a.MOItemId = @CurMOItemId AND a.DeleteFlag = '0'
  AND NOT EXISTS (SELECT 1 FROM @TempSelected t WHERE ...四字段...)
  AND a.IsOccupyAllocatedQty = 1;   -- 已扣数行（IsOccupyAllocatedQty=0）跳过，原样保留

-- Step 5. SAP 同步：把 @UpdatedRows + 取消行明细一起上报
IF @SapRet <> 0 BEGIN ROLLBACK ...; RETURN -1 END

COMMIT TRANSACTION TallyReassign;
```

**三态保留规则**（Step 2 / Step 3 / Step 4 都必须遵守）：

| 行状态 | 本次动作 | 处理方式 |
|---|---|---|
| 未确认（`0/1/0`） | 仍选、数量变化 | 更新 Qty；状态保持 `0/1/0` |
| 已理货（`1/1/0`） | 仍选、数量变化 | 更新 Qty；状态保持 `1/1/0`；SAP 同步上报"改理货量" |
| 已扣数（`1/0/0`） | 仍选 / 不选 | **原样保留，跳过**（由 PDA 扣料流程管理，不允许重分配触碰） |
| 已理货（`1/1/0`） | 不再选 | 走 `DeleteLot` 三态：置 `1/1/1`，保留占用，SAP 上报取消 |
| 未确认（`0/1/0`） | 不再选 | 置 `0/0/1`，释放占用 |

**为什么这样改**：

- 已扣数行是物料已经被实际扣走的证据，数量由 `LoadingItemLotRecord` 决定，任何"手工改数量"的入口都不应该能触碰它；
- 已理货行的数量调整需要 SAP 侧同步调整占用，当前"取消 + 重插"会让 SAP 产生多余的取消/新增过账；
- Upsert 让"重分配"在业务语义上等于"把理货明细改成这份新清单"，而不是"推倒重来"。

---

## 七、`PDA_FPInkCheckInput_PL`（按理货数据灌墨）

### 7.1 扫描批次取数（约 L1028–L1035）

新增变量并取库存行维度：

```sql
DECLARE @MFactoryId char(12) = '', @MWorkcenterId char(12) = ''

SELECT @WWId = WWId, @MLotId = LotId, @MLotSN = LotSN, @MProductId = ProductId,
       @DateCode = ProductionLotNO, @MLotProductionLotNO = ProductionLotNO,
       @LotAvailableQty = Qty,
       @MFactoryId = FactoryId, @MWorkcenterId = WorkcenterId      -- 【新增】理货维度
FROM dbo.WW_RMInventory
WHERE LotSN = @InputScan AND LotStatus = '1' AND IsStorage = 1 AND Qty > 0
```

**为什么**：PDA 扫描的是 MES 批次（容载器 → `BoxLotSn` → `LotSN`），而理货锁的是"仓库里的 SAP 批次量"。必须由扫描批次反查其工厂/仓库，才能匹配到唯一一条理货记录。

### 7.2 理货准入校验（约 L1119–L1136）

```sql
IF NOT EXISTS (
    SELECT 1
    FROM dbo.MOSemiFinishedLotAllocation a
    WHERE a.MOId = @MOId AND a.MOItemId = @IssueMOItemId AND a.ProductId = @MProductId
      AND a.DeleteFlag = '0' AND a.IsOccupyAllocatedQty = 1 AND a.ConfirmStatus = '1'
      -- 【新增】必须同一工厂、同一仓库，避免用 A 仓批次去扣 B 仓的理货
      AND a.FactoryId = @MFactoryId AND a.WorkcenterId = @MWorkcenterId
      AND ( a.LotSN = @InputScan
            OR (ISNULL(a.LotSN, '') = '' AND ISNULL(a.ProductionLotNO, '') <> ''
                AND a.ProductionLotNO = @MLotProductionLotNO) )
)
```

### 7.3 理货数量取数（约 L1140–L1145）

`@TallyQty` 的 `WHERE` 条件同步加 `FactoryId / WorkcenterId`，保证取到的是**本仓库**理货量，而不是该 SAP 批次全部仓库合计。

### 7.4 已扣数量统计（约 L1157–L1166）

现状按 `WRI.ProductionLotNO` 汇总，需要改为按四字段：

```sql
SELECT @TallyUsedQty = ISNULL(SUM(ISNULL(LIR.Qty, 0)), 0)
FROM dbo.LoadingItemLotRecord LIR
    INNER JOIN dbo.LoadingItemLotDetail LID ON LID.LoadingItemLotDetailId = LIR.LoadingItemLotDetailId
    INNER JOIN dbo.WW_RMInventory WRI ON WRI.LotSN = LIR.LotSN
WHERE LID.MOItemId = @IssueMOItemId
  AND LID.LoadingItemLotId = @LoadingItemLotId
  AND WRI.FactoryId = @MFactoryId
  AND WRI.WorkcenterId = @MWorkcenterId
  AND WRI.ProductionLotNO = @MLotProductionLotNO
```

> 已扣数量统计口径现已明确：**按四字段 + 全工单物料行累计**（即同一工单物料行下，同工厂同仓库同 SAP 批次的所有扫码数量累加），
> 与本次"严格等于理货量"的触发条件保持一致，不再区分 `LoadingItemLotId`。

### 7.5 扫码数量严格匹配（**本次改造必做**）

**现状**：灌墨允许人工填写 `@InputNumber` 扣数数量；已扣数标记是"实际扣减量 ≥ 理货量才置 0"。
这条路径下仓库可以只扫一部分就报工完工，SAP 侧会多扣未实际扣掉的量。

**改造为"扫码严格匹配 + 流程结束约束"**：

1. **移除手工填写扣数数量的入口** —— `@InputNumber` 分支直接返回错误 `"ServerMessage:本次灌墨不支持手工填写数量，请扫描批次完成扣数"`；
2. **扫码数量由 MES 批次剩余可用量决定** —— 每次扫描的扣减量 = `MIN(WW_RMInventory.Qty, 同维度剩余理货数量)`，不允许人工覆盖；
3. **单维度累计扫码量严格等于理货量**：

```sql
-- 每次扫描后，实时核对"本维度累计扫码量"是否达到该维度理货量
IF EXISTS (
    SELECT 1 FROM dbo.MOSemiFinishedLotAllocation a
    WHERE a.MOId = @MOId AND a.MOItemId = @IssueMOItemId
      AND a.FactoryId = @MFactoryId AND a.WorkcenterId = @MWorkcenterId
      AND a.ProductionLotNO = @MLotProductionLotNO
      AND a.DeleteFlag = '0' AND a.IsOccupyAllocatedQty = 1 AND a.ConfirmStatus = '1'
      AND EXISTS (
          SELECT 1 FROM dbo.LoadingItemLotRecord LIR
          INNER JOIN dbo.LoadingItemLotDetail LID ON LID.LoadingItemLotDetailId = LIR.LoadingItemLotDetailId
          INNER JOIN dbo.WW_RMInventory WRI ON WRI.LotSN = LIR.LotSN
          WHERE LID.MOItemId = @IssueMOItemId
            AND WRI.FactoryId = @MFactoryId
            AND WRI.WorkcenterId = @MWorkcenterId
            AND WRI.ProductionLotNO = @MLotProductionLotNO
          GROUP BY WRI.FactoryId, WRI.WorkcenterId, WRI.ProductionLotNO
          HAVING SUM(ISNULL(LIR.Qty, 0)) <> a.Qty      -- 累计扫码 ≠ 理货量
      )
)
BEGIN
    -- 未扫满，不允许置已扣数，提示继续扫
    RETURN N'ServerMessage:[批次][' + @MLotProductionLotNO + N'][工厂][' + @MFactoryId + N'][仓库][' + @MWorkcenterId + N']已扫码[' + @TallyUsedQty + N']/理货[' + @TallyQty + N']，请继续扫描';
END
```

4. **流程结束约束** —— 调用 `MakingComplete` / 报工 / 批次下线三处触发点，全部必须先通过校验：

```sql
-- 【流程结束校验】本工单该物料行所有有效理货维度的累计扫码量 = 理货量
IF EXISTS (
    SELECT 1 FROM dbo.MOSemiFinishedLotAllocation a
    WHERE a.MOId = @MOId AND a.MOItemId = @IssueMOItemId
      AND a.DeleteFlag = '0' AND a.IsOccupyAllocatedQty = 1 AND a.ConfirmStatus = '1'
      AND NOT EXISTS (
          -- 累计扫码 = 理货量的维度已完成，跳过
          SELECT 1 FROM dbo.LoadingItemLotRecord LIR
          INNER JOIN dbo.LoadingItemLotDetail LID ON LID.LoadingItemLotDetailId = LIR.LoadingItemLotDetailId
          INNER JOIN dbo.WW_RMInventory WRI ON WRI.LotSN = LIR.LotSN
          WHERE LID.MOItemId = @IssueMOItemId
            AND WRI.FactoryId = a.FactoryId
            AND WRI.WorkcenterId = a.WorkcenterId
            AND WRI.ProductionLotNO = a.ProductionLotNO
          GROUP BY WRI.FactoryId, WRI.WorkcenterId, WRI.ProductionLotNO
          HAVING SUM(ISNULL(LIR.Qty, 0)) = a.Qty
      )
)
BEGIN
    ROLLBACK TRANSACTION InkLoading;
    SET @I_ReturnMessage = N'ServerMessage:本物料行存在未扫满理货的批次，不允许结束流程';
    RETURN -1;
END
```

5. **已扣数置位** —— 校验通过后，**精确置位本维度**，禁止"一整行置 0"：

```sql
-- 【置已扣数】仅对累计扫码 = 理货量的维度置位
UPDATE A
SET A.IsOccupyAllocatedQty = 0, A.ModifyDate = GETDATE()
OUTPUT inserted.MOSemiFinishedLotAllocationId INTO @DeductedRows (MOSemiFinishedLotAllocationId)
FROM dbo.MOSemiFinishedLotAllocation A
WHERE A.MOId = @MOId AND A.MOItemId = @IssueMOItemId
  AND A.DeleteFlag = '0' AND A.IsOccupyAllocatedQty = 1 AND A.ConfirmStatus = '1'
  AND EXISTS (
      -- 该维度累计扫码 = 理货量
      SELECT 1 FROM dbo.LoadingItemLotRecord LIR
      INNER JOIN dbo.LoadingItemLotDetail LID ON LID.LoadingItemLotDetailId = LIR.LoadingItemLotDetailId
      INNER JOIN dbo.WW_RMInventory WRI ON WRI.LotSN = LIR.LotSN
      WHERE LID.MOItemId = @IssueMOItemId
        AND WRI.FactoryId = A.FactoryId
        AND WRI.WorkcenterId = A.WorkcenterId
        AND WRI.ProductionLotNO = A.ProductionLotNO
      GROUP BY WRI.FactoryId, WRI.WorkcenterId, WRI.ProductionLotNO
      HAVING SUM(ISNULL(LIR.Qty, 0)) = A.Qty
  );
```

**三处触发点统一走同一校验**（过站报工约 L1641、自动完成灌墨约 L2233、批次下线约 L2453），
第三处原按 `MOId` 整单置 0 的逻辑**直接删除**，改为按四维度逐行校验后再置位。

**SAP 同步**：校验通过后先置位 `@DeductedRows`，再同步 SAP"已扣数"报文，失败则回滚整个事务。

### 7.6 废弃手工输入数量分支

原约 L1796–L1809 的 `InputNumber` 分支（`@Command='InputNumber'` 或条件匹配），
本次改造中**整段废弃**，统一返回固定错误：

```sql
IF @Command = 'InputNumber' OR ISNULL(@InputNumber, '0') <> '0'
BEGIN
    SET @I_ReturnMessage = N'ServerMessage:本次灌墨不支持手工填写数量，请扫描批次完成扣数';
    RETURN -1;
END
```

**为什么**：扫码严格匹配要求"扣减量完全由批次可用量与剩余理货决定"，
任何人工输入都会打破这条闭环，导致 SAP 与 MES 数量不一致。

---

## 八、SAP 同步影响

| 动作 | 同步明细主键（改造后） |
|---|---|
| 已理货（ConfirmLot） | `FactoryId + WorkcenterId + ProductId + ProductionLotNO + Qty` |
| 取消分配（DeleteLot） | 同上，数量为取消量 |
| 已扣数（灌墨释放） | 同上，数量为理货量 |

- SAP 侧对应「工厂（WERKS）+ 库存地点（LGORT）+ 物料 + 批次」。
- `WorkcenterId` → SAP 库存地点的映射关系需确认（是否已存在于 `Workcenter` 表或维护表）；若没有，需要新增映射，否则接口无法落库位。
- 同步仍是**同步调用、失败回滚本地事务**，调用点已预留在 `ConfirmLot` / `DeleteLot` 的 COMMIT 之前，本次改造只是把明细键补齐。

---

## 九、其他受影响对象

| 对象 | 影响 | 处理建议 |
|---|---|---|
| `mmbe.sql` | 历史按 `a.LotSN` + `ConfirmStatus='1'` 统计 | **暂废弃，本次改造不处理**。后续如需恢复，需按四字段口径重写 |
| `zpp12.sql` | 历史汇总理货量 | **暂废弃，本次改造不处理**。后续如需恢复，需按四字段口径重写 |
| 前端理货网格 | 行标识、列 | 增加「工厂」「仓库」列；提交 XML 带 `FactoryId` / `WorkcenterId`；同批次多行需可见区分 |
| SAP 接口过程 `APISyncU_SemiFinishedTallyToSAP`（待创建） | 入参明细键 | 按上表四字段设计，预留 `WorkcenterId` 到 SAP 库位的映射 |

---

## 十、上线步骤

1. 建索引（第三节）；旧数据已清理，无需存量回填；
2. 发布四个存储过程（建议顺序：对话框脚本 → 主流程 → 手工指定 → PDA）；
3. 前端同步发布网格列与 XML 字段；
4. 按第十一节用例回归；
5. 观察 `MOSemiFinishedLotAllocation` 中 `FactoryId/WorkcenterId` 是否还有 `NULL`（新数据不应再产生）。

---

## 十一、测试用例

### 11.1 维度与分配（基础）

| # | 场景 | 预期 |
|---|---|---|
| T1 | 同一 SAP 批次 A 仓 60、B 仓 40，工单需求 80，自动分配 | 生成两行：A 仓 60 + B 仓 20（FIFO 顺序），总数 80；不出现一行 80 |
| T2 | 打开"可分配批次"对话框 | 同批次显示两行，工厂/仓库不同，各自可分配数量正确 |
| T3 | 手工指定 A 仓数量为 30 | 只改 A 仓行，B 仓行不变 |
| T4 | A 仓库存被其他单据占用后确认理货 | 确认被拒绝，提示对应批次与仓库库存不足 |
| T4a | MO 工厂为 9502，库存仅有 9302 的同批次 | 对话框与自动分配均不出现该批次；不可分配 |
| T4b | MO 工厂为 9302，库存有 9502 与 9302 同批次各 50 | 只出现 9302 的 50；9502 的 50 不可分配 |
| T4c | MO 工厂为 9304，库存有 9502 与 9302 同批次各 50 | 只出现 9502 的 50；9502 即受托工厂的共享库存 |
| T4d | MO 未维护 FactoryId | 对话框返回错误（GetInventory 已废弃）；AutoAssign 跳过并提示该工单 |

### 11.2 Upsert 重分配

| # | 场景 | 预期 |
|---|---|---|
| T5 | 重分配：原 A 仓已理货 50 → 改成 30，A 仓行存在 | 该行 Qty 更新为 30；状态保持 `1/1/0`；SAP 同步"改理货量 50→30" |
| T6 | 重分配：原 A 仓已扣数 50（`1/0/0`） → 改成 30 | **原样保留**，已扣数行不被触碰；事务返回成功但该行无变化 |
| T7 | 重分配：原 A 仓未确认 40（`0/1/0`） → 改成 60，且 A 仓库存只剩 50 | 预检报错"A 仓库存不足"，事务回滚；数据库不变 |
| T8 | 重分配：原选 A 仓 50 + B 仓 50，现只选 A 仓 30 | A 仓行更新为 30；B 仓行走取消三态（已理货→`1/1/1`，未确认→`0/0/1`）；已扣数行跳过 |
| T9 | 重分配：原无 C 仓行，本次新增 C 仓 20 | 新增一行，状态 `0/1/0`；SQL INSERT 触发 |
| T10 | 重分配：已扣数行（A 仓 50 `1/0/0`）仍选入新清单 | 已扣数行**原样保留**；新清单的其他正常行正常更新/插入；已扣数行不参与 SAP 同步 |

### 11.3 扫码数量严格匹配

| # | 场景 | 预期 |
|---|---|---|
| T11 | 理货 A 仓批次 50，扫 A 仓 MES 批次扣 50 | 扣减成功；该维度累计扫码 = 理货量 |
| T12 | 理货 A 仓批次 50，扫 A 仓 MES 批次扣 30 后报工 | 报工被拒绝，提示"A 仓批次已扫码 30/理货 50，请继续扫描"；事务回滚 |
| T13 | 理货 A 仓 50 + C 仓 D 批次 50，只扫完 A 仓就尝试报工 | 报工被拒绝，提示"存在未扫满理货的批次"；C 仓行仍为已理货 |
| T14 | 用 A 仓 MES 批次扫超过 50 扣 60 | PDA 自动取 `MIN(剩余理货, 库存)` = 50，剩余库存 10 保留；不允许人工填 60 |
| T15 | 扫完所有维度（A 仓 50 + C 仓 50 = 100）后报工 | 三处校验全部通过；两个维度同时置 `IsOccupyAllocatedQty=0`；SAP 已扣数同步成功 |
| T16 | 手动填写 `InputNumber` 任何值 | 直接返回错误"不支持手工填写数量"；不执行任何事务 |

### 11.4 流程结束边界

| # | 场景 | 预期 |
|---|---|---|
| T17 | 理货 2 个维度，各扫完一个，另一个还剩 1 没扫 | 报工被拒绝；已扫完的维度**不得提前置已扣数**（仍保持 `1/1/0`） |
| T18 | 工单物料行有 3 个理货维度，2 个已扫完，第三个因库存不足无法扫满 | 报工被拒绝；错误提示中包含未扫满的维度清单；已完成的 2 个不得提前置已扣数 |
| T19 | 工单只有 1 个理货维度，扫码量 = 理货量 = 1 | 报工通过；该维度置 `IsOccupyAllocatedQty=0`；SAP 同步"已扣数" |
| T20 | 工单 0 个理货维度（不需要半成品） | `NOT EXISTS` 子查询直接通过；报工正常走原逻辑，无已扣数置位 |
| T21 | 扫码累计量因 `LoadingItemLotRecord` 脏数据（重复行）导致 SUM ≠ 理货量 | 校验失败，报工被拒绝；需先清理脏数据（数据库层面加唯一约束建议：`LoadingItemLotDetailId + LotSN` 唯一） |

### 11.5 SAP 同步事务

| # | 场景 | 预期 |
|---|---|---|
| T22 | ConfirmLot 校验通过、SAP 已理货同步返回失败 | 本地事务回滚；理货记录保持 `0/1/0` 未确认状态 |
| T23 | DeleteLot 取消已理货行、SAP 取消同步失败 | 本地事务回滚；该行仍为 `1/1/0`，未被置为 `1/1/1` |
| T24 | 报工校验通过、已扣数置位完成后 SAP 同步失败 | 本地事务回滚；该行恢复为 `1/1/0`，已扣数动作不落地 |

---

## 十二、风险与待确认

1. **前端是否支持同批次多行**：网格行标识不能再用 `ProductionLotNO`，需要 `WWId` 或四字段组合；需要前端确认。
2. **`WorkcenterId` → SAP 库存地点映射**是否已存在，若缺失则 SAP 同步无法落地库位。
3. ~~**多仓库存量分配**无法自动回填~~ —— **旧数据已清理，无需回填，本条关闭**。
4. **Upsert 三态保留规则**：实现复杂度较高（已扣数跳过、已理货更新、未确认更新/取消、取消行走 DeleteLot 三态），建议按伪代码分步验证，每一步单独写单元测试。
5. **流程结束校验的性能**：每次报工/完工/下线都要跑 `LoadingItemLotRecord` 按四字段 `GROUP BY` 的 `SUM` 聚合；需确认 `LoadingItemLotDetailId + LotSN` 是否有索引，或考虑在表上加外键约束与统计维护。
6. **`ConfirmLot` 的 `#ConfirmedRows` 列数不匹配**是当前已存在的编译级缺陷（临时表只定义 1 列，`OUTPUT INTO` 却写了 6 列），建议在本次改造中一并修复。
7. ~~报表（`mmbe` / `zpp12`）与外部查询若有按 `ProductionLotNO` 单独匹配理货记录的写法~~ —— **已确认暂废弃，本次改造不处理**。
8. **工厂映射硬编码**：`9502/9304 → 9502`、`9302 → 9302` 目前以 `CASE` 写死在过程里。若后续新增工厂或调整受托关系，必须同步修改对话框脚本与主流程两处；建议后续收敛为配置表或标量函数。
9. ~~**手工指定过程尚未加工厂校验**~~ —— **已在 Step 3 实现**：`MOLotSpecify_AssignReserveLotByProductionLotNo_DoMethod` 在解析出选中维度后校验「维度工厂 = 工单允许库存工厂」，并禁止修改已扣数行。
