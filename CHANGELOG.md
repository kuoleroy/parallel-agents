# Changelog

遵循 [Keep a Changelog](https://keepachangelog.com/) 与语义化版本。

## Unreleased

`v0.2.0` 首推到 GitHub，Actions 在 ubuntu runner 上三条运行全红。两个都是真 bug，都不是 Windows 上能看出来的。

### Fixed

- **闸门会借用端口上别人的服务做实测**：原逻辑「端口已有人监听 → WARN 一句 → 直接拿它实测」。上一轮遗留的 node 还占着端口时，闸门给一个根本没跑本分支代码的进程出了结论，合规分支被判 `FAIL 边界用例期望 4xx，实际 200`。现在端口被占即 `FAIL`，不猜不借；确实要测外部服务用 `HEALTH_URL` 显式声明（WARN 提示无法确认来源）。闸门自己起的服务在实测结束那一刻就 `kill` + 轮询确认端口释放，不再拖到脚本退出。
- **重构实测分支时带出的两处小 bug**：探活被跳过时健康检查仍会跑（现在用 `PROBING` 标志守住）；`curl` 取状态码时 `|| echo 000` 与前面的输出拼接成 `000000`，导致「无响应」那条分支永远不匹配。
- 以上两条均由 `tests/run-test.sh` 新增的第 9 条违规注入常驻盯住（测试自己往任务端口上起一个外来服务，断言闸门拒绝）。注入数从 8 → 9，正向断言 10 项不变，合规分支 `OK 11` → `OK 12`（多一条「测试服务已停，端口已释放」）。

### Changed

- 文档与实录同步到真实数字：`README.md` / `README.zh.md` / `SKILL.md` / `docs/methodology.md` / `docs/evidence.md`。`docs/evidence.md` 新增「这套测试自己放过的两个 bug（由 CI 抓到）」一节与实录四。
- **教训进了方法论文档**：机制测试只在一种环境跑过就等于没跑过。CI 覆盖 ubuntu + windows 两个 runner 不是仪式感，它这轮就是唯一抓到这两个 bug 的东西。

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

### Fixed

- **四个 `.sh` 在 git 里没有可执行位（模式 `100644`）**：Windows 上本地测不出来（Git Bash 把所有文件都当可执行），Linux / macOS 用户 `./scripts/new-task.sh` 直接 `Permission denied`，CI 首推三条运行因此全红。已用 `git update-index --chmod=+x` 修正，并在 `tests/run-test.sh` 里加了第 10 条断言专门盯它——把「只在一种环境跑过」这个盲区变成常驻检查。
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

### Known limits of this release

- shellcheck 在本机装不上（网络受限），那个 job 从没在作者机器上跑过，因此 CI 里标了 `continue-on-error`——它报告问题但不阻断合入。第一次跑绿之后应删掉这行，让它变成硬门禁。
- `v0.2.0` tag 指向加徽章之前的提交；徽章 job 的那次 CI 运行不在 tag 上，属预期。

## 0.1.0 — 初始版本

方法论文档、契约与任务书模板、`new-task.sh`、`gate.sh`（体检 / 构建 / 接口实测三段）。
