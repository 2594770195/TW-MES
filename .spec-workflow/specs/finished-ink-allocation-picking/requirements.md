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
- 按预分配余额与工单剩余需求控制实际使用数量。
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

### F-002 批次可用量计算
按预分配余额扣除当前上料会话已使用量，计算本次可灌墨数量。

验收标准：
- [ ] `批次可用量 = SUM(占用分配Qty) - SUM(当前LoadingItemLot中该批次已用Qty)`。
- [ ] 占用分配仅统计 `DeleteFlag='0' AND IsOccupyAllocatedQty=1` 的记录。
- [ ] 已用数量仅统计当前 `LoadingItemLotId` 下对应 `MOItemId + LotSN` 的 `LoadingItemLotRecord.Qty`。
- [ ] 批次可用量小于等于 0 或工单物料剩余需求小于等于 0 时阻断。

### F-003 超量扫描数量确认
当批次可用量大于工单物料剩余需求时，扫描阶段只返回建议数量，不写库。

验收标准：
- [ ] 扫描事件返回 `InputNumber=剩余需求`、`Command='MLotSNScan'`，并 `RETURN 0`。
- [ ] 扫描阶段不写入 `LoadingItemLotDetail`、`LoadingItemLotRecord`、`DataChainAssyIssue`。
- [ ] `InputNumberDefocus` 在 `Command='MLotSNScan'` 时重新计算余额并校验确认数量。
- [ ] 确认数量合法后才写入实际使用记录与投料数据链。

### F-004 可用量内自动写入
当批次可用量小于或等于工单物料剩余需求时，维持现有扫描即写入行为。

验收标准：
- [ ] 自动使用数量取当前批次可用量。
- [ ] 写入 `LoadingItemLotDetail`、`LoadingItemLotRecord`、`DataChainAssyIssue`。
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
- 工单物料剩余需求：沿用现有 `@MQtyRequired - @MActualQty` 口径。
- 半成品范围：`Product.ProductClassify='2'`。
- 错误提示：遵循 OrBit 规范，参数相关异常须带出具体参数值，格式 `ServerMessage:[字段名][参数值]描述`。

---

## 4. 风险与控制

- 防止超分配使用：写入前重新计算批次可用量与剩余需求。
- 防止未领料即过站：领料单生成失败时不允许继续完工。
- 防止误释放：仅释放当前会话实际使用批次对应的分配记录。
- 防止字段猜测：实现前必须以 `MES/table/` 表结构为准。
- 生产部署：除 SELECT 外须 DBA 审批后执行。

---

## 5. 关联规格

- 预分配写入：`.spec-workflow/specs/finished-mo-semifinished-lot-allocation/`
- 本规格负责 PDA 灌墨消费预分配、数量确认、完工领料与占用释放。
