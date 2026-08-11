---
name: mh-dev-audit
description: This skill should be used during mh-dev audit track, when Auditor is executing deep architecture audit, or when performing semantic verification of AC/AX items. Auditor audit methodology SOP with Phase 0-7, root cause analysis, and report production.
---

# mh-dev-audit: Auditor 审计方法论 SOP

> 角色契约见 `tools/mh-dev/agents/auditor.md`。本 skill 承载 Auditor 的审计方法论 Phase 0-7。

## Phase 0: 范围确定 + 复杂度分级

1. 读取 `state.json` 的 `baseline` 和当前 HEAD
2. 审计范围 = baseline..HEAD + 已验证的 worktree changes
3. 执行 `git log --oneline --stat <range>` 确认提交列表和变更量
4. **全量审计**：所有审计均执行 Phase 1–5，不做分级裁剪。Phase 0（范围确定）、Phase 6（报告输出）、Phase 7（自检）同样始终执行。

## Phase 1: 预检门禁

```bash
bash tools/mh-dev/scripts/audit-preflight.sh
```

收集：脚本可执行性、命令/技能注册一致性、禁止外发操作扫描、文档引用一致性。

**门禁规则：** 全部 PASS 方可继续。若有 FAIL 项：

- 列入报告"已知基线问题"章节
- 评估是否影响本次审计准确性
- 如影响准确性，停止审计并输出阻断原因

## Phase 2: 需求审计

检查 `requirement.md` 和 `acceptance-criteria.json`：

| 检查点 | 关注内容 |
|--------|----------|
| 无歧义 | 无多义词、模糊量词、无边界条件的描述 |
| 完整性 | 功能需求 + 对抗性需求（AX） |
| 验收标准 | 每条 AC/AX 有非空说明和可验证要求 |
| 占位符 | 无 TBD/TODO/待补充 |
| ID 一致性 | acceptance-criteria.json 与 acceptance-criteria.md 的 ID 集合一致 |

## Phase 3: 设计审计

| 检查点 | 关注内容 |
|--------|----------|
| 轨道适当性 | track 是否与变更影响匹配；治理关键路径是否 formal |
| 范围完整性 | approved_scope 是否覆盖了所有实际变更路径 |
| 最优性 | 是否有更简方案？是否过度设计？ |
| 缺陷识别 | 脆弱点、隐式依赖、硬编码、不可逆变更 |
| 兼容性 | 是否与现有框架契约冲突？ |
| 迁移策略 | 老代码如何适配？是否有过渡方案？ |
| 设计理由 | 为何选择此方案（trade-off 是否记录） |

## Phase 4: 实现审计（所有级别）

按优先级阅读变更文件：

| 优先级 | 类别 | 关注点 |
|--------|------|--------|
| P0 | 治理核心（`CLAUDE.md`、`scripts/role-guard.sh`、状态 schema） | 逻辑正确性、角色隔离、状态源隔离 |
| P1 | 脚本（`scripts/*.sh`、`tools/mh-dev/scripts/*.sh`） | 路径引用、退出码语义、NUL 安全解析 |
| P2 | 工作流（`workflows/lib/*.js`） | 决策逻辑、契约引用 |
| P3 | 技能/角色协议（`skills/*.md`、`agents/*.md`、`tools/mh-dev/agents/*.md`） | 与脚本行为一致、自包含 |
| P4 | 模板（`templates/*.md`、`templates/*.json`） | 格式契约 |
| P5 | 文档（`README.md`、`docs/*.md`） | 与实现一致 |
| P6 | 测试（`tests/*.sh`、`tests/*.js`、`tools/mh-dev/tests/*.sh`） | 覆盖变更、负例 |

每个文件关注：

- **实现-设计一致性**：代码是否符合设计方案，有无偏差或超范围实现
- 路径引用是否指向实际存在的文件
- 退出码语义是否与门禁判定一致（0=PASS、1=BLOCKED、2=用法错误）
- JSON schema 字段是否与 `validate-outputs.sh` 校验逻辑匹配
- 角色写入白名单是否与 `role-guard.sh` 的判定一致

**根因分析**（对每个发现的问题）：

