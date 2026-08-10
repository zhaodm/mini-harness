# mh-dev

`mh-dev` 是 Mini-Harness 的自开发控制面：它直接治理本仓库的 `agents/`、`skills/`、`scripts/`、`workflows/`、`templates/`、`.claude/`、文档与测试。

它不替代 `/mh-run`。`/mh-run` 使用 Mini-Harness 交付外部项目；`mh-dev` 维护 Mini-Harness 本身。

## 使用

从仓库根目录运行：

```bash
bash tools/mh-dev/start.sh
bash tools/mh-dev/scripts/verify.sh
```

运行态仅写入 `tools/mh-dev/.mh-dev/`，并被 Git 忽略。该目录的 `state.json` 仅是 mh-dev 流程的权威状态，不影响外部项目工作流的 `deliverables/<REQ-ID>/.state.md`。

## 轨道

- `fast`：局部文档、配置或明确缺陷修复。
- `light`：有限跨文件行为改动。
- `formal`：工作流、角色权限、状态、验证、命令面、发布契约或多子系统改动。

所有轨道都要求人工确认。涉及治理关键路径或未闭合 AX 验收项时，必须升级到 `formal`。

## 发布边界

mh-dev 只生成 release candidate、验证证据和人工后续命令；不得自动执行 commit、tag、push、publish 或创建远程发行。
