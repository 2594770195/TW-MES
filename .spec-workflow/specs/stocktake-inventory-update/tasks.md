# Tasks: 库存盘点更新

## 状态
- **状态**：待开发 Todo
- **创建日期**：2026-06-18
- **目标**：完成 `WW_RMInventory` 库存盘点批量更新功能的开发、测试和上线准备

---

## 任务列表

### 阶段一：需求与字段确认

- [x] 1. 确认 Excel 输入模板
  - 字段固定为：工厂、仓库、物料号、库存数量、单位、SAP批号
  - 确认盘点来源不提供 MES 内部批号 `LotSN`
  - 确认 SAP批号 必填，`LotSN` 不作为必填字段和主匹配键
  - 确认同一工厂、仓库、物料号、SAP批号重复时阻断本次处理
  - 已补充模板说明：`input-template.md`

- [x] 2. 复核主数据字段映射
  - 确认 `Factory` 表使用 `FactoryName` 匹配工厂
  - 确认物料号通过 `ProductRoot.ProductName` 匹配，并关联 `Product.ProductRootId` 获取 `ProductId`
  - 确认 `Workcenter` 使用 `WorkcenterName` 匹配仓库，并限定同工厂
  - 确认 `UOM` 使用 `UOMName` 或 `ERPUnitcode` 匹配单位

- [x] 3. 确认 SAP 批号落库字段
  - 确认 Excel `SAP批号` 写入 `WW_RMInventory.ProductionLotNO`
  - 确认本期不同步写入 `SAPRemark`
  - 确认新增库存时 `LotSN` 使用系统批号规则 `WW_MP_LotSN` 生成，不使用盘点来源 `LotSN`

- [x] 4. 确认置出库范围
  - 确认处理本次盘点仓库内全部在库库存
  - 确认同一 SAP 批次下超出盘点数量的更旧库存批次需设置 `IsStorage=0`
  - 确认库存表中该仓库存在、但 Excel 中该仓库不存在的物料需设置 `IsStorage=0`

---

### 阶段二：存储过程开发

- [x] 5. 整理输入临时表 `#StocktakeData`
  - 定义 `RowNo`
  - 定义 `FactoryName`
  - 定义 `WarehouseName`
  - 定义 `ProductNo`
  - 定义 `StockQty`
  - 定义 `UOMName`
  - 定义必填 `SAPBatchNo`
  - 可选定义 `LotSN`，但不参与主匹配

- [x] 6. 完成全局校验逻辑
  - 校验临时表是否存在
  - 校验盘点数据不能为空
  - 校验必填字段不能为空
  - 校验库存数量不能小于 `0`
  - 校验同一工厂、仓库、物料、SAP批号不能重复

- [x] 7. 完成主数据解析逻辑
  - 将工厂名称解析为 `FactoryId`
  - 将仓库名称解析为 `WorkcenterId`
  - 将物料号解析为 `ProductId`
  - 将单位解析为 `UOMId`
  - 输出无法解析的数据行和原因

- [x] 8. 完成按仓库分组处理逻辑
  - 按 `WorkcenterId` 获取本次盘点仓库列表
  - 每个仓库单独开启事务
  - 单仓失败时回滚该仓
  - 继续处理后续仓库

- [x] 9. 完成已有库存更新逻辑
  - 按 `FactoryId + WorkcenterId + ProductId + ProductionLotNO` 匹配 `WW_RMInventory`
  - 使用 `SUM(inv.Qty) OVER (...)` 按 `CreateDate DESC, WWId DESC` 计算累计数量
  - 对累计数量未超过盘点数量的批次完整保留，原 `Qty` 不变
  - 对最后一个超过盘点数量的保留批次，将 `Qty` 调整为剩余需要数量
  - 对超出盘点数量的更旧批次设置 `IsStorage=0`
  - 更新 `UOMId`
  - 对保留批次设置 `IsStorage=1`
  - 更新 `ModifyDate`

- [x] 10. 完成缺失库存新增逻辑
  - 为新增记录生成 `WWId`
  - `LotSN` 不依赖盘点来源，使用系统批号规则 `WW_MP_LotSN` 生成
  - 写入 `Qty` 和 `OrgQty`
  - 写入 `FactoryId`、`WorkcenterId`、`ProductId`、`UOMId`
  - 将 Excel `SAP批号` 写入 `ProductionLotNO`
  - 设置 `IsStorage=1`
  - 写入 `CreateDate` 和 `ModifyDate`

- [x] 11. 完成 Excel 缺失 SAP 批次置出库逻辑
  - 限定当前仓库 `WorkcenterId`
  - 限定当前工厂 `FactoryId`
  - 不限定本次盘点涉及的 `ProductId`，本仓库 Excel 不存在的物料也需置出库
  - 对 Excel 中不存在的 `FactoryId + WorkcenterId + ProductId + ProductionLotNO` 设置 `IsStorage=0`
  - 对同一 SAP 批次累计后超出盘点数量的更旧库存批次设置 `IsStorage=0`
  - 更新 `ModifyDate`

