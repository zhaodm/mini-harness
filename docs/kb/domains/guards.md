# Guards

> 本域指南描述硬校验体系的内部机制。修改本域代码前请先阅读。
> 对应源码: `scripts/`

## 职责与边界

**做什么：**
- 实现三层校验体系：结构校验(verify.sh)、内容质量校验(verify-qa.sh)、PPT 专项(verify-ppt.sh —— 含 bash 静态层与 Node/Playwright 渲染层)
- 实现 role-guard.sh PreToolUse Hook，按角色限制文件写入路径
- 实现归档完整性校验(verify-archive.sh)
- 实现框架自检(check-harness.sh)和基线对比(baseline.sh)
- 实现 Code Review 格式校验(verify-code-review.sh)

**不做什么（由其他域负责）：**
- 校验规则的定义来源 → 见 [skills.md](skills.md)
- 校验通过标准的决策 → 见 [roles.md](roles.md)（Orchestrator 质量门禁）
- 产出格式模板 → 见 [templates.md](templates.md)
- mh-dev 内部验证脚本 → 见 [mh-dev.md](mh-dev.md)

## 内部结构

```
scripts/
├── verify.sh               结构校验（A/B/C/D/E 类）
├── verify-qa.sh            内容质量校验（QA-1~13）
├── verify-ppt.sh           PPT 专项校验（静态层 + 渲染层 + export 子命令）
├── verify-archive.sh       归档完整性校验
├── verify-code-review.sh   Code Review 格式校验
├── role-guard.sh           角色文件写入权限拦截（PreToolUse Hook）
├── baseline.sh             基线对比
└── check-harness.sh        框架自检
```

| 子模块 | 职责 | 文件 |
|--------|------|------|
| 结构校验 | 文件存在性(A)、阶段完整性(B)、流程一致性(C)、健康度(D)、契约(E) | `scripts/verify.sh` |
| 质量校验 | 模糊词、测试结果、报告结论、报告完整性、设计规格、代码规范、经验采集 | `scripts/verify-qa.sh` |
| PPT 校验 | A 文件存在性与单文件形态、B 静态合规（字号分档/版式登记/多样性/结构）、C 内容完整性与页数、D 渲染几何测量（溢出/重叠/留白/标题间距）。含检查器运行时自检 | `scripts/verify-ppt.sh` |
| 归档校验 | deliverables/{REQ-ID}/ 完整性 + docs/kb/ 校验 | `scripts/verify-archive.sh` |
| Code Review 校验 | CR-1~5 格式与维度校验 | `scripts/verify-code-review.sh` |
| 角色权限 | PreToolUse Hook，按角色限制写入路径 | `scripts/role-guard.sh` |
| 基线对比 | 检测非流程修改 | `scripts/baseline.sh` |
| 框架自检 | 受版本控制的框架文件完整性检查 | `scripts/check-harness.sh` |

## 核心数据结构

<!-- 待后续 CR 填充 -->

## 关键流程

<!-- 待后续 CR 填充 -->

## 对外接口

<!-- 待后续 CR 填充 -->

## 文件清单与影响范围

| 文件 | 职责 | 改动时需同步检查 |
|------|------|----------------|
| `scripts/verify.sh` | 结构校验（A/B/C/D/E 类） | `skills/mh-verify/SKILL.md`、`docs/designs/design.md` §7.4 |
| `scripts/verify-qa.sh` | 内容质量校验（QA-1~13） | `skills/mh-verify/SKILL.md`、`docs/designs/design.md` §7.4 |
| `scripts/verify-ppt.sh` | PPT 专项校验（静态层 bash + 渲染层 Node/Playwright；退出码 3 = 渲染环境不可用） | `skills/mh-slideflow/SKILL.md`、`templates/ppt-quality-rules.md`、`templates/ppt-templates/registry.json`、`package.json` |
| `scripts/verify-archive.sh` | 归档完整性校验 + deliverables docs/kb/ 校验 | `skills/mh-deliver/SKILL.md` |
| `scripts/verify-code-review.sh` | Code Review 格式与维度校验（CR-1~5） | `skills/mh-verify/SKILL.md` |
| `scripts/role-guard.sh` | 角色文件写入权限拦截（PreToolUse Hook） | `CLAUDE.md` §5、`docs/designs/source-of-truth.md`、`docs/kb/domains/guards.md` |
| `scripts/baseline.sh` | 基线对比 | `docs/designs/design.md` §7.4 |
| `scripts/check-harness.sh` | 框架自检 | `docs/designs/design.md`、`.claude/commands/` |

## 约束与陷阱

### role-guard.sh mh-dev 分支的 scope 匹配口径

`approved_scope` 由 Planner 直写 `tools/mh-dev/.mh-dev/state.json`，条目可能是相对路径也可能是绝对路径。匹配采用**双向归一化**：把 scope 条目与目标路径一并转为绝对形态后比较，因此四种组合（scope 相对/绝对 × 写入路径相对/绝对）结论一致。

以 `/` 结尾的 scope 条目按**目录前缀**放行，与 `tools/mh-dev/scripts/validate-changes.sh` 的目录前缀语义对齐（此前两道门禁不对称：`docs/designs/modules/` 能过归属校验却过不了 hook）。条目保留结尾 `/` 是安全关键——`docs/m-evil/` 不以 `docs/m/` 开头，故目录名前缀伪造不会命中。

