# Handoff 完成回报示例

角色完成任务后，在 handoff 文件的"完成回报"部分填写。以下为参考示例。

---

## 成功示例

```
- status: done
- output_files: ["deliverables/REQ001/thinker/design.md"]
- read_files: ["deliverables/REQ001/proposal.md"]
- summary: "架构设计完成，含 3 个 Task 和需求映射表"
- issues: "N/A"
```

## 失败示例

```
- status: failed
- output_files: []
- read_files: ["deliverables/REQ001/thinker/design.md", "deliverables/REQ001/output/src/api.ts"]
- summary: "lint 检查失败，3 次自修未能解决"
- issues: "ESLint error: no-unused-vars in src/utils.ts:42, 自动修复引入新错误"
```
