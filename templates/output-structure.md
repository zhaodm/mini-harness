# deliverables/{REQ-ID}/ 产品区目录结构规范

> 本文件是归档产出目录结构的权威参考。
> 所有角色在归档时以此为准，verify-archive.sh 强制校验。
> CR-010: 取消根 output/ 二份存放，产出即归档。

---

## 目录布局

```
deliverables/{REQ-ID}/
├── .engine/                          ← 引擎运行态（平铺，文件名保持原样）
│   ├── .state.md
│   ├── handoffs/                     ← Orchestrator 独占（任务+白名单+约束）
│   ├── reports/                      ← 被派发角色写入完成回报（<handoff-basename>.report.md）
│   ├── process.log
│   ├── lessons.md
│   ├── SR{N}-record.md
│   └── plan-action.md
├── .archiveignore                    ← Thinker 产出（归档排除规则）
├── ORCHESTRATOR-init-proposal.md     ← Orchestrator 产出（init 阶段）
├── THINKER-propose-*.md             ← Thinker 产出
├── WORKER-apply-*.md                ← Worker 产出
├── VERIFIER-apply-*.md              ← Verifier 产出
├── docs/                             # 文档类产出（框架归档生成）
│   ├── spec/                         # 需求+设计规格
│   │   ├── requirement-spec.md       # Thinker 需求规格
│   │   └── design.md                 # Thinker 技术设计
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
│   └── {unit/, integration/, e2e/}   # 测试代码（Worker 交付）
├── deploy/                           # 部署/基础设施产出
│   └── {Dockerfile, docker-compose.yml, k8s/, .github/, CI configs}
├── assets/                           # 静态资源/设计稿
│   └── {wireframes/, images/, fonts/, icons/}
└── reference/                        # 参考资料
    └── {外部文档、API 文档截图等}
```

---

## 分类规则

| 目录 | 放什么 | 谁生成 | 说明 |
|------|--------|--------|------|
| .engine/ | 引擎运行态 | Orchestrator/框架 | 不归档，运行态文件 |
| .engine/reports/ | 各棒完成回报 | 被派发角色（Orchestrator 兜底） | 唯一由执行角色写入的引擎态目录，回报名由 handoff basename 派生 |
| docs/ | 供人/AI 阅读的文档 | 框架 ARC 步骤 | 不可执行，纯知识载体 |
| docs/spec/ | 需求规格 + 技术设计 | ARC-1, ARC-2 | change 模式走 merge 流程 |
| src/ | 可执行的项目源代码 | Worker | 按 output-guide 组织 |
| tests/ | 测试代码 + 回归套件 | Worker + 框架 | regression-suite.md 由 ARC-5 生成 |
| deploy/ | 部署、CI/CD、基础设施 | Worker | Dockerfile, k8s, GitHub Actions 等 |
| assets/ | 非代码静态文件 | Thinker / Worker | 设计稿、图片、字体 |
| reference/ | 外部参考资料 | Orchestrator (ARC-4) | 不修改，仅归档保存 |

---

## 产品区根目录允许的文件

deliverables/{REQ-ID}/ 根目录允许以下文件（非目录）：

- `ORCHESTRATOR-*.md` — Orchestrator 产出
- `THINKER-*.md` — Thinker 产出
- `WORKER-*.md` — Worker 产出
- `VERIFIER-*.md` — Verifier 产出
- `README.md` — 项目说明
- `package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` — 包管理
- `tsconfig.json` / `vite.config.*` / `webpack.config.*` — 构建配置
- `.env.example` — 环境变量模板
- `.gitignore` — Git 忽略规则
- `Makefile` — 构建脚本（如未放入 deploy/）

其他文件必须归入对应子目录。

---

## ARC 步骤与路径对应

> CR-010: ARC-2/3/5 已取消（产出即归档，无二份存放）

| ARC 步骤 | 写入路径 |
|----------|---------|
| ARC-1 .archiveignore 禁止项 | 检查 deliverables/{REQ-ID}/ 产品区 |
| ARC-4 归档非空 | 检查 deliverables/{REQ-ID}/ 产品区（排除 .engine/） |
| ARC-5 测试用例沉淀 | `deliverables/{REQ-ID}/tests/regression-suite.md` |
| ARC-6 执行指标 | `deliverables/{REQ-ID}/docs/metrics.md` |
| ARC-7 经验沉淀 | `deliverables/{REQ-ID}/docs/lessons-learned.md`（从 .engine/lessons.md 归档） |
| ARC-8 AI 知识库 | `deliverables/{REQ-ID}/docs/kb/`（system-map + domains/ + recipes/ + kb-verify.sh） |

---

## output_type 特化规则

| output_type | 额外说明 |
|-------------|---------|
| code | 产出物放 `src/` + `tests/` + `docs/` + `deploy/`（按需） |
| ppt | 产出物为**单一 HTML 文件** + CSS，直接放产品区根（导航在文件内实现一次）；wireframes 放 `assets/wireframes/` |
| documentation | 无 src/，主产出在 `docs/` |
| infrastructure | 主产出在 `deploy/`，src/ 可选 |
