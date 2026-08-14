---
id: CR-018
title: 交付物面向项目化 — 设计
requirement_doc: docs/requirements/CR-018-project-oriented-deliverables.md
created: 2026-08-14
---

# CR-018 设计：交付物面向项目化

> 需求单: docs/requirements/CR-018-project-oriented-deliverables.md
> 本文档定义方案（怎么做）；意图（要什么）见需求单。

## 设计概览

四项决策承载九条需求：

| 决策 | 覆盖需求 | 核心内容 |
|---|---|---|
| D1 项目标识符 | R1 R2 | slug 字符集 + 校验落点 + 单一标识符字段 |
| D2 目录与命名契约 | R3 R4 R5 | 产品区/引擎态归属划分 + 去前缀后的文件名 |
| D3 授权归属表 | R6 R7 | 肯定式路径归属表 + 全局指针定位 |
| D4 门禁与模板适配 | R8 R9 | 六脚本路径迁移 + ARC-7 收紧 + ppt 同步 |

---

## D1 — 项目标识符

### D1.1 字符集

正则：`^[a-z][a-z0-9-]{0,63}$`

| 约束 | 排除的构造 | 理由 |
|---|---|---|
| 全小写 | `WEB-CLI`、`.ENGINE` | 守卫的 WORKER 排除规则用 `grep -qi`（大小写不敏感），大写标识符会与排除项产生非预期交叉命中 |
| 仅 `a-z0-9-` | `web.cli`、`a/b`、`../etc`、`a b` | `${req}` 被插入 bash `[[ =~ ]]` 正则与路径拼接：`.` 是通配符（`web.cli` 会命中 `webXcli`），`/` 与 `..` 是路径穿越，空格破坏词法 |
| 首字符 `a-z` | `-rf`、`9lives`、空值 | 前导 `-` 在脚本中会被当作选项；数字开头不合法包名 |
| ≤64 字符 | 超长串 | 路径长度上界，避免拼接后触及文件系统限制 |

该正则下标识符是**正则字面量安全**的：`a-z0-9-` 在 bash ERE 中无元字符语义（`-` 仅在字符类内部有范围语义，此处出现在被匹配串中而非模式中）。这使 D3 的 `${req}` 插值继续安全，无需引入转义层。

### D1.2 保留标识符

以下值即使满足字符集也须拒绝，因其与产品区顶层目录或引擎态目录同名，会使路径归属产生歧义：

`docs`、`src`、`tests`、`deploy`、`assets`、`reference`、`engine`

### D1.3 校验落点

单一实现 + 两处调用：

- **实现**：`scripts/validate-slug.sh <slug>` —— 新增脚本，退出码 0/2，拒绝时 stdout 打印原因。单一实现避免正则在多处漂移（CR-015 的教训：判据分散即口径分歧）。
- **调用点 1（生成时）**：`skills/mh-intake/SKILL.md` Step 1 —— 与用户确认标识符后立即校验，不通过则重新询问。
- **调用点 2（消费时）**：`scripts/role-guard.sh` —— 从 state 读出 `project` 后校验，不通过则 `exit 2` 并提示 state 被污染。

> 消费侧必须独立校验，不能信任生成侧：state 文件是被治理方可写的（`docs/kb/domains/guards.md` 的自授权定位），生成侧校验可被绕过。守卫在插值前自校验，是 AX-01「即使 state 被直接构造」那一半的实现。

### D1.4 字段命名

`.state.md` 的 `req_id:` 改名为 `project:`。

不保留 `req_id` 别名：兼容期会使读取端必须处理两种字段名，而 `deliverables/` 为空、无存量可兼容。全局指针 `deliverables/.state.md` 同步改用 `project:`。

handoff 与回报 basename 形态：`<project>-<STAGE>-<TASK>-R<N>`，例：`web-cli-THINK-DESIGN-R1`、`web-cli-DEV1-T1-R1`。

---

## D2 — 目录与命名契约

### D2.1 目标结构

