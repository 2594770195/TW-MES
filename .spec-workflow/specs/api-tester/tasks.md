# Tasks: API Tester

## 状态
- **状态**：已完成 Done
- **创建日期**：2026-05-12

---

## 任务列表

### 阶段一：页面结构与样式

- [x] 1. 创建 index.html 基础骨架
  - DOCTYPE、meta charset、viewport 设置
  - 引入内联 CSS 变量与 reset 样式
  - 顶部导航栏（标题 + 主题切换按钮）

- [x] 2. 实现请求行区域
  - HTTP 方法下拉选择器（GET / POST）
  - URL 输入框（占满剩余宽度）
  - 发送按钮（含 Loading 状态）

- [x] 3. 实现请求配置区域
  - Headers / Body 两个 Tab 切换
  - Header 编辑器（动态 Key-Value 行，添加/删除）
  - Body 编辑器（文本域，GET 时禁用）

- [x] 4. 实现响应展示区域
  - 响应状态栏（状态码 + 耗时）
  - 响应内容区（JSON 高亮 / 原始文本，限高滚动）

- [x] 5. 实现深色/浅色主题切换
  - CSS 变量方案，切换 data-theme 属性
  - 主题状态持久化到 localStorage

---

### 阶段二：核心功能逻辑

- [x] 6. 实现 buildRequest 模块
  - URL 非空校验与格式校验
  - Header 行过滤（跳过空 Key）
  - GET 时忽略 Body
  - JSON Body 自动追加 Content-Type

- [x] 7. 实现 sendRequest 模块
  - 使用 AbortController 设置 30s 超时
  - 记录请求开始/结束时间，计算耗时
  - 捕获网络错误与超时错误，转换为友好提示

- [x] 8. 实现 highlightJson 模块
  - 递归遍历 JSON 对象
  - 用 span 包裹各类型（键名/字符串/数字/布尔/null）
  - XSS 防护：对字符串值做 HTML 转义

- [x] 9. 实现 renderResponse 模块
  - 状态码颜色判断（2xx 绿 / 4xx 橙 / 5xx 红）
  - 尝试 JSON.parse，成功则调用 highlightJson
  - 失败则以 pre 标签原始展示
  - 错误状态（网络错误）的展示样式

---

### 阶段三：集成与验收

- [x] 10. 整合全部模块，绑定发送按钮事件
  - 发送中禁用按钮，显示 Loading 指示器
  - 发送完成后恢复按钮状态
  - 键盘快捷键：Ctrl+Enter 触发发送

- [x] 11. 边界场景验收测试
  - URL 为空 / 格式非法的提示
  - GET 请求发送验证（httpbin.org/get）
  - POST+JSON Body 发送验证
  - 响应非 JSON 时的原始文本展示
  - 网络错误提示验证

---

## 任务依赖关系

```
1
└── 2
      └── 3
            └── 4
                  └── 5
1 ～ 5
└── 6
      └── 7
            └── 8
                  └── 9
                        └── 10
                              └── 11
```

---

## 估时参考

| 阶段 | 任务 | 估时 |
|---|---|---|
| 阶段一：页面结构与样式 | 任务 1 ～ 5 | 3 小时 |
| 阶段二：核心功能逻辑 | 任务 6 ～ 9 | 3 小时 |
| 阶段三：集成与验收 | 任务 10 ～ 11 | 1 小时 |
| **合计** | | **7 小时** |
