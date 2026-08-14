# deliverables/{project}/ 产品区目录结构规范

> 本文件是交付物目录结构的权威参考。
> 所有角色在产出时以此为准，verify-archive.sh 强制校验。
> CR-010: 取消根 output/ 二份存放，产出即归档。
> CR-018: 交付目录以项目标识符命名；流程证据内聚 `.engine/`；产品区不含角色名与相位名。

---

## 目录布局

```
deliverables/
├── .state.md                             ← 全局指针（project: {slug}）
└── {project}/                            ← 项目标识符命名（^[a-z][a-z0-9-]{0,63}$）
    ├── .engine/                          ← 引擎运行态（平铺，仅下列子目录分层）
    │   ├── .state.md
    │   ├── handoffs/                     ← Orchestrator 独占（任务+白名单+约束）
    │   ├── reports/                      ← 被派发角色写入完成回报（<handoff-basename>.report.md）
    │   ├── baselines/                    ← change 模式 spec 备份
    │   ├── process.log
    │   ├── plan-action.md
    │   ├── lessons.md
    │   ├── SR{N}-record.md
    │   ├── proposal.md                   ← Orchestrator 产出（init 阶段）
    │   ├── verify-strategy.md            ← Thinker 产出（集成预检策略）
    │   ├── code-report-t{N}.md           ← Worker 产出（每 Task 一份）
    │   ├── quality-gate-report.md        ← 质量门禁归因报告
    │   ├── final-test-report.md          ← Verifier 产出（VERIFY-2）
    │   ├── temp-test-report.md           ← Verifier 产出（VERIFY-1）
    │   └── archive-manifest.md
    ├── .archiveignore                    ← Thinker 产出（归档排除规则）
    ├── README.md                         # 项目说明
    ├── docs/                             # 文档类产出
    │   ├── spec/                         # 需求+设计规格（Thinker 直接产出到此）
    │   │   ├── requirement-spec.md       # 需求规格（SHALL + GWT）
    │   │   ├── design.md                 # 技术设计（单文件模式）
    │   │   ├── design-overview.md        # 技术设计（多文件模式入口）
    │   │   └── slide-spec.md             # 版式规格（ppt track）
    │   ├── kb/                           # 分层知识库（AI 项目上下文）
    │   │   ├── system-map.md             # Layer 0: 全景入口（≤150行）
    │   │   ├── domains/                  # Layer 1: 域指南（每份≤400行）
    │   │   ├── recipes/                  # Layer 2: 操作食谱（每份≤80行）
    │   │   └── kb-verify.sh              # 新鲜度检查脚本
    │   ├── lessons-learned.md            # 经验沉淀（EXP-N）
    │   └── metrics.md                    # 执行指标
    ├── src/                              # 源代码产出（Worker 交付）
    │   └── {按 output-guide 组织}
    ├── tests/                            # 测试产出
    │   ├── regression-suite.md           # 回归套件（框架自动沉淀）
    │   └── {unit/, integration/, e2e/}   # 测试代码（Worker + Verifier 交付）
    ├── deploy/                           # 部署/基础设施产出
    │   └── {Dockerfile, docker-compose.yml, k8s/, .github/, CI configs}
    ├── assets/                           # 静态资源/设计稿
    │   └── {wireframes/, images/, fonts/, icons/}
    └── reference/                        # 参考资料
        └── {外部文档、API 文档截图等}
```

**产品区（`.engine/` 之外）的文件与目录名不得含引擎角色名（THINKER/WORKER/VERIFIER/ORCHESTRATOR）
或相位名（init/propose/apply/archive）。** CR-010 R2 的 `<role>-<phase>-<name>.md` 规则在产品区废止；
可追溯性由引擎态承载——`.engine/reports/<handoff-basename>.report.md` 的 basename 已含阶段与轮次
（如 `web-cli-DEV1-T1-R1`），`.engine/process.log` 记录时序。

