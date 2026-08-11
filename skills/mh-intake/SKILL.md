---
name: mh-intake
description: This skill should be used when the user starts a new project requirement, runs "/mh-clarify", or when in the init/clarify phase. Requirement initialization and clarification with track selection, tech stack detection, and test strategy recommendation.
---

# Skill: mh-intake

需求初始化与澄清。Orchestrator 主导，人机协作打磨 Proposal。

**日志规则：** 见 `templates/logging-standard.md`

---

## 前置检查

1. 如 `deliverables/.state.md` 不存在，从 `templates/state-pointer-template.md` 拷贝
2. 如存在，读取 req_id 和对应 `.engine/.state.md` 的 phase
3. 如 `deliverables/{REQ-ID}/docs/lessons-learned.md` 存在，加载历史经验
4. **调用 `detectScenario()`**（`workflows/lib/detect-scenario.js`）判断场景
5. RESUME → 提示用户继续或放弃；CHANGE → 增量开发模式；NEW → 全新项目
5. **旧角色 schema 迁移**：如 .engine/.state.md 含旧 current_role（PM/BA/SA/DE/TE/UX），
   提示"检测到旧角色 schema，将自动迁移"并映射：
   - PM → ORCHESTRATOR
   - BA/SA/UX → THINKER
   - DE → WORKER
   - TE → VERIFIER

### CHANGE 模式要点

- Proposal 标注"增量开发，基于 deliverables/{REQ-ID}/ 已有代码"
- Thinker 仅产出增量文档，归档时 `archiveMerge()` 负责 merge 全量
- Worker handoff 白名单包含 design.md 规划的项目代码路径；Verifier 回归覆盖全部已有功能

## 环境预检

**调用 `detectTechStack()`**（`workflows/lib/recommend-type-mode.js`）自动推断，或手动扫描配置文件：
- 语言: pyproject.toml→Python, package.json→JS/TS, go.mod→Go, Cargo.toml→Rust, pom.xml→Java
- 包管理器: poetry.lock→poetry, package-lock.json→npm, yarn.lock→yarn, pnpm-lock.yaml→pnpm
- 浏览器检测（仅 UI 类需求）: Playwright/Selenium/Cypress 可用性

检测不完整时向用户确认。结果写入 `.engine/.state.md` tech_stack 和 env 字段。

## Step 1: 初始化任务目录 + Track 选择

1. 生成 REQ-ID → 创建 `deliverables/{REQ-ID}/` 目录结构（含 `.engine/` 子目录）
2. **Track 选择**（由入口命令决定）：
   - `/mh-run` → `track: code`
   - `/mh-ppt` → `track: ppt`
3. 写入 `.engine/.state.md`（schema 见 `templates/state-template.md`），含 track 字段
4. track 写入后只读，切换需重新开需求

## Step 2: 需求澄清（人机协作）

1. 读取 reference/ 参考资料（含图片识别）
2. 逐轮向用户提问（每轮 ≤3 问，聚焦歧义/边界/优先级）
3. CHANGE 模式下仅围绕变更点提问
4. 生成 Proposal 草稿
5. reference/ 含 ≥3 文件或 ≥1000 行时，附加参考摘要（标注 [HIGH]/[LOW] 精读优先级）

## Step 3: 验证策略确认

**调用 `recommendTestStrategy()`**（`workflows/lib/recommend-type-mode.js`），根据 tech_stack 和浏览器可用性推断 test_strategy。

向用户呈现推荐结果并请求确认，确认后写入 test_strategy 到 `.engine/.state.md`。

## Step 4: Proposal 定稿

1. 写入 `deliverables/{REQ-ID}/ORCHESTRATOR-init-proposal.md`
2. 向用户呈现，请求确认
3. 确认 → 更新 `.engine/.state.md`: phase=init, current_step=INIT-DONE；更新 `deliverables/.state.md`: req_id={REQ-ID}（全局指针）
4. 驳回 → 修改后重新呈现，循环直到确认

### Proposal 格式

```markdown
# Proposal: {标题}
## 背景与目标
## 功能模块
## 范围（包含/不包含）
## 关键约束
## 参考资料
```

## 异常处理

- reference/ 为空：提示用户补充或口述
- RESUME 用户放弃：清理 .engine/.state.md，重新 NEW
