# CR-012 设计: role-guard mh-dev 分支路径归一化

## 方案选型

### 候选 A: bash 层归一化 + index() 精确匹配（采用）

在 mh-dev 分支内、`jq index()` 之前，用 bash 剥离仓库根前缀，把绝对路径转为相对路径，再与 `approved_scope` 精确匹配。

```bash
ROOT="$(pwd)"
if [[ "$FILE_PATH" == "$ROOT"/* ]]; then
  NORM_PATH="${FILE_PATH#$ROOT/}"
else
  NORM_PATH="$FILE_PATH"
fi
# 后续 index() 和 case 用 NORM_PATH
```

### 候选 B: jq 层 endswith 后缀匹配（否决）

不改 bash 层，在 jq 里用 `any(.approved_scope[]; $path | endswith("/" + .))`。

否决理由：仓库外路径 `/tmp/scripts/role-guard.sh` 会对 `scripts/role-guard.sh` 产生后缀匹配——虽然加 `"/"` 前缀缓解了基本前缀伪造，但无法排除仓库外同后缀路径。精确匹配更安全。

### 候选 C: 改 approved_scope 存绝对路径（否决）

与 validate-changes.sh 的归一化逻辑冲突（它假设 scope 是相对路径，比较时转绝对）。破坏现有约定。

## 采用方案 A 的设计依据

### 1. 与 validate-changes.sh 口径对齐

`validate-changes.sh:30` 已有归一化：
```python
abs_scope = set(os.path.join(root, p) if not os.path.isabs(p) else p for p in scope)
```
它把 scope 转绝对、用绝对比较。role-guard 反向对齐：把 FILE_PATH 转相对、用相对比较。两者等价，取实现更简洁者。bash 层剥离前缀比 jq 层操纵 scope 数组更直接。

### 2. 仓库根定位：pwd

role-guard.sh 被 PreToolUse hook 调用，`command: "bash scripts/role-guard.sh"`，cwd = 项目根。脚本内 `MH_DEV_STATE="${MH_DEV_RUNTIME:-tools/mh-dev/.mh-dev}/state.json"` 已依赖同一 cwd 假设（用相对路径定位 state）。归一化复用 `pwd`，不引入新假设。

不选 `git rev-parse --show-toplevel` 的理由：role-guard 现有代码不依赖 git 子进程；每次 Write/Edit 都 fork git（0.019s/次）增加开销；若 git 不可用需 fallback，引入复杂度。`pwd` 与现有 MH_DEV_STATE 的假设同源，一致性好。

### 3. 归一化须早于 sensitive 检查

当前第 36-41 行：
```bash
if jq -e --arg path "$FILE_PATH" '.approved_scope | index($path) != null' ...; then
  case "$FILE_PATH" in
    CLAUDE.md|.claude/settings.json|scripts/role-guard.sh|templates/state-template.md)
      [[ "$MH_TRACK" == "formal" ]] || { echo "BLOCKED: ..."; exit 2; }
      ;;
  esac
  exit 0
fi
```

`case` 也用 `$FILE_PATH`。若只归一化 index() 而不归一化 case，绝对路径进不了 case 分支 → sensitive 治理关键路径在非 formal 轨道下会被误放行（绕过 formal 门禁）。**归一化后的 `NORM_PATH` 须同时用于 index() 和 case。**

## 精确改动点

`scripts/role-guard.sh` 第 31-47 行 mh-dev 分支。在第 36 行 `if jq ...` 之前插入归一化，后续 `--arg path` 传 `NORM_PATH` 而非 `FILE_PATH`，`case` 也用 `NORM_PATH`。

```diff
 if [[ -z "$STATE_FILE" && -f "$MH_DEV_STATE" ]] && jq -e '...' "$MH_DEV_STATE" >/dev/null 2>&1; then
+  # 路径归一化：绝对路径剥离仓库根前缀，转为相对路径再与 approved_scope 精确匹配。
+  # 与 validate-changes.sh 的归一化口径对齐（见该脚本第 30 行注释）。
+  ROOT="$(pwd)"
+  if [[ "$FILE_PATH" == "$ROOT"/* ]]; then
+    NORM_PATH="${FILE_PATH#$ROOT/}"
+  else
+    NORM_PATH="$FILE_PATH"
+  fi
   [[ "$FILE_PATH" =~ tools/mh-dev/\.mh-dev/ ]] && exit 0

-  MH_TRACK=$(jq -r '.track // empty' "$MH_DEV_STATE")
-  if jq -e --arg path "$FILE_PATH" '.approved_scope | index($path) != null' "$MH_DEV_STATE" >/dev/null 2>&1; then
-    case "$FILE_PATH" in
+  MH_TRACK=$(jq -r '.track // empty' "$MH_DEV_STATE")
+  if jq -e --arg path "$NORM_PATH" '.approved_scope | index($path) != null' "$MH_DEV_STATE" >/dev/null 2>&1; then
+    case "$NORM_PATH" in
       CLAUDE.md|.claude/settings.json|scripts/role-guard.sh|templates/state-template.md)
         [[ "$MH_TRACK" == "formal" ]] || { echo "BLOCKED: ..."; exit 2; }
         ;;
     esac
     exit 0
   fi
-  echo "BLOCKED: mh-dev 未批准写入路径 $FILE_PATH"
+  echo "BLOCKED: mh-dev 未批准写入路径 $NORM_PATH"
   exit 2
 fi
```

注：第 33 行 `[[ "$FILE_PATH" =~ tools/mh-dev/\.mh-dev/ ]]` 是正则子串匹配，绝对路径能命中，无需归一化——保持用 `FILE_PATH`。

## 安全分析

| 路径形态 | 归一化后 | index() | case sensitive | 结果 |
|---|---|---|---|---|
| 绝对路径在 scope 内 | 相对路径 | MATCH | 命中 formal 检查 | 放行/按 track 判定 |
| 绝对路径越权 | 相对路径 | NO MATCH | 不进入 | 拦截 |
| 绝对路径仓库外（/tmp/...） | 不剥离（无 ROOT 前缀）| NO MATCH | 不进入 | 拦截 |
| 相对路径在 scope 内 | 原样 | MATCH | 命中 | 放行 |
| 含 `..` 的绝对路径 | — | — | — | 第 20 行先行拦截 |
| 前缀伪造（.evil 后缀）| 相对路径含 .evil | 精确 NO MATCH | 不进入 | 拦截 |

## 不改动项

- 第 20 行 `..` 穿越检测（用原始 FILE_PATH，正确）
- 第 33 行运行态文件放行（正则子串，绝对路径能命中）
- 第 61-93 行 deliverables 分支 check_permission（正则子串，无需改动）