**归属判据：** 文档消费者是引擎/门禁脚本 → 引擎态（`.engine/`）；是交付项目读者 → 产品区。

---

## 分类规则

| 目录 | 放什么 | 谁生成 | 说明 |
|------|--------|--------|------|
| .engine/ | 引擎运行态与流程证据 | Orchestrator/各角色 | 不归档，运行态文件 |
| .engine/reports/ | 各棒完成回报 | 被派发角色（Orchestrator 兜底） | 回报名由 handoff basename 派生 |
| docs/ | 供人/AI 阅读的文档 | Thinker（spec）+ 框架 ARC 步骤 | 不可执行，纯知识载体 |
| docs/spec/ | 需求规格 + 技术设计 | Thinker 直接产出（ARC-1/2 校验） | change 模式走 merge 流程 |
| src/ | 可执行的项目源代码 | Worker | 按 output-guide 组织 |
| tests/ | 测试代码 + 回归套件 | Worker + Verifier + 框架 | regression-suite.md 由 ARC-5 生成 |
| deploy/ | 部署、CI/CD、基础设施 | Worker | Dockerfile, k8s, GitHub Actions 等 |
| assets/ | 非代码静态文件 | Thinker / Worker | 设计稿、wireframes、图片、字体 |
| reference/ | 外部参考资料 | Orchestrator (ARC-4) | 不修改，仅归档保存 |

---

## 产品区根目录允许的文件

`deliverables/{project}/` 根目录只允许以下文件（非目录）。此清单与 `scripts/role-guard.sh` 的
`is_product_root_file()` 全名白名单同源——用白名单而非「根目录下任意文件」，避免产品区根重新
变成散落区：

- `README.md` — 项目说明
- `package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` — 包管理
- `tsconfig.json` / `vite.config.*` / `webpack.config.*` — 构建配置
- `.env.example` — 环境变量模板
- `.gitignore` — Git 忽略规则
- `Makefile` — 构建脚本（如未放入 deploy/）
- `*.html` / `*.css` — ppt track 单文件产出（CR-014）
- `.archiveignore` — 归档排除规则（Thinker 产出）

其他文件必须归入对应子目录。**角色前缀文件名（`THINKER-*.md` 等）不再是合法根文件——
它现在是违规特征**，`verify-archive.sh` ARC-7 据此判违规。

---

## ARC 步骤与路径对应

> CR-010: ARC-3 已取消（产出即归档，无二份存放）
> CR-018: ARC-1/ARC-2 在 new 模式下退化为存在性校验（Thinker 直接写 `docs/spec/`），
> change 模式下仍走 `archiveMerge()`

| ARC 步骤 | 写入/校验路径 |
|----------|---------|
| ARC-1 需求归档 | 校验 `deliverables/{project}/docs/spec/requirement-spec.md`；change 模式 `archiveMerge()` |
| ARC-2 设计归档 | 校验 `deliverables/{project}/docs/spec/design.md`；change 模式 `archiveMerge()` |
| ARC-4 参考资料归档 | `deliverables/{project}/reference/` |
| ARC-5 测试用例沉淀 | `deliverables/{project}/tests/regression-suite.md` |
| ARC-6 执行指标 | `deliverables/{project}/docs/metrics.md` |
| ARC-7 经验沉淀 | `deliverables/{project}/docs/lessons-learned.md`（从 `.engine/lessons.md` 归档） |
| ARC-8 AI 知识库 | `deliverables/{project}/docs/kb/`（system-map + domains/ + recipes/ + kb-verify.sh） |

---

## output_type 特化规则

| output_type | 额外说明 |
|-------------|---------|
| code | 产出物放 `src/` + `tests/` + `docs/` + `deploy/`（按需） |
| ppt | 产出物为**单一 HTML 文件** + CSS，直接放产品区根（导航在文件内实现一次）；wireframes 放 `assets/wireframes/` |
| documentation | 无 src/，主产出在 `docs/` |
| infrastructure | 主产出在 `deploy/`，src/ 可选 |