- [x] 12. 完成预览模式 `DryRun`
  - `DryRun=1` 时只校验和统计
  - 不修改 `WW_RMInventory`
  - 返回预计更新、新增、置出库数量

- [x] 13. 完成处理结果返回
  - 返回批次号 `batchNo`
  - 返回总仓库数
  - 返回成功仓库数
  - 返回失败仓库数
  - 返回每个仓库处理明细

- [x] 14. 补充中文注释
  - 每段校验逻辑前添加中文注释
  - 每段更新、新增、置出库逻辑前添加中文注释
  - 每段事务和异常处理逻辑前添加中文注释

---

### 阶段三：测试验证

- [x] 15. 准备测试数据
  - 准备一个已有 SAP 批次且只命中一行库存，用于验证更新
  - 准备一个已有 SAP 批次且命中多行库存，用于验证按创建时间累计保留
  - 准备一个新 SAP 批次，用于验证新增
  - 准备一个 MES 有但 Excel 没有的 SAP 批次，用于验证 `IsStorage=0`
  - 准备一个异常仓库，用于验证仓库级回滚

- [x] 16. 验证预览模式
  - 执行 `DryRun=1`
  - 确认 `WW_RMInventory` 无变化
  - 确认返回统计数量正确
  - 确认异常数据能返回错误原因

- [x] 17. 验证正式更新模式
  - 执行 `DryRun=0`
  - 确认已有 SAP 批次按 `FactoryId + WorkcenterId + ProductId + ProductionLotNO` 匹配
  - 确认多库存行按 `CreateDate DESC, WWId DESC` 累计保留
  - 确认最后一个保留批次只调整为剩余需要数量，批次号不变
  - 确认超出盘点数量的更旧批次 `IsStorage=0`
  - 确认新 SAP 批次被新增
  - 确认缺失 SAP 批次 `IsStorage=0`
  - 确认仓库级返回结果正确

- [ ] 18. 验证异常场景
  - 工厂不存在
  - 仓库不存在
  - 物料不存在
  - 单位不存在
  - 库存数量为负数
  - 同一工厂、仓库、物料、SAP批号重复

- [ ] 19. 验证事务隔离
  - 同一批数据包含两个仓库
  - 仓库 A 数据正常
  - 仓库 B 数据异常
  - 确认仓库 A 提交成功
  - 确认仓库 B 回滚失败

---

### 阶段四：上线准备

- [ ] 20. 备份受影响库存数据
  - 按本次盘点仓库备份 `WW_RMInventory`
  - 记录备份时间和备份 SQL
  - 确认备份可用于回滚

- [ ] 21. DBA 审核 SQL
  - 审核更新范围是否带有 `WorkcenterId`
  - 审核匹配条件是否统一使用 `FactoryId + WorkcenterId + ProductId + ProductionLotNO`
  - 审核窗口函数累计保留逻辑是否符合 SQL Server 执行计划和锁风险
  - 审核 `IsStorage=0` 范围是否符合业务要求
  - 审核是否需要新增索引
  - 审核事务和锁风险

- [ ] 22. 业务试算确认
  - 先执行 `DryRun=1`
  - 导出预览结果
  - 由业务确认预计更新、新增、置出库数量

- [ ] 23. 正式执行
  - 在约定时间窗口执行 `DryRun=0`
  - 保存返回 JSON
  - 抽查关键仓库、物料、SAP批号

- [ ] 24. 上线后复盘
  - 记录实际更新、新增、置出库数量
  - 整理异常数据原因
  - 将字段映射和执行注意事项补充到项目说明文档

---

## 任务依赖关系

```text
1
├── 2
├── 3
└── 4
      └── 5
            └── 6
                  └── 7
                        └── 8
                              ├── 9
                              ├── 10
                              └── 11
                                    └── 12
                                          └── 13
                                                └── 14
                                                      └── 15
                                                            ├── 16
                                                            ├── 17
                                                            ├── 18
                                                            └── 19
                                                                  └── 20
                                                                        └── 21
                                                                              └── 22
                                                                                    └── 23
                                                                                          └── 24
```

---

## 估时参考

| 阶段 | 任务 | 估时 |
|---|---|---|
| 阶段一：需求与字段确认 | 任务 1 ～ 4 | 0.5 天 |
| 阶段二：存储过程开发 | 任务 5 ～ 14 | 1.5 天 |
| 阶段三：测试验证 | 任务 15 ～ 19 | 1 天 |
| 阶段四：上线准备 | 任务 20 ～ 24 | 0.5 天 |
| **合计** | | **3.5 天** |

---

## 完成标准
- `requirements.md`、`design.md`、`tasks.md` 已完成并通过评审。
- 存储过程通过 SQL Server 编译。
- 预览模式与正式更新模式均验证通过。
- 更新、新增、置出库、异常和事务场景均有测试记录。
- 业务确认正式执行结果符合盘点预期。
