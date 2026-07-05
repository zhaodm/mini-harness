# {域名}

> 本域指南描述 {模块/组件} 的内部机制。修改本域代码前请先阅读。
> 对应源码: {source_paths}

## 职责与边界

**做什么：**
- {responsibility 1}
- {responsibility 2}

**不做什么（由其他域负责）：**
- {boundary 1} → 见 {other_domain}.md

## 内部结构

```
{子模块关系图，ASCII}
{module_a} → {module_b} → {module_c}
```

| 子模块 | 职责 | 文件 |
|--------|------|------|
| {sub} | {desc} | {path} |

## 核心数据结构

{关键类型/Schema，字段级描述}

```
{TypeName} {
  field1: type  // 语义说明
  field2: type  // 约束条件
}
```

## 关键流程

### 正常路径

```
{伪代码级流程描述}
1. {step}
2. {step}
3. {step}
```

### 异常路径

- {error_case}: {handling}

## 对外接口

| 接口 | 签名/路径 | 输入 | 输出 | 副作用 |
|------|----------|------|------|--------|
| {name} | {signature} | {input} | {output} | {side_effect} |

## 文件清单与影响范围

| 文件 | 职责 | 改动时需同步检查 |
|------|------|----------------|
| {path} | {desc} | {related_files} |

## 约束与陷阱

**不变量（必须始终满足）：**
- [ ] {invariant}

**常见误区：**
- ⚠️ {pitfall}: {why and how to avoid}
