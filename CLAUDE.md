# CLAUDE.md

## 工程准则

以下六节为 Mini-Harness 仓库始终生效的通用工程纪律，不自动启动任何多角色工作流。流程纪律仅在显式调用 `/mh-run` 或 `/mh-ppt` 后生效（见 §6）。

### 1. 编码前思考

**不要假设。不要隐藏困惑。坦诚的权衡利弊。**

在执行之前首先推理：
- **明确说明假设** — 如果不确定，询问而不是猜测
- **呈现多种解释** — 当存在歧义时，不要默默选择
- **适时提出异议** — 如果存在更简单的方法，说出来
- **困惑时停下来** — 指出不清楚的地方并要求澄清

## 2. 简洁优先

**用最少的代码解决问题。不要过度推测。**

对抗过度工程的倾向：
- 不要添加要求之外的功能
- 不要为一次性代码创建抽象
- 不要添加未要求的"灵活性"或"可配置性"
- 不要为不可能发生的场景做错误处理
- 如果 200 行代码可以写成 50 行，重写它

**检验标准：** 资深工程师会觉得这过于复杂吗？如果是，简化。

## 3. 精准修改

**只修改必须修改的。只清理自己造成的混乱。**

编辑现有代码时：
- 不要"改进"相邻的代码、注释或格式
- 不要重构没有问题的代码
- 匹配现有风格，即使你更倾向于不同的写法
- 如果注意到无关的死代码，请指出来 —— 不要删除它

当你的改动导致孤立代码时：
- 删除因你的改动而变得无用的导入/变量/函数
- 不要删除已有的死代码，除非被要求

**检验标准：** 每一行修改都应该能直接追溯到用户的请求。

## 4. 目标驱动执行

**定义成功标准。循环验证直到达成。**

将任务转化为可验证的目标：

| 不要这样做... | 转化为... |
|--------------|-----------------|
| "添加验证" | "编写无效输入的测试，并确保测试通过" |
| "修复 bug" | "编写重现 bug 的测试，并确保测试通过" |
| "重构 X" | "确保重构前后测试都能通过" |

对于多步骤任务，说明一个简短的计划：
```
1. [步骤] → 验证: [检查]
2. [步骤] → 验证: [检查]
3. [步骤] → 验证: [检查]
```

严格的成功标准让你能够独立循环执行。弱标准（"让它工作"）需要不断澄清。

## 5. 仓库自治理纪律

