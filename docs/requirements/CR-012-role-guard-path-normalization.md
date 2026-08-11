# CR-012: role-guard mh-dev 分支路径归一化

## 背景

在 mh-dev 需求开发流程中，Developer SubAgent 使用 Write tool 修改 `approved_scope` 内的文件时频繁被 role-guard 拦截，报错形态为 "No stderr output" / "BLOCKED: mh-dev 未批准写入路径"。

## 根因

`scripts/role-guard.sh` 第 36 行 mh-dev 分支使用 `jq 'index($path)'` 对 `approved_scope` 做精确字符串匹配：

- `approved_scope` 存储仓库根相对路径（如 `scripts/role-guard.sh`），由 Planner 基于 scope-scan 结果写入
- Write tool 传入的 `file_path` 为绝对路径（如 `/Users/devin/.../scripts/role-guard.sh`）
- 绝对路径 ≠ 相对路径 → `index()` 返回 null → 匹配失败 → `exit 2` 拦截

对照 `tools/mh-dev/scripts/validate-changes.sh` 第 30 行已用 `os.path.join(root,p)` 归一化后再比较，事后校验能 PASS；但 role-guard 是 PreToolUse hook，在 Write 执行前拦截，漏了归一化，导致 Developer 实际写不进去。

## 需求

### R1: mh-dev 分支路径归一化

role-guard.sh mh-dev 分支在调用 `jq index()` 前，须将 `FILE_PATH` 归一化为仓库根相对路径后再与 `approved_scope` 比较。归一化口径须与 validate-changes.sh 一致（绝对路径剥离仓库根前缀；已是相对路径则原样使用）。

### R2: 归一化须早于 sensitive 路径检查

第 37-41 行的 sensitive 路径判定（`case "$FILE_PATH" in ...）也使用传入的 `FILE_PATH`。归一化须在进入该 `case` 之前完成，使 sensitive 检查也基于相对路径——否则归一化只修了 index() 而 sensitive case 仍因绝对路径不匹配而误放行治理关键路径。

### R3: deliverables 分支不受影响（确认项，非改动）

第 61-93 行 `check_permission` 使用 `[[ =~ ]]` 正则子串匹配，绝对路径能命中。本次不改动该分支。

## 影响范围

- `scripts/role-guard.sh` — 唯一需修改的源文件（第 31-47 行 mh-dev 分支内插入归一化）
- `tests/test-role-guard.sh` — 需新增绝对路径放行测试（由 Tester 产出）
- `docs/source-of-truth.md` / `CLAUDE.md` — 若描述了 role-guard 匹配口径须同步（由 doc-sync 检查触发，视实际描述而定）

## 非目标

- 不修改 validate-changes.sh（已正确归一化）
- 不修改 deliverables 分支的 check_permission 正则逻辑
- 不修改 approved_scope 的存储约定（仍存相对路径）

## 补充需求（用户追加）

调查 role-guard bug 过程中发现两个相关联的框架缺陷，并入本 CR 一起修复：

### R4: round 口径统一为 repair.round

**现状 bug**：round 口径在三处冲突：
- CLAUDE.md `for round in 1..max_rounds`（首轮=1）
- state.json `repair.round`（首轮=0，进 repair 才 +1）
- validate-outputs.sh 用 `repair.round` 校验 verdict/snapshot/attribution 的 round 字段
- dispatch-prompts.md 用 `<N>` 占位符不明确，fast 轨写 0

**修复**：统一以 `state.json` 的 `repair.round` 为单一真相源。
- 首轮（非修复）round=0
- 第 N 次修复 round=N
- CLAUDE.md 循环语义改为 `for round in 0..max_rounds`（或等价表述）
- dispatch-prompts.md 的 `<N>` 明确为"取 state.json 的 repair.round 值"
- validate-changes.sh / validate-outputs.sh / capture-snapshot.sh 口径一致

### R5: done 门禁字段回填

**现状 bug**：`check-transition.sh` 要求 done 时 `mechanical_preflight=='pass'` 且 `test_verdict=='PASS'`，但无脚本写入这两个字段。done 转移永远 BLOCKED。

**修复**：在 validate-outputs.sh verify PASS 后，或 transition-state.sh done 时，回填这两个字段：
- `mechanical_preflight = 'pass'`（当 audit-preflight.sh / verify.sh 通过）
- `test_verdict = 'PASS'`（当 test-verdict.json verdict==PASS）

取实现更简洁且单一真相源者。

## 影响范围（补充）

- scripts/role-guard.sh（R1-R3，已修）
- tests/test-role-guard.sh（R1-R3 测试，Tester 已写）
- docs/source-of-truth.md / CLAUDE.md / README.md / docs/workflow.md（R1-R3 文档同步，已修）
- tools/mh-dev/scripts/validate-outputs.sh（R4 round 口径 + R5 回填）
- tools/mh-dev/scripts/validate-changes.sh（R4 round 口径对齐，若需）
- tools/mh-dev/scripts/capture-snapshot.sh（R4，若需）
- tools/mh-dev/CLAUDE.md（R4 循环语义表述）
- tools/mh-dev/templates/dispatch-prompts.md（R4 N 取值说明）
