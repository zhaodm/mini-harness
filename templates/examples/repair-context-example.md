# 金标准示例：修复上下文

> 展示 Orchestrator 在修复循环中如何进行根因分析并构建结构化修复上下文。

---

## 示例 1：测试失败（最常见）

**Verifier 报告摘要：** Task-2 审计失败，3 个测试未通过

**Orchestrator 根因分析：**

```
失败特征:
  - 错误类型: test_failure
  - 关键错误信息:
    - "AssertionError: expected status 200, got 500" (test_register_success)
    - "AssertionError: expected body.user_id to exist" (test_register_response)
    - "TypeError: Cannot read property 'id' of null" (test_register_duplicate)
  - 影响范围: 3/15 测试失败，均在 register endpoint

根因假设:
  - 高概率: UserService.create() 返回 null 而非 user 对象（3 个失败都指向同一调用链）
  - 低概率: 数据库连接问题（但其他测试通过，排除）

建议修复方向:
  - 检查 src/services/user.ts 的 create() 方法返回值
  - 确认 repository.save() 是否正确返回创建的实体
  - 修复后确认 3 个失败测试全部通过

历史尝试: 首次修复（R1→R2）
```

---

## 示例 2：Lint 错误（修复后引入新问题）

**Verifier 报告摘要：** Task-1 审计失败，lint 错误

**Orchestrator 根因分析：**

```
失败特征:
  - 错误类型: lint_error
  - 关键错误信息:
    - "no-unused-vars: 'result' is defined but never used" (src/utils.ts:42)
    - "no-explicit-any: Unexpected any" (src/utils.ts:38)
  - 影响范围: 2 个 lint 错误，同一文件

根因假设:
  - 上轮修复（R1）解决了逻辑错误，但重构时留下了未使用的变量
  - any 类型是临时绕过，需要补充正确的类型定义

建议修复方向:
  - src/utils.ts:42 — 删除未使用的 result 变量，或使用它
  - src/utils.ts:38 — 将 any 替换为具体类型（参考函数返回值推断）
  - 修复后运行 lint 确认无新错误

历史尝试:
  - R1: 修复了 "Cannot find module" 错误（import 路径错误）
  - R2: 本轮修复 lint 错误（R1 修复引入的副作用）

收敛判断: 收敛（R1 有 1 个编译错误，R2 只有 2 个 lint 警告，严重程度降低）
```

---

## 示例 3：发散场景（应提前升级）

**Verifier 报告摘要：** Task-3 审计失败，新增 2 个测试失败

**Orchestrator 根因分析：**

```
失败特征:
  - 错误类型: test_failure
  - 关键错误信息:
    - "AssertionError: expected 'active', got 'pending'" (test_confirm_email) — 新增失败
    - "TimeoutError: operation timed out" (test_send_email) — 新增失败
  - 影响范围: 2 个新失败（上轮是 1 个不同的失败）

根因假设:
  - 上轮修复引入了新问题（修改了状态转换逻辑，影响了邮件确认流程）
  - 错误类型从 "数据库错误" 变为 "状态逻辑错误"，说明修复方向偏离

收敛判断: ⚠️ 发散
  - R1: 1 个失败 (db_connection)
  - R2: 1 个失败 (assertion, 不同测试)
  - R3: 2 个失败 (assertion + timeout, 又是不同测试)
  - 连续 2 轮错误类型变化 + 失败数增加 → 触发提前升级

建议: 上升人工审核。当前修复方向可能有根本性问题，需要人工判断是否需要回退到 R1 之前的状态重新设计修复策略。
```
