---
name: mh-self-test
description: This skill should be used when Worker completes coding, before filling code-report, or when running dev-test. Worker self-test SOP with test execution, lint check, build verification, and self-check checklist.
---

# Skill: mh-self-test

Worker 开发自测标准操作规程。编码完成后、提交回报前必须执行。

**日志规则：** 见 `templates/logging-standard.md`

---

## 触发时机

Worker 完成编码实现后，在填写 code-report.md 之前执行。

## 前置: 读取技术栈信息

1. 读取 `deliverables/{REQ-ID}/.engine/.state.md` 中 tech_stack、test_strategy 字段
2. 根据 tech_stack.language 确定命令路由

---

## Step 1: 测试执行

根据 tech_stack.language 路由测试命令：

| language | 检测方式 | 默认命令 |
|----------|---------|---------|
| javascript | package.json scripts.test | npm test / yarn test / pnpm test |
| python | pytest.ini / pyproject.toml | pytest / python -m pytest |
| go | go.mod | go test ./... |
| rust | Cargo.toml | cargo test |
| java | pom.xml / build.gradle | mvn test / gradle test |
| unknown | .engine/.state.md tech_stack.test_framework | 读取用户指定的命令 |

跳过条件：
- test_strategy=none 或 test_strategy=manual: 跳过此步，记录 "测试跳过（test_strategy={value}）"

执行后记录结果：通过数 / 失败数 / 跳过数。如有失败：修复代码，重新运行。

## Step 2: Lint 检查

根据 tech_stack.language 路由 lint 命令：

| language | 检测方式 | 默认命令 |
|----------|---------|---------|
| javascript | .eslintrc* / biome.json / package.json | npx eslint . / npx prettier --check . |
| python | ruff.toml / pyproject.toml [tool.ruff] | ruff check . / black --check . |
| go | .golangci.yml | golangci-lint run |
| rust | (内置) | cargo clippy -- -D warnings |
| java | checkstyle.xml | mvn checkstyle:check |
| unknown | .engine/.state.md tech_stack.lint_tool | 读取用户指定的命令；如无则跳过 |

自动修复可修复项，不可自动修复的手动修复。

## Step 3: 构建验证

根据 tech_stack.language 路由构建命令：

| language | 检测方式 | 默认命令 |
|----------|---------|---------|
| javascript | package.json scripts.build | npm run build |
| python | pyproject.toml [build-system] | python -m build / pip install -e . |
| go | go.mod | go build ./... |
| rust | Cargo.toml | cargo build --release |
| java | pom.xml / build.gradle | mvn package -DskipTests / gradle build |
| unknown | .engine/.state.md tech_stack.build_tool | 读取用户指定的命令；如无则跳过 |

跳过条件：
- test_strategy=manual 或 test_strategy=none: 跳过构建步骤

## Step 4: 自检清单

逐项确认：

- [ ] 所有新增代码有对应测试（test_strategy=none/manual 时改为"已确认无需自动化测试"）
- [ ] 测试全部通过（或已跳过且记录原因）
- [ ] Lint 无错误（或已跳过且记录原因）
- [ ] 构建成功（或已跳过且记录原因）
- [ ] 未修改白名单外的文件
- [ ] 未引入新的安全漏洞（无硬编码密钥、无 SQL 拼接等）

## 输出

将结果记录到 deliverables/{REQ-ID}/WORKER-apply-code-report-t{N}.md 的"测试结果"和"自检结果"部分：

```
## 测试结果
- 测试数: {N}
- 通过: {N}
- 失败: 0
- 跳过说明: {如有}

## 自检结果
- dev-test: PASS
```

## 失败处理

- 任何一步失败：修复后从该步重新执行
- Worker 内部自修最多 3 次（子循环）：超出后在 handoff 回报中标记 status=failed，附带错误日志
- Orchestrator 层面的修复循环最多 5 轮（见 mh-build skill）
