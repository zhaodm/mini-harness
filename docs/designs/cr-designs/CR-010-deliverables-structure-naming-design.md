# CR-010 技术设计：deliverables 目录结构规范化 — 引擎态分离 + 命名统一 + 产出即归档

> CR: CR-010-deliverables-structure-naming
> 日期: 2026-08-11
> 状态: 设计中
> 参考: psdt-agent CR018 的 .engine/ 思路

---

## 1. 架构定位

三个问题共享一个架构根因：`deliverables/{REQ-ID}/` 目录同时承载引擎运行态、过程角色产出和最终交付件，且通过根 `output/` 做二份存放。本设计分三层修复：

| 层 | 修复 | 对应问题 |
|----|------|----------|
| 引擎态隔离层 | 运行态文件归入 `.engine/` | 问题1（引擎态与产品产出混放） |
| 命名统一层 | `<ROLE>-<phase>-<name>.md` 规则 + 目录扁平化 | 问题2（文件命名不统一） |
| 产出即归档层 | 取消 output/ 二份存放，设计阶段规划目录结构 | 问题3（源产出与归档目标二份存放） |

---

## 2. 引擎态隔离设计（问题1）

### 2.1 .engine/ 目录结构

```
deliverables/{REQ-ID}/
├── .engine/                    ← 引擎运行态（平铺）
│   ├── .state.md               ← 流程状态
│   ├── handoffs/               ← SubAgent 交接文件
│   ├── process.log             ← 执行日志
│   ├── lessons.md              ← 经验采集（过程暂存）
│   ├── SR{N}-record.md         ← 审批记录
│   └── plan-action.md          ← 执行计划
├── .archiveignore              ← 归档排除规则（Thinker 产出，非引擎态）
├── proposal.md                 ← Orchestrator 产出
├── THINKER-propose-*.md        ← Thinker 产出（命名见 §3）
├── WORKER-apply-*.md           ← Worker 产出
├── VERIFIER-apply-*.md         ← Verifier 产出
└── {项目代码目录}              ← Worker 按 design.md 规划
```

**设计决策：**

| 决策 | 内容 | 理由 |
|------|------|------|
| .engine/ 内部平铺 | 不再分层（无 handoffs/ 子目录的子目录） | 文件数量少（6 项），平铺足够清晰 |
| .engine/ 内文件名保持原样 | .state.md 等不改名 | 被 702 处脚本硬编码引用，改名风险极高；dotfile / .log 后缀自带"非产品产出"语义 |
| .archiveignore 不进 .engine/ | 保留在产品区根目录 | 由 Thinker 产出（非引擎运行态），且 verify-archive.sh ARC-1 直接读取 |
| 全局指针 deliverables/.state.md 不变 | 仍在 deliverables/ 根 | 全局指针指向活跃 REQ-ID，不属于单个 REQ-ID 的引擎态 |

### 2.2 迁移清单

| 旧路径 | 新路径 | 声明位置 |
|--------|--------|---------|
| `deliverables/{REQ-ID}/.state.md` | `deliverables/{REQ-ID}/.engine/.state.md` | 全部 skill/agent/script |
| `deliverables/{REQ-ID}/handoffs/` | `deliverables/{REQ-ID}/.engine/handoffs/` | orchestrator.md, mh-build, mh-repair |
| `deliverables/{REQ-ID}/process.log` | `deliverables/{REQ-ID}/.engine/process.log` | mh-codeflow, logging-standard.md |
| `deliverables/{REQ-ID}/lessons.md` | `deliverables/{REQ-ID}/.engine/lessons.md` | orchestrator.md, mh-deliver |
| `deliverables/{REQ-ID}/SR{N}-record.md` | `deliverables/{REQ-ID}/.engine/SR{N}-record.md` | orchestrator.md, mh-design, mh-build |
| `deliverables/{REQ-ID}/plan-action.md` | `deliverables/{REQ-ID}/.engine/plan-action.md` | orchestrator.md, mh-design, mh-build, mh-deliver |

---

## 3. 命名统一设计（问题2）

### 3.1 命名规则

```
<ROLE>-<phase>-<name>.md
```

