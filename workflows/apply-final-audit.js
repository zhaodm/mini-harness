/**
 * apply-final-audit.js — Apply 阶段 TE 最终全量审计
 *
 * 触发时机: SR2 功能评审通过后，派发 TE 做最终全量审计（E2E + 回归 + 工程验证）。
 * 调用方: PM 主会话通过 Workflow 工具调用。
 *
 * args:
 *   reqId  — 需求编号 (e.g., "REQ003")
 *   prompt — TE SubAgent 的完整 prompt（角色契约 + 最终审计 handoff）
 *
 * 返回:
 *   { result, passed }
 *   PM 根据 passed 判断进入 SR3 或修复循环。
 */
export const meta = {
  name: "apply-final-audit",
  description: "Apply 阶段 TE 最终全量审计",
  phases: ["final-audit"]
};

const result = await agent(`[TE] 最终审计 ${args.reqId}`, {
  prompt: args.prompt,
  model: "sonnet"
});

// 判断审计结论：优先看明确结论，兜底检查 FAIL 关键字
let passed = true;
if (result.includes("结论: FAIL") || result.includes("conclusion: FAIL")) {
  passed = false;
} else if (result.includes("结论: PASS") || result.includes("conclusion: PASS")) {
  passed = true;
} else {
  passed = !result.includes("FAIL");
}

return { result, passed };
