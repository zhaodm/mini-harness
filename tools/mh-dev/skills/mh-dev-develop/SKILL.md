---
name: mh-dev-develop
description: This skill should be used during the develop phase of mh-dev, when Developer is executing code changes, or when performing impact analysis and modification planning. Developer workflow SOP with requirement understanding, impact analysis, modification planning, execution, self-repair, and report production.
---

# mh-dev-develop: Developer 工作流程 SOP

> 角色契约见 `tools/mh-dev/agents/developer.md`。本 skill 承载 Developer 的工作流程步骤。

## 1. 理解需求

读取 `requirement.md` 和 `acceptance-criteria.json`，明确：

- 要改什么（功能目标、行为变更）
- 改动的边界（不做什么——非目标）
- 成功标准（每条 AC/AX 的期望结果）
- `approved_scope` 限定的文件范围

## 2. 影响分析（先搜后改）

```bash
# 从需求中提取关键词，全仓库搜索
grep -rn "关键词1\|关键词2\|旧路径" agents/ skills/ scripts/ workflows/ templates/ .claude/ docs/ tests/ --include='*.md' --include='*.sh' --include='*.js' --include='*.json'
```

**仔细阅读搜索结果**，确认所有需要修改的文件列表。不要遗漏。不要凭记忆假设影响范围。

## 3. 制定修改计划

列出需要修改的文件及修改内容，按以下分类和优先级：

| 优先级 | 类别 | 关注点 |
|--------|------|--------|
| P0 | 治理核心（`CLAUDE.md`、`scripts/role-guard.sh`、状态 schema） | 逻辑正确性、角色隔离 |
| P1 | 脚本（`scripts/*.sh`、`tools/mh-dev/scripts/*.sh`） | 路径引用、退出码语义 |
| P2 | 工作流（`workflows/lib/*.js`） | 决策逻辑、契约引用 |
| P3 | 技能/角色协议（`skills/*.md`、`agents/*.md`、`tools/mh-dev/agents/*.md`） | 与脚本行为一致 |
| P4 | 模板（`templates/*.md`、`templates/*.json`） | 格式契约 |
| P5 | 文档（`README.md`、`docs/*.md`、`docs/designs/source-of-truth.md`） | 与实现一致 |
| P6 | 测试（`tests/*.sh`、`tests/*.js`、`tools/mh-dev/tests/*.sh`） | 覆盖变更 |

## 4. 执行修改

按计划逐一修改。每改完一个文件确认改动正确。**匹配现有风格**，不引入新模式。

## 5. 内部自修复

如果 `bash tools/mh-dev/scripts/validate-changes.sh` 失败：

1. 分析错误输出，定位失败原因
2. 修复代码或撤回越权文件
3. 重新执行 validate-changes.sh
4. 内部最多重试 3 次

如果 3 次内部重试后仍有失败项，在 dev-report.md 中标注未解决项及原因，正常退出。

## 6. 退出前必做

```bash
# 采集 after 快照
bash tools/mh-dev/scripts/capture-snapshot.sh --role developer --round <N> --kind after

# 验证变更归属
bash tools/mh-dev/scripts/validate-changes.sh \
  --role developer --round <N> \
  --before tools/mh-dev/.mh-dev/snapshots/developer.<N>.before.json \
  --after tools/mh-dev/.mh-dev/snapshots/developer.<N>.after.json
```

确认输出无 FAIL。如果输出 FAIL，撤回违规文件的修改，重新调整实现方案。

## 7. 产出报告

将修改总结写入 `tools/mh-dev/.mh-dev/evidence/dev-report.md`（格式见 `tools/mh-dev/templates/dev-report-template.md`）。