- **ROLE**: `THINKER` | `WORKER` | `VERIFIER` | `ORCHESTRATOR`（大写）
- **phase**: `init` | `propose` | `apply` | `archive`（小写）
- **name**: 小写 kebab-case 描述名

正则：`^(THINKER|WORKER|VERIFIER|ORCHESTRATOR)-[a-z]+-[a-z0-9-]+\.md$`

### 3.2 命名映射表

| 旧路径 | 新路径 | 角色 | phase |
|--------|--------|------|-------|
| `thinker/requirement-spec.md` | `THINKER-propose-requirement-spec.md` | THINKER | propose |
| `thinker/design.md` | `THINKER-propose-design.md` | THINKER | propose |
| `thinker/verify-strategy.md` | `THINKER-propose-verify-strategy.md` | THINKER | propose |
| `thinker/slide-spec.md` | `THINKER-propose-slide-spec.md` | THINKER | propose |
| `thinker/wireframes/` | `THINKER-propose-wireframes/` | THINKER | propose |
| `worker/code-report-t{N}.md` | `WORKER-apply-code-report-t{N}.md` | WORKER | apply |
| `worker/code-report-r{N}.md` | `WORKER-apply-code-report-r{N}.md` | WORKER | apply |
| `worker/quality-gate-report-b{N}.md` | `WORKER-apply-quality-gate-report-b{N}.md` | WORKER | apply |
| `verifier/temp-test-report.md` | `VERIFIER-apply-temp-test-report.md` | VERIFIER | apply |
| `verifier/final-test-report.md` | `VERIFIER-apply-final-test-report.md` | VERIFIER | apply |
| `proposal.md` | `ORCHESTRATOR-init-proposal.md` | ORCHESTRATOR | init |

### 3.3 目录扁平化

**决策：** 取消 `thinker/`、`worker/`、`verifier/` 子目录。

**理由：** 命名前缀已承载角色信息，目录层级冗余。扁平化后：
- 文件名即可判断归属（`THINKER-propose-*` 一目了然）
- role-guard 白名单正则更简单（`deliverables/${req}/THINKER-.*\.md`）
- verify-archive.sh 重复检测简化（无需排除子目录）

**例外：** Worker 产出的项目代码（`src/`、`tests/`、`deploy/` 等）保留目录结构——这些是项目自身的代码组织，命名遵循项目规范，不受 R2 约束。

### 3.4 豁免范围

| 类别 | 示例 | 豁免理由 |
|------|------|---------|
| .engine/ 内文件 | .state.md, process.log | 引擎态，自带非产品语义 |
| 代码文件 | .ts, .py, .go | 消费者是编译器/运行时 |
| 机器数据 | .json | 脚本间传递的结构化数据 |
| 项目代码目录 | src/, tests/, deploy/ | 按设计文档规划，遵循项目规范 |

### 3.5 role-guard.sh 白名单适配

```bash
# ORCHESTRATOR
[[ "$file" =~ deliverables/${req}/\.engine/\.state\.md ]] && return 0
[[ "$file" =~ deliverables/${req}/\.engine/handoffs/.*\.md ]] && return 0
[[ "$file" =~ deliverables/${req}/\.engine/plan-action\.md ]] && return 0
[[ "$file" =~ deliverables/${req}/\.engine/SR.*-record\.md ]] && return 0
[[ "$file" =~ deliverables/${req}/\.engine/lessons\.md ]] && return 0
[[ "$file" =~ deliverables/${req}/\.engine/process\.log ]] && return 0
[[ "$file" =~ deliverables/${req}/ORCHESTRATOR-.*\.md ]] && return 0
[[ "$file" =~ deliverables/\.state\.md ]] && return 0    # 全局指针不变
# 移除: [[ "$phase" == "archive" && "$file" =~ ^output/docs/ ]] && return 0

# THINKER
[[ "$file" =~ deliverables/${req}/THINKER-.*\.md ]] && return 0
[[ "$file" =~ deliverables/${req}/\.archiveignore ]] && return 0

# WORKER
[[ "$file" =~ deliverables/${req}/WORKER-.*\.md ]] && return 0
# 项目代码路径由 handoff 白名单精确指定（按 design.md 规划）

# VERIFIER
[[ "$file" =~ deliverables/${req}/VERIFIER-.*\.md ]] && return 0
```

