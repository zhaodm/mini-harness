# output/ 目录结构规范

> 本文件是归档产出目录结构的权威参考。
> 所有角色在归档时以此为准，verify-archive.sh 强制校验。

---

## 目录布局

```
output/
├── docs/                         # 文档类产出（框架归档生成）
│   ├── spec/                    # 需求+设计规格
│   │   ├── requirement-spec.md  # BA 需求规格
│   │   └── design.md           # SA 技术设计
│   ├── kb/                      # 分层知识库（AI 项目上下文）
│   │   ├── system-map.md       # Layer 0: 全景入口（≤150行）
│   │   ├── domains/            # Layer 1: 域指南（每份≤400行）
│   │   ├── recipes/            # Layer 2: 操作食谱（每份≤80行）
│   │   └── kb-verify.sh       # 新鲜度检查脚本
│   ├── lessons-learned.md       # 经验沉淀（EXP-N）
│   └── metrics.md               # 执行指标
├── src/                          # 源代码产出（DE 交付）
│   └── {按 output-guide 组织}
├── tests/                        # 测试产出
│   ├── regression-suite.md      # 回归套件（框架自动沉淀）
│   └── {unit/, integration/, e2e/}  # 测试代码（DE 交付）
├── deploy/                       # 部署/基础设施产出
│   └── {Dockerfile, docker-compose.yml, k8s/, .github/, CI configs}
├── assets/                       # 静态资源/设计稿
│   └── {wireframes/, images/, fonts/, icons/}
└── reference/                    # 参考资料
    └── {外部文档、API 文档截图等}
```

---

## 分类规则

| 目录 | 放什么 | 谁生成 | 说明 |
|------|--------|--------|------|
| docs/ | 供人/AI 阅读的文档 | 框架 ARC 步骤 | 不可执行，纯知识载体 |
| docs/spec/ | 需求规格 + 技术设计 | ARC-1, ARC-2 | change 模式走 merge 流程 |
| src/ | 可执行的项目源代码 | DE | 按 output-guide 组织 |
| tests/ | 测试代码 + 回归套件 | DE + 框架 | regression-suite.md 由 ARC-5 生成 |
| deploy/ | 部署、CI/CD、基础设施 | DE | Dockerfile, k8s, GitHub Actions 等 |
| assets/ | 非代码静态文件 | UX / DE | 设计稿、图片、字体 |
| reference/ | 外部参考资料 | PM (ARC-4) | 不修改，仅归档保存 |

---

## 根目录允许的文件

output/ 根目录只允许以下文件（非目录）：

- `README.md` — 项目说明
- `package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` — 包管理
- `tsconfig.json` / `vite.config.*` / `webpack.config.*` — 构建配置
- `.env.example` — 环境变量模板
- `.gitignore` — Git 忽略规则
- `Makefile` — 构建脚本（如未放入 deploy/）

其他文件必须归入对应子目录。

---

## ARC 步骤与路径对应

| ARC 步骤 | 写入路径 |
|----------|---------|
| ARC-1 需求归档 | `output/docs/spec/requirement-spec.md` |
| ARC-2 设计归档 | `output/docs/spec/design.md` |
| ARC-3 产出物归档 | `output/src/`, `output/tests/`, `output/deploy/` (按类型分流) |
| ARC-4 参考资料归档 | `output/reference/` |
| ARC-5 测试用例沉淀 | `output/tests/regression-suite.md` |
| ARC-6 执行指标 | `output/docs/metrics.md` |
| ARC-7 经验沉淀 | `output/docs/lessons-learned.md` |
| ARC-8 AI 知识库 | `output/docs/kb/`（system-map + domains/ + recipes/ + kb-verify.sh） |

---

## ARC-3 分流规则

DE 交付的 `deliverables/{REQ-ID}/output/` 内容按以下规则分流：

| 文件模式 | 目标目录 |
|---------|---------|
| `src/**`, `lib/**`, `app.**`, `main.**`, `index.**` | `output/src/` |
| `tests/**`, `test/**`, `__tests__/**`, `*_test.*`, `*.test.*`, `*.spec.*` | `output/tests/` |
| `Dockerfile*`, `docker-compose*`, `.github/**`, `k8s/**`, `*.workflow`, `deploy/**` | `output/deploy/` |
| `*.png`, `*.jpg`, `*.svg`, `*.gif`, `*.ico`, `fonts/**`, `wireframes/**`, `images/**` | `output/assets/` |
| `package.json`, `*.toml`, `*.mod`, `Makefile`, `README.md`, `tsconfig*`, `.*rc`, `.env*`, `.gitignore` | `output/`（根目录） |
| 其他 `*.md`（非上述匹配） | `output/docs/` |

如果 DE 的 output/ 已经有 `src/`, `tests/` 等目录结构，则保持原结构直接对应复制。

---

## output_type 特化规则

| output_type | 额外说明 |
|-------------|---------|
| ppt | 产出物直接放 `output/src/`（HTML+CSS），wireframes 放 `output/assets/wireframes/` |
| documentation | 无 src/，主产出在 `output/docs/` |
| infrastructure | 主产出在 `output/deploy/`，src/ 可选 |
