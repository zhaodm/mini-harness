# docs/ 目录导航

## 目录结构

| 目录 | 用途 |
|------|------|
| `kb/` | 框架知识库（system-map + domains + recipes + kb-verify.sh） |
| `designs/` | 设计文档（架构地图 + 流程总览 + 权威源映射） |
| `designs/modules/` | 子模块深度设计文档（预留，后续 CR 填充） |
| `designs/cr-designs/` | CR（变更请求）设计文档 |
| `requirements/` | CR 需求单 |
| `audits/` | 审计报告 |
| `retrospectives/` | 复盘报告 |

## 知识库

`docs/kb/` 是 AI 和开发者理解框架的主要入口。

- **Layer 0**: `kb/system-map.md` — 全景入口，六域速查
- **Layer 1**: `kb/domains/*.md` — 域指南（roles/skills/workflow/guards/templates/mh-dev）
- **Layer 2**: `kb/recipes/*.md` — 操作食谱
- **校验**: `kb/kb-verify.sh` — 新鲜度与覆盖检查

修改框架代码后建议同步更新对应域指南。详见 [kb/README.md](kb/README.md)。

## 设计文档

`docs/designs/` 归集所有设计文档：

| 文件 | 说明 |
|------|------|
| `designs/design.md` | 架构地图，每个概念一句话 + 指向权威源 |
| `designs/workflow.md` | 流程总览 + 状态机 |
| `designs/source-of-truth.md` | 权威源映射表 |
| `designs/modules/` | 子模块深度设计（预留） |
| `designs/cr-designs/` | CR 设计文档（CR-004 起） |
