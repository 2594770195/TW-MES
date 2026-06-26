# MES 工具箱（库存盘点导入）

统一前端入口「MES 工具箱」，当前已上线「库存盘点导入」模块。用于将盘点 Excel 导入 MES 数据库（OrBitMOMTestBack）。程序先将数据写入 `TempStocktakeData` 暂存表，再调用存储过程 `dbo.Batch_StocktakeUpdateRMInventory` 完成预览与正式更新。

## 前端结构

```text
frontend/src/
├── config/modules.ts      # 门户功能卡片配置
├── pages/HomePage.tsx     # 首页入口（/）
├── layout/ModuleLayout.tsx # 子功能页布局（返回首页、标题）
├── modules/stocktake/     # 库存盘点模块（/stocktake）
└── App.tsx                # 路由定义
```

新增功能：在 `config/modules.ts` 增加卡片配置，在 `modules/` 下新建模块并在 `App.tsx` 注册路由。

## 功能

- 下载标准 Excel 模板
- 上传并解析盘点 Excel
- 预览模式（DryRun=1）：只校验和统计，不修改库存
- 正式更新（DryRun=0）：写入 `WW_RMInventory`
- 展示按仓库的处理结果（更新 / 新增 / 置出库）

## Excel 模板列

| 列名 | 必填 | 说明 |
|---|---|---|
| 工厂 | 是 | 对应 `Factory.FactoryName` |
| 仓库 | 是 | 对应 `Workcenter.WorkcenterName` |
| 物料号 | 是 | 对应 `ProductRoot.ProductName` |
| 库存数量 | 是 | 不能小于 0 |
| 冻结数量 | 否 | 缺省为 0；不为 0 时存储过程会将同一 SAP 批次的在库记录 `LotStatus` 置为 0（冻结） |
| 单位 | 是 | 对应 `UOM.UOMName` 或 `ERPUnitcode` |
| SAP批号 | 是 | 匹配 `WW_RMInventory.ProductionLotNO` |
| 批号 / MES批号 | 否 | 可选，不参与主匹配 |

## 环境要求

- .NET 8 SDK
- Node.js 18+
- 能访问 SQL Server：`192.73.80.142:36257`
- 数据库中已部署表结构 `MES/table/TempStocktakeData.sql`
- 数据库中已部署存储过程 `MES/procedure/Batch_StocktakeUpdateRMInventory.sql`

## 配置数据库

连接字符串统一使用 `ConnectionStrings:MesDatabase`。ASP.NET 会根据运行环境自动选择配置：

| 环境 | 配置文件 | 数据库 |
|---|---|---|
| 测试（Development） | `appsettings.Development.json` | `OrBitMOMTestBack_WMSQAS` |
| 生产（Production） | `appsettings.json` | `OrBitMOM` |

编辑对应文件中的连接字符串，例如测试环境 `backend/StocktakeImport.Api/appsettings.Development.json`：

```json
"ConnectionStrings": {
  "MesDatabase": "Server=192.73.80.142,36257;Database=OrBitMOMTestBack_WMSQAS;User Id=sa;Password=你的密码;TrustServerCertificate=True;Encrypt=True;"
}
```

生产环境部署时设置 `ASPNETCORE_ENVIRONMENT=Production`，并确保 `appsettings.json` 中 `Database=OrBitMOM`。

> **注意**：`dotnet run` 默认使用 `http` 启动配置，该配置不再强制覆盖环境变量。请使用下列方式之一切换环境：
> - 测试库：`dotnet run --launch-profile Development`
> - 生产库：`dotnet run --launch-profile Production` 或 `$env:ASPNETCORE_ENVIRONMENT="Production"; dotnet run`

页面右上角会显示当前环境标签与数据库名（如「测试环境 · OrBitMOMTestBack_WMSQAS · 已连接」），生产环境为琥珀色提示，测试环境为蓝色提示。

## 启动方式

### 开发模式（前后端分离，热更新）

#### 1. 启动后端（测试库）

```powershell
cd web/stocktake-import/backend/StocktakeImport.Api
dotnet run --launch-profile Development
```

后端默认地址：`http://localhost:5025`  
Swagger：`http://localhost:5025/swagger`

#### 2. 启动前端

```powershell
cd web/stocktake-import/frontend
npm install
npm run dev
```

前端默认地址：`http://localhost:5173`（已代理 `/api` 到后端）

- 首页：`http://localhost:5173/` — MES 工具箱门户
- 盘点：`http://localhost:5173/stocktake` — 库存盘点导入

### 生产模式（单网址，后端托管前端）

```powershell
cd web/stocktake-import/frontend
npm install
npm run build:deploy

cd ../backend/StocktakeImport.Api
正式环境
dotnet run --launch-profile Production
生产环境
dotnet run --launch-profile Development
```



访问 `http://localhost:5025` 即可同时打开门户页面和 API（`/api/*`）。

## 推荐使用流程

1. 打开首页，确认右上角「数据库：已连接」
2. 点击「库存盘点导入」进入功能页
3. 点击「下载模板」，按格式填写盘点数据
4. 选择 Excel，点击「导入 Excel」
5. 点击「预览（DryRun）」查看各仓库预计影响
6. 确认无误后，点击「正式更新」

## API 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/stocktake/health` | 检查数据库连接，返回 `database` 与 `environment` |
| GET | `/api/stocktake/template` | 下载 Excel 模板 |
| POST | `/api/stocktake/import` | 上传 Excel 并写入 TempStocktakeData |
| POST | `/api/stocktake/execute` | 从 TempStocktakeData 执行预览或正式更新 |

## 注意事项

- 正式更新前务必先预览，并确认 Excel 已覆盖该仓库全部物料
- 同一工厂、仓库、物料号、SAP批号不能重复
- 数据库账号密码请勿提交到 Git 仓库
