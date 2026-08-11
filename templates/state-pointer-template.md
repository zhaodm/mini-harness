---
req_id:
---

# 全局状态指针

本文件仅记录当前活跃的 REQ-ID。各需求的详细状态存放在 `deliverables/{REQ-ID}/.engine/.state.md` 中。

Orchestrator 恢复时：读取此文件获取 req_id → 读取 `deliverables/{req_id}/.engine/.state.md` 获取详细状态。
