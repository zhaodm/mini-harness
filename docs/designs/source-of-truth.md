# 权威源映射表（Source of Truth）

> 本文件供人类维护者参考，AI Agent 运行时不读取。
> 运行时冲突解决规则见本文件"冲突解决规则"节。

本文件定义每个设计概念的权威文件。当多个文件描述同一概念时，以权威源为准。

---

## 核心映射

| 设计概念 | 权威源 | 辅助参考 |
|---------|--------|---------|
| 全局工程纪律 | CLAUDE.md "工程准则"节 | — |
| 工作流纪律 | orchestrator.md + CLAUDE.md §6 + skills/mh-codeflow/SKILL.md | docs/designs/design.md §4.1 |
| 角色职责与禁止事项 | agents/*.md | docs/designs/design.md §3 |
| 角色质量标准与思考框架 | skills/mh-design/SKILL.md + skills/mh-build/SKILL.md + skills/mh-verify/SKILL.md | — |
| 流程步骤与 track 裁剪 | skills/mh-*/SKILL.md | docs/designs/design.md §4 |
| Orchestrator 调度协议 | skills/mh-codeflow/SKILL.md "调度协议"节 | docs/designs/design.md §3 |
| Orchestrator 质量门禁清单 | skills/mh-codeflow/SKILL.md "质量门禁"节 + templates/orchestrator-quality-gate.md | — |
| SR Gate 通过标准 | skills/mh-design/SKILL.md, skills/mh-build/SKILL.md, skills/mh-deliver/SKILL.md | docs/designs/design.md §4 |
| 状态 schema | templates/state-template.md | docs/designs/design.md §4.4 |
| Handoff 协议与格式 | templates/handoff-template.md | docs/designs/design.md §5.3 |
| 日志格式 | templates/logging-standard.md | — |
| 修复收敛机制 | skills/mh-repair/SKILL.md "决策"节 | docs/designs/design.md §6 |
| repair_history schema | templates/state-template.md | skills/mh-repair/SKILL.md 示例 |
| repair_snapshots schema | templates/state-template.md | skills/mh-repair/SKILL.md "修复派发"节 |
| 硬校验规则 | scripts/*.sh | docs/designs/design.md §7.4 |
| PPT track 规则 | skills/mh-slideflow/SKILL.md（流程骨架 + 按需加载索引） | docs/designs/design.md §6 |
| PPT 视觉叙事原则（人类判断项） | skills/mh-slideflow/SKILL.md "PPT 视觉叙事原则"节 | — |
| PPT 硬约束数值（字号分档 / 几何阈值 / 豁免规则 / 布局规则） | templates/ppt-quality-rules.md | scripts/verify-ppt.sh |
| PPT 版式登记（ID / 类型 / 密度归属） | templates/ppt-templates/registry.json | templates/ppt-quality-rules.md |
| PPT 密度模型 | templates/ppt-quality-rules.md "密度模型"节 | templates/state-template.md `ppt_density` |
| PPT 渲染几何测量 | scripts/verify-ppt.sh D 类（内联 Node/Playwright 测量器） | templates/ppt-quality-rules.md |
| PPT 单文件形态与导航 | templates/ppt-base.html | templates/ppt-quality-rules.md |
| 经验采集规则 | skills/mh-deliver/SKILL.md "经验采集规则"节 | — |
| Mini-Harness 自身开发协议 | tools/mh-dev/CLAUDE.md | tools/mh-dev/skills/mh-dev/SKILL.md |
| mh-dev 自开发状态 schema | tools/mh-dev/templates/state.json.template | tools/mh-dev/.mh-dev/state.json |
| mh-dev 转换、范围与发布硬门禁 | tools/mh-dev/scripts/*.sh | tools/mh-dev/CLAUDE.md |
| 金标准示例 | templates/examples/*.md | — |
| 产出结构参考 | templates/output-guides/*.md | — |
| 执行指标模板 | templates/metrics-template.md | skills/mh-deliver/SKILL.md ARC-6 |
| 框架知识库 | docs/kb/system-map.md + domains/*.md | docs/designs/design.md |

---

## 三层一致性保障

```
第一层：结构化约束（预防）
  ├─ check-harness.sh — 框架文件完整性自检
  ├─ Handoff 协议 — 角色间信息传递必须结构化
  ├─ 模板约束 — 产出物必须按模板格式
  └─ Orchestrator 调度协议 — 标准化调度行为

第二层：自动检测（发现）
  ├─ verify.sh A/B/C/D — 产出物校验（退出码驱动）
  ├─ 本文件 — 权威源映射（冲突时查阅）
  └─ design.md 权威声明 — "如有冲突以 skills/agents 为准"

第三层：人工评审（兜底）
  ├─ SR1-4 审批节点（决策上下文卡辅助判断）
  ├─ Orchestrator 质量门禁（内容级验收）
  └─ 用户最终确认
```

---

## 冲突解决规则

1. **skills/*.md vs docs/designs/design.md** → 以 skills 为准（skills 是执行权威）
2. **agents/*.md vs docs/designs/design.md** → 以 agents 为准（agents 是角色契约）
3. **CLAUDE.md vs 其他所有文件** → 以 CLAUDE.md 为准（最高约束）
4. **templates/ vs skills/** → templates 定义格式，skills 定义何时使用
5. **scripts/*.sh vs Agent 自述** → 以 scripts 退出码为准（硬校验 > 自述）

---

## 维护规则

- 修改 skills/agents 后，检查 docs/designs/design.md 对应章节是否需要同步
- 新增模板文件后，更新本文件的映射表
- 新增 scripts 检查项后，更新 docs/designs/design.md §6
- 发现映射表与实际不符时，以实际文件为准，更新映射表
- `scripts/role-guard.sh` 覆盖 `Write`/`Edit`/`NotebookEdit` 三种写入工具（`NotebookEdit` 的路径参数是 `notebook_path`；路径参数缺失时保守放行并打印 `WARN`）。归一化后**按路径归属路由**：`deliverables/` 前缀（目录前缀语义）归 `/mh-run` 角色白名单，其余归 mh-dev 框架治理，无活跃 mh-dev 授权时框架路径放行（默认会话透明）。两条流水线路径集不相交，互不阻断。
- `scripts/role-guard.sh` **完成回报例外**（CR-017）——THINKER/WORKER/VERIFIER/ORCHESTRATOR 四者均可写本需求 `deliverables/{REQ-ID}/.engine/reports/*.report.md`（回报独立落盘，`handoffs/` 仍 ORCHESTRATOR 独占）。该条**无内容判据**（有意：内容判据是 CR-016 两个 P0 的共同载体），故排列次序对抗不适用；路径正则 `^…$` 双向锚定（`.report.md.evil`/`.report.mdX`/`.report.md/child.md` 与 `x/deliverables/…` 嵌套伪造均不命中），`${req}` 取自当前 state 故不跨需求；不放大到 `handoffs/`、`plan-action.md` 等其他引擎态文件。写权由「当前谁持权」而非「文件名声称的角色」约束（避免引入第二主体）。提升的是落盘可追溯性，非身份认证——守卫仍无法证明回报由谁写
- `scripts/role-guard.sh` mh-dev 分支**只校验 `approved_scope`，不校验写入者角色**（三角色共享同一张通行证）。CR-017 D3 曾设计按 `state.json` 的 `current_role` 收窄，因该字段恒为 `planner`（`transition-state.sh:19` 硬写）而未落地，理由见 `docs/kb/domains/guards.md`
- `scripts/role-guard.sh` WORKER 角色可写 `deliverables/{REQ-ID}/` 下除 `.engine/`（大小写不敏感）、`THINKER-*.md`、`VERIFIER-*.md`、`ORCHESTRATOR-*.md`、`.archiveignore` 外的所有路径（项目代码路径放行）；THINKER/WORKER/VERIFIER 额外有**交还例外**——写本需求 `.engine/.state.md` 且本次写入内容的首个 `current_role:` 行其值恰为 `ORCHESTRATOR` 时放行（判据与读取端同源，非存在性量词；取本次写入新内容而非磁盘旧值；**交还例外只接受 `Write`**，`Edit` 写该文件一律拒（片段判据无法覆盖合并结果，曾可提权）；路径正则 `^…$` 双向锚定 `.state.md` 全名，后缀伪造如 `.state.md.evil`/`.state.mdX` 与嵌套伪造路径均不命中；不放大到 `handoffs/` 等其他引擎态文件，不跨需求生效）；全局路径穿越检测拒绝包含 `..` 组件的写入路径；mh-dev 分支采用双向归一化匹配 `approved_scope`（两侧统一转绝对形态后比较，兼容 scope 的相对/绝对两种存储形态），以 `/` 结尾的 scope 条目按目录前缀放行，仓库外绝对路径直接拦截，仓库根由脚本自身位置推导而非 cwd，`tests/` 与 `tools/mh-dev/tests/` 作为 Tester 专属路径按目录前缀放行（与 `tools/mh-dev/scripts/validate-changes.sh` 的 tester_scope 同口径）
- role-guard 的判据存放在被治理方自己可写的文件中，故为**自授权机制**；`Bash` 通道不在 hook matcher 内、不受覆盖；其定位是防误撞而非安全边界（详见 `docs/kb/domains/guards.md`「授权模型与能力边界」）

---

## 版本升级自检清单

每次重大变更后执行：

- [ ] `grep -r "见 agents/orchestrator.md" skills/` → 确认引用描述与 orchestrator.md 实际内容一致
- [ ] `grep -r "见 agents/pm.md\|见 agents/ba.md\|见 agents/sa.md\|见 agents/de.md\|见 agents/te.md\|见 agents/ux.md" skills/ docs/` → 确认无旧角色文件引用残留
- [ ] `grep -r "A/B/C/D" .` → 确认所有引用已更新为 A/B/C/D/E（如适用）
- [ ] `find skills/ -name '*.md' -not -path '*/SKILL.md'` → 确认无扁平 skill 文件残留
- [ ] `bash scripts/check-harness.sh` → 框架完整性通过
- [ ] 对比 state-template.md 与最近的 deliverables/*/.engine/.state.md → schema 一致
- [ ] 检查 CHANGELOG.md 是否已更新
