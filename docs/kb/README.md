# 框架知识库 (docs/kb/)

## 分层结构

| 层级 | 目录 | 用途 | 行数约束 |
|------|------|------|---------|
| Layer 0 | `system-map.md` | 全景入口，AI 读完后判断任务涉及哪个域 | ≤150 行 |
| Layer 1 | `domains/*.md` | 域指南，6 份，每域一份（roles/skills/workflow/guards/templates/mh-dev） | ≤400 行/份 |
| Layer 2 | `recipes/*.md` | 操作食谱，逐步指南（如添加新 Skill） | ≤80 行/份 |
| 校验 | `kb-verify.sh` | 新鲜度与覆盖检查脚本 | — |

## 渐进式阅读路径

1. **入门**：先读 `system-map.md` 建立框架心智模型
2. **深入**：根据任务涉及域，读对应 `domains/*.md`
3. **操作**：如需执行常见任务，查 `recipes/*.md`

## 六域速查

| 域 | 对应源码 | 域指南 |
|----|---------|--------|
| Roles | `agents/` | `domains/roles.md` |
| Skills | `skills/` | `domains/skills.md` |
| Workflow | `workflows/` | `domains/workflow.md` |
| Guards | `scripts/` | `domains/guards.md` |
| Templates | `templates/` | `domains/templates.md` |
| mh-dev | `tools/mh-dev/` | `domains/mh-dev.md` |

## 维护保障

### kb-verify.sh

校验脚本，检测知识库是否需要同步更新：

```bash
# 普通模式：有 WARN 不阻断
bash docs/kb/kb-verify.sh

# strict 模式：WARN 升级为 ERROR，退出码 1
bash docs/kb/kb-verify.sh --strict
```

### 检查项

| 检查项 | 严重级 | 说明 |
|--------|--------|------|
| 结构完整性 | ERROR | system-map.md + 6 份 domains/ + README.md + kb-verify.sh 存在且非空 |
| 行数约束 | WARN（strict→ERROR） | Layer 0 ≤150、Layer 1 ≤400、Layer 2 ≤80 |
| 路径有效性 | WARN | 域指南引用的文件路径存在 |
| 新鲜度检测 | WARN（strict→ERROR） | 域指南不比对应源码旧 |

### 退出码语义

- 无 ERROR 无 WARN → exit 0
- 有 WARN 无 ERROR → exit 0（普通）/ exit 1（--strict）
- 有 ERROR → exit 1

### 维护建议

- 修改框架代码后，运行 `bash docs/kb/kb-verify.sh` 检查知识库是否需要同步
- 域指南的"文件清单与影响范围"章节是核心价值——改文件时直接查"改动时需同步检查"列
- 新增模块时，同步更新对应域指南的文件清单
