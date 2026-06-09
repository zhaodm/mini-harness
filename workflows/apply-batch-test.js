/**
 * apply-batch-test.js — Apply 阶段 Batch 内 TE 并行审计
 *
 * 触发时机: Batch 内所有 DE Task 通过质量门禁后，并行派发 TE 审计。
 * 调用方: PM 主会话通过 Workflow 工具调用。
 *
 * args:
 *   reqId   — 需求编号 (e.g., "REQ003")
 *   batchId — 批次编号 (e.g., 1)
 *   tasks   — Task 列表，每项包含:
 *     taskId  — Task 编号 (e.g., "1")
 *     prompt  — TE SubAgent 的完整 prompt（角色契约 + handoff 内容）
 *
 * 返回:
 *   { batchId, tasks: [{ taskId, result, passed }] }
 *   PM 根据 passed 字段判断是否进入修复循环。
 */
export const meta = {
  name: "apply-batch-test",
  description: "Apply 阶段 Batch 内 TE 并行审计",
  phases: ["batch-test"]
};

const results = await parallel(
  args.tasks.map(task =>
    agent(`[TE] 审计 Task-${task.taskId} (${args.reqId} Batch-${args.batchId})`, {
      prompt: task.prompt,
      model: "sonnet"
    })
  )
);

return {
  batchId: args.batchId,
  tasks: args.tasks.map((task, i) => ({
    taskId: task.taskId,
    result: results[i],
    passed: !results[i].includes("FAIL") ||
            (results[i].includes("结论: PASS") || results[i].includes("conclusion: PASS"))
  }))
};