1. **追问两层 Why**：症状 → 直接原因 → 根本原因
2. **构建因果链**：commit → 代码变更 → 引入 bug → 运行时表现 → 测试/用户影响
3. **复现与验证**：执行实际命令验证，不接受纯目视断言
4. **影响范围评估**：这个问题影响多少文件/功能/用户路径
5. **同类穷举**：发现 1 个文件有问题，立即检查所有同类文件

**架构评价**：

| 评价维度 | 关注点 |
|---------|--------|
| 方向正确性 | 变更是否符合架构演进路线 |
| 执行完成度 | 迁移/重构是否彻底，有无遗漏 |
| 一致性 | 代码/文档/配置三者是否同步 |
| 防御性 | 是否引入新的脆弱点（硬编码、隐式依赖） |
| 可逆性 | 问题是否容易修复，还是已造成不可逆扩散 |
| 状态隔离 | mh-dev 运行态是否污染 `/mh-run` 的状态源 |
| 劣化判断 | 架构整体是否比变更前更好还是更差 |

## Phase 5: 测试审计（所有级别）

| 检查点 | 关注内容 |
|--------|----------|
| 需求-测试追溯 | 每条 AC/AX 是否有对应测试用例 |
| 测试通过率 | 是否全部通过，失败项根因 |
| 回归影响 | 是否影响了现有测试（新增失败） |
| 覆盖度 | 核心路径 vs 边界场景 vs 异常路径 |
| 负例覆盖 | 是否覆盖了越权、升级、repair 上限等反例 |
| 补充建议 | 修复区域是否缺乏测试覆盖，建议补充哪些用例 |

## Phase 6: 报告输出

> 格式骨架见 `tools/mh-dev/templates/audit-report.md`。

### semantic-verdict.json（机器可读，权威）

```json
{
  "schema_version": 1,
  "role": "auditor",
  "round": 1,
  "verdict": "PASS",
  "generated_at": "{timestamp}",
  "tester_verdict_ref": "evidence/test-verdict.json",
  "mechanical_preflight": {
    "exit_code": 0,
    "evidence": "evidence/audit-preflight.json"
  },
  "acceptance": [
    {
      "id": "AC-01",
      "status": "PASS",
      "evidence": ["audit-01"],
      "summary": "实现与验收一致"
    }
  ],
  "evidence": [
    {
      "id": "audit-01",
      "kind": "inspection",
      "location": "{file_path}",
      "summary": "{检查摘要}"
    }
  ],
  "findings": [],
  "disposition": "PASS",
  "release_recommendation": "APPROVE"
}
```

**verdict 字段取值规则：**

- 全部通过 → `"PASS"`，disposition `"PASS"`，release_recommendation `"APPROVE"`
- 有实现缺陷 → `"FAIL"`，disposition `"FAIL_IMPL"`，release_recommendation `"BLOCKED"`
- 有设计缺陷 → `"FAIL"`，disposition `"FAIL_DESIGN"`，release_recommendation `"BLOCKED"`
- 有需求缺陷 → `"FAIL"`，disposition `"FAIL_REQUIREMENT"`，release_recommendation `"BLOCKED"`
- 环境阻断 → `"BLOCKED"`，disposition `"BLOCKED"`，release_recommendation `"BLOCKED"`

**disposition 不触发状态转移。** 审计只产出报告。disposition 标注问题类型供用户参考，不触发任何状态转移。修复由用户另起 `/mh-dev` 会话执行。

### semantic-report.md（人类可读）

格式见 `tools/mh-dev/templates/audit-report.md`。

## Phase 7: 自检

全量执行所有自检项：

1. **路径验证**：`ls <claimed_path>` 或 `grep -n '<pattern>' <file>` 确认存在
2. **修复方案验证**：确认建议的修复代码语法正确、引用的函数/模块存在
3. **覆盖完整性**：对同类问题用 `grep` 确认是否还有遗漏的同类文件
4. **措辞精确性**：重读报告，确认每句话的主语/因果关系无歧义
5. **四层覆盖验证**：按分级确认需求/设计/实现/测试各层均已审计到位
6. **开发规范遵守检查**：确认变更是否遵守 Mini-Harness 开发规范（CR 单、设计文档、Tester 验收、文件白名单、轨道匹配）
7. **运行时协议自包含性**：角色协议不应隐式依赖设计文档；复杂逻辑优先由脚本返回值传递
