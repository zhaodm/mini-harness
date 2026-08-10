/**
 * thinker-design.js — Propose 阶段 Thinker 相位串行执行
 *
 * 原 propose-parallel.js（SA∥TE 并行），重构后为 Thinker 相位执行。
 * 自验证消除后，Verifier 不再在 propose 阶段介入——验收标准由 Thinker 产出。
 *
 * 触发时机: Orchestrator 完成结构协商后，派发 Thinker 执行 needs/design/visual 相位。
 * 调用方: Orchestrator 主会话通过 Workflow 工具调用。
 *
 * args:
 *   reqId    — 需求编号 (e.g., "REQ003")
 *   phase    — Thinker 相位: "needs" | "design" | "visual"
 *   prompt   — Thinker SubAgent 的完整 prompt（角色契约 + handoff 内容）
 *
 * 返回:
 *   { result }
 *   Orchestrator 根据返回结果执行质量门禁。
 */
export const meta = {
  name: "thinker-design",
  description: "Propose 阶段 Thinker 相位执行（needs/design/visual）",
  phases: ["thinker-needs", "thinker-design", "thinker-visual"]
};

const result = await agent(`[THINKER] ${args.phase || 'design'} ${args.reqId}`, {
  prompt: args.prompt,
  model: "sonnet"
});

return {
  result
};
