# Requirements: 成品灌墨指定批次与完工领料

## 状态
- **状态**：草稿 Draft
- **创建日期**：2026-07-17
- **范围**：改造 PDA 成品灌墨流程，由“先领料后灌墨”改为“先指定批次后灌墨，完工前再领料”
- **目标对象**：`PDA_FPInkCheckInput`、`MOSemiFinishedLotAllocation`、`LoadingItemLot*`、`PickingList*`
- **上游依赖**：`.spec-workflow/specs/finished-mo-semifinished-lot-allocation/`（半成品批次预分配）

---

## 1. 背景与目标

### 1.1 背景
当前 `PDA_FPInkCheckInput` 在扫描墨水批次时，校验该批次是否已通过 `PickingListItemLot` 完成领料。业务已引入 `MOSemiFinishedLotAllocation` 预分配台账，投产前即可指定半成品批次，灌墨环节应消费预分配记录，而非要求提前领料。

### 1.2 目标
- 灌墨扫描以预分配记录作为批次准入条件。
- 实际使用数量可超过预分配数量，但批次必须是当前工单已预分配且仍占用的批次。
- 每次确认实际使用数量时，同步扣减对应批次库存，并写入完整批次追溯与上料数据链。
- 按扣减后的库存可用量与工单剩余需求控制实际使用数量。
- 扫描工单时校验当前已分配批次的库存是否覆盖分配数量；库存不足时要求仓库重新分配。
- 批次可用量大于剩余需求时，由 PDA 数量框确认后再写入使用记录。
- 自动完工或手工批次下线前，为当前上料会话生成生产领料单。
- 完工成功后释放实际使用批次的预分配占用，保留历史记录。

### 1.3 非目标
- 不改造 `MOSemiFinishedLotAllocationDoMethod` 的分配 UI 与分支。
- 不改造 WMS/SAP 同步流程。
- 不新增前端页面或后端 API。
- 不修改 `MOSemiFinishedLotAllocation` 表结构。

---

## 2. 功能需求

### F-001 扫描指定批次准入
成品灌墨扫描半成品批次时，校验当前工单、工单物料、批次号存在有效且占用中的预分配记录。

验收标准：
- [ ] 不再以 `PickingListItemLot` 是否已领料作为扫描准入条件。
- [ ] 校验 `MOSemiFinishedLotAllocation` 中存在 `MOId + MOItemId + LotSN` 一致且 `DeleteFlag='0' AND IsOccupyAllocatedQty=1` 的记录。
- [ ] 批次须存在于 `WW_RMInventory`，且 `IsStorage=1`、`Qty>0`。
- [ ] 批次物料须为当前工单 BOM 中的半成品（`ProductClassify='2'`）。
- [ ] 同一工单任务中重复扫描同一批次时阻断。
- [ ] 未指定、已释放或不属于当前工单的批次返回包含批次号的 `ServerMessage` 并 `RETURN -1`。

### F-002 扫描工单时校验分配批次库存
扫描工单并取得当前工单的有效预分配记录后，按工单物料校验已分配批次的库存总量是否覆盖分配数量；不足时阻断灌墨，要求仓库重新分配。

验收标准：
- [ ] 仅统计 `DeleteFlag='0' AND IsOccupyAllocatedQty=1` 的预分配记录。
- [ ] 按 `MOItemId + ProductId + LotSN` 汇总预分配 `Qty`，避免同一批次存在多条分配记录时重复计算库存。
- [ ] 按相同物料与批次读取 `WW_RMInventory` 中 `LotStatus='1' AND IsStorage=1` 的 `Qty` 并汇总。
- [ ] 任一工单物料的已分配批次库存总量小于该物料的分配数量总量时，返回包含工单号和物料号的 `ServerMessage` 并 `RETURN -1`，提示“当前分配批次库存不足，请仓库重新分配”。
- [ ] 无有效预分配记录的工单物料不参与本校验；后续扫描该物料批次时仍由 F-003 准入规则阻断。

### F-003 扫描指定批次与可用量计算
实际使用数量不受预分配数量限制；只要批次属于当前工单有效预分配记录，即可使用，但不得超过该批次当前库存可用量或工单物料剩余需求。库存会在每次实际使用记录写入时同步扣减，因此可用量直接取当前库存余额。

验收标准：
- [ ] 批次准入仍校验 `MOSemiFinishedLotAllocation` 中存在 `MOId + MOItemId + LotSN` 一致且 `DeleteFlag='0' AND IsOccupyAllocatedQty=1` 的记录，不校验本次使用量是否超过该记录的分配 `Qty`。
- [ ] `批次可用量 = SUM(WW_RMInventory.Qty)`；仅统计当前物料、批次且 `LotStatus='1' AND IsStorage=1` 的库存余额。
- [ ] 不再使用当前 `LoadingItemLotRecord` 的已用数量二次扣减，避免库存已扣减后重复扣减。
- [ ] 批次可用量小于等于 0 或工单物料剩余需求小于等于 0 时阻断。

