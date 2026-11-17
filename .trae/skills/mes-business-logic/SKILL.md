---
name: "mes-business-logic"
description: "描述当前 MES 系统已确认的业务逻辑（入库申请/接收、领料、批次分配与拆分、盘点、过站、WMS/SAP 接口）。当需要开发或排查 MES 存储过程、理解业务流转与表关系时调用。"
---
# MES 业务逻辑

本 Skill 汇总当前仓库中**已确认**的 MES 业务逻辑，供开发、排查存储过程时快速对照。
凡标注 **【已确认】** 的，均有表结构或存储过程源码/规格文档为依据；标注 **【待确认】** 的仅保留标题，内容尚未核实，使用前必须回到源码或向业务方确认。

> 阅读顺序建议：先看「系统底座与核心数据模型」→ 再按需跳到具体业务模块。

---

## 一、系统底座与核心数据模型 【已确认】

### 1.1 技术底座

- 数据库：SQL Server，OrBit MOM 平台；开发/测试库 `OrBitMOMTestBack`，生产库 `OrBitMOM`。
- 仓库结构：
  - 表结构：`MES/table/<表名>.sql`
  - 存储过程：`MES/procedure/<过程名>.sql`
  - 规格文档：`.spec-workflow/specs/<功能名>/`
- 存储过程命名前缀：`Txn_`（事务）、`PDA_`（PDA 端扫描/提交）、`TxnBase_`（公共基础事务）、`APISync*/WebAPI_*`（WMS/外部接口）、`Batch_*`（批处理）。

### 1.2 OrBit 过程固定接口参数

Save/DoMethod 类过程必须保留的系统参数：`@I_Sender`、`@I_ReturnMessage`（输出）、`@I_ExceptionFieldName`（输出）、`@I_LanguageId`、`@I_PlugInCommand`、`@I_OrBitUserId`、`@I_OrBitUserName`、`@I_ResourceId`、`@I_ResourceName`、`@I_PKid`、`@I_ParentPKId`、`@I_Parameter`。

- 业务校验失败统一：`SET @I_ReturnMessage='ServerMessage:[参数名][参数值]错误描述'` 并 `RETURN -1`。
- 过程体惯例：`SET NOCOUNT ON` + `SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED`，分段写中文注释。

### 1.3 核心表与职责

