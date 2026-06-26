# Tasks: 半成品盘点导入

## 状态
- **状态**：待开发 Todo
- **创建日期**：2026-06-26
- **目标**：在 MES 工具箱新增「半成品盘点」模块（Excel 导入 + 调用 `UpdateInventoryBySAP_BCP`）

---

## 任务列表

### 后端

- [ ] 1. 新增 Excel 模型与解析服务
  - 定义半成品行模型（工厂、仓库、物料、批号、在库/质检/锁定数量、单位、入库日期、备注）
  - 仿 `StocktakeExcelService` 实现 `Parse` 与 `CreateTemplate`
  - 增加字段长度校验并返回行级错误（按 `SAP_PRODUCT_INVENTORY` 表结构）

- [ ] 2. 新增数据库服务方法
  - `ImportSapInventoryAsync`：先提取去重的工厂+仓库集合并删除旧数据，再批量写入 `SAP_PRODUCT_INVENTORY`，`Id=GUID`、`isChange=0`
  - `ExecuteSapInventoryAsync`：先预检工厂仓库存在，再调用 `dbo.UpdateInventoryBySAP_BCP`（入参工厂、仓库）

- [ ] 3. 新增 Controller 接口
  - `GET /api/sap-inventory/template`
  - `POST /api/sap-inventory/import`
  - `POST /api/sap-inventory/execute`
  - 注册依赖注入
  - 响应格式统一 `ApiResponse<T>`

### 前端

- [ ] 4. 注册模块入口
  - `config/modules.ts` 增加「半成品盘点」卡片
  - `App.tsx` 注册路由 `/sap-inventory`

- [ ] 5. 实现模块页面
  - `modules/sap-inventory/api.ts`、`types.ts`
  - `index.tsx`：下载模板 + 上传导入 + 工厂仓库表单 + 执行盘点

### 测试

- [ ] 6. 功能验证
  - 模板下载、导入成功、缺列/空值报错
  - 重复导入覆盖
  - 执行成功更新 `WW_RMInventory`、`isChange=1`
  - 找不到仓库 / 无数据提示

### 上线

- [ ] 7. 上线准备
  - 测试库验证后切生产配置
  - 执行前备份相关 `WW_RMInventory`
  - 更新 `web/stocktake-import/README.md` 模块说明

---

## 依赖关系

```text
1 → 2 → 3 → 4 → 5 → 6 → 7
```

## 估时
| 阶段 | 任务 | 估时 |
|---|---|---|
| 后端 | 1 ～ 3 | 0.5 天 |
| 前端 | 4 ～ 5 | 0.5 天 |
| 测试与上线 | 6 ～ 7 | 0.5 天 |
| **合计** | | **1.5 天** |
