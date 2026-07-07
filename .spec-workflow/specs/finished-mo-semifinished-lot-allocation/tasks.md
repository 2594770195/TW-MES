# Tasks: 成品工单半成品批次分配

## 状态
- **状态**：待开发 Todo
- **创建日期**：2026-07-06
- **目标**：完成成品工单半成品批次预分配表结构、存储过程和基础验证

---

## 任务列表

### 阶段一：需求与字段确认

- [x] 1. 确认功能范围
  - 按 `@I_Sender` 区分 5 个功能：查询工单半成品需求、查询物料库存、查询已分配批次、输入 `LotSN` 分配、输入记录 ID 删除。
  - 本期只做数据库对象，不做前端和后端 API。
  - 本期只维护预分配记录，不直接扣减库存。

- [x] 2. 确认分配数量规则
  - 输入 `LotSN` 后自动分配。
  - 分配数量 = `MIN(当前工单半成品剩余需求, 当前批次可用库存)`。
  - 不额外增加手工输入分配数量参数。

- [x] 3. 确认半成品筛选规则
  - 只查询 `Product.ProductClassify='2'` 的半成品物料。
  - 工单物料行需满足 `LineSequence<>'000'` 且未删除。

- [x] 4. 复核核心表字段
  - `MO`：工单主表。
  - `MOItem`：工单物料需求。
  - `Product`、`ProductRoot`：物料主数据。
  - `WW_RMInventory`：库存批次。
  - `MOProductionLot` 已存在或被历史流程引用，本期改用新表名 `MOSemiFinishedLotAllocation`。

- [x] 5. 确认实际领料差异处理规则
  - 实际领料和预分配可能不同，但仍需保留预分配记录。
  - 新增 `IsOccupyAllocatedQty` 表字段控制是否占用已分配数量，默认 `1`。
  - 只有 `DeleteFlag='0'` 且 `IsOccupyAllocatedQty=1` 的记录参与已分配数量和已分配库存计算。
  - 本存储过程不增加 `IsOccupyAllocatedQty` 参数，也不提供调整占用标记功能。

---

### 阶段二：表结构开发

- [x] 6. 新增 `MES/table/MOSemiFinishedLotAllocation.sql`
  - 创建 `MOSemiFinishedLotAllocationId` 主键。
  - 保存 `MOId`、`MOName`、`MOItemId`、`ProductId`。
  - 保存 `WWId`、`LotSN`、`ProductionLotNO`。
  - 保存 `FactoryId`、`WorkcenterId`、`CellId`、`UOMId`。
  - 保存 `Qty` 分配数量。
  - 增加 `IsOccupyAllocatedQty` 是否占用已分配数量字段，默认 `1`。
  - 增加 `DeleteFlag` 逻辑删除字段，`0`=有效，`1`=删除，默认 `0`。
  - 增加 `CreateUserId`、`CreateUserName`、`CreateDate`、`ModifyDate`。

- [x] 7. 增加索引
  - `MOId + MOItemId + ProductId + DeleteFlag + IsOccupyAllocatedQty` 支持工单需求和已分配查询。
  - `LotSN + DeleteFlag + IsOccupyAllocatedQty` 支持批次已分配库存扣减。
  - `ProductId + DeleteFlag + IsOccupyAllocatedQty` 支持物料库存查询。

---

### 阶段三：存储过程开发

- [x] 8. 新增 `MES/procedure/MOSemiFinishedLotAllocationDoMethod.sql`
  - 使用 OrBit DoMethod 标准参数。
  - 增加 `@MOId`、`@MOName`、`@MOItemId`、`@ProductId`、`@LotSN`、`@MOSemiFinishedLotAllocationId`。
  - 不增加 `@IsOccupyAllocatedQty` 参数，新增记录默认占用。
  - 初始化 `@I_ReturnMessage`。

- [x] 9. 实现 `GetMOProduct`
  - 解析 `@MOId` 或 `@MOName`。
  - 查询工单半成品物料需求。
  - 汇总 `DeleteFlag='0'` 且 `IsOccupyAllocatedQty=1` 的占用分配记录。
  - 返回所需数量、已分配数量、剩余数量和物料信息。

- [x] 10. 实现 `GetInventory`
  - 根据 `@ProductId` 查询 `WW_RMInventory`。
  - 只取正常在库且数量大于 `0` 的批次。
  - `LotSN` 在库存表中默认唯一；若 `WW_RMInventory` 同一 `LotSN` 存在多行在库记录，视为异常，不参与查询。
  - 按 `LotSN` 汇总 `DeleteFlag='0'` 且 `IsOccupyAllocatedQty=1` 的已分配库存。
  - 返回库存、已分配库存、可用库存和库存位置。
  - 只返回可用库存大于 `0` 的记录。

- [x] 11. 实现 `GetAllocatedLots`
  - 解析 `@MOId` 或 `@MOName`。
  - 查询当前工单 `DeleteFlag='0'` 的有效分配记录。
  - 关联物料、库存、工厂、仓库、单位信息。
  - 返回 `IsOccupyAllocatedQty`，便于识别记录是否继续占用已分配数量。

- [x] 12. 实现 `AssignLot`
  - 校验 `@MOItemId` 和 `@LotSN`。
  - 校验工单物料行为半成品且未删除。
  - 校验批次存在、状态正常、在库、物料一致。
  - 事务内重新计算剩余需求和批次可用库存。
  - 插入 `MOSemiFinishedLotAllocation`，默认 `IsOccupyAllocatedQty=1`。
  - 返回新分配记录或成功提示。

- [x] 13. 实现 `DeleteLot`
  - 校验 `@MOSemiFinishedLotAllocationId`。
  - 事务内将 `DeleteFlag` 更新为 `1`。
  - 删除后不参与后续查询和库存扣减。

- [x] 14. 补充中文注释和错误处理
  - 每段校验、查询、事务、写入逻辑前添加中文注释。
  - 失败时设置 `@I_ReturnMessage='ServerMessage:...'` 并 `RETURN -1`。

---

### 阶段四：自检与验证

- [ ] 15. 字段与口径自检
  - 确认所有字段来自 `MES/table/` 真实表结构。
  - 确认可用库存扣减只统计 `DeleteFlag='0'` 且 `IsOccupyAllocatedQty=1` 的分配记录。
  - 确认 `LotSN` 唯一性仅约束 `WW_RMInventory`；分配表按 `LotSN` 汇总占用数量。
  - 确认不会修改库存数量、库存状态和正式领料数量。

- [ ] 16. 查询功能验证
  - 验证 `GetMOProduct` 返回半成品需求和剩余数量。
  - 验证 `GetInventory` 只返回可分配批次。
  - 验证 `GetAllocatedLots` 只返回当前工单有效记录。

- [ ] 17. 分配功能验证
  - 剩余需求小于批次可用库存时，按剩余需求分配。
  - 批次可用库存小于剩余需求时，按批次可用库存分配。
  - 批次物料不一致时阻断。
  - 无剩余需求或无可用库存时阻断。

- [ ] 18. 删除功能验证
  - 删除后已分配数量减少。
  - 删除后批次可用库存恢复。
  - 重复删除返回业务提示。

---

### 阶段五：文档与上线准备

- [ ] 19. 更新 `readme.md`
  - 记录新增规格目录。
  - 说明新增表和存储过程用途。
  - 说明部署前需 DBA 审批。

- [ ] 20. 准备部署说明
  - 表结构脚本先部署。
  - 存储过程脚本后部署。
  - 使用测试工单完成查询、分配、删除回归。