---

## 4. 产出即归档设计（问题3）

### 4.1 核心变更：取消 output/ 二份存放

**现状流程：**
```
Worker 产出 → deliverables/{REQ-ID}/output/（临时区）
ARC-3 归档 → 拷贝分流到 根 output/（归档区）
verify-archive.sh ARC-2 检测重复 + ARC-3 检测更新方向 + ARC-5 检测 REQ-ID 隔离
```

**新流程：**
```
需求阶段: needs-spec 声明产出物目录结构要求
设计阶段: design.md 规划完整目录结构（顶层目录 + 每个 Task 产出路径）
Worker 实现: 按 design.md 规划路径直接产出到 deliverables/{REQ-ID}/ 下最终位置
归档阶段: 无拷贝操作（产出已在正确位置）
```

### 4.2 需求模板变更

`templates/needs-spec-template.md` 新增字段：

```markdown
## 产出物目录结构要求

> 声明本项目期望的产出物顶层目录结构（Thinker 在设计阶段将细化为完整路径规划）

- 顶层目录: {如 src/, docs/, tests/, deploy/ ...}
- output_type: {code | ppt | documentation | infrastructure}
- 特殊要求: {如有}
```

### 4.3 设计模板变更

`templates/design-spec-template.md` 强制新增章节：

```markdown
## 产出物目录结构

> Thinker 在设计阶段规划完整产出物目录结构。Worker 按此路径落位。

### 顶层目录

| 目录 | 用途 | 产出角色 |
|------|------|---------|
| {src/} | {源代码} | {WORKER} |
| {tests/} | {测试代码} | {WORKER} |
| {docs/} | {项目文档} | {WORKER/ORCHESTRATOR} |

### Task 产出路径

| Task ID | 产出文件路径（相对 deliverables/{REQ-ID}/） | 验证方式 |
|---------|------------------------------------------|---------|
| Task-1 | src/api.ts | {验证方式} |
| Task-2 | tests/api.test.ts | {验证方式} |

### output_type 特化

| output_type | 目录差异 |
|-------------|---------|
| code | src/ + tests/ + docs/ + deploy/（按需） |
| ppt | HTML+CSS 直接放产品区根（无 src/），wireframes 放 THINKER-propose-wireframes/ |
| documentation | 无 src/，主产出在 docs/ |
| infrastructure | 主产出在 deploy/，src/ 可选 |
```

### 4.4 Worker handoff 路径变更

`templates/handoff-template.md` L57 注释更新：

```markdown
<!-- ⚠️ Orchestrator 自检: Worker 任务的输出路径必须以 deliverables/{REQ-ID}/ 开头，
且符合 design.md "产出物目录结构" 章节规划的路径，禁止自行决定路径 -->
```

### 4.5 mh-deliver ARC 步骤变更

| ARC 步骤 | 现状 | 新方案 |
|----------|------|--------|
| ARC-1 需求归档 | 复制 proposal.md → output/docs/spec/ | proposal 已在产品区，无拷贝（如需归档到 docs/spec/，由 Orchestrator 在 archive 阶段整理） |
| ARC-2 设计归档 | 复制 design.md → output/docs/spec/ | design 已在产品区，无拷贝 |
| ARC-3 产出物归档 | 按分流规则复制 output/ → 根 output/ | **取消**（产出已在正确位置） |
| ARC-4 参考资料归档 | 复制 reference/ → output/reference/ | reference/ 已在 deliverables/{REQ-ID}/reference/ |
| ARC-5 测试用例沉淀 | 写入 output/tests/regression-suite.md | 写入 deliverables/{REQ-ID}/tests/regression-suite.md |
| ARC-6 执行指标 | output/docs/metrics.md | deliverables/{REQ-ID}/docs/metrics.md |
| ARC-7 经验沉淀 | output/docs/lessons-learned.md | deliverables/{REQ-ID}/docs/lessons-learned.md（从 .engine/lessons.md 归档） |
| ARC-8 知识库 | output/docs/kb/ | deliverables/{REQ-ID}/docs/kb/ |