```
deliverables/
├── .state.md                          ← 全局指针（project: web-cli）
└── web-cli/                           ← D1 标识符命名
    ├── .engine/                       ← 引擎态（平铺，仅 handoffs/ reports/ baselines/ 分层）
    │   ├── .state.md
    │   ├── handoffs/                  ← ORCHESTRATOR 独占
    │   ├── reports/                   ← 四角色共写（CR-017 D1）
    │   ├── baselines/                 ← change 模式 spec 备份
    │   ├── process.log
    │   ├── plan-action.md
    │   ├── lessons.md
    │   ├── SR{N}-record.md
    │   ├── proposal.md                ← 原 ORCHESTRATOR-init-proposal.md
    │   ├── verify-strategy.md         ← 原 THINKER-propose-verify-strategy.md
    │   ├── code-report-t{N}.md        ← 原 WORKER-apply-code-report-t{N}.md
    │   ├── quality-gate-report.md     ← 原 WORKER-apply-quality-gate-report.md
    │   └── final-test-report.md       ← 原 VERIFIER-apply-final-test-report.md
    ├── .archiveignore                 ← THINKER 产出
    ├── README.md
    ├── docs/
    │   ├── spec/
    │   │   ├── requirement-spec.md    ← 原 THINKER-propose-requirement-spec.md
    │   │   └── design.md              ← 原 THINKER-propose-design.md
    │   ├── kb/
    │   ├── lessons-learned.md
    │   └── metrics.md
    ├── src/
    ├── tests/
    ├── deploy/
    ├── assets/
    └── reference/
```

`docs/spec/` 沿用既有声明而非平铺到 `docs/`：`scripts/verify.sh:23`、`scripts/baseline.sh:19`、`workflows/lib/archive-merge.js` 已按该路径实现，且 change 模式的 baseline 备份按目录粒度拷贝 `docs/spec/`，平铺后须改为按文件清单枚举。

### D2.2 多文件设计模式

`verify.sh:97` 支持 `THINKER-propose-overview.md`（多文件设计模式）。新形态为 `docs/spec/design-overview.md`，与 `verify.sh:153` 既有的 `docs/spec/design-overview.md` 检查天然合流。

### D2.3 ppt track 落位（R9）

| 原路径 | 新路径 | 归属 |
|---|---|---|
| `THINKER-propose-slide-spec.md` | `docs/spec/slide-spec.md` | 产品区 —— 版式规格是交付物的一部分 |
| `THINKER-propose-wireframes/` | `assets/wireframes/` | 产品区 —— `output-structure.md` 已声明该目录 |
| 单文件 HTML 产出 | 产品区根（不变） | CR-014 语义不变 |

### D2.4 命名规则的替代

CR-010 R2 的 `^(THINKER|WORKER|VERIFIER|ORCHESTRATOR)-[a-z]+-[a-z0-9-]+\.md$` 在产品区废止。产品区不再有「按角色区分的文件」需要正则识别——归属由**目录**承载（D3.1）。

引擎态承接可追溯性：`.engine/reports/<handoff-basename>.report.md` 的 basename 已含阶段与轮次（`web-cli-DEV1-T1-R1`），`.engine/process.log` 记录时序。

---

## D3 — 授权归属表与定位

### D3.1 路径归属表

`scripts/role-guard.sh` 的 `check_permission()` 改为肯定式表。每角色声明可写路径集：

| 角色 | 可写路径（`deliverables/${req}/` 下，均为目录前缀或全名锚定） |
|---|---|
| ORCHESTRATOR | `.engine/.state.md`、`.engine/handoffs/*.md`、`.engine/plan-action.md`、`.engine/SR*-record.md`、`.engine/lessons.md`、`.engine/process.log`、`.engine/proposal.md`、`.engine/archive-manifest.md`、`.engine/baselines/`、`.engine/reports/*.report.md`、`docs/`、`tests/regression-suite.md`、全局 `deliverables/.state.md` |
| THINKER | `docs/spec/`、`.archiveignore`、`assets/`、`.engine/verify-strategy.md`、`.engine/reports/*.report.md`、交还例外 |
| WORKER | `src/`、`tests/`、`deploy/`、`assets/`、产品区根的项目配置文件（见 D3.2）、`.engine/code-report-t*.md`、`.engine/quality-gate-report.md`、`.engine/reports/*.report.md`、交还例外 |
| VERIFIER | `tests/`、`.engine/final-test-report.md`、`.engine/reports/*.report.md`、交还例外 |

变化要点：

- **WORKER 的否定式谓词（原 L234-241）整体删除**。原谓词「产品区下不含其他角色前缀者皆可写」在去前缀后退化为产品区全通。新表下 WORKER 不可写 `docs/`——规格文档的写权归 THINKER 与 ORCHESTRATOR（后者用于 ARC 归档）。
- **ORCHESTRATOR 获得 `docs/` 写权**：ARC-5~8 要写 `docs/metrics.md`、`docs/lessons-learned.md`、`docs/kb/`。原实现依赖 L200 的 `ORCHESTRATOR-*.md` 前缀 + L205-206 读 phase 后无判据（该 `phase` 变量取出后未被使用，是既有死逻辑），改为显式声明 `docs/`。
- **`tests/` 由 WORKER 与 VERIFIER 共写**：Worker 写实现测试（TDD 的 Red 步）、Verifier 写回归测试，这是既有分工（`skills/mh-build/SKILL.md` L127）。共写不构成越权：二者产出同类文件，且 `.engine/reports/` 已有四角色共写先例。
- **`assets/` 由 THINKER 与 WORKER 共写**：Thinker 出 wireframes/设计稿，Worker 出运行期静态资源（`output-structure.md` 分类规则既有声明）。

