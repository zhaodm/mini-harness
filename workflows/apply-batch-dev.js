/**
 * apply-batch-dev.js — Apply 阶段 Batch 内 Worker 并行开发
 *
 * 触发时机: Orchestrator 计算出 Batch 后，为 Batch 内所有 Task 并行派发 Worker 开发。
 * 调用方: Orchestrator 主会话通过 Workflow 工具调用。
 *
 * args:
 *   reqId   — 需求编号 (e.g., "REQ003")
 *   batchId — 批次编号 (e.g., 1)
 *   tasks   — Task 列表，每项包含:
 *     taskId  — Task 编号 (e.g., "1")
 *     prompt  — Worker SubAgent 的完整 prompt（角色契约 + handoff 内容）
 *   merged  — (可选) 合并派发列表，每项包含:
 *     taskIds — 合并的 Task 编号数组 (e.g., ["2", "3"])
 *     prompt  — 合并后的 Worker SubAgent prompt
 *
 * 支持两种派发模式:
 *   1. 标准模式: 每个 Task 独立一个 agent()
 *   2. 合并模式: 同模块无共享依赖的 Task 合并为一个 agent()（CR-002-B 优化，≤3 Task）
 *
 * 返回:
 *   { batchId, tasks: [{ taskId, result }] }
 *   Orchestrator 根据返回结果逐 Task 执行质量门禁。
 */
export const meta = {
  name: "apply-batch-dev",
  description: "Apply 阶段 Batch 内 Worker 并行开发",
  phases: ["batch-dev"]
};

const agentCalls = [];

// 标准模式: 每个 Task 独立 agent
if (args.tasks && args.tasks.length > 0) {
  for (const task of args.tasks) {
    agentCalls.push({
      taskIds: [task.taskId],
      call: agent(`[WORKER] Task-${task.taskId} (${args.reqId} Batch-${args.batchId})`, {
        agentType: "worker",
        prompt: task.prompt,
        model: "sonnet"
      })
    });
  }
}

// 合并模式 (CR-002-B): 多个 Task 合入一个 agent
if (args.merged && args.merged.length > 0) {
  for (const group of args.merged) {
    const label = group.taskIds.join(',');
    agentCalls.push({
      taskIds: group.taskIds,
      call: agent(`[WORKER] Task-${label} (${args.reqId} Batch-${args.batchId})`, {
        agentType: "worker",
        prompt: group.prompt,
        model: "sonnet"
      })
    });
  }
}

// 并行执行所有 agent
const results = await parallel(agentCalls.map(c => c.call));

// 组装返回结果：将合并的 Task 展开为独立条目
const taskResults = [];
agentCalls.forEach((call, i) => {
  for (const taskId of call.taskIds) {
    taskResults.push({
      taskId,
      result: results[i]
    });
  }
});

return {
  batchId: args.batchId,
  tasks: taskResults
};