- 任何文件写入后必须验证文件存在且非空
- **脚本硬约束优先于自然语言软约束**：以脚本退出码为准，Agent 自述不作为通过依据
- `scripts/role-guard.sh` 强制引擎态与产品产出分离：`/mh-run` 运行态文件与流程证据（`.state.md`、`handoffs/`、`reports/`、`process.log`、`proposal.md`、`verify-strategy.md`、`code-report-t{N}.md`、`quality-gate-report.md`、`final-test-report.md` 等）须写入 `deliverables/{project}/.engine/`，产品区（`.engine/` 之外）的文件与目录名**不得含引擎角色名或相位名**（CR-018 R3，`<ROLE>-<phase>-<name>.md` 命名规则在产品区废止，可追溯性由引擎态的 handoff basename 与 `process.log` 承载）；产品区授权是**肯定式路径归属表**（CR-018 R6）：THINKER 写 `docs/spec/`、`assets/`、`.archiveignore`，WORKER 写 `src/`、`tests/`、`deploy/`、`assets/` 与产品区根文件全名白名单，VERIFIER 写 `tests/`，ORCHESTRATOR 写 `docs/`、`tests/regression-suite.md` 与全局 `deliverables/.state.md`——**不得以「不含其他角色前缀」作为授权谓词**（去前缀后该否定式谓词退化为产品区全通）；归属表每条均 `^…$` 双向锚定，目录前缀条目形如 `^…/src/.+$`（尾部 `.+` 使目录自身不命中，左锚拒嵌套伪造）；全局路径穿越检测拒绝包含 `..` 组件的写入路径；mh-dev 分支采用双向归一化匹配 `approved_scope`（目标路径与 scope 条目一并转绝对形态后比较，故 scope 存相对或绝对路径均正确），以 `/` 结尾的条目按目录前缀放行，仓库外绝对路径直接拦截，仓库根由脚本自身位置推导而非 cwd，`tests/` 与 `tools/mh-dev/tests/` 作为 Tester 专属路径按目录前缀放行（与归属校验的 tester_scope 同口径，`tests-evil/` 不命中）
- **活跃交付物定位以全局指针为准**（CR-018 R7）：`role-guard.sh` 读 `deliverables/.state.md` 的 `project` 字段，**不得以文件系统扫描首个命中项替代**——`deliverables/` 下多项目并存是常态形态，`find … | head -1` 会取到任意一个项目的状态判权。五形态语义：指针文件不存在 / `project` 为空 / 指针指向的交付物或其 state 不存在 / `current_role` 空或畸形 → `exit 0` 放行；`project` 非法 slug → `exit 2`（唯一收紧项，出现即 state 被污染，此时放行等于在污染态下判权）。**任一形态下都不遍历 `deliverables/` 寻找替代 state。** 项目标识符字符集 `^[a-z][a-z0-9-]{0,63}$` 且不得为保留名（`docs`/`src`/`tests`/`deploy`/`assets`/`reference`/`engine`），由 `scripts/validate-slug.sh` 单一实现强制，生成侧（`skills/mh-intake`）与消费侧（守卫，插值前自校验，不信任生成侧）各调用一次
- `scripts/role-guard.sh` 覆盖 `Write`/`Edit`/`NotebookEdit` 三种写入工具（`NotebookEdit` 的路径参数是 `notebook_path`；路径参数缺失时保守放行并向 stderr 打印 `WARN`）。归一化后**按路径归属路由**，不再以「是否存在活跃需求」作为分支条件：`deliverables/` 前缀（目录前缀语义，`deliverables-evil/` 不命中）归 `/mh-run` 角色白名单，其余归 mh-dev 框架治理；无活跃 mh-dev 授权时框架路径放行（默认会话透明，见 §6），有授权则 `approved_scope` 不可被空/畸形/终态的需求 state 绕过。两条流水线路径集不相交，互不阻断
- **交还例外**：THINKER/WORKER/VERIFIER 持权时写本交付物 `.engine/.state.md`，若该次写入内容的**首个** `current_role:` 行其值恰为 `ORCHESTRATOR` 则放行，使调度循环可收尾。判据与守卫读取端同源（`grep '^current_role:' | head -1 | awk '{print $2}'`）——**存在性量词（任一行匹配即放行）曾导致横向夺权**，见 `docs/kb/domains/guards.md`。判据取本次写入的**新内容**而非磁盘旧值。**交还例外只接受 `Write`**：`Edit` 只暴露 `new_string` 片段，守卫看不到合并结果，跨行 `old_string` 可使片段判据与落盘生效值分歧而提权（audit F-01），故 `Edit` 写 `.engine/.state.md` 一律 `exit 2`——**交还必须用 Write 一次完整写入**。例外不放大到 `handoffs/`、`plan-action.md`、`SR*-record.md`、`lessons.md`、`process.log`，也不跨交付物生效；例外的路径正则 `^…$` 双向锚定到 `.state.md` 全名，`.state.md.evil`、`.state.mdX`、`.state.md/child.md` 等后缀伪造与 `x/deliverables/.../.state.md` 等嵌套伪造均不命中
- **完成回报例外**（CR-017 D1）：完成回报独立落盘到 `deliverables/{project}/.engine/reports/<handoff-basename>.report.md`，THINKER/WORKER/VERIFIER/ORCHESTRATOR 四角色均可写（ORCHESTRATOR 保留该权限用于驳回轮次与 SubAgent 失联时的兜底代填）。写权由**当前谁持权**约束，而非文件名声称的角色——加角色前缀判据会引入「文件名声称的角色」与「state 里的角色」两个主体，正是本条要消除的那类不一致。`handoffs/*.md` 仍 ORCHESTRATOR 独占：任务描述与输入白名单在 handoff、`read_files` 核对在回报，白名单与回报分处两套写权，故质量门禁比较的两侧无法自洽伪造。该放行条**无内容判据**（有意：内容判据是 CR-016 两个 P0 的共同载体，回报不承载流程状态故不引入）；路径正则 `^…$` 双向锚定，`.report.md.evil`、`.report.mdX`、`.report.md/child.md` 等后缀伪造与 `x/deliverables/.../reports/…` 等嵌套伪造均不命中，`${req}` 取自全局指针的 `project` 故不跨交付物生效；例外不放大为 `.engine/` 目录直通，`handoffs/`、`plan-action.md`、`SR*-record.md`、`lessons.md`、`process.log` 均不在此正则内
- role-guard 的判据存放在被治理方自己可写的文件中，故为**自授权机制**；`Bash` 通道不在 hook matcher 内、不受守卫覆盖；其定位是防误撞而非安全边界（详见 `docs/kb/domains/guards.md`「授权模型与能力边界」）
- 修改框架后运行 `bash scripts/check-harness.sh` 确认框架完整性

## 6. 多角色工作流协议

详见 `skills/mh-codeflow/SKILL.md`。仅在用户显式调用 `/mh-run`、`/mh-ppt` 或 `/mh-dev` 后生效，默认会话不启动任何多角色流程。核心铁律：

- Orchestrator 只做调度，不做专业判断
- 三角色（Thinker/Worker/Verifier）职责严格分离
- 角色切换必须通过 Handoff 文件
- SR 节点不可自主跨越
- code track（/mh-run）与 ppt track（/mh-ppt）各自独立流水线，共享 3-role spine
