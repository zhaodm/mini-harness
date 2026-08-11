---
name: mh-dev-test
description: This skill should be used during the verify phase of mh-dev, when Tester is executing acceptance tests, or when performing adversarial verification and free exploration. Tester workflow SOP with snapshot capture, AC/AX verification, free exploration, permission check, and verdict production.
---

# mh-dev-test: Tester 工作流程 + 失败分类 SOP

> 角色契约见 `tools/mh-dev/agents/tester.md`。本 skill 承载 Tester 的工作流程步骤和失败分类规则。

## 失败分类规则

验收失败时，必须对每个失败项判定类型：

| 类型 | 含义 | 判定依据 |
|------|------|----------|
| FAIL_IMPL | 代码逻辑错误 | Developer 按验收标准即可修复 |
| FAIL_DESIGN | 设计层面问题 | 代码行为看起来是"按某种设计正确实现的"，但仍不符合验收预期 |
| FAIL_REQUIREMENT | 需求问题 | 需求本身有歧义、不完整、自相矛盾 |

**判定原则：**

- 如果代码逻辑看起来是"有意为之"（非 bug），但行为不符合验收标准 → FAIL_DESIGN
- 如果验收标准本身有歧义，无法确定"正确行为"是什么 → FAIL_REQUIREMENT
- 其他所有情况 → FAIL_IMPL

## 测试用例规范

- 测试文件放在 `tools/mh-dev/tests/` 或 `tests/` 目录下
- shell 测试命名：`test-<feature>.sh`
- node 测试命名：`test-<feature>.js`
- 测试应覆盖：
  - 正向验证（新行为生效）
  - 反向验证（旧行为不再存在）
  - 边界场景（如适用）
- 测试用例是交付物的一部分，会被提交到仓库

---

## 阶段一：采集 Tester 快照

```bash
# 开发前基线（Developer 的 after 快照即为 Tester 的 before 基线）
bash tools/mh-dev/scripts/capture-snapshot.sh --role tester --round <N> --kind before
```

## 阶段二：功能验收（AC 条目逐条验证）

1. 读取 `acceptance-criteria.json` 中 `kind: "AC"` 的条目
2. 逐条设计测试用例并执行
3. 记录每条 PASS/FAIL，失败项标注失败类型

## 阶段三：对抗性验收（AX 条目逐条探测）

1. 读取 `acceptance-criteria.json` 中 `kind: "AX"` 的条目
2. 针对每个 AX 条目（边界值、错误路径、集成点、回归、隐含约束）：
   - 阅读变更文件的实际代码
   - 设计针对性的破坏性测试
   - 执行并记录结果
3. 对抗性验收失败同样计入 verdict

## 阶段四：自由探索（超出 AC/AX 的发现）

基于对变更文件代码的阅读，主动探索以下未被 AC/AX 覆盖的场景：

- **死代码/孤立引用** — 改动是否遗留无用的 import、变量、函数
- **文档一致性** — 代码行为与注释/文档是否矛盾
- **命名一致性** — 新增标识符是否符合项目既有命名规范
- **顺序依赖** — 是否存在隐式的执行顺序假设
- **状态隔离** — mh-dev 运行态是否污染 `/mh-run` 的无活跃需求行为

自由探索发现的问题归类为 FAIL_IMPL（除非明显是设计/需求层面的缺陷）。

## 阶段五：按影响范围测试 + 权限校验

```bash
# 全量回归
bash tests/run-all-tests.sh

# 框架自检
bash scripts/check-harness.sh

# mh-dev 预检
bash tools/mh-dev/scripts/audit-preflight.sh
```

执行受影响测试子集 + 格式检查。如有失败，定位原因并归类。

```bash
# 采集 after 快照
bash tools/mh-dev/scripts/capture-snapshot.sh --role tester --round <N> --kind after

# 验证 Tester 变更归属
bash tools/mh-dev/scripts/validate-changes.sh \
  --role tester --round <N> \
  --before tools/mh-dev/.mh-dev/snapshots/tester.r<N>.before.json \
  --after tools/mh-dev/.mh-dev/snapshots/tester.r<N>.after.json
```

确认 Tester 只修改了测试文件和专属 evidence。如果输出 FAIL，撤回违规文件的修改。

## 阶段六：产出验收结果

输出两个文件（格式见 `tools/mh-dev/templates/test-report-template.md`）：

### test-verdict.json（机器可读）

```json
{
  "schema_version": 1,
  "role": "tester",
  "round": 1,
  "verdict": "PASS",
  "generated_at": "{timestamp}",
  "delta_ref": "snapshots/developer.r1.after.json",
  "commands": [
    {
      "id": "cmd-01",
      "command": "bash tests/run-all-tests.sh",
      "cwd": "{project_root}",
      "started_at": "{timestamp}",
      "ended_at": "{timestamp}",
      "exit_code": 0,
      "summary": "全部测试通过"
    }
  ],
  "acceptance": [
    {
      "id": "AC-01",
      "status": "PASS",
      "evidence": ["cmd-01"],
      "summary": "功能验证通过"
    }
  ],
  "failures": [],
  "summary": "所有验收项通过。"
}
```

**verdict 字段取值规则：**

- 全部通过 → `"PASS"`
- 有任何 FAIL_DESIGN 项 → `"FAIL"`（disposition 字段标注 `FAIL_DESIGN`）
- 有任何 FAIL_REQUIREMENT 项 → `"FAIL"`（disposition 字段标注 `FAIL_REQUIREMENT`）
- 仅有 FAIL_IMPL 项 → `"FAIL"`（disposition 字段标注 `FAIL_IMPL`）
- 环境阻断无法执行 → `"BLOCKED"`

### test-report.md（人类可读）

通过时和失败时的格式见 `tools/mh-dev/templates/test-report-template.md`。
