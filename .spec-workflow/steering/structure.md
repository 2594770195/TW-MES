# Structure Steering

## Codebase Organization
项目采用前后端分离架构，前端为 React SPA，后端为 ASP.NET Core Web API。两者独立部署，通过 RESTful 接口通信。规格文档统一存放于 `.spec-workflow/` 目录。

```text
project-root/
├── .spec-workflow/          # 规格工作流文档（需求/设计/任务/审批）
│   ├── approvals/
│   ├── specs/
│   └── steering/
├── frontend/                # React 前端应用
│   ├── src/
│   ├── public/
│   └── package.json
├── backend/                 # ASP.NET Core 后端服务
│   ├── src/
│   └── ApiTest2.sln
├── tests/                   # 端到端 / 集成测试
└── README.md
```

## Module Architecture

### 1) 业务模块划分
- `api-tester`: 接口请求发送、参数配置与响应展示核心功能
- `test-case`: 测试用例创建、编辑、分组管理
- `test-runner`: 测试用例执行引擎与结果记录
- `test-report`: 测试报告生成与查看
- `environment`: 环境变量与全局变量配置管理
- `auth`: 用户认证与鉴权

### 2) 单模块内部结构（后端）
```text
backend/src/modules/<module-name>/
├── api/               # Controller，接口路由定义
├── application/       # 应用层，用例编排（Service）
├── domain/            # 领域模型与业务规则
├── infrastructure/    # 数据访问（Repository / SQL）
└── dto/               # 数据传输对象（Request / Response）
```

### 3) 前端模块内部结构
```text
frontend/src/modules/<module-name>/
├── components/        # 该模块专属组件
├── hooks/             # 自定义 Hook
├── services/          # API 调用封装
├── types/             # TypeScript 类型定义
└── index.tsx          # 模块入口
```

### 4) 依赖规则（强制）
- 上层可以依赖下层，禁止循环依赖
- `domain` 层禁止依赖 `infrastructure` 层
- 跨模块调用只允许通过 `application` 层暴露的接口进行
- 前端模块间禁止直接引用对方内部文件，需通过 `index.tsx` 导出

## Directory Conventions
- **目录名**：kebab-case（如 `test-case`、`api-tester`）
- **类名**：PascalCase（如 `TestCaseService`）
- **方法 / 变量**：camelCase（如 `getTestCaseById`）
- **数据库表名**：PascalCase + 下划线分隔（如 `Test_Case`）
- **SQL 文件**：存放于对应模块的 `infrastructure/sql/` 目录，以功能命名

## Open Items
- [ ] 前端构建产物是否需要 CDN 加速？
- [ ] 后端是否需要独立的网关层（API Gateway）？
- [ ] 多环境配置（dev / staging / prod）的注入方式待确认
