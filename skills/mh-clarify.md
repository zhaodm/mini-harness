# Skill: mh-clarify

需求初始化与澄清。PM 主导，人机协作打磨 Proposal。

**日志规则：** 见 `templates/logging-standard.md`

---

## 前置检查

1. 检测 deliverables/.state.md 是否存在（全局状态指针）
   - 如不存在：从 `templates/state-pointer-template.md` 拷贝到 `deliverables/.state.md`
2. 如存在，读取其中 req_id，检查 `deliverables/{req_id}/.state.md` 的 phase
3. 加载历史经验：如 `output/lessons-learned.md` 存在，读取并在后续流程中传达给各角色
4. 检测场景模式（按优先级从高到低判断）：
   - **RESUME**: 最近 REQ 的 phase 非空且 phase≠done → 有未完成的流程，提示用户继续或放弃
   - **CHANGE**: output/spec/ 目录下存在 .md 文件（即有已归档的历史需求）→ 变更模式
   - **NEW**: 以上均不满足 → 全新项目

⚠️ 关键：phase=done 且 output/spec/ 有文件时，必须进入 CHANGE 模式，不得识别为 NEW。

### CHANGE 模式 - 增量开发

当 output/ 已有代码且本次需求是在其基础上迭代时：
1. PM 在 Proposal 中标注"增量开发，基于 output/ 已有代码"
2. BA/SA 仅产出本次变更的增量文档（不重复已有内容），归档时由 PM 负责 merge 成全量
3. DE 的 handoff 白名单自动包含 `output/`（已有代码）
4. TE 的回归测试范围覆盖 output/ 全部已有功能
5. 归档时使用变更归档策略（将增量 merge 进 output/spec/ 全量文档）

## 环境预检

1. 扫描项目根目录，检测技术栈：
   - 语言: 通过配置文件推断（pyproject.toml→Python, package.json→Node.js, go.mod→Go, Cargo.toml→Rust, pom.xml/build.gradle→Java）
   - 包管理器: 通过 lock 文件推断（poetry.lock→poetry, uv.lock→uv, package-lock.json→npm, yarn.lock→yarn, pnpm-lock.yaml→pnpm, go.sum→go modules, Cargo.lock→cargo）
   - 测试框架: 通过配置文件中的 test 相关配置推断
   - 构建工具: 通过 build 相关配置推断
   - Lint 工具: 通过 lint 配置文件推断（.eslintrc*, ruff.toml, .golangci.yml 等）

2. 浏览器可用性检测（仅 output_type 涉及 UI 时）：检测 Playwright/Selenium/Cypress 可用性

3. 将检测结果写入 `deliverables/{REQ-ID}/.state.md` 的 tech_stack 和 env 字段

4. 如检测结果不完整或 language=unknown，向用户展示检测结果并请求补充：
   ```
   [环境检测结果]
   语言: {language}
   包管理器: {package_manager}
   测试框架: {test_framework}
   构建工具: {build_tool}
   Lint: {lint_tool}
   
   以上信息是否正确？如有遗漏请补充。
   ```

## Step 1: 初始化任务目录

**执行角色:** PM

1. 生成需求编号（REQ001, REQ002...递增）
2. 创建 `deliverables/{REQ-ID}/` 隔离目录结构：
   ```
   deliverables/{REQ-ID}/
   ├── sa/
   ├── te/
   ├── de/
   ├── output/
   ├── handoffs/
   ├── baselines/
   ├── .state.md
   └── process.log
   ```
3. 写入 `deliverables/{REQ-ID}/.state.md`（完整 schema 见 `templates/state-template.md`）:
   ```yaml
   req_id: REQ{NNN}
   mode: ""
   output_type: ""
   phase: init
   current_step: INIT-1
   current_role: PM
   current_handoff: ""
   completed_steps: []
   auto_advance: false
   repair_round: 0
   repair_task: ""
   sr_status:
     SR1: pending
     SR2: pending
     SR3: pending
     SR4: pending
   last_updated: "{timestamp}"
   tech_stack:
     language: ""
     package_manager: ""
     test_framework: ""
     build_tool: ""
     lint_tool: ""
   test_strategy: ""
   env:
     browser_available: false
   ```
4. `[PM] 初始化完成，进入需求澄清`

## Step 2: 需求澄清（人机协作）

**执行角色:** PM

1. 读取 reference/ 目录下的参考资料
   - 如含图片，使用 Read 工具直接识别内容
2. 基于参考资料，逐轮向用户提问：
   - 每轮最多 3 个问题
   - 聚焦于消除歧义、明确边界、确认优先级
3. CHANGE 模式下：
   - 读取 output/spec/ 下已有规格
   - 仅围绕变更点提问，不重复已有内容
