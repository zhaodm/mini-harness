# Backend API 产出结构参考

> 适用于 output_type=backend-api。不绑定具体框架，描述通用后端 API 的产出结构。
> 目录规范见 `templates/output-structure.md`。

## 推荐目录结构

```
output/
├── src/
│   ├── routes/          # 路由定义（URL → handler 映射）
│   ├── controllers/     # 请求处理（参数解析、响应构造）
│   ├── services/        # 业务逻辑（核心算法、规则）
│   ├── repositories/    # 数据访问（DB 查询、外部 API 调用）
│   ├── models/          # 数据模型 / ORM 定义
│   ├── middleware/      # 中间件（认证、日志、错误处理）
│   ├── validators/      # 输入校验 schema
│   ├── types/           # 类型定义
│   ├── config/          # 配置加载（从环境变量）
│   └── app.{ts|py|go}  # 应用入口（初始化 + 启动）
├── tests/
│   ├── unit/            # 单元测试（service、validator）
│   └── integration/     # 集成测试（API endpoint 级别）
├── deploy/              # 部署相关（Dockerfile, docker-compose, k8s/）
├── package.json / pyproject.toml / go.mod  # 依赖管理
└── README.md            # API 文档 + 运行说明
```

## 关键文件说明

| 文件/目录 | 必须 | 说明 |
|-----------|------|------|
| src/routes/ | ✓ | 所有 API 端点的路由定义 |
| src/services/ | ✓ | 业务逻辑，不依赖 HTTP 框架 |
| src/validators/ | ✓ | 输入校验，返回结构化错误 |
| tests/ | ✓ | 至少覆盖核心 service + 主要 endpoint |
| README.md | ✓ | 含 API 列表、请求/响应示例、启动命令 |
| .env.example | ✓ | 环境变量模板（DB_URL、PORT、SECRET 等） |

## 质量检查点

- [ ] 应用能启动且监听端口（`npm start` / `python -m app` / `go run .`）
- [ ] 所有 endpoint 有输入校验（不接受任意输入）
- [ ] 错误响应格式统一（如 `{error: string, code: string, details?: any}`）
- [ ] 认证/授权中间件就位（如需要）
- [ ] 数据库操作使用参数化查询（防 SQL 注入）
- [ ] 敏感配置从环境变量读取，不硬编码
- [ ] 集成测试覆盖每个 endpoint 的正常 + 错误路径
- [ ] API 响应状态码语义正确（200/201/400/401/404/409/422/500）
