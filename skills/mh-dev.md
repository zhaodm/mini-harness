# mh-dev

`/mh-dev` 用于开发、治理、验证和准备发布 **Mini-Harness 自身**。它与 `/mh-run` 严格分离：`/mh-run` 使用框架交付外部项目；mh-dev 直接修改本仓库受版本控制的框架文件。

## 执行入口

- `/mh-dev`（无参数）→ 开发轨
- `/mh-dev audit` → 审计轨（独立流程，不修改开发轨状态）

1. 完整读取 `tools/mh-dev/CLAUDE.md`。
2. 确认当前目标是 Mini-Harness 自身，而非外部项目；否则改用 `/mh-run`。
3. 使用 `tools/mh-dev/.mh-dev/state.json` 维护 mh-dev 生命周期状态。该状态仅适用于本工具，不取代外部项目的 `deliverables/<REQ-ID>/.state.md`。
4. 依次执行 intake → propose → develop → verify → done；每次推进前运行 `tools/mh-dev/scripts/check-transition.sh`。
5. 使用 `tools/mh-dev/scripts/verify.sh` 完成机械验证。经 Tester 结构化 PASS 后，转移到 done 终态，等待用户确认提交。

## 安全边界

- 直接修改的对象是 Mini-Harness 根目录的 `agents/`、`skills/`、`scripts/`、`workflows/`、`templates/`、`.claude/`、`docs/`、`tests/` 等文件。
- 所有轨道都需要人工确认；formal 轨道还需要需求与设计审批，以及 AC/AX 验收标准。
- 开发轨终态为 done，用户手动 git commit。禁止自动 commit、tag、push、publish 或创建远程发行。