### 4.6 verify-archive.sh 变更

| 检查项 | 现状 | 新方案 |
|--------|------|--------|
| ARC-1 .archiveignore 禁止项 | 检查 output/ | 检查 deliverables/{REQ-ID}/ 产品区 |
| ARC-2 文件重复检测 | deliverables 顶层 vs output/ | **取消**（无二份存放） |
| ARC-3 更新方向检测 | output/ vs deliverables/output/ | **取消**（无拷贝） |
| ARC-4 归档非空 | 检查 output/ | 检查 deliverables/{REQ-ID}/ 产品区（排除 .engine/） |
| ARC-5 REQ-ID 隔离 | 检查 output/docs/ 下 req-id 子目录 | **取消**（产出已在 {REQ-ID}/ 下，天然隔离） |
| ARC-6 知识库 | 检查 output/docs/kb/ | 检查 deliverables/{REQ-ID}/docs/kb/ |
| ARC-7 目录结构合规 | 检查 output/ 顶层 | 检查 deliverables/{REQ-ID}/ 产品区顶层 |

### 4.7 detect-archive-mode.js / detect-scenario.js 变更

这两个 workflow lib 依赖 `output/spec/` 判断归档模式和新旧场景。新路径改为 `deliverables/{REQ-ID}/docs/spec/`。

- `detect-archive-mode.js`: `outputSpecFiles` 从 `output/docs/spec/` 读取改为 `deliverables/{REQ-ID}/docs/spec/`
- `detect-scenario.js`: 全局 `outputSpecFiles` 检查改为按活跃 REQ-ID 读取 `deliverables/{REQ-ID}/docs/spec/`

---

## 5. 完整目标目录结构

```
deliverables/
├── .state.md                                    ← 全局指针（不变）
└── {REQ-ID}/
    ├── .engine/                                  ← 引擎运行态（平铺）
    │   ├── .state.md
    │   ├── handoffs/
    │   │   └── {REQ-ID}-DEV1-T{N}-R{N}.md
    │   ├── process.log
    │   ├── lessons.md
    │   ├── SR1-record.md
    │   ├── SR3-record.md
    │   └── plan-action.md
    ├── .archiveignore                            ← Thinker 产出
    ├── ORCHESTRATOR-init-proposal.md             ← Orchestrator 产出
    ├── THINKER-propose-requirement-spec.md       ← Thinker needs 相位
    ├── THINKER-propose-design.md                ← Thinker design 相位
    ├── THINKER-propose-verify-strategy.md       ← Thinker design 相位
    ├── THINKER-propose-slide-spec.md            ← Thinker visual 相位（ppt track）
    ├── THINKER-propose-wireframes/               ← Thinker visual 相位（ppt track）
    ├── WORKER-apply-code-report-t1.md           ← Worker 每 Task 独立
    ├── WORKER-apply-code-report-t2.md
    ├── WORKER-apply-quality-gate-report-b1.md   ← Worker 质量门禁
    ├── VERIFIER-apply-temp-test-report.md       ← Verifier VERIFY-1
    ├── VERIFIER-apply-final-test-report.md      ← Verifier VERIFY-2
    ├── src/                                      ← Worker 项目代码（按 design.md 规划）
    │   └── {按 output-guide 组织}
    ├── tests/
    │   ├── {unit/, integration/, e2e/}
    │   └── regression-suite.md
    ├── docs/
    │   ├── spec/
    │   │   ├── requirement-spec.md              ← 归档的需求规格
    │   │   └── design.md                         ← 归档的技术设计
    │   ├── metrics.md
    │   ├── lessons-learned.md
    │   └── kb/                                   ← 知识库（用户请求时生成）
    ├── deploy/
    ├── assets/
    └── reference/
```

---

## 6. 影响范围与执行计划

### 6.1 影响模块汇总