4. 根据用户回答，生成 Proposal 草稿
5. **参考摘要生成**（reference/ 含 3 个以上文件或总行数超过 1000 行时）：
   - PM 在 proposal.md 末尾附加 `## 参考摘要` 节
   - 每个参考文件一行摘要 + 关键接口/约束列表（≤5 行/文件）
   - 标注精读优先级: `[HIGH]` 需 SA 深入参考 / `[LOW]` 仅供了解背景
   - 后续 propose 阶段 SA handoff 白名单根据此优先级分配访问级别

## Step 3: 产出类型选择

**执行角色:** PM（人机交互）

1. 基于需求澄清结果和环境检测，PM 推荐 output_type：
   ```
   [产出类型选择]
   根据需求分析，建议产出类型为: {推荐类型}

     web-app        — Web 应用（前端/全栈，需浏览器测试）
     backend-api    — 后端服务/API（REST/gRPC，需接口测试）
     cli-tool       — 命令行工具（需功能测试）
     data-pipeline  — 数据管道/ETL（需数据验证）
     infrastructure — 基础设施代码（Terraform/K8s，需 plan/dry-run 验证）
     documentation  — 文档/规格（需人工审阅，无自动化测试）
     ppt            — 演示文稿/HTML slides（需视觉校验）
     library        — 库/SDK（需单元测试 + API 兼容性）
     custom         — 自定义（请描述验证方式）

   请选择或确认:
   ```

2. 推荐逻辑：
   - 检测到 Playwright/Cypress + 前端框架（React/Vue/Angular）→ web-app
   - 检测到 Express/FastAPI/Gin/Spring 等 → backend-api
   - 检测到 CLI 框架（commander/click/cobra）→ cli-tool
   - reference/ 中全是文档 + language=unknown → documentation
   - 用户明确说"PPT"/"演示"/"slides" → ppt
   - 检测到 Terraform/Pulumi/CDK → infrastructure
   - 检测到 dbt/Airflow/Spark → data-pipeline
   - 无明确信号 → 请用户选择

3. 用户确认后写入 `deliverables/{REQ-ID}/.state.md`: output_type={选择}

4. 根据 output_type 推导 test_strategy 默认值：
   - web-app → e2e（如 env.browser_available=true）或 integration
   - backend-api → integration
   - cli-tool → integration
   - data-pipeline → smoke
   - infrastructure → smoke
   - documentation → manual
   - ppt → manual
   - library → unit
   - custom → 由用户指定

5. 写入 test_strategy 到 .state.md

6. 如 output_type 涉及 UI（web-app / ppt），此时执行浏览器可用性检测并更新 env.browser_available

## Step 4: 模式选择

**执行角色:** PM（人机交互）

Proposal 草稿完成后，PM 根据需求规模向用户推荐模式：

```
[模式选择]
根据需求规模分析，建议使用 {推荐模式} 模式：

  fast     — 小调整（bug修复、≤5个文件、无需重新设计）
             流程：PM出plan → DE开发 → TE轻量审计 → 人工确认 → 归档
             预估：5-10分钟

  standard — 新功能（需设计，不跨模块）
             流程：SA设计 → TE用例 → DE开发 → TE审计 → SR2+SR3 → 归档
             预估：15-20分钟

  full     — 大型需求（跨模块、需完整评审链）
             流程：BA需求 → SA设计 → TE用例 → SR1 → DE开发 → SR2+SR3 → SR4
             预估：30+分钟

💡 提示：即使选择 full 模式，也可以在选择后声明"跳过所有人工审核点"，
   框架将自动通过 SR1-SR4，保留完整角色协作但跳过等待，大幅加快速度。

请选择模式:
```

推荐逻辑：
- 涉及文件 ≤5 且无新架构 → 推荐 fast
- 单模块新功能或中等改动 → 推荐 standard
- 跨模块、多角色协作、需完整追溯 → 推荐 full

用户选择后，写入 `deliverables/{REQ-ID}/.state.md`: `mode: {fast|standard|full}`

## Step 5: Proposal 定稿

**执行角色:** PM

1. 将 Proposal 草稿写入 `deliverables/{REQ-ID}/proposal.md`
2. 向用户呈现 Proposal 全文，请求确认
3. 用户确认通过：
   - 更新 `deliverables/{REQ-ID}/.state.md`: `phase: init, current_step: INIT-DONE`
   - 更新 `deliverables/.state.md`: `req_id: {REQ-ID}`（全局指针）
   - `[PM] Proposal 定稿完成（模式: {mode}），可执行 /mh-propose`
4. 用户要求修改：
   - 根据反馈修改 Proposal
   - 重新呈现，循环直到确认

## Proposal 格式

```markdown
# Proposal: {项目/需求标题}

## 背景与目标
{为什么要做这件事}

## 功能模块（至少列出主要模块）
- {模块1}: {一句话描述}
- {模块2}: {一句话描述}

## 范围
- 包含: {列举}
- 不包含: {列举}

## 关键约束
- {约束1}
- {约束2}

## 参考资料
- {来源列表}
```

## 异常处理

- reference/ 为空：提示用户补充参考资料或直接口述需求
- RESUME 模式用户选择放弃：清理未完成的 .state.md，重新进入 NEW 模式
