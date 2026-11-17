# MES 查询历史记录

> 由 mes-sql-query skill 自动追加，请勿手工删除历史条目。

## 表映射确认

- 2026-09-18 用户确认：SysUser 表中 UserName 是工号，UserDescription 才是中文姓名。按中文名（如"罗年"）查人时应用 `UserDescription = N'姓名'`，不可用 UserName

## 查询记录

## 2026-09-18 查询操作人"罗年"的过滤记录及过滤时间
- 表：PGFilter（过滤记录）, ProductionGrind（研磨过滤工艺主表，CreateUserId 为操作人）, SysUser（用户表）
- 关键规则：PGFilter 无操作人字段，需经 ProductionGrindId 关联 ProductionGrind，再经 CreateUserId 关联 SysUser.UserDescription（中文姓名，UserName 是工号）；FilterTime 仅在停止过滤时写入
- SQL：
  SELECT u.UserDescription AS 操作人, pg.LotSN AS 批号, pf.FilterType AS 过滤类型,
         pf.StartTime AS 过滤开始时间, pf.StopTime AS 过滤停止时间,
         pf.FilterTime AS 累计过滤时长, pf.FilterQty AS 过滤数量, pf.CreateDate AS 记录创建时间
  FROM dbo.PGFilter pf
  INNER JOIN dbo.ProductionGrind pg ON pf.ProductionGrindId = pg.ProductionGrindId
  INNER JOIN dbo.SysUser u ON pg.CreateUserId = u.UserId
  WHERE u.UserDescription = N'罗年'
  ORDER BY pf.CreateDate DESC;

## 2026-10-19 报表 zpp12 已理货数量取自半成品批次分配表
- 文件：MES/sql/zpp12.sql（在原有报表 SQL 上完善，未新建文件）
- 表：MO, Product, ProductRoot, Factory, MOItem, SO, SOItem, MOSemiFinishedLotAllocation
- 关键规则：已理货 = 按 MOId + MOItemId + ProductId 汇总 MOSemiFinishedLotAllocation.Qty，过滤条件 DeleteFlag='0' AND IsOccupyAllocatedQty=1 AND ConfirmStatus='1'（与 MOSemiFinishedLotAllocationDoMethod.sql 的"已分配数量"口径一致，用户确认只统计已确认理货量）
- 半制品MO1~MO5：生产当前物料行物料的生产订单，关联关系 半制品工单.ProductId = mi.ProductId（用户确认），按 PlannedDateFrom 升序取前 5 条；MOn数量=MOQtyRequired，MOn基本开始日期=PlannedDateFrom；排除当前工单自身与已逻辑删除工单；用 ROW_NUMBER + CASE 聚合一次扫描生成 5 组列
- 早期口径（已被上面【最终口径】替代，仅作历史对照）：预留=本工单 mi.ItemQtyRequired-ItemQtyIssued+ItemQtyBack；库存=WW_RMInventory 中 LotStatus='1' 且 IsStorage=1 的记录，超期按 ValidityEndDate 判断
- 其他修复：原 SQL 缺少 SO 表别名（`dbo.SO on so.SOName=mo.SOName`）导致无法执行；`LEFT JOIN MOItem` 后接 `INNER JOIN Product` 使左连接失效，改为 INNER JOIN；SoItemSequence/ItemSequence 的 CAST 改为 TRY_CONVERT 防止转换报错
- SQL：见 MES/sql/zpp12.sql

## 2026-10-27 成品工单同一天使用同一个半成品物料的统计
- 文件：MES/sql/Q_FGMO_SameSemiProductPerDay_20261027.sql
- 表：MO, MOItem, Product, ProductRoot
- 关键规则（用户确认口径）：
  1) 使用口径 = 工单 BOM 物料行（MOItem），一条物料行算一次使用，不看是否已投料/已分配
  2) 日期 = MO.PlannedDateFrom（工单计划开始日期）取日期部分
  3) 使用次数 = COUNT(*) 使用记录条数（物料行条数）
  4) 成品工单判定 = mo.MOName LIKE '2%'（与 AssignLot_GetLot_Script、MOSemiFinishedLotAllocationBatchDoMethod 一致，返工工单以 7 结尾不计）
  5) 半成品判定 = Product.ProductClassify='2'（与 zpp12 一致）
  6) 过滤：DeleteFlag<>'1'、LineSequence<>'000'、PlannedDateFrom 非空；默认 HAVING COUNT(*)>1 只输出同日多次使用
- SQL：见文件

## 2026-10-10 通过容载器码获取当前数量
- 表：ZR_ContainerCode（容器）→ ZR_ToFac_ContainerCode（中间表）→ ZR_ContainerCodeDetails（明细，num=数量）
- 关键规则：按 ContainerCode 过滤，取 createDate 最新一条明细的 num 作为当前数量
- SQL：
  SELECT TOP 1 d.num
  FROM dbo.ZR_ContainerCode c
  INNER JOIN dbo.ZR_ToFac_ContainerCode t ON t.ZR_ContainerCodeId = c.ZR_ContainerCodeId
  INNER JOIN dbo.ZR_ContainerCodeDetails d ON d.ZR_ToFac_ContainerCodeID = t.ZR_ToFac_ContainerCodeID
  WHERE c.ContainerCode = @ContainerCode
  ORDER BY d.createDate DESC;
