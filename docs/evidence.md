# 机制验证实录

> 这套方法宣称能拦住什么，这里就用可复现的方式证明它拦住了。
> 复现：`bash tests/run-test.sh`（完整输出 `VERBOSE=1 bash tests/run-test.sh`）。
> **不调用任何 AI，不联网，不花 token**，本机几秒跑完。

## 结论

```
违规注入 8 次 → 拦下 8 次；正向断言 10 项。
全部通过: 8 次违规全部拦下，合规分支真实跑绿（起服务 + curl 实测 + 契约测试）。
```

合规分支在 `REQUIRE_FULL=1`（任何跳过都算失败）下的闸门结果：

```
闸门结果: OK 11 · SKIP 0 · FAIL 0
```

## 测了什么

| # | 违规注入 | 拦在哪 |
|---|---|---|
| 1 | 新任务独占清单与在跑任务重叠（`src/db/schema.sql` vs `src/db`） | 建任务时拒绝，不留 worktree |
| 2 | 把冻结文件（`package-lock.json`）写进独占清单 | 建任务时拒绝 |
| 3 | 契约写明「非法分页 → 400」，代码静默回落到 1，分支只加了句注释 | 闸门接口实测：`FAIL 边界用例期望 4xx，实际 200` |
| 4 | 任务 01 顺手改了任务 02 的文件 | 闸门：`FAIL 侵入了其他在跑任务的边界` |
| 5 | 任务分支改动 `package.json`（冻结） | 闸门：`FAIL 动了冻结文件` |
| 6 | 改动没 commit 就想收工 | 闸门：`FAIL worktree 有未提交改动` |
| 7 | 绕过 `new-task.sh` 自己开分支来收口 | 闸门：`FAIL 分支不在归属表里` |
| 8 | 构建/实测/测试都没配，想拿"绿色"糊过去 | 闸门：`REQUIRE_FULL=1：有 3 项未验证，不构成完整通过` |

正向断言 10 项：脚本在 git 里带可执行位、建任务、归属表登记与自动分端口、两个 worktree 独立、合规分支全绿、全绿输出 `SKIP 0`、`master` 仓库（无 `main` 分支）自动探测基线等。

## 这套测试自己漏掉的一个 bug

0.2.0 首推之后，GitHub Actions 三条运行全红。原因：**四个 `.sh` 在 git 里的模式是 `100644`，没有可执行位**。

```
$ git ls-files -s scripts
100644 ... scripts/gate.sh
100644 ... scripts/new-task.sh
```

在 Windows 上跑 `bash tests/run-test.sh` 一切正常——Git Bash 把所有文件都当可执行。在 Linux 上，测试内部直接 `"$ROOT/scripts/new-task.sh"` 调用就是 `Permission denied`，断言成片失败。而真实用户拿到的体验更糟：`./scripts/new-task.sh 01 data src/db` 在 macOS/Linux 上根本跑不起来。

也就是说：**这套「违规必拦」的测试，自己因为只在一种环境下跑过，把一个平台级的破坏性 bug 放过去了。** 现在多了第 10 条断言专门盯可执行位，CI 的 ubuntu runner 成了这个 bug 的常驻捕手——这正是把测试放到第二种环境上跑的价值，也是本仓库刻意让 CI 覆盖 ubuntu + windows 两个 runner 的理由。

（同一次 CI 里 shellcheck 那条也在红。它从未在作者机器上跑过——本机装不上、网络装不了——所以已经先标成 `continue-on-error`，只报告不阻断。）

## 实录一：契约未实现，被接口实测抓住

分支只加了一句注释，边界、构建、体检全绿——契约要求的 400 没实现，靠 `curl` 当场抓住：

```
闸门: feature/search

-- 前置
  OK    基线 main
  OK    归属表已登记: 02 search · 端口 28263
-- 改动 1 个文件

-- 体检
  OK    worktree 干净
  OK    无验证残留

-- 边界检查（独占清单之外必须零改动）
  OK    零越界 · 零侵入 · 零动冻结

-- 任务书「不要动」复核
  OK    保护区零改动 (13 条)

-- 构建
    node --check server.mjs (在 .../wk-search)
  OK    构建通过

-- 接口实测
  OK    服务已启动 (pid 2228, port 28263)
  OK    健康检查 http://127.0.0.1:28263/api/health
  FAIL  边界用例期望 4xx，实际 200

闸门结果: OK 9 · SKIP 0 · FAIL 1
```

这就是「两个 agent 对同一个字段/同一条契约理解不同」那一类返工：它不是合并冲突，git 看不见，只有按契约跑一次真实请求才暴露。

## 实录二：越界改动被拒

```
闸门: feature/data

-- 前置
  OK    基线 main
  OK    归属表已登记: 01 data · 端口 28262
-- 改动 1 个文件

-- 体检
  OK    worktree 干净
  OK    无验证残留

-- 边界检查（独占清单之外必须零改动）
      src/api/search.js (属于 02 search @ feature/search)
  FAIL  侵入了其他在跑任务的边界，两边会互相覆盖

闸门结果: OK 4 · SKIP 0 · FAIL 1
```

## 实录三：合规分支全绿

同一分支按契约补上校验后：

```
-- 接口实测
  OK    服务已启动 (pid 2228, port 28263)
  OK    健康检查 http://127.0.0.1:28263/api/health
  OK    边界用例 http://127.0.0.1:28263/api/items?page=abc 返回 400

-- 回归
    node src/api/__tests__/search.test.js (在 .../wk-search)
契约测试通过: 非法分页返回 400，不再静默回落
  OK    测试通过
    改既有 1 个 · 新增 0 个
      ~ src/api/search.js
  WARN  上面这些是既有文件，人工确认调用方与行为未被改动打穿

闸门结果: OK 11 · SKIP 0 · FAIL 0
闸门通过: feature/search
```

服务由闸门自己起、自己收（`SERVE_CMD` + 归属表分配的独立端口），执行方不需要也不允许起服务。

## 局限（请连同结论一起读）

1. **这是机制验证，不是效果验证。** 它证明闸门确实拦得住这些注入，**不**证明"用了它你的三 agent 并行返工从 X 降到 Y"。后者需要真实多 agent 运行，本仓库目前**没有**这个数据，也不宣称有。
2. **被测栈是 60 行的 node 微服务**，不是真实项目。边界、冻结、实测三项机制与语言无关，但 `BUILD_CMD` / `SERVE_CMD` / `TEST_CMD` 需要你按自己的栈配置。
3. **重叠判定是启发式**：支持精确路径、裸目录、`dir/**`、`dir/*` 和单层 `*.ts`，不支持取反与花括号展开。相邻清单是否真冲突仍需人判断，所以方法论要求"清单宁可窄不可宽"。
4. **未在 Windows 原生 PowerShell 下测试**，脚本走 Git Bash；`mktemp` / `curl` / `awk` 是依赖项。
5. 端口在每次跑测时随机取（`20000+`），所以实录里的端口与你本机不同。
