# 完成回报示例

角色完成任务后，写入独立的回报文件，**不写进 handoff 文件**（handoff 是 ORCHESTRATOR 独占，执行角色写入被 role-guard 拒绝）。

回报路径由所属 handoff 的 basename 机械派生：

```
deliverables/web-cli/.engine/
├── handoffs/web-cli-THINK-NEEDS-R1.md          ← ORCHESTRATOR 独占（任务+白名单+约束）
└── reports/web-cli-THINK-NEEDS-R1.report.md    ← 被派发角色可写（回报）
```

五个字段均须行首无缩进 —— `scripts/verify.sh` 与 `scripts/verify-qa.sh` 按行首锚定读取。

---

## 成功示例

文件 `deliverables/web-cli/.engine/reports/web-cli-THINK-DESIGN-R1.report.md`：

```
status: done
output_files: ["deliverables/web-cli/docs/spec/design.md"]
read_files: ["deliverables/web-cli/.engine/proposal.md"]
summary: "架构设计完成，含 3 个 Task 和需求映射表"
issues: "N/A"
```

## 失败示例

文件 `deliverables/web-cli/.engine/reports/web-cli-DEV1-T1-R2.report.md`：

```
status: failed
output_files: []
read_files: ["deliverables/web-cli/docs/spec/design.md", "deliverables/web-cli/src/api.ts"]
summary: "lint 检查失败，3 次自修未能解决"
issues: "ESLint error: no-unused-vars in src/utils.ts:42, 自动修复引入新错误"
```