### F-004 实际使用写入、扣库存与追溯
当批次可用量小于或等于工单物料剩余需求时，维持现有扫描即写入行为；无论扫描自动写入或数量确认写入，均须在同一事务内完成实际使用记录、库存扣减和批次追溯。

验收标准：
- [ ] 自动使用数量取当前批次可用量。
- [ ] 更新 `LoadingItemLotDetail.ActualQty`，并插入 `LoadingItemLotRecord`。
- [ ] 按扫描取得的库存主键 `WWId` 执行 `WW_RMInventory.Qty -= @UsedQty`；扣减前再次校验库存余额不少于 `@UsedQty`。
- [ ] 调用 `TxnBase_MLotTrack` 写入批次跟踪，备注包含扣减前库存、本次上料数量、扣减后库存和工单号。
- [ ] 调用 `TxnBase_DataChainMainLine` 并插入 `DataChainAssyIssue`，写入本次上料批次、物料、工单、工单物料和实际使用数量。
- [ ] 上述写入逻辑参照 `PDA_ProductionMaking_LotSNScan` 的 `@I_Sender='UsedQtyScan'` 分支（约 L781–895），字段和调用参数以实现时表结构与现有过程为准。
- [ ] 库存扣减、批次跟踪、上料记录和数据链任一步失败时，整体回滚，不保留部分写入。
- [ ] 累计实际用量达到需求后可触发自动完工逻辑。

### F-005 完工前生成生产领料单
自动完工与 `CMDLOTMOVE` 手工下线路径，在批次过站报工前先为当前上料会话生成生产领料单。

验收标准：
- [ ] 仅处理当前 `LoadingItemLot` 中 `LoadingItemLotRecord.IsPicking=0` 的实际使用记录。
- [ ] 领料单生成方式参照 `PDA_ProductionMakingSubmit` 的 `MakingComplete` 分支。
- [ ] 创建生产领料单头、工单关联、物料明细与批次明细。
- [ ] 更新 `MOItem.ItemQtyDone/ItemQtyIssued`，并将上料记录标记为 `IsPicking=1`。
- [ ] 领料失败时 `RETURN -1`，不继续过站报工。

### F-006 完工后释放预分配占用
过站报工成功后，释放当前会话实际使用批次对应的预分配占用。

验收标准：
- [ ] 将对应有效分配记录更新为 `IsOccupyAllocatedQty=0`，并更新 `ModifyDate`。
- [ ] 不逻辑删除分配记录，保留历史。
- [ ] 未实际使用的预分配记录继续占用。
- [ ] 其他工单、其他上料会话的分配记录不受影响。

---

## 3. 数据口径

- 有效分配记录：`MOSemiFinishedLotAllocation.DeleteFlag='0' AND IsOccupyAllocatedQty=1`。
- 有效库存：`WW_RMInventory.LotStatus='1' AND IsStorage=1 AND Qty>0`。
- 工单扫描库存校验：按 `MOItemId + ProductId + LotSN` 汇总分配 `Qty`，并按相同物料批次汇总库存 `Qty`；库存总量不得小于分配数量总量。
- 灌墨批次可用量：直接取当前批次在库 `WW_RMInventory.Qty`；每次写入实际使用记录时同步扣减库存，不再减当前上料会话已用数量。预分配 `Qty` 只作为批次准入和工单扫描库存校验依据，不限制实际使用数量。
- 工单物料剩余需求：沿用现有 `@MQtyRequired - @MActualQty` 口径。
- 半成品范围：`Product.ProductClassify='2'`。
- 错误提示：遵循 OrBit 规范，参数相关异常须带出具体参数值，格式 `ServerMessage:[字段名][参数值]描述`。

---

## 4. 风险与控制

- 防止超库存使用：写入前重新计算批次库存可用量与剩余需求。
- 防止库存与上料记录不一致：库存扣减、批次跟踪、`LoadingItemLotRecord` 和 `DataChainAssyIssue` 必须在同一事务中写入或回滚。
- 防止无库存分配：扫描工单时校验当前分配批次库存覆盖分配数量，不足时阻断并要求仓库重新分配。
- 逻辑保留：实施中不再使用的既有校验或计算必须以 SQL 注释保留，并在注释前说明替换原因；不得直接删除。
- 防止未领料即过站：领料单生成失败时不允许继续完工。
- 防止误释放：仅释放当前会话实际使用批次对应的分配记录。
- 防止字段猜测：实现前必须以 `MES/table/` 表结构为准。
- 生产部署：除 SELECT 外须 DBA 审批后执行。

---

## 5. 关联规格

- 预分配写入：`.spec-workflow/specs/finished-mo-semifinished-lot-allocation/`
- 本规格负责 PDA 灌墨消费预分配、数量确认、完工领料与占用释放。
