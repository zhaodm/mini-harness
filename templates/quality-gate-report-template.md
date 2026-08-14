<!-- 质量门禁失败报告模板
  使用场景: Orchestrator 执行 test_strategy 门禁命令后发现错误，需归因并派发修复
  使用方式: 复制到 deliverables/{project}/.engine/quality-gate-report.md 并填写
-->
---
report_id: "QG-B{N}-001"
phase: "Batch-{N} 质量门禁"
gate_command: "{从 .engine/.state.md test_strategy 读取}"
result: "{PASS | FAIL (N errors)}"
created_at: "{YYYY-MM-DDTHH:MM:SSZ}"
---

# 质量门禁报告 — Batch-{N}

## 门禁命令

```bash
{实际执行的命令}
```

## 结果: {PASS | FAIL}

{错误总数} 个错误，归因分布: {Task-X: N个, Task-Y: M个}

## 错误清单

| # | 文件:行 | 错误信息 | 归因 Task | 修复方向 |
|---|---------|---------|-----------|---------|
| 1 | | | | |

## 集成问题（跨 Task，无法归因到单一 Task）

| # | 涉及 Task | 冲突描述 | 指定修复 Worker |
|---|-----------|---------|------------|
| 1 | | | |

## 根因分析

{简要说明错误的系统性根因，帮助 Worker 理解问题本质}

## 影响范围

{列出受影响的文件和模块，帮助 Worker 评估修复边界}