**Tester 专属路径 `tests/` 与 `tools/mh-dev/tests/` 在 scope 匹配之前按目录前缀放行**，不要求列入 `approved_scope`。这两个前缀在 `tools/mh-dev/scripts/validate-changes.sh` 的 tester_scope 内被无条件认可；若 hook 仍要求精确列出，两道门禁对同一路径结论相反，Tester 落盘任何测试都被 `exit 2` 拦下，`testcase_adding_required=true` 无法被满足。放行写成 `case` 的 `tests/*|tools/mh-dev/tests/*`，是目录前缀语义而非子串匹配——`tests-evil/`、`mytests/`、`tools/mh-dev/tests-evil/` 下的路径与裸文件名 `tests` 均不命中。放行位于归一化之后，故绝对与相对两种写入形态结论一致，且 `/tmp/tests/` 下的路径已在上一步被仓库外判定拦下，含 `..` 的穿越写法被全局穿越检测拦下。

**仓库外绝对路径直接 `exit 2`**，不进入 scope 匹配。`case` 必须分三支（仓库内绝对 / 其余绝对 / 相对），不能写成宽泛的 `/*)` 单分支：后者对 `/tmp/evil.sh` 执行 `${FILE_PATH#$ROOT/}` 不做任何替换，会把一个绝对路径当相对路径带进后续逻辑；此时若 scope 含仓库根自身作目录条目，`$ROOT//tmp/evil.sh` 确以 `$ROOT/` 开头，整个文件系统被放行（已实测复现）。下游 sensitive 判定用相对字面量匹配，该中间态在 sensitive 列表扩项时同样是隐患。

**jq 管道重绑定陷阱。** 目录前缀判定必须先绑定当前条目：

```
正确：any($abs[]; . as $s | ($s | endswith("/")) and ($ap | startswith($s)))
错误：any($abs[]; endswith("/") and ($ap | startswith(.)))
```

错误写法中 `|` 把 `.` 重绑定为管道左侧值，`startswith(.)` 退化为 `$ap | startswith($ap)` 恒真，**放行任意越权路径**（实测一个与 scope 完全无关的 `evil/` 下路径被放行）。

`..` 穿越检测在归一化之前独立生效，不受本口径影响。

### 仓库根推导不依赖 cwd

`ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`。hook 由 Claude Code 触发，cwd 不受脚本控制；`$(pwd)` 会让归一化随调用位置漂移——从子目录触发时仓库内绝对路径无法剥离前缀，进而误拦合法写入。`find "$ROOT/deliverables"`、`MH_DEV_STATE` 默认值、scope 归一化三处共用同一 `ROOT`，故任意 cwd 下退出码与消息一致。

`find` 返回绝对路径使 `STATE_FILE` 变绝对，`check_permission` 用 `[[ =~ ]]` 子串匹配 `deliverables/${req}/...`，绝对路径同样命中，deliverables 分支判定不变。

### verify-ppt.sh 禁止 GNU grep 扩展与错误吞没

仓库运行于 macOS，`/usr/bin/grep` 是 BSD grep，不支持 `-P`/`\K`/前后向断言。交互 shell 的 `grep`
可能被 ugrep 接管而支持 `-P`，导致**人工验证通过、脚本执行失效**——验证脚本行为必须用
`bash script.sh` 实跑。

CR-014 前的字号检查用 `grep -oP 'font-size:\s*\K\d+(?=px)' "$f" 2>/dev/null | awk ... || true`：
BSD grep 报错被 `2>/dev/null` 吞掉，非 0 退出码被 `|| true` 吞掉，结果**恒定通过**。同类失效还有
`grep -c ... || echo "0"`（无匹配时 `grep -c` 已自行输出 `0` 并返回 1，`|| echo "0"` 再补一个，
产出 `"0\n0"` 令整数比较报错后被吞没）与漏 `-maxdepth 1` 导致 wireframe 子目录被重复计数。

现行处置：字号扫描与登记表解析经 `require_ok()` 包装（失败时打印实际 stderr 并累加 ERRORS），
且脚本启动时对已知违规/合规 fixture 自测字号检查一次，行为不符即报"检查器自身失效"并 exit 1。
理由：静态扫描防不住新引入的等价写法，运行时自检才防得住。

`require_ok` 的输出经全局 `REQUIRE_OK_OUT` 回传，**不写 stdout 供 `$(...)` 捕获**——
后者会把 `require_ok` 放进子 shell，`ERRORS` 累加随子 shell 一同丢弃，包装就退化成纯装饰。
这是"注释声称的机制与实现不符"的一类：门禁空转比没有门禁更危险，因为它提供虚假保障。

### 字号检查的覆盖面即其有效性

CR-014 repair round 1：字号扫描只匹配 `font-size: <n>px` 字面量，而设计系统 CSS 的字号
全部走 `var(--font-*)`，字面值只出现在 token 定义行（`--font-caption: 18px`，无 `font-size:`
前缀）。结果 `--font-caption` 可被改到 9px 而静态层与渲染层同时报 PASS。`font: 600 8px/1`
简写同理绕过——而 `ppt-base.html` 骨架自身就用此写法。

处置：静态扫描覆盖三形态（字面量 / `--font-*` token 定义 / `font` 简写），
D 类渲染层对每个文本元素读 `getComputedStyle().fontSize` 作为不可绕过的兜底。
**教训：检查器"能报出违规"不等于"覆盖了违规能出现的全部形态"。** 少一种形态就少一道门。

### bash 变量名与多字节字符相邻

`"$DENSITY（...）"` 中的全角括号会被 bash 并入变量名，`set -u` 下报
`DENSITY?: unbound variable`。中文消息里变量后紧跟非 ASCII 字符时**必须写 `${VAR}`**。
该类缺陷只在特定分支被执行时才暴露，容易漏测。