| 表                                       | 职责（已确认）                                                                                                                                                  |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Lot`                                  | 生产批次主表，`LotSN` 唯一；记录 `ProductId`、`Qty`、`LotStatus`、`MOId`、`WorkflowId`、`WorkflowStepId`、`SpecificationId`、`QualityMark` 等 |
| `MO` / `MOItem` / `MOItemLot`      | 工单、工单物料、工单批次关联                                                                                                                                    |
| `FinishingEntry`                       | 入库单主表，状态 `FinishingEntryStates`（10 待提交 / 20 已提交 / 30 已确认等），`FinishingEntryType` 为入库类别                                             |
| `FinishingEntryItem`                   | 入库单明细行（按 MO + 物料 + 产品归并），`ItemQtyEntry` 为申请数量合计                                                                                        |
| `FinishingEntryItemLot`                | 入库单批次行，`LotSN` + `Qty`（申请数量）+ `IsAccepted`（整行是否接收完成，bit）                                                                          |
| `WW_RMInventory`                       | 库存表；`IsStorage=1` 表示在库，`LotStatus='9'` 表示单据未确认、`'1'` 表示可用；一个批次通常一行                                                          |
| `Bill` / `BillStates` / `BillType` | 单据类型、状态及其描述字典                                                                                                                                      |
| `Workcenter` / `Cell`                | 仓库（工作中心）/ 储位                                                                                                                                          |
| `ShipBox` / `ShipPallet`             | 装箱、装栈信息（PDA 入库/接收可扫箱号、栈板号）                                                                                                                 |

---

## 二、入库申请与入库接收 【已确认】

### 2.1 业务定位

- 产线先做「入库申请」扫描并生成入库单；仓库再做「入库接收」扫描，收满后单据确认并调用 ERP 接口。
- 涉及过程：`Txn_FinishedEntryApply_Scan`、`Txn_FinishedEntryApply_Submit`、`PDA_FinishedEntryReceive_Scan`（分别有 `PDA_` 包装过程转发调用）。

### 2.2 申请扫描（`Txn_FinishedEntryApply_Scan`）

- 支持按 **Lot / MO** 两种入库单位；`@I_Sender='LotScan'` 时先返回批次数量给前端录入，再二次提交。
- 申请时即写入：
  - `FinishingEntry`（状态 `10`）
  - `FinishingEntryItem`（按 MO + MOItem + Product 归并，`ItemQtyEntry`=申请量合计）
  - `FinishingEntryItemLot`（`LotSN`、`Qty`、`EntryUnit`）
  - `WW_RMInventory`（`LotStatus='9'`、`IsStorage=0`、`Qty`=申请量）
- 关键卡控（已确认）：
  - 批次状态必须 `LotStatus='1'`，数量 > 0；
  - 批次当前工序必须为入库节点（`Specification.IsEntryStep=1`）；
  - 工序代码仅允许 `FBXR/FCXR/UBXR/UCXR/OTXR/HXXR/SXXR`（2026-02-02 起含活性、水性申请节点）；
  - 已在库（`WW_RMInventory.IsStorage=1`）不允许再申请；
  - **同一 `LotSN` + `MOId` + `ProductId` 已有入库申请记录即禁止重复申请**（提示去「申请撤销」页签撤销）；
  - 已装箱/已装栈（`ShipBox.IsAutoBoxing`）不允许按批号入库。

### 2.3 申请提交（`Txn_FinishedEntryApply_Submit`）

- 状态允许 `10`、`21` 提交。
- 正常流程置 `FinishingEntryStates='20'`（已审核），写 `ApproveUserId/ApproveDate`。
- 特殊工作流（墨水、返工、活性/水性半成品等，如 `WKF1000000YT/YV/ZL/ZK/ZE/ZB/ZY`）置 `'50'`，且不改状态时仍需注意其与仓库接收的衔接【待确认：50 状态单据走哪种接收路径】。
- 过站处理：对工序代码 `FBXR/FCXR/UBXR/UCXR/OTXR/HXXR/SXXR` 的批次逐批调用 `TxnBase_LotMove`；墨水类批次在满足条件时调用 `AlarmSendMessage` 发「入待处理仓」提醒邮件。
- 可把备注追加到对应 `MO.NoteMessage`。

### 2.4 入库接收（`PDA_FinishedEntryReceive_Scan`）

- 接收单位：`Lot`、`MO`（箱/栈分支在代码中保留）。
- 前置校验：必须选仓库；储位号存在且 `IsActivity=1`；批次存在且存在 `FinishingEntryItemLot.IsAccepted=0` 记录；入库单状态必须 `20`（`10` 提示"产线未提交"，其他提示"无需再次接收"）；半成品(类型 `01`)且品质标记 `YB/RB` 只能入报废仓 `B59Z`；UV 类工单需完成 C 点检验。
- 接收动作：逐行 `IsAccepted=1`、`AcceptUserId/AccepteDate/WorkcenterId`；`WW_RMInventory.IsStorage=1`（不合格品 `YB/RB/NQ` 置 `LotStatus=0`）；写 `TxnBase_MLotTrack` 批次追踪。
- 确认时机：当该单**不存在** `IsAccepted=0` 的行时，调用 `TxnBase_MBill_FinishingEntryConfirm` 确认单据（注释描述为置状态 `30` 并调用 ERP 接口）；该过程本体不在本仓库，内部细节【待确认】。
- 确认成功后自动拆批绑定容载器：按单据下已接收批号取未绑定 MES 批次的容器，逐个按容器最新 `num` 调用 `Txn_MaterialLotSplit`（`@IsSilent=1`）拆出 MES 批次并写入 `ZR_ToFac_ContainerCode.BoxLotSn`；容器数量等于批号剩余库存时整批直接绑定原批号；拆批失败只提示、不影响已完成的接收。
- 收尾规则（已确认）：9302 工厂 TZ 线成品转 9502 `B57Z` 库位；受托工厂 `9102/9304` 库存 `FactoryId` 统一改 `FAC1000000SW`（9502）。

### 2.5 现状限制：不支持部分接收 【已确认】

- 接收是「整行布尔」：`FinishingEntryItemLot.IsAccepted` 只能 0/1，**没有「已接收数量」字段**；收一次即整行完成。
- 因此「一次申请、分批接收、实物码不变」的诉求当前无法实现；若要做，需引入行级累计接收数量（如 `ReceivedQty`）+ 接收流水表，并把确认时机改为「待收数量=0」。

### 2.6 容载器 / 货位码表的批次字段口径 【已确认】

- `ZR_ContainerCode.CurrentProudctionLotSN` 存的是 **SAP 批次**（即 `WW_RMInventory.ProductionLotNO`），**不是 MES 批次号**；禁止把 `Txn_MaterialLotSplit` 拆出的新 MES 批号写回该字段。
- `ZR_ToFac_ContainerCode.BoxLotSn` 存的是 **MES 批次号**（`WW_RMInventory.LotSN`）；两套库存的纽带即 `BoxLotSn = WW_RMInventory.LotSN`。
- `ZR_ContainerCodeDetails` 记录容器每次的数量/货位码流水，取 `createDate DESC, ZR_ContainerCodeDetailsId DESC` 的第一条作为当前值（`num` 为容器实际数量，不参与单据数量计算）。
- 因此「入库接收后按容器数量自动拆批」时，拆出的新 MES 批号只写 `ZR_ToFac_ContainerCode.BoxLotSn`，不改 `CurrentProudctionLotSN`。
- 参考过程：`PDA_ToFac`、`PDA_ToFac_Split`（这两者在扫描 MES 批次后会先换算成 `ProductionLotNO` 再绑定容器）；`PDA_FinishedEntryReceive_Scan`（入库接收后自动拆批并绑定容器）。

---

## 三、领料业务 【已确认（高层）】

- 单据类型：生产领料、杂发、委外、外协（`PickingListType_ViewListPK`）。
- 生命周期操作（过程即证据）：
  - 生成/指定批次：`Txn_MOPickingRequest*`（工单指定批次生成领料申请单）、`PickingListOtherLotSN_DoMethod`（杂发单指定批次）；
  - 审核 / 取消审核：`PickingListApproveDoMethod`、`PickingListApproveCancelDoMethod`；
  - 确认：`PickingListConfirm_DoMethod` → 统一入口 `TxnBase_MBill_PickingListConfirm`；
  - 关闭 / 强制关闭：`PickingListCloseDoMethod`、`Txn_MBill_PickingListShutDown`；
  - 一键领料：`PickingListOnKeyDoMethod`；
  - 撤销领料申请：`Txn_RevokePickingDoMethod`；
  - 建议储位：`TxnBase_MBill_PickingListAdviceLot*`；
  - 打印：`PickingListPrintDoMethod`。
- PDA 领料确认：`PDA_PickingListConfirm`；线边仓领料 `Txn_PickingToProductionLine`；超发料 `Txn_PickingOfOverIssuedMaterials`。
- 领料明细与批次：`PickingList` / `PickingListItem` / `PickingListItemLot`。

---

## 四、批次分配与灌墨上料 【已确认】

### 4.1 半成品批次预分配（`MOSemiFinishedLotAllocationDoMethod`）

按 `@I_Sender` 分支：

| Sender               | 作用                                                   |
| -------------------- | ------------------------------------------------------ |
| `GetMOProduct`     | 查工单半成品需求/已分配/未分配                         |
| `GetInventory`     | 查可分配批次库存（按 `EntryDate` 排序）              |
| `GetAllocatedLots` | 查已分配批次                                           |
| `AssignLot`        | 扫 `LotSN` 单批分配                                  |
| `AutoAssign`       | 按入库时间 FIFO 自动填满剩余需求（入参 `@MOItemId`） |
| `DeleteLot`        | 逻辑删除分配记录                                       |

- `AutoAssign` 规则：按 `EntryDate`、`LotSN` 升序，逐批取 `MIN(剩余需求, 批次可用量)`，库存不足时部分分配并返回剩余量。

### 4.2 成品灌墨指定批次（`PDA_FPInkCheckInput`）

- 灌墨扫描以 `MOSemiFinishedLotAllocation` 的有效占用记录为准入，不再要求已生成领料记录。
- 实际用量可超分配量，但批次必须是当前工单仍占用的已分配批次；批次可用量取 `WW_RMInventory.Qty`，且不超工单物料剩余需求。
- 上料写入同事务完成：库存扣减、`LoadingItemLotDetail`/`LoadingItemLotRecord`、`TxnBase_MLotTrack` 追溯、`DataChainAssyIssue` 数据链；参考 `PDA_ProductionMaking_LotSNScan` 的 `UsedQtyScan` 分支。
- 完工/下线前，仅为当前上料会话未领料记录生成生产领料单；过站报工成功后解除对应分配占用（历史保留）。

---

## 五、库存盘点更新 【已确认（文档）】

- 过程：`Batch_StocktakeUpdateRMInventory`（v1.08），配套 Web 工具 `web/stocktake-import/`。
- 规则（已确认）：
  - 按仓库独立事务处理；支持 `DryRun` 预览。
  - 已有库存累计保留更新；缺失库存新增；缺失物料或 SAP 批次置出库。
  - 结果以 JSON 返回。
  - SAP 批号写入 `WW_RMInventory.ProductionLotNO`；新增库存 `LotSN` 用系统批号规则 `WW_MP_LotSN` 生成。
  - `FrozenQty<>0` 时同一 SAP 批次在库记录 `LotStatus` 置 0。
  - 正式更新时数量变更写 `StocktakeUpdateLog`（修改前/后数量）。
- 主数据匹配：工厂=`Factory.FactoryName`；仓库=`Workcenter.WorkcenterName`（限工厂）；物料号=`ProductRoot.ProductName` → `Product`；单位=`UOM.UOMName/ERPUnitcode`。
- 已知待办：v1.08 日志、v1.09 半成品 `OrgLotSN` 规则**未测试**；约 30 万行 Excel 导入**待修复**。

---

## 六、过站与批号流转 【已确认】

- `TxnBase_LotMove` 为 MES 标准传送事务：读取 `Lot` 当前 `WorkflowStepId`/`NextWorkflowStepId`，经 `TxnBase_WkfPathSelect` 计算下一节点，支持 MoveIn 判定；报文码 `TxnCode='MOVE'` / `'MOVE IN'`。
- 入库申请提交、生产上料、报工等都会复用该公共事务推进批次节点。

---

## 七、批号拆分 / 合并 【已确认】

- `Txn_MaterialLotSplit`（物料拆分）：用于库存批号拆分、产线物料拆分；生成新批号依赖序列号规则 `SNRule='WW_MP_LotSN'`；原批号 `WW_RMInventory.Qty` 扣减，新批号 `IsSM=1`（散料）；支持 `@IsSilent` 供嵌套调用。
- `TxnBase_LotSplitCombine`（MES 批号合并及拆分）：公共批号合并/拆分事务。

---

## 八、质检相关 【已确认（存在与用途）】

- 过程检验：`Txn_QC_Process_InspectionGet`（按批号取检验单）、`...InspectionItem_Refresh`、`...InspectionItemDet_Submit/Deleted/Refresh`、`Txn_QC_Process_InspectionJudge_Submit`（提交判定结果）。
- D 点检验：`Txn_QC_DPointInspectionQuery`（查询待检测检验单）、`Txn_QC_DPointInspectionJudge`（判定并更新子表/扩展信息）。
- 批号核验：`Txn_LotDJudgmentDoMethod`（按批号判定 `QualityMark`，含报废/隔离相关处理）。
- 入库侧质检卡控：UV 半成品完成 C 点检测（`QC_ProcessIns.SubmissCategory='IPQC'` 未出结果时阻断入库）。

---

## 九、WMS / SAP 接口 【已确认（存在与用途）】

| 过程                                      | 用途                                                               |
| ----------------------------------------- | ------------------------------------------------------------------ |
| `APISyncD_WMSInventory`                 | 查询 WMS 库存信息                                                  |
| `APISyncU_ReceiveToWMS`                 | 调用 WMS 收货单                                                    |
| `APISyncU_PickingOtherToWMS`            | 杂发单回写 WMS（对应过站原材料扣料）                               |
| `APISyncU_ProductAllotToWMS` / `_DOs` | 调拨申请传给 WMS                                                   |
| `APISyncU_AdujstmentToWMS`              | 调用 WMS 库存调整单                                                |
| `WebAPI_FinishedEntryFromWMS`           | WMS 完工入库回调 MES（内部转调 `PDA_FinishedEntryReceive_Scan`） |
| `EDI_DSProductInventoryForSAP`          | 物料批次库存接口（SAP）                                            |
| `Batch_StocktakeUpdateRMInventory`      | 盘点结果回写库存                                                   |

- `WebAPI_FinishedEntryFromWMS` 关键已确认点：解析 JSON（`DOC_CODE/FinishingEntryName/WhCategory/ToWorkcenter/CellName/LotSN/EntryQty`）；校验单据类型=`FinishedEntry`、类别 `01/02`、状态不可为 `40/50`（`60` 已废弃、`70` 已入库）；`LotSN` 需与入库单 `SUBSTRING(LotSN,0,11)` 前缀一致；按 `LotSN+'001'` 的规则关联 Lot 工序节点（`SPGW/FSPD/SFGW/OQC/OTGW`）。

---

## 十、其他已确认的库存/批号规则

- `WW_RMInventory.IsStorage=1` 才是在库可用；查可用库存默认加 `IsStorage=1`（必要时 `Qty>0`）。
- 批次状态约定：单据未确认 `LotStatus='9'`，确认后 `'1'`；不合格/停用相关会置 `0`。
- 物料/批次拆分生成新码统一走序列号规则（`SNRule` + `StartRuleSNDoMethod`），主键统一 `SysGetObjectPKId` / `SysGetObjectPKIdBatch` 生成 `char(12)`。
- 批次追踪统一写 `TxnBase_MLotTrack`（事务码如 `F-入库申请`、`F-入库接收`）。

---

## 十一、待确认（仅标题，使用前必须核实）

### 11.1 报工与工单状态流转

### 11.2 工单关闭 / 半成品下线 / 尾数处理

### 11.3 委外、外协、退料、成品退货完整流程

### 11.4 调拨申请 → 仓库调拨单的完整规则（`Txn_MOAllotRequest*`）

### 11.5 装箱 / 装栈 / 发货 / 成品理货

### 11.6 ERP 过账与财务对账（`TxnBase_MBill_FinishingEntryConfirm` 本体、SAP 回写字段）

### 11.7 质量冻结 / 隔离 / 报废的完整状态机

### 11.8 序列号规则体系（`SNRule` / `StartRuleSNDoMethod`）全貌

### 11.9 多工厂 / 受托转库规则（9102、9304 → 9502 的完整口径）

### 11.10 用户、权限与资源（`UserGroupAuthorize`、`SysUser` 等）

### 11.11 生产成本、工时、设备与排程

### 11.12 入库单状态在 PDA 流程（10/20/30）与 WMS 回调流程（40/50/60/70）之间的对应关系

---

## 十二、使用方式

1. 先按「核心表」确认字段与主键（以 `MES/table/` 实际脚本为准，禁止凭记忆猜字段）。
2. 按业务模块找到相关存储过程，阅读源码再动手，本 Skill 只作导航与已确认结论。
3. 涉及标注【待确认】的内容，不得直接写入方案或代码，必须先核实源码或询问业务方。
4. 修改存储过程时遵循 `.trae/skills/mes-sqlserver/SKILL.md` 的开发规范（中文注释、非空/格式/边界校验、错误提示带出参数值）。
