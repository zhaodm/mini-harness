/**
 * propose-parallel.js — Propose 阶段 SA∥TE 并行设计
 *
 * 触发时机: PM 完成结构协商后，需要同时派发 SA 架构设计和 TE 测试用例设计。
 * 调用方: PM 主会话通过 Workflow 工具调用。
 *
 * args:
 *   reqId    — 需求编号 (e.g., "REQ003")
 *   saPrompt — SA SubAgent 的完整 prompt（角色契约 + handoff 内容）
 *   tePrompt — TE SubAgent 的完整 prompt（角色契约 + handoff 内容）
 *
 * 返回:
 *   { sa: { result }, te: { result } }
 *   PM 根据返回结果执行质量门禁。
 */
export const meta = {
  name: "propose-parallel",
  description: "Propose 阶段 SA∥TE 并行设计（架构 + 测试用例）",
  phases: ["sa-te-parallel"]
};

const [saResult, teResult] = await parallel([
  agent(`[SA] 架构设计 ${args.reqId}`, {
    prompt: args.saPrompt,
    model: "sonnet"
  }),
  agent(`[TE] 测试用例设计 ${args.reqId}`, {
    prompt: args.tePrompt,
    model: "sonnet"
  })
]);

return {
  sa: { result: saResult },
  te: { result: teResult }
};
