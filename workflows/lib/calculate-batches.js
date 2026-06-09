/**
 * calculate-batches.js — 批次计算引擎
 *
 * 对任务列表进行拓扑排序，按依赖层级分批，同层贪心合并。
 *
 * @module workflows/lib/calculate-batches
 */

/**
 * @typedef {Object} Task
 * @property {string} id - 任务编号
 * @property {string[]} deps - 依赖的任务 ID 列表
 */

/**
 * @typedef {Object} CalculateBatchesInput
 * @property {Task[]} tasks - 任务列表
 * @property {number} mergeThreshold - 合并阈值（同一 agent 最多处理的任务数）
 */

/**
 * @typedef {Object} BatchResult
 * @property {number} batchId - 批次编号（从 1 开始）
 * @property {{taskId: string}[]} standard - 独立执行的任务
 * @property {{taskIds: string[]}[]} merged - 合并执行的任务组
 */

/**
 * @typedef {Object} CalculateBatchesResult
 * @property {BatchResult[]} [batches] - 批次列表
 * @property {string} [error] - 错误信息（如循环依赖）
 */

/**
 * 计算任务批次
 *
 * 算法:
 * 1. 拓扑排序（Kahn's algorithm）检测循环
 * 2. 按拓扑层级分层（同层任务无互相依赖，可并行）
 * 3. 同层内贪心合并（≤threshold 个任务合为一组）
 *
 * @param {CalculateBatchesInput} input
 * @returns {CalculateBatchesResult}
 */
export function calculateBatches(input) {
  const { tasks, mergeThreshold } = input;

  if (!tasks || tasks.length === 0) {
    return { batches: [] };
  }

  // 构建邻接表和入度表
  const taskMap = new Map(); // id → task
  const inDegree = new Map(); // id → number
  const dependents = new Map(); // id → [ids that depend on it]

  for (const task of tasks) {
    taskMap.set(task.id, task);
    inDegree.set(task.id, 0);
    dependents.set(task.id, []);
  }

  // 计算入度（仅计算存在于 tasks 列表中的依赖）
  for (const task of tasks) {
    for (const dep of task.deps) {
      if (taskMap.has(dep)) {
        inDegree.set(task.id, inDegree.get(task.id) + 1);
        dependents.get(dep).push(task.id);
      }
    }
  }

  // Kahn's algorithm — 按层级分批
  const layers = [];
  let queue = [];

  // 初始化: 入度为 0 的节点
  for (const [id, degree] of inDegree) {
    if (degree === 0) {
      queue.push(id);
    }
  }

  let processed = 0;

  while (queue.length > 0) {
    layers.push([...queue]);
    processed += queue.length;

    const nextQueue = [];
    for (const id of queue) {
      for (const dependent of dependents.get(id)) {
        const newDegree = inDegree.get(dependent) - 1;
        inDegree.set(dependent, newDegree);
        if (newDegree === 0) {
          nextQueue.push(dependent);
        }
      }
    }
    queue = nextQueue;
  }

  // 循环检测
  if (processed < tasks.length) {
    return { error: '检测到循环依赖，无法排序', batches: [] };
  }

  // 将层级转换为批次，应用合并策略
  const batches = layers.map((layer, index) => {
    const batch = {
      batchId: index + 1,
      standard: [],
      merged: []
    };

    if (layer.length === 1) {
      // 单任务不合并
      batch.standard.push({ taskId: layer[0] });
    } else if (layer.length <= mergeThreshold) {
      // 整层可合并为一组
      batch.merged.push({ taskIds: [...layer] });
    } else {
      // 超过阈值：按 threshold 分组合并，剩余放 standard
      let i = 0;
      while (i < layer.length) {
        const remaining = layer.length - i;
        if (remaining <= mergeThreshold) {
          // 剩余部分可以作为一组合并
          if (remaining > 1) {
            batch.merged.push({ taskIds: layer.slice(i, i + remaining) });
          } else {
            batch.standard.push({ taskId: layer[i] });
          }
          i += remaining;
        } else {
          // 取 threshold 个合并
          batch.merged.push({ taskIds: layer.slice(i, i + mergeThreshold) });
          i += mergeThreshold;
        }
      }
    }

    return batch;
  });

  return { batches };
}
