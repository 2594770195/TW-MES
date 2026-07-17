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

- [ ] 5. 改造 `InputScanDefocus` 墨水扫描段
  - 移除 `PickingListItemLot` 已领料校验
  - 增加 `MOSemiFinishedLotAllocation` 有效占用分配校验
  - 增加批次可用量与剩余需求计算

- [ ] 6. 增加超量扫描数量确认分支
  - 可用量大于剩余需求时扫描仅返回建议数量
  - 设置 `Command='MLotSNScan'` 与 `@I_ExceptionFieldName='InputNumber'`

- [ ] 7. 改造 `InputNumberDefocus` 数量确认
  - 重算预分配余额与剩余需求
  - 校验确认数量不超过可用量与剩余需求
  - 通过后写入上料、投料与数据链记录

- [ ] 8. 自动完工路径接入领料与释放
  - 调用 `PDA_ProductionMakingSubmit MakingComplete`
  - 过站报工成功后释放 `IsOccupyAllocatedQty`

- [ ] 9. `CMDLOTMOVE` 路径接入领料与释放
  - 与自动完工保持相同顺序与失败策略

- [ ] 10. 补充中文注释
  - 每段校验、计算、领料、释放逻辑前添加中文注释

---

## 阶段三：测试与上线

- [ ] 11. 扫描校验回归
  - 未指定批次、已释放批次、其他工单批次均应阻断
  - 有效指定批次可正常进入灌墨

- [ ] 12. 数量确认回归
  - 可用量大于需求：扫描不写库，确认后写入
  - 可用量小于等于需求：扫描自动写入
  - 非法数量、超可用量、超剩余需求均应阻断

- [ ] 13. 完工领料回归
  - 自动完工与 `CMDLOTMOVE` 均生成当前会话生产领料单
  - 领料失败时不继续过站
  - `LoadingItemLotRecord.IsPicking` 正确更新

- [ ] 14. 占用释放回归
  - 实际使用批次 `IsOccupyAllocatedQty` 变为 0
  - 未使用批次与其他会话记录不受影响

- [ ] 15. 更新 `readme.md` 指向本 spec 目录
- [ ] 16. 提交 DBA 审批部署

---

## 执行门禁

进入阶段二 SQL 实现需同时满足：
1. 阶段一任务 1–4 已完成并经确认
2. 用户明确发送「按 spec 实现」或等价执行指令
