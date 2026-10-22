# Changelog

遵循 [Keep a Changelog](https://keepachangelog.com/) 与语义化版本。

## 0.2.0 — 2026-10-22

把「边界工程」从文档主张变成机器校验。此前整套方法的立身承诺（独占文件边界）没有任何代码在守，闸门还宣称自动化了它没做的步骤。

### Added

- `scripts/parallel-lib.sh`：归属表查询、基线分支探测、通配作用域匹配与重叠判定，两个脚本共用。
- **边界检查**（`gate.sh`）：逐个改动文件核对是否落在自己的独占清单内、是否碰冻结文件、是否侵入其他在跑任务的边界。越界 / 侵入 / 冻结三类违规分别报错并点名归属者。
- **归属表** `docs/tasks/ownership.md`：`new-task.sh` 自动登记「任务 / 分支 / worktree / 波次 / 端口 / 独占文件 / 状态」，`gate.sh` 以此为事实源。
- **冻结清单** `docs/tasks/frozen.patterns`：首次运行自动生成默认项，可按项目改。
- **端口分配**：按任务号从 `BASE_PORT`（默认 3100）分配，每个任务独占一个端口，执行方抢不了。
- **建任务时拒绝冲突**：独占清单与在跑任务重叠、或写进冻结文件时直接退出，不留 worktree 与任务书残渣。
- `gate.sh` 现在能**自己起服务**（`SERVE_CMD` + 分配端口），探完自动收；解决了"禁止执行方起服务，但实测需要服务"的死角。
- `REQUIRE_FULL=1`：任何 `SKIP` 视为失败，供 CI 使用。
- `tests/run-test.sh` + `tests/fixture/`：端到端机制测试，不调用 AI、不联网。注入 8 次违规全部拦下，合规分支 `OK 11 · SKIP 0 · FAIL 0`。
- `docs/evidence.md`：实录与局限。
- `AGENTS.md`：给只读规则文件的 agent 用的浓缩版。
- `.github/workflows/ci.yml`：Ubuntu + Windows 两个 runner 上跑语法检查与机制测试；shellcheck 另列一个 job。
- README 徽章（CI / release / license / Agent Skills）。
- 发布 tag `v0.2.0`，GitHub 与 Gitee 镜像同步。

### Known limits of this release

- shellcheck 在本机装不上（网络受限），那个 job 从没在作者机器上跑过，因此 CI 里标了 `continue-on-error`——它报告问题但不阻断合入。第一次跑绿之后应删掉这行，让它变成硬门禁。
- `v0.2.0` tag 指向加徽章之前的提交；徽章 job 的那次 CI 运行不在 tag 上，属预期。

### Fixed

- **`new-task.sh` 的分支存在性判断逻辑写反**（`A || B || {报错}` 在分支与 worktree 都不存在时反而报"分支已存在"），导致任务几乎无法创建。
- **`gate.sh` 的"回归"步骤是假的**：只 `echo` 一句提醒，却在 `SKILL.md` 里被宣称已自动化。现在真的核对任务书「不要动」保护区与基线既有文件清单。
- `gate.sh` 中 `sed 's/^/      ~/ /'` 多一个斜杠，运行时报 `unknown option`。
- 工作区干净检查原来查的是主控目录（任务书未提交时必然误报），改为查该任务自己的 worktree。
- 两个脚本硬编码 `main`，`master` 仓库直接失败；改为自动探测并支持 `BASE_BRANCH`。
- `SKILL.md` 里 Step 3 已创建 worktree、Step 4 又叫创建一次；Step 4 改为"预装依赖"。
- `SKILL.md` 声称闸门自动化了含"回归"在内的 4 步，实际只做了部分；改为逐项列出自动化与人工的分界，并明确闸门跑在合并**之前**。

### Changed

- 文档改英文首屏（`README.md`），中文移至 `README.zh.md`。
- `SKILL.md` frontmatter 补 `license`，私有字段 `agent_created` 收进 `metadata`，符合 Agent Skills 规范。
- 安装说明改为跨工具路径表；未验证的 plugin 打包方式明确不写。

## 0.1.0 — 初始版本

方法论文档、契约与任务书模板、`new-task.sh`、`gate.sh`（体检 / 构建 / 接口实测三段）。
