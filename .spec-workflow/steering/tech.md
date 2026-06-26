# Tech Steering

## Architecture Decisions

### ADR-001: 后端框架选型
- **决策**：采用 ASP.NET Core Web API 作为后端框架
- **理由**：团队熟悉 .NET 技术栈，生态成熟，与 SQL Server 集成紧密
- **影响**：依赖 Windows 部署环境，需统一运行时版本管理

### ADR-002: 数据库选型
- **决策**：使用 SQL Server（OrBitMOMTestBack 数据库）
- **理由**：已有企业授权，DBA 熟悉运维，数据安全合规
- **影响**：所有数据操作仅允许在 OrBitMOMTestBack 数据库中进行

### ADR-003: 前端框架选型
- **决策**：采用 React + TypeScript + TailwindCSS
- **理由**：组件复用性强，类型安全，样式维护成本低
- **影响**：构建产物为静态文件，可独立部署

## Technology Stack
| 层 | 技术 | 说明 |
|---|---|---|
| 前端 | React + TypeScript | 主框架，强类型保障 |
| 前端样式 | TailwindCSS | 原子化 CSS，快速构建 UI |
| 前端组件 | shadcn/ui | 预置高质量组件库 |
| 后端 | ASP.NET Core Web API | RESTful 接口服务 |
| 数据库 | SQL Server | 数据持久化，仅限 OrBitMOMTestBack 库 |
| ORM | Dapper | 轻量级 SQL 映射，保留 SQL 可读性 |
| 版本控制 | Git | 代码管理 |

## Development Principles

### 1) 输入校验（强制）
- 所有外部输入必须做非空检查
- 所有关键字段必须做格式验证（URL 格式、HTTP 方法枚举、状态码范围等）
- 所有集合/分页接口必须做边界条件处理（PageSize 上限、PageIndex 下界）

### 2) 代码与注释规范
- 每段核心业务逻辑必须有中文注释
- SQL 存储过程每段逻辑块需加中文说明注释
- 所有 SQL 均以 SQL Server 语法编写
- 除 SELECT 语句外，其余 SQL 不直接执行，需经过审批

### 3) 错误处理
- 后端统一返回标准错误响应格式（Code / Message / Data）
- 不向前端暴露内部异常堆栈信息

### 4) 安全规范
- 禁止 SQL 拼接，统一使用参数化查询
- 接口调用需鉴权（Token / API Key）

## Non-Functional Targets
| 指标 | 目标 |
|---|---|
| 接口平均响应时间 | ≤ 500ms（P95） |
| 系统可用率 | ≥ 99.5% |
| 单次测试执行耗时 | ≤ 3s（含断言） |
| 前端首屏加载时间 | ≤ 2s |

## Risks and Constraints
- 所有数据操作仅限 OrBitMOMTestBack 数据库，禁止跨库访问
- SQL Server 版本需与已有生产环境一致，避免语法兼容问题
- 第三方 API 调用存在网络超时风险，需设置合理超时与重试策略
- 敏感配置（连接字符串、密钥）必须通过环境变量或配置中心注入，禁止硬编码