### D3.2 产品区根文件

WORKER 可写的根文件用**全名白名单**而非模式匹配，逐条列出：

`README.md`、`package.json`、`pyproject.toml`、`go.mod`、`Cargo.toml`、`tsconfig.json`、`Makefile`、`.env.example`、`.gitignore`、`vite.config.*`、`webpack.config.*`

来源：`templates/output-structure.md` L70-83 既有清单。用白名单而非「根目录下任意文件」，避免产品区根重新变成散落区（R3 的目的即此）。

### D3.3 匹配语义统一

所有归属条目按两种形态之一锚定，不使用无锚正则：

- **目录前缀**：`^deliverables/${req}/docs/spec/.+$` —— 尾部 `.+` 确保不匹配目录自身
- **文件全名**：`^deliverables/${req}/\.engine/proposal\.md$` —— 双向锚定

双向锚定是既有不变量（CR-016 D1、CR-017 D1 注释已详述）：无 `$` 锚时 `.state.md` 退化为前缀，`.state.md.evil`、`.state.md/child.md` 全部命中；无 `^` 锚时 `x/deliverables/…` 嵌套伪造命中。**新表的每一条都须双向锚定**，包括目录前缀条目——`^…/src/.+$` 才能拒绝 `x/deliverables/web-cli/src/a.ts`。

`-evil` 后缀类绕过（`deliverables-evil/`、`tests-evil/`）由 `^deliverables/${req}/` 前缀 + `${req}` 的字符集共同排除：`deliverables-evil` 不等于 `deliverables`，且路由分支的 `case NORM_PATH in deliverables/*` 已是目录前缀语义（L65-68 既有）。

### D3.4 全局指针定位（R7）

`role-guard.sh` L120-126 的 `find … | head -1` 替换为：

```
1. 读 deliverables/.state.md 的 project 字段
2. project 为空/缺失/文件不存在 → exit 0（放行，见下方语义表）
3. validate-slug 校验 project → 失败则 exit 2
4. STATE_FILE = deliverables/${project}/.engine/.state.md
5. STATE_FILE 不存在 → exit 0
6. 读 current_role；为空 → exit 0
```

指针异常时的行为（AX-02 的五形态）：

| 形态 | 行为 | 理由 |
|---|---|---|
| 指针文件不存在 | exit 0 放行 | 无活跃交付物，等价于 `/mh-run` 未启动。与既有 L122 同语义 |
| 指针存在但 `project` 空 | exit 0 放行 | 同上。初始化中途的正常瞬态 |
| `project` 非法 slug | **exit 2 拦截** | 唯一收紧项：合法流程不会写入非法 slug，出现即 state 被污染，此时放行等于在污染态下判权 |
| 指针指向的交付物目录/state 不存在 | exit 0 放行 | 指针滞后于目录（如手工清理），非越权信号 |
| `current_role` 空/畸形 | exit 0 放行 | 沿用既有 L126 语义 |

**绝不退化为扫描**：任一形态下都不再遍历 `deliverables/` 寻找替代 state。多交付物并存时，非指针所指的交付物其 `current_role` 不参与任何判权。

> 放行为主的设计与守卫定位一致（防误撞，非安全边界）：误拦会使正常流程中断且原因难查，而漏拦的后果由「守卫本就不是安全边界」这一既有定位承担。唯一的 exit 2 留给「污染态」——那是唯一无法用正常流程解释的形态。

### D3.5 不变量保持清单（AX-04）

以下既有判据在重构中**逐字保留**，不随归属表改写：

- `is_handback()`：仅接受 `Write`、复用读取端解析 `grep '^current_role:' | head -1 | awk '{print $2}'`（CR-016 D1）
- `is_report()`：`^deliverables/${req}/\.engine/reports/.*\.report\.md$`，无内容判据（CR-017 D1）
- 交还例外的路径锚定：`^deliverables/${req}/\.engine/\.state\.md$`
- 全局 `..` 穿越检测、仓库外绝对路径拦截、路径归一化（L42-58）
- mh-dev 分支的 `approved_scope` 匹配与 formal 轨关键路径约束（L73-110）
- `NotebookEdit` 的 `notebook_path` 提取、路径缺失时保守放行（L20-40）

