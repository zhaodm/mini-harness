# 过程日志标准

所有角色执行步骤时必须追加日志到 `deliverables/{REQ-ID}/process.log`。

**格式：** `[{timestamp}] [{角色}] {事件描述}`

**timestamp 获取方式：** 优先使用 `date -u +%Y-%m-%dT%H:%M:%SZ`；如 date 命令不可用，使用递增序号 `#NNN`。

**强制落盘规则：**
- Orchestrator 的每条心跳 `[ORCHESTRATOR] xxx` 必须同时执行: `echo "[{timestamp}] [ORCHESTRATOR] xxx" >> deliverables/{REQ-ID}/process.log`
- SubAgent 完成时追加一条: `echo "[{timestamp}] [{角色}] 完成 {task_id}，产出: {file_list}" >> deliverables/{REQ-ID}/process.log`
- 心跳仅打印到 stdout 而未写入 process.log 视为违规
- SR Gate 审批结果必须追加一条（含通过/驳回 + 原因摘要）

**写入时机：**
- Orchestrator 每次调度前、验证后各追加一条
- Thinker/Worker/Verifier 完成任务后追加一条（含产物路径）
- 人工审批结果追加一条
- 异常/失败追加一条（含原因摘要）

**最低行数要求（phase=done 时）：**
- fast 模式: ≥ 6 行（init + dev + test + confirm + archive + done）
- standard/full 模式: ≥ 10 行
