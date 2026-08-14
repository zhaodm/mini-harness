# CLI Tool 产出结构参考

> 适用于 output_type=cli-tool。不绑定具体框架，描述通用命令行工具的产出结构。
> 目录规范见 `templates/output-structure.md`。

## 推荐目录结构

```
deliverables/{project}/
├── src/
│   ├── commands/        # 子命令实现（每个命令一个文件）
│   ├── core/            # 核心业务逻辑（不依赖 CLI 框架）
│   ├── utils/           # 工具函数（文件操作、格式化、网络）
│   ├── config/          # 配置加载（CLI 参数 + 配置文件 + 环境变量）
│   ├── types/           # 类型定义
│   └── main.{ts|py|go} # 入口（解析参数、路由到子命令）
├── tests/
│   ├── unit/            # 单元测试（core 逻辑）
│   └── integration/     # 集成测试（完整命令执行）
├── deploy/              # 部署相关（发布脚本, CI/CD）
├── package.json / pyproject.toml / go.mod  # 依赖管理
└── README.md            # 使用说明 + 命令参考
```

## 关键文件说明

| 文件/目录 | 必须 | 说明 |
|-----------|------|------|
| src/main.* | ✓ | 入口，解析参数并路由 |
| src/commands/ | ✓ | 每个子命令独立文件 |
| src/core/ | ✓ | 业务逻辑，与 CLI 框架解耦（便于测试） |
| tests/ | ✓ | 至少覆盖核心逻辑 + 主要命令 |
| README.md | ✓ | 含安装方式、命令列表、使用示例 |

## 质量检查点

- [ ] 主命令 `--help` 输出清晰的使用说明
- [ ] 每个子命令有 `--help` 描述
- [ ] 必填参数缺失时给出明确错误提示（不是 stack trace）
- [ ] 非法输入时退出码非 0，并输出人类可读的错误信息到 stderr
- [ ] 成功执行退出码为 0
- [ ] 支持 `--version` 输出版本号
- [ ] 长时间操作有进度提示（spinner 或进度条）
- [ ] 核心逻辑与 CLI 框架解耦（core/ 可独立测试）
- [ ] 配置优先级正确：CLI 参数 > 环境变量 > 配置文件 > 默认值
- [ ] 无硬编码路径（使用相对路径或可配置路径）