| 层 | 模块 | 改动类型 |
|----|------|---------|
| 引擎态 | agents/*.md, skills/mh-*, scripts/*.sh, templates/*.md | 路径声明 → .engine/ 前缀 |
| 命名 | agents/*.md, skills/mh-*, templates/*.md | 产出文件名 → ROLE-phase-name.md |
| role-guard | scripts/role-guard.sh | 白名单正则重写 |
| 产出即归档 | skills/mh-deliver, scripts/verify-archive.sh, scripts/baseline.sh | 取消拷贝/重复检测/方向检测 |
| 模板 | templates/output-structure.md, needs-spec, design-spec, handoff-* | 重写/新增章节 |
| workflow lib | detect-archive-mode.js, detect-scenario.js, archive-merge.js | 路径适配 |
| 文档 | docs/design.md, docs/workflow.md, docs/source-of-truth.md | 路径引用同步 |
| 测试 | tests/test-*.sh, tests/test-*.js | 路径断言更新（Tester 执行） |

### 6.2 执行批次

| 批次 | 内容 | 验证 |
|------|------|------|
| 批次1 | R1 引擎态 .engine/ 分离 + role-guard.sh 白名单适配 | `bash tests/test-role-guard.sh` + `bash scripts/check-harness.sh` |
| 批次2 | R2 命名规则 + role-guard.sh 命名正则 + 目录扁平化 | `bash tests/test-role-guard.sh` + `bash scripts/check-harness.sh` |
| 批次3 | R3 产出即归档 + verify-archive.sh 适配 + 模板重写 | `bash scripts/verify-archive.sh` + `bash scripts/check-harness.sh` |
| 批次4 | R4 workflow lib + 文档同步 + 测试更新 | 全量测试 + `bash scripts/check-harness.sh` |

---

## 7. 机器可检查清单

```
CHECK: \.engine/ IN agents/*.md — 引擎态路径已更新
CHECK: \.engine/ IN skills/mh-*/SKILL.md — 引擎态路径已更新
CHECK: \.engine/ IN scripts/*.sh — 引擎态路径已更新
CHECK: THINKER-propose-|WORKER-apply-|VERIFIER-apply-|ORCHESTRATOR-init- IN agents/*.md — 命名规则已落地
CHECK: THINKER-propose-|WORKER-apply-|VERIFIER-apply-|ORCHESTRATOR-init- IN skills/mh-*/SKILL.md — 命名规则已落地
CHECK: deliverables/\$\{req\}/THINKER- IN scripts/role-guard.sh — 白名单已适配新命名
CHECK: deliverables/\$\{req\}/\.engine/ IN scripts/role-guard.sh — 白名单已适配 .engine/
CHECK: 产出物目录结构 IN templates/design-spec-template.md — 设计模板含强制章节
CHECK: 产出物目录结构要求 IN templates/needs-spec-template.md — 需求模板含字段
CHECK: deliverables/\{REQ-ID\}/ IN templates/output-structure.md — 产出结构规范已重写
```

---

## 8. 风险与缓解

| 风险 | 等级 | 缓解 |
|------|------|------|
| 702 处路径引用遗漏 | 中 | scope-scan 全量搜索 + 分批验证 + check-harness.sh 门禁 |
| role-guard 白名单正则过宽/过窄 | 中 | test-role-guard.sh 全量用例覆盖 + AX-02/AX-03 对抗性验证 |
| verify-archive.sh 取消 ARC-2/3/5 后逻辑断裂 | 低 | ARC-2/3/5 是独立函数，删除不影响 ARC-1/4/6/7 |
| detect-archive-mode.js / detect-scenario.js 路径适配 | 低 | 有对应测试覆盖（test-detect-archive-mode.js, test-detect-scenario.js） |
| Worker 自行决定路径（绕过 design.md 规划） | 中 | handoff-template.md 注释提醒 + role-guard WORKER 白名单按 handoff 精确指定 |

---

## 9. 不做什么

- 不改 .state.md schema（字段名和语义不变）
- 不改 auto-advance 状态机（phase/step 语义不变）
- 不改 output_type 枚举
- 不做存量迁移（deliverables/ 为空）
- 不引入独立 git 仓库或 product/ 目录
- 不改 mh-dev 自身的 .mh-dev/ 目录结构（mh-dev 状态在 tools/mh-dev/.mh-dev/，与 /mh-run 的 deliverables/ 是不同体系）
