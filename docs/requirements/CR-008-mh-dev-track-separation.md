---
id: CR-008
title: "mh-dev 轨道分离 + 测试夹具隔离 + 需求归档"
status: designing
design_doc: docs/designs/CR-008-mh-dev-track-separation-design.md
created: "2026-08-10"
---

# CR-008: mh-dev 轨道分离 + 测试夹具隔离 + 需求归档

## 背景

mh-dev 工具存在三个缺陷，经核查均确认成立：

1. **开发轨与审计轨未分离** — 开发轨 Tester 验收 PASS 后，状态机自动推进到审计轨（`verify→audit`）。但两轨本应完全独立：开发轨是代码交付流程，审计轨是独立审计流程。当前 `check-transition.sh` 的 `verify:audit` 转移和 `release-candidate` 门禁强制 `semantic_audit==PASS`，把两个独立轨道焊死。

2. **测试夹具清空真实运行态** — `test-governance.sh` 第 3 行 `RUNTIME="$ROOT_DIR/tools/mh-dev/.mh-dev"` 指向真实运行态目录，第 4 行 `trap 'rm -rf "$RUNTIME"' EXIT` 在套件退出时删除该真实目录。Tester 跑 `run-all-tests.sh` 会调起此套件，导致治理状态丢失。

3. **需求与设计文档未版本控制归档** — mh-dev 把需求文档和验收标准全塞在临时 `.mh-dev/` 目录（被 gitignore），没有像 psdt-dev 那样将 CR 需求单归档到 `docs/requirements/`、设计文档归档到 `docs/designs/`。

## 共享根因

问题2和问题3共享同一架构根因：**`.mh-dev/` 目录职责混淆**——它同时承载运行态（state.json、snapshots、evidence，临时、会话级、gitignore）和持久交付物（requirement.md、acceptance-criteria.md，本应版本控制、跨会话留存）。

- 问题2的路径：trap 删整个 `.mh-dev/` → 运行态丢失
- 问题3的路径：需求文档在 `.mh-dev/` → 被 gitignore → 非持久交付物

两者各自是对方的部分缓解但非根治。必须都修才能彻底解决职责混淆。

## 需求

### R1: 轨道分离

- R1.1: 开发轨 verify PASS 后转移到 done 终态，不可转移到 audit
- R1.2: done 门禁仅要求 test_verdict==PASS（用户确认提交由铁律覆盖，不是状态节点）
- R1.3: 审计轨由 `/mh-dev audit` 独立参数触发，不走开发轨状态机
- R1.4: 审计轨不再触发 repair 循环，不修改开发轨 state.json 的 phase
- R1.5: 审计轨前置仍要求 test-verdict.json 存在且 PASS

### R2: 测试夹具隔离

- R2.1: 治理脚本支持 MH_DEV_RUNTIME 环境变量覆盖运行态路径，不设变量时回退硬编码路径
- R2.2: test-governance.sh 使用临时目录作为测试夹具，trap 只清理临时目录
- R2.3: test-governance.sh 中途异常退出时不删除真实 .mh-dev/ 目录
- R2.4: run-all-tests.sh 调用 test-governance.sh 后真实 .mh-dev/ 治理状态不丢失

### R3: 需求与设计文档归档

- R3.1: 需求单归档到 docs/requirements/CR-xxx-<slug>.md 作为版本控制交付物
- R3.2: 设计文档归档到 docs/designs/CR-xxx-<slug>-design.md 作为版本控制交付物
- R3.3: .mh-dev/requirement.md 退化为基于需求单精简的 Developer 可执行运行态文件
- R3.4: 旧需求单 docs/requirements/CR-001~CR-007 格式不被破坏

### R4: 附带修复

- R4.1: testcase_adding_required 检查从 propose 阶段移到 verify 阶段（pre-existing 缺陷：propose 阶段无测试文件变更，检查必定 FAIL）
- R4.2: release-candidate.sh manifest 不再硬编码 semantic_audit==PASS

## 非目标

- 不重构开发轨内部阶段（intake/propose/develop/verify 保持不变）
- 不删除审计轨本身（Auditor 角色和审计方法论保留，改为独立入口触发）
- 不改动 /mh-run 外部项目流程
- 不为审计轨新建独立状态机（审计轨无状态、纯咨询）
- 不迁移旧需求单格式

## 风险与回滚

| 风险 | 回滚方案 |
|------|----------|
| 状态机转移规则变更可能遗漏消费者 | `git checkout` 相关脚本 |
| 环境变量覆盖需保证生产路径行为不变 | 还原变量赋值行 |
| 归档层引入需保证旧需求单格式兼容 | 恢复 .mh-dev 作为需求文档唯一存放点 |
