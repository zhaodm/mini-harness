# 添加新 Skill

> 场景: 需要为 Mini-Harness 新增一个执行阶段或独立操作 SOP 时。

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `skills/mh-<name>/SKILL.md` | 新建 | Skill 定义文件 |
| `.claude/commands/mh-<name>.md` | 修改 | 在命令面注册新 Skill |
| `scripts/check-harness.sh` | 修改 | 在目录检查数组中新增 `skills/mh-<name>` |
| `docs/designs/source-of-truth.md` | 修改 | 在映射表中新增条目 |
| `agents/*.md` | 修改 | 如涉及新角色则更新契约 |

## 前置条件

- 已确认该 Skill 不属于现有 9 个 Skill 的职责范围
- 已确认 track 归属（共享/code/ppt）
- 已获得用户审批

## 步骤

<!-- 待后续 CR 填充具体操作步骤 -->

1. 创建 `skills/mh-<name>/SKILL.md` — 参考: `skills/mh-intake/SKILL.md`

2. 注册到 `.claude/commands/mh-<name>.md`

3. ⚠️ 同步更新 `scripts/check-harness.sh`（容易遗漏）

4. ⚠️ 同步更新 `docs/designs/source-of-truth.md`（容易遗漏）

## 验证

```bash
bash scripts/check-harness.sh
```
