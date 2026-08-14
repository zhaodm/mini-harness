---
project:
---

# 全局状态指针

本文件仅记录当前活跃交付物的**项目标识符**。各交付物的详细状态存放在 `deliverables/{project}/.engine/.state.md` 中。

Orchestrator 恢复时：读取此文件获取 project → 读取 `deliverables/{project}/.engine/.state.md` 获取详细状态。

`role-guard.sh` 亦以本文件定位活跃交付物（CR-018 R7）：`deliverables/` 下多项目并存是常态形态，
守卫不得以文件系统扫描首个命中项替代本指针。指针缺失或 `project` 为空时守卫放行（无活跃交付物）；
`project` 非法（不满足 `^[a-z][a-z0-9-]{0,63}$`，见 `scripts/validate-slug.sh`）时守卫 `exit 2`——
合法流程不会写入非法标识符，出现即状态被污染。
