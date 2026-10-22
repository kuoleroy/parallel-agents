# parallel-agents

**多个 AI 同时写一个项目，还不打架。**

> English: [README.md](README.md)

<p align="center">
  <a href="https://github.com/kuoleroy/parallel-agents/actions/workflows/ci.yml"><img src="https://github.com/kuoleroy/parallel-agents/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/kuoleroy/parallel-agents/releases/tag/v0.2.0"><img src="https://img.shields.io/badge/release-v0.2.0-blue" alt="release v0.2.0"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
  <a href="https://agentskills.io"><img src="https://img.shields.io/badge/Agent_Skills-compatible-lightgrey" alt="Agent Skills standard"></a>
</p>

**[已验证：注入 8 次违规 → 拦下 8 次 · 合规分支 `OK 11 · SKIP 0 · FAIL 0`](docs/evidence.md)**

> 一套与工具无关的并行 AI 开发方法：主控定契约、排波次、管合并；执行 AI 各占一个 git worktree 与一条**机器校验**的独占文件边界并行推进。遵循 [Agent Skills](https://agentskills.io) 开放规范——不依赖任何平台特性、不需要 MCP server、不需要斜杠命令。

---

## 你以为 vs 实际

你有 3 个 AI 窗口，想同时推进一个项目。实际发生的是：

| 你以为 | 实际 |
|---|---|
| 三倍速度 | 主控在解冲突，变成人肉串行器 |
| 各写各的 | 两个 agent 改了同一个文件，一个静默覆盖另一个 |
| 前后端并行 | 前端写 `userId`，后端写 `user_id`，联调才发现 |
| 都装依赖 | 抢端口、依赖漂移、锁文件互相覆盖 |
| 都说"做完了" | 没人能跑出一条验证命令 |

**并行开发不是"多开几个窗口"，是一套边界与契约工程。**

## 机制是被测过的，不是被宣称的

[`tests/run-test.sh`](tests/run-test.sh) 会自建一个一次性仓库，用真脚本建真任务、开真 worktree，然后**故意注入这套方法声称能拦住的那些错误**：

```
违规注入 8 次 → 拦下 8 次；正向断言 9 项。
```

**不调用任何 AI，不联网，不花 token**，本机几秒跑完。

最有价值的一条不是合并冲突。契约写了「非法分页必须返回 400」，agent 实现成静默回落到第 1 页。边界干净、构建干净、git 什么都不报：

```
-- 边界检查（独占清单之外必须零改动）
  OK    零越界 · 零侵入 · 零动冻结

-- 构建
  OK    构建通过

-- 接口实测
  OK    服务已启动 (pid 2228, port 28263)
  OK    健康检查 http://127.0.0.1:28263/api/health
  FAIL  边界用例期望 4xx，实际 200
```

越界改动会被点名到归属者：

```
      src/api/search.js (属于 02 search @ feature/search)
  FAIL  侵入了其他在跑任务的边界，两边会互相覆盖
```

完整实录与局限见 [docs/evidence.md](docs/evidence.md)。

## 四个核心机制

**1. 契约先行。** 开分支前冻结三样并 commit 到基线分支，落 `docs/contracts/`：接口（端点、方法、请求/响应 schema、错误码）、数据模型（表、字段名、类型、可空性、索引）、共享类型（前端 TS 类型与后端 DTO 同处一文件）。冻结后任何分支不得改，只有主控能改，且改完必须广播并在每个在跑的 worktree 里 `git merge <基线>`。

并行开发的返工，绝大多数来自「两个 agent 对同一个字段名理解不同」。契约冻结把这类返工从**合并时发现**提前到**开工前消除**。

**2. 波次编排。** 波内并行、波间串行：

```
波次 1（无依赖，全并行）  数据模型 / 路由骨架 / 设计令牌 / 部署编排
波次 2（依赖波 1 契约）   后端接口 / 前端页面 / 数据导入
波次 3（依赖波 2）        集成联调 / 端到端验收
```

依赖判定只有一条：**A 的产出是否出现在 B 的输入里**（接口形状、字段名、类型定义）。答案是否，就该同波。只是「逻辑上相关」不算依赖——把相关的都串起来，是白扔并行窗口。

**3. 机器校验的文件边界。** 一个任务 = 一个分支 = 一个 worktree = 一条独占文件清单，登记在 `docs/tasks/ownership.md`。`new-task.sh` 在清单与在跑任务重叠、或写进冻结文件时**直接拒绝建任务**，并按任务号给每个任务分配独立端口，执行方抢不了端口。`gate.sh` 再拿这条记录逐个文件核对。

**4. 合并闸门。** `gate.sh <分支>` 在**合并之前**跑，任一步红就不许落地：前置 → 未提交/残留 → 边界 → 任务书「不要动」→ 构建 → 真实 HTTP 实测 → 测试。验收标准必须是命令加期望输出：

```
✅  curl -s "localhost:3102/api/items?page=abc" → 400 {"code":"INVALID_QUERY"}
❌  功能正常
```

没配置的步骤报 `SKIP`，绝不冒充通过；CI 里设 `REQUIRE_FULL=1` 让任何 `SKIP` 直接算失败。

## 为什么不直接上 14 个 agent

有个流行的做法是搞一套完整 SDLC 编制：PM / PO / 研究 / 分析 / 架构 / 设计 / 前端 / 后端 / DevOps / 文档 / 测试 / 批判 / 安全 / 合并，14 个角色全程在线。

听起来很完整，实际会**变慢**：每个角色交接点都在丢上下文，13 次交接 = 13 次信息衰减；串行阶段排满，并行窗口被切成碎片；角色越多，主控的调度成本越高。

`parallel-agents` 的取舍是**角色按项目规模伸缩**：

| 档位 | 编制 | 适用 |
|---|---|---|
| **L1** 默认 | 主控 + 执行 ×2~3 | 功能模块、页面、数据层 |
| **L2** | + 架构（只在契约阶段）+ 验收（只在收口阶段） | 新项目从 0 起、跨端 |
| **L3** | + 安全审查 + 文档 | 对外发布、涉钱涉权限 |

架构和验收都只出现一次就退场，不参与日常。**加角色是成本，不是能力。**

## 快速开始

```bash
git clone https://github.com/kuoleroy/parallel-agents.git
# 国内镜像: git clone https://gitee.com/kuoleroy/parallel-agents.git

# 1. 在你的项目里冻结契约
mkdir -p docs/contracts     # 照 templates/contract.md 写完，commit 到基线分支

# 2. 建任务：worktree + 分支 + 任务书 + 归属表 + 独立端口
./parallel-agents/scripts/new-task.sh 01 data src/db migrations
./parallel-agents/scripts/new-task.sh 02 search src/api/search.ts

# 3. 主控预装依赖，然后把每份任务书交给各自的 AI 窗口

# 4. 每个分支收口前跑闸门
./parallel-agents/scripts/gate.sh feature/search
```

按你的技术栈用环境变量配闸门：`BUILD_CMD` / `TEST_CMD` / `SERVE_CMD` / `BASE_BRANCH` / `BASE_PORT` / `REQUIRE_FULL`。

## 安装为 Skill

仓库根目录**就是** skill 目录，`SKILL.md` 的 `name` 与目录名一致，符合规范，所以任何读 Agent Skills 的工具都能直接装：

| Agent | 路径 |
|---|---|
| Claude Code | `cp -r parallel-agents ~/.claude/skills/parallel-agents`（项目级：`.claude/skills/`） |
| Cursor | `.cursor/skills/parallel-agents` 或 `.agents/skills/parallel-agents` |
| Codex / Gemini CLI / Copilot 等 | 复制进该 agent 的 skills 目录 |
| 只读规则文件的 agent | 把 [`AGENTS.md`](AGENTS.md) 拷进你的项目 |
| 什么都不装 | 直接把 [`docs/methodology.md`](docs/methodology.md) 丢给 AI 读，它一样能照做 |

刻意**不依赖平台特性、不需要 MCP server、不需要斜杠命令**。Claude Code / Codex 的 plugin 清单暂时没加——作者没在真实安装环境验证过，不愿写未经核实的安装方式；带验证的 PR 欢迎。

## 适用 / 不适用

**适用**：项目级建设，能拆成若干**文件不重叠、可独立验收**的模块。

**不适用**：

- 小改动（一个 bug、一个函数）—— 直接单窗口
- 任务数 < 3 —— 协调开销吃掉收益
- 任务之间共享大量文件 —— 先重构边界
- 需求还没定清楚 —— 先写文档再开分支

判断口诀：**文件清单能不能互不相交？任务数够不够 3 个？**

## 局限（请连同结论一起读）

- 测试验证的是**机制**，不是一次真实多 agent 协作的成果。这里**没有**「返工从 X 降到 Y」的数字，本 README 也不宣称有。
- 边界重叠判定是启发式：认得精确路径、裸目录、`dir/**`、`dir/*`、单层 `*.ts`；不认得取反与花括号展开。所以清单宁可窄不可宽。
- 脚本是 bash（Windows 走 Git Bash），没有 PowerShell 版本。
- 脚本输出与生成的任务书目前是中文，文档已中英双语。要本地化输出得同时改 `gate.sh` 的任务书解析和全部模板，不做半吊子。
- 闸门实测走 HTTP，没有 HTTP 层的技术栈配 `BUILD_CMD` / `TEST_CMD`，然后如实读那个 `SKIP`。

## 安全说明

只从 GitHub 的 `kuoleroy/parallel-agents` 或 Gitee 的 `kuoleroy/parallel-agents` 安装。本仓库只有 markdown 与 shell 脚本，**不发任何二进制**；脚本不联网，`tests/` 只在本机临时目录里绑端口。

## License

MIT。
