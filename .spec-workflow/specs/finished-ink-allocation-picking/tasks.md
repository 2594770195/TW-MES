# Tasks: 成品灌墨指定批次与完工领料

## 状态
- **状态**：待评审 Todo
- **创建日期**：2026-07-17
- **目标**：完成 PDA 成品灌墨指定批次改造的需求确认、SQL 实现与测试上线
- **关联规格**：`.spec-workflow/specs/finished-mo-semifinished-lot-allocation/`

---

## 阶段一：规格确认

- [ ] 1. 评审 `requirements.md` 业务规则与 F-001~F-006 验收标准
- [ ] 2. 评审 `design.md` 事件分支、数量口径与事务边界
- [ ] 3. 确认与 `finished-mo-semifinished-lot-allocation` 的职责边界
- [ ] 4. 确认错误提示格式符合 mes-sqlserver 规范

---

## 阶段二：SQL 实现（spec 通过后执行）

- [x] 5. 改造 `InputScanDefocus` 工单扫描段
  - 查询当前有效预分配记录，并按物料、批次汇总分配数量
  - 汇总相同物料、批次的在库 `WW_RMInventory.Qty`
  - 任一物料的已分配批次库存不足分配数量时，阻断并提示仓库重新分配

- [x] 6. 改造 `InputScanDefocus` 墨水扫描段
  - 将 `PickingListItemLot` 已领料校验和 `@BeginQty` 自动用量计算改为 SQL 注释保留，注明由预分配准入与实时库存校验替代
  - 增加 `MOSemiFinishedLotAllocation` 有效占用分配校验
  - 预分配数量只校验批次准入，不限制实际使用数量
  - 直接按当前批次 `WW_RMInventory.Qty` 计算可用量，不再减当前会话已用量

- [x] 7. 增加超量扫描数量确认分支
  - 可用量大于剩余需求时扫描仅返回建议数量
  - 设置 `Command='MLotSNScan'` 与 `@I_ExceptionFieldName='InputNumber'`

- [x] 8. 改造 `InputNumberDefocus` 数量确认
  - 重算批次库存可用量与剩余需求
  - 校验确认数量不超过可用量与剩余需求
  - 参照 `PDA_ProductionMaking_LotSNScan` 的 `UsedQtyScan` 分支，在同一上料事务内更新 `LoadingItemLotDetail`、扣减 `WW_RMInventory.Qty`、写入 `LoadingItemLotRecord`、批次跟踪和 `DataChainAssyIssue`
  - 自动写入路径复用相同的写入单元

- [x] 9. 自动完工路径接入领料与释放
  - 调用 `PDA_ProductionMakingSubmit MakingComplete`
  - 过站报工成功后释放 `IsOccupyAllocatedQty`

- [x] 10. `CMDLOTMOVE` 路径接入领料与释放
  - 与自动完工保持相同顺序与失败策略

- [ ] 11. 补充中文注释
  - 每段校验、计算、库存扣减、批次追踪、数据链、领料、释放逻辑前添加中文注释
  - 所有不再执行的既有 SQL 必须以注释保留并说明替代原因，不得直接删除

---

## 阶段三：测试与上线

- [ ] 12. 工单扫描库存校验回归
  - 已分配批次库存覆盖分配数量时可正常进入灌墨
  - 任一物料的已分配批次库存不足分配数量时阻断，并提示仓库重新分配

- [ ] 13. 扫描校验回归
  - 未指定批次、已释放批次、其他工单批次均应阻断
  - 有效指定批次可正常进入灌墨

- [ ] 14. 数量确认回归
  - 可用量大于需求：扫描不写库，确认后写入
  - 可用量小于等于需求：扫描自动写入
  - 已分配批次可实际使用超过分配数量，但不得超过库存可用量或剩余需求
  - 非法数量、超库存可用量、超剩余需求均应阻断
  - 每次确认或自动写入后，`WW_RMInventory.Qty` 按实际使用数量扣减一次，不因已存在 `LoadingItemLotRecord` 重复扣减
  - 库存扣减、`LoadingItemLotDetail`、`LoadingItemLotRecord`、批次跟踪与 `DataChainAssyIssue` 全部成功，或全部回滚

- [ ] 15. 完工领料回归
  - 自动完工与 `CMDLOTMOVE` 均生成当前会话生产领料单
  - 领料失败时不继续过站
  - `LoadingItemLotRecord.IsPicking` 正确更新

- [ ] 16. 占用释放回归
  - 实际使用批次 `IsOccupyAllocatedQty` 变为 0
  - 未使用批次与其他会话记录不受影响

- [ ] 17. 更新 `readme.md` 指向本 spec 目录
- [ ] 18. 提交 DBA 审批部署

---

## 执行门禁

进入阶段二 SQL 实现需同时满足：
1. 阶段一任务 1–4 已完成并经确认
2. 用户明确发送「按 spec 实现」或等价执行指令
