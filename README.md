# parallel-agents

**多个 AI 同时写一个项目，还不打架。**

> 一套与工具无关的并行 AI 开发方法：主控定契约、排波次、管合并；执行 AI 各占一个 git worktree 与独占文件边界并行推进。
>
> **EN** — An agent-agnostic playbook for running multiple AI coding agents on one project concurrently: freeze the contract first, schedule by dependency waves, isolate each agent in its own git worktree, and merge only through a gate. Works with Claude Code, Cursor, Trae, Codex, OpenCode, Antigravity — anything that can read files and run git.

---

## 问题

你有 3 个 AI 窗口，想同时推进一个项目。实际发生的是：

| 你以为 | 实际 |
|---|---|
| 三倍速度 | 主控在解冲突，变成人肉串行器 |
| 各写各的 | 两个 agent 改了同一个文件 |
| 前后端并行 | 前端写 `userId`，后端写 `user_id`，联调才发现 |
| 都装依赖 | 抢端口、依赖漂移、锁文件互相覆盖 |
| 都说"做完了" | 没人能跑出一条验证命令 |

**并行开发不是"多开几个窗口"，是一套边界与契约工程。**

---

## 四个核心机制

### 1. 契约先行 — 消除最大一类返工

开分支前冻结三样，落 `docs/contracts/`：

- **接口契约**：端点、方法、请求/响应 schema、错误码
- **数据模型**：表 / 字段名 / 类型 / 可空性 / 索引
- **共享类型**：前端 TS 类型、后端 DTO

并行开发的返工，绝大多数来自「两个 agent 对同一个字段名理解不同」。契约冻结把这类返工从**合并时发现**提前到**开工前消除**。

> 这是全文唯一一个「花时间反而省时间」的环节。

### 2. 波次编排 — 真正的提速点

按依赖分波，波内并行、波间串行：

```
波次 1（无依赖，全并行）  数据模型 / 路由骨架 / 设计令牌 / 部署编排
波次 2（依赖波 1 契约）   后端接口 / 前端页面 / 数据导入
波次 3（依赖波 2）        集成联调 / 端到端验收
```

依赖判定标准只有一条：**A 的产出是否出现在 B 的输入里**（接口形状、字段名、类型定义）。

只是「逻辑上相关」不算依赖。这条能砍掉大量假依赖——很多人把相关的都串起来，白白浪费并行窗口。

### 3. 文件边界 — 合并零冲突

一个任务 = 一个分支 = 一个 worktree = 一条独占文件清单。

```bash
git worktree add ../wk-taskA -b feature/taskA main
```

共享文件（锁文件、共享类型、迁移目录、主文档、compose）**冻结**，只由主控维护。

### 4. 合并闸门 — 红了就不算完成

体检 → `merge --no-ff` → 构建 → 接口实测 → 回归 → 清理。任一步红就退回。

验收标准必须能跑出结果：

```
✅  curl -s "localhost:3000/api/items?page=abc" | jq -r .code   →  "INVALID_QUERY"
❌  功能正常
```

`scripts/gate.sh` 把这一串固化成一条命令。

---

## 为什么不直接上 14 个 agent

有个流行的做法是搞一套完整 SDLC 编制：PM / PO / 研究 / 分析 / 架构 / 设计 / 前端 / 后端 / DevOps / 文档 / 测试 / 安全 / 批判 / 合并，14 个角色全程在线。

听起来很完整，实际会**变慢**：

- 每个角色交接点都在丢上下文，13 次交接 = 13 次信息衰减
- 串行阶段排满，并行窗口被切成碎片
- 角色越多，主控的调度成本越高

`parallel-agents` 的取舍是：**角色按项目规模伸缩**。

| 档位 | 编制 | 适用 |
|---|---|---|
| **L1** 默认 | 主控 + 执行 ×2~3 | 功能模块、页面、数据层 |
| **L2** | + 架构（只在契约阶段）+ 验收（只在收口阶段） | 新项目从 0 起、跨端 |
| **L3** | + 安全审查 + 文档 | 对外发布、涉钱涉权限 |

关键设计：**架构和验收都只出现一次就退场**，不参与日常。加角色是成本，不是能力。

---

## 快速开始

```bash
# 1. 拿到 skill
git clone https://github.com/<you>/parallel-agents.git

# 2. 在你的项目里建契约目录，照 templates/contract.md 写契约
mkdir -p docs/contracts
# → 写完 commit 到 main，之后任何分支不得改

# 3. 建任务：worktree + 分支 + 任务书
./parallel-agents/scripts/new-task.sh 01 data src/db/** migrations/**

# 4. 把任务书贴给一个执行 AI 窗口

# 5. 收口
./parallel-agents/scripts/gate.sh feature/data
```

---

## 安装为 Skill

**WorkBuddy / Claude Code（用户级）**

```bash
cp -r parallel-agents ~/.workbuddy-ai/skills/parallel-agents
# 或 Claude Code: ~/.claude/skills/parallel-agents
```

**项目级（团队共享，跟着仓库走）**

```bash
mkdir -p .agent/skills && cp -r parallel-agents .agent/skills/
```

**或者什么都不装** —— 直接把 `docs/methodology.md` 丢给 AI 读，它一样能照做。

这是刻意的设计：**不依赖任何平台特性、不需要 MCP server、不需要斜杠命令**。

---

## 目录结构

```
parallel-agents/
├── SKILL.md                      # 可安装的 skill（触发后按此执行）
├── docs/
│   └── methodology.md            # 完整方法论长文
├── templates/
│   ├── contract.md               # 契约模板
│   └── task-book.example.md      # 任务书示例（已填好）
├── scripts/
│   ├── new-task.sh               # 建 worktree + 生成任务书
│   └── gate.sh                   # 合并闸门
└── LICENSE
```

---

## 真提速 vs 假提速

| 看起来提速 | 实际 |
|---|---|
| 多加几个执行窗口 | ❌ 超过 5~6 个，主控合并成本吃掉全部收益 |
| 跳过契约直接开写 | ❌ 返工成本 = 省下时间的 3~5 倍 |
| 一次全开，看起来最并行 | ❌ 冲突排队，实际比串行还慢 |
| 让 AI 自己装依赖 | ❌ 抢端口 / 依赖漂移，调试时间远超装依赖时间 |
| **先定契约再开分支** | ✅ 消除最大一类返工 |
| **正确分波次，波 1 塞满** | ✅ 唯一能全速跑的窗口不浪费 |
| **依赖主控预装** | ✅ 每个 agent 省 2~3 分钟，且不冲突 |
| **任务书自包含 + 带契约 sha** | ✅ agent 不用探索代码库、不用提问 |
| **闸门脚本化** | ✅ 每次收口 15 分钟 → 40 秒 |

---

## 适用 / 不适用

**适用**：项目级建设，能拆成若干**文件不重叠、可独立验收**的模块。

**不适用**：

- 小改动（一个 bug、一个函数）—— 直接单窗口
- 任务数 < 3 —— 协调开销吃掉收益
- 任务之间共享大量文件 —— 先重构边界
- 需求还没定清楚 —— 先写文档再开分支

判断口诀：**文件清单能不能互不相交？任务数够不够 3 个？**

---

## License

MIT