`.ipynb` 扩展名的处理：原 THINKER/VERIFIER 条目含 `\.(md|ipynb)`。新表下由目录归属承载——`docs/spec/` 与 `assets/` 前缀条目不限扩展名，notebook 落在其中自然放行。

---

## D4 — 门禁与模板适配

### D4.1 六脚本改动性质

`verify.sh`、`verify-qa.sh`、`verify-ppt.sh`、`verify-archive.sh`、`verify-code-review.sh`、`baseline.sh` 均已从 `deliverables/.state.md` 读 `req_id`（`verify-archive.sh:20`、`verify-qa.sh:17`、`verify.sh:16`、`baseline.sh:15`、`verify-code-review.sh:20`、`verify-ppt.sh:94`），**定位逻辑无需改动**，只需：

1. 字段名 `req_id:` → `project:`
2. 内部变量与消费路径改名（`$REQ_DIR` 保留变量名，取值不变）
3. 产出文件路径按 D2.1 迁移

`verify-qa.sh:436` 的回归套件标签 `<!-- REQ-${req_id} START -->` 改为 `<!-- PROJECT-${project} START -->`，`workflows/lib/regression-suite.js` 与 `tests/test-regression-suite.js` 同步。

### D4.2 ARC-7 收紧（R8）

`verify-archive.sh:237` 现判据：根 `.md` 文件中，非 `README.md` 且不匹配 `^(THINKER|WORKER|VERIFIER|ORCHESTRATOR)-` 者告警。

改为：根 `.md` 文件中，非 `README.md` 者一律告警。角色前缀不再是豁免理由——它现在是违规特征。

`verify-archive.sh:206` 的 `allowed_dirs` 不变（`docs src tests deploy assets reference`）。

### D4.3 强度不降的验证方式（AX-05）

每个脚本的改动均须有一份「应当 FAIL 的输入」证明判据仍生效。`tools/mh-dev/tests/` 已有 `test-ppt-gate.sh` 采用 sandbox + baseline 对照的形态（对照改动前脚本副本，验证结论一致或更严），Tester 沿用该形态。

### D4.4 模板与文档

`templates/output-structure.md` 重写：删除 L22-25 的产品区根 `ROLE-*.md` 声明（与 L26-30 矛盾的那一半），保留并补全 `docs/spec/` 声明；L70-83 根文件清单与 D3.2 对齐；L91-98 的 ARC 路径表按 D2.1 更新。

`skills/mh-deliver/SKILL.md` ARC-1/ARC-2 的「如需归档到 docs/spec/ 由 Orchestrator 整理」删除。产出即归档下，Thinker 直接写 `docs/spec/`，ARC-1/ARC-2 在 new 模式下退化为存在性校验，change 模式下仍走 `archiveMerge()`。

`CLAUDE.md` §5 的 role-guard 条款：`{REQ-ID}` 措辞改为 `{project}`，「WORKER 可写产品区下的项目代码路径」改为归属表口径，「产品区文档须遵循 `<ROLE>-<phase>-<name>.md` 命名」整条删除。

`docs/kb/domains/guards.md` 增补：授权模型从否定式改肯定式的理由、指针定位的五形态语义表。

---

## 实施批次

| 批次 | 内容 | 独立可回滚 |
|---|---|---|
| ① | D1 全部（validate-slug.sh + 字段改名 + intake 校验）+ D3.4 指针定位 | 是 |
| ② | D2 全部（目录与命名迁移，含 skills/agents/templates 声明） | 是 |
| ③ | D3.1~D3.3 归属表重建 | 是（风险最高，单独成批） |
| ④ | D4 全部（六脚本 + ARC-7 + 文档） | 是 |

③ 单独成批的理由：它改的是 `check_permission()` 整个函数体，与其余批次仅通过 `${req}` 和路径常量耦合。若对抗测试发现归属表有漏放行，可单独 revert ③ 而保留①②④。

## 风险控制

| 风险 | 控制 |
|---|---|
| 归属表漏声明某角色合法路径 | 误拦表现为流程中断（响亮失败），由 AC-07 逐角色正向验证覆盖 |
| 归属表多放行 | 静默权限扩大，由 AX-03 逐角色反向验证覆盖（每角色尝试写其他角色路径） |
| 双向锚定遗漏 | AX-04 的后缀与嵌套伪造用例逐条覆盖；D3.3 要求新表每条都锚定 |
| `${req}` 插值面 | D1.1 字符集使标识符正则字面量安全；D1.3 消费侧独立校验 |
| 指针语义定义不当致守卫整体失效 | D3.4 五形态表穷举；AX-02 逐形态验证 |
| 六脚本路径遗漏致漏报 | D4.3 要求每脚本有「应当 FAIL」输入；AX-05 覆盖 |
