# 经验沉淀机制设计方案

## 目标

每次需求执行结束后，将过程中使用者对框架的调教、纠正、优秀经验持久化沉淀，用于：
1. 下次需求执行时自动加载，避免重蹈覆辙
2. 提供给框架开发者持续改进框架

## 设计方案

### 1. 新增文件：`output/lessons-learned.md`（累积型全量文档）

与 `output/spec/` 同级，归档在 output/ 下，是所有历史经验的累积全量文档。

每次新 REQ 执行完毕，在 archive 阶段由 PM 将本次经验 merge 进去（与 spec 的 CHANGE 归档逻辑一致）。

### 2. 经验采集时机（4个采集点）

| 采集点 | 时机 | 采集内容 |
|--------|------|---------|
| CP-1: SR驳回 | 每次 SR 审批被用户驳回时 | 驳回原因 + 用户的修正方向 |
| CP-2: 过程纠正 | 用户在流程中主动纠正 Agent 行为时 | 纠正内容 + 原因 |
| CP-3: 修复循环 | 修复循环≥2轮时 | 系统性根因（非个案bug） |
| CP-4: 结项回顾 | SR4 审批前，PM 主动询问用户 | 用户对本次执行的总结评价和改进建议 |

### 3. 过程中的暂存：`deliverables/{REQ-ID}/lessons.md`

每个 REQ 执行过程中，PM 在上述采集点实时追加记录到 `deliverables/{REQ-ID}/lessons.md`。
归档时 merge 到 `output/lessons-learned.md`。

### 4. 新增 archive 步骤：ARC-6（经验归档）

在 ARC-5（指标生成）之后、SR4 之前，新增 ARC-6：
1. PM 向用户呈现本次执行的经验采集记录（CP-1~CP-3 已自动收集的内容）
2. PM 主动问用户："本次执行有什么经验/建议要沉淀？"（CP-4）
3. 用户补充后，PM 将 `deliverables/{REQ-ID}/lessons.md` merge 到 `output/lessons-learned.md`

### 5. 下次执行时的加载

在 mh-clarify 前置检查中：
- 如 `output/lessons-learned.md` 存在，PM 读取并在 Proposal 阶段传达给各角色
- 相关经验条目通过 handoff 白名单传递给对应角色

### 6. 文档格式

```markdown
# 经验沉淀

## 全局经验（适用于所有需求）

### EXP-{N}: {经验标题}
- 来源: {REQ-ID}
- 类别: {设计/实现/流程/测试/沟通}
- 角色: {PM/BA/SA/DE/TE/UX}
- 经验: {具体内容}
- 原因: {为什么这样做更好}
- 适用场景: {什么情况下应用此经验}

## 产出类型特有经验

### PPT 类经验
- ...

### Web App 类经验
- ...
```

### 7. 对框架开发者的价值

框架开发者可以定期 review `output/lessons-learned.md`，识别共性经验并固化到框架中：
- 反复出现的经验 → 升级为 agents/*.md 中的规则
- 验证类经验 → 升级为 verify.sh 检查项
- 流程类经验 → 升级为 skills/*.md 步骤

### 8. 涉及修改的文件清单

1. `templates/lessons-template.md`（新建）— 经验文档格式模板
2. `skills/mh-archive.md` — 新增 ARC-6 步骤
3. `skills/mh-clarify.md` — 前置检查增加读取 output/lessons-learned.md
4. `agents/pm.md` — 新增经验采集职责描述（CP-1~CP-4）
5. `templates/state-template.md` — 步骤ID枚举增加 ARC-6
6. `README.md` — archive 表格增加 ARC-6
