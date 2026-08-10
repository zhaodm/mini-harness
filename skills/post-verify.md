# Skill: post-verify

Worker 交付前校验标准操作规程。dev-test 通过后、填写回报前执行。

**日志规则：** 见 `templates/logging-standard.md`

---

## 触发时机

dev-test skill 全部通过后执行。这是 Worker 交付前的最后一道自检。

## Step 1: 运行 verify.sh

1. 执行 `./scripts/verify.sh A`（文件存在性检查）
2. 确认退出码为 0
3. 如失败：检查缺失文件，补充后重试

## Step 2: 产出物完整性

1. 对照 handoff 中"期望输出"列表
2. 逐一确认每个文件：
   - 存在
   - 非空
   - 格式正确（如有格式要求）
3. 如有缺失：补充生成

## Step 3: 无越权修改检查

1. 列出本次所有文件变更（新增 + 修改）
2. 对照 handoff 白名单 + 期望输出路径
3. 确认没有修改白名单外的文件
4. 如有越权修改：撤销该修改

## Step 4: 回归检查

1. 如果是修复轮次（R>1）：确认之前通过的测试仍然通过
2. 如果有已有代码：确认未破坏已有功能

## 输出

在 code-report.md 中记录：

```
## 自检结果
- dev-test: PASS
- post-verify: PASS
```

## 失败处理

- verify.sh 退出码非 0：根据错误信息修复，重新执行
- 发现越权修改：撤销后重新检查
- 回归失败：修复回归问题，重新执行 dev-test + post-verify
