# 质量门禁检查清单骨架

> Orchestrator 接收角色回报后按此清单逐项核对。SOP 见 mh-codeflow skill "质量门禁"节。

## Step 0: 白名单校验（所有角色通用）

核对来源是落盘的回报文件 `deliverables/{REQ-ID}/.engine/reports/{handoff-basename}.report.md`（由角色自己写入，可 diff、可留痕），不依赖 SubAgent 返回值。

- [ ] 回报文件存在（缺失 → 任务视为未完成，驳回或按兜底代填处置）
- [ ] 对比回报文件中 `read_files` 与 handoff 文件中的白名单
- [ ] 出现白名单外的文件 → 驳回，标注信息泄露风险
- [ ] read_files 为空或缺失 → 提醒角色补填（非阻塞）

## Thinker needs 产出验收

- [ ] 每条功能需求有 SHALL 语句
- [ ] 每条 SHALL 有至少 1 个 GWT 验收条件
- [ ] 无模糊量词（"适当"、"合理"、"尽量"等）
- [ ] 需求间无明显矛盾

## Thinker design 产出验收

- [ ] 对照表覆盖所有需求/Proposal 要点（无遗漏行）
- [ ] Tasks 清单每项有依赖标注（`[deps: ...]`）
- [ ] 每个 Task 有明确的验证方式
- [ ] Task 数量与需求复杂度匹配
- [ ] structure_skeleton 已定义时，产出的文件/章节结构须符合预定义
- [ ] test_strategy 为 e2e/integration 时，verify-strategy.md 存在且格式合规

## Thinker visual 产出验收

- [ ] slide-spec.md 中每页有布局说明
- [ ] wireframe 文件数量与 spec 描述一致
- [ ] 无空白占位页

## Worker 产出验收

- [ ] WORKER-apply-code-report 中 dev-test = PASS
- [ ] WORKER-apply-code-report 中 post-verify = PASS
- [ ] deliverables/{REQ-ID}/ 中文件数量与 Task 描述匹配
- [ ] 无 TODO/FIXME/placeholder 拋留在交付代码中

## Verifier 产出验收

- [ ] 报告结论明确（PASS 或 FAIL），无模棱两可
- [ ] PASS 时无未解决的失败项
- [ ] FAIL 时每个失败项有：复现步骤 + 期望vs实际 + 严重程度
- [ ] 降级验证时标注了原因和未覆盖的风险
- [ ] `scripts/verify-code-review.sh` 通过（Code Review 格式合规）
- [ ] `scripts/verify-qa.sh` QA-12 通过（回归套件存在时报告含回归结果）
- [ ] `scripts/verify-qa.sh` QA-13 通过（归档阶段用例沉淀完整性）
