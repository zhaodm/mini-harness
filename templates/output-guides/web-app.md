# Web App 产出结构参考

> 适用于 output_type=web-app。不绑定具体框架，描述通用 Web 应用的产出结构。
> 目录规范见 `templates/output-structure.md`。

## 推荐目录结构

```
deliverables/{REQ-ID}/
├── src/
│   ├── components/      # UI 组件（按功能分组）
│   ├── pages/           # 页面/路由级组件
│   ├── services/        # API 调用、外部服务交互
│   ├── utils/           # 工具函数
│   ├── types/           # 类型定义
│   ├── styles/          # 全局样式
│   └── app.{tsx|vue|svelte}  # 应用入口
├── tests/
│   ├── unit/            # 单元测试（组件、工具函数）
│   ├── integration/     # 集成测试（页面级、API 交互）
│   └── e2e/             # E2E 测试（用户流程）
├── deploy/              # 部署相关（Dockerfile, CI/CD, nginx 配置等）
├── assets/              # 静态设计资源（wireframes, 设计稿等，非 public/）
├── public/              # 运行时静态资源
├── package.json         # 依赖和脚本
├── tsconfig.json        # TypeScript 配置（如适用）
└── README.md            # 运行说明
```

## 关键文件说明

| 文件/目录 | 必须 | 说明 |
|-----------|------|------|
| src/ | ✓ | 源代码，按关注点分离 |
| tests/ | ✓ | 测试代码，结构镜像 src/ |
| package.json | ✓ | 含 scripts.dev / scripts.build / scripts.test |
| README.md | ✓ | 含安装步骤、启动命令、环境变量说明 |
| .env.example | 推荐 | 环境变量模板（不含真实值） |

## 质量检查点

- [ ] `npm install && npm run build` 成功
- [ ] `npm test` 全部通过
- [ ] 无硬编码的 API URL / 端口 / 密钥
- [ ] 组件有基本的 props 类型定义
- [ ] 页面有基本的错误状态处理（loading / error / empty）
- [ ] 表单有输入校验和错误提示
- [ ] 可访问性：交互元素有 aria-label 或语义化标签
