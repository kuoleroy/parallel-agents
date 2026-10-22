#!/usr/bin/env bash
#
# parallel-agents 端到端测试 —— 不调用任何 AI，不联网，不花 token
#
# 它证明的是机制本身：
#   1. 独占清单之外的改动，闸门拦得住
#   2. 冻结文件被改，闸门拦得住
#   3. 两个任务边界重叠，建任务时就拒绝
#   4. 契约写了「非法分页返回 400」而代码静默回落，接口实测拦得住
#   5. 未提交改动 / 未登记分支，闸门拒绝
#   6. 端口被外来服务占用，闸门拒绝借用它做实测（CI 的 ubuntu runner 抓出来的真 bug）
#   7. 合规分支在 REQUIRE_FULL=1 下真跑全绿（node 起服务 + curl 实测 + 契约测试）
#
# 用法: bash tests/run-test.sh
#       VERBOSE=1 bash tests/run-test.sh   # 打印闸门完整输出，README 实录素材

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
FIX="$HERE/fixture"
NEW="$ROOT/scripts/new-task.sh"
GATE="$ROOT/scripts/gate.sh"
VERBOSE="${VERBOSE:-0}"

TMP="$(mktemp -d)"
FOREIGN_PID=""
PORT_BASE=$((20000 + (RANDOM % 10000)))
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

OK_COUNT=0
FAILED=0
INJECTED=0
BLOCKED=0

cleanup() {
  [ -z "$FOREIGN_PID" ] || kill "$FOREIGN_PID" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

c_g=$'\033[32m'; c_r=$'\033[31m'; c_d=$'\033[2m'; c_0=$'\033[0m'

group() { printf '\n%s== %s%s\n' "$c_d" "$1" "$c_0"; }

# check_block <标签> <期望关键字> <命令串>  —— 断言命令失败且输出含关键字
check_block() {
  local label="$1" needle="$2" cmd="$3" out st
  INJECTED=$((INJECTED + 1))
  out="$(eval "$cmd" 2>&1)" && st=0 || st=$?
  if [ "$st" -ne 0 ] && printf '%s' "$out" | grep -q -- "$needle"; then
    BLOCKED=$((BLOCKED + 1))
    printf '%s 拦住%s  %-32s %s(命中 "%s")%s\n' "$c_g" "$c_0" "$label" "$c_d" "$needle" "$c_0"
  else
    FAILED=$((FAILED + 1))
    printf '%s 漏网%s  %-32s exit=%s 期望失败且含 "%s"\n%s\n' "$c_r" "$c_0" "$label" "$st" "$needle" "$out"
  fi
  [ "$VERBOSE" = "1" ] && printf '%s%s%s\n' "$c_d" "$out" "$c_0"
}

# check_pass <标签> <期望关键字> <命令串>  —— 断言命令成功且输出含关键字
check_pass() {
  local label="$1" needle="$2" cmd="$3" out st
  out="$(eval "$cmd" 2>&1)" && st=0 || st=$?
  if [ "$st" -eq 0 ] && printf '%s' "$out" | grep -q -- "$needle"; then
    OK_COUNT=$((OK_COUNT + 1))
    printf '%s 通过%s  %s\n' "$c_g" "$c_0" "$label"
  else
    FAILED=$((FAILED + 1))
    printf '%s 失败%s  %-32s exit=%s 期望含 "%s"\n%s\n' "$c_r" "$c_0" "$label" "$st" "$needle" "$out"
  fi
  [ "$VERBOSE" = "1" ] && printf '%s%s%s\n' "$c_d" "$out" "$c_0"
}

# check_absent <标签> <路径>  —— 被拒绝的创建动作不该留下残渣
check_absent() {
  local label="$1" path="$2"
  if [ ! -e "$path" ]; then
    OK_COUNT=$((OK_COUNT + 1))
    printf '%s 干净%s  %s\n' "$c_g" "$c_0" "$label"
  else
    FAILED=$((FAILED + 1))
    printf '%s 残渣%s  %-32s 仍存在: %s\n' "$c_r" "$c_0" "$label" "$path"
  fi
}

make_repo() {
  local dir="$1" branch="$2"
  mkdir -p "$dir/src/api/__tests__" "$dir/src/db" "$dir/shared/types" \
    "$dir/migrations" "$dir/docs/contracts"
  git init -q -b "$branch" "$dir"
  git -C "$dir" config user.name test
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config core.autocrlf false
  cp "$FIX/server.mjs" "$dir/server.mjs"
  cp "$FIX/src/api/search.js" "$dir/src/api/search.js"
  cp "$FIX/src/api/__tests__/search.test.js" "$dir/src/api/__tests__/search.test.js"
  printf '{ "name": "demo", "type": "module", "private": true }\n' > "$dir/package.json"
  printf 'items(id text primary key, title text not null, created_at timestamptz not null)\n' \
    > "$dir/src/db/schema.sql"
  printf 'export type Item = { id: string; title: string; createdAt: string };\n' \
    > "$dir/shared/types/item.ts"
  printf 'CREATE TABLE items (id text primary key);\n' > "$dir/migrations/001.sql"
  printf 'services:\n  api:\n    image: node\n' > "$dir/docker-compose.yml"
  printf '# 契约 v1\n\nGET /api/items?page=  非法值 -> 400 INVALID_QUERY，不得静默回落到 1\n' \
    > "$dir/docs/contracts/v1.md"
  printf 'wk-*\n' > "$dir/.gitignore"
  git -C "$dir" add -A
  git -C "$dir" commit -qm "init demo stack"
}

# ---------------------------------------------------------------- 场景一
group "场景一：main 仓库，两个任务并行（$PORT_BASE 起端口）"

# 这一条是给 CI 兜底的：Windows 下 Git Bash 把所有文件都当可执行，
# 本地永远测不出「Linux/macOS 用户 ./scripts/new-task.sh 直接 Permission denied」。
if [ -d "$ROOT/.git" ]; then
  check_pass "脚本在 git 里带可执行位" "100755" \
    "git -C \"$ROOT\" ls-files -s scripts/new-task.sh scripts/gate.sh"
fi

APP="$TMP/app"
make_repo "$APP" main
BASE_SHA="$(git -C "$APP" rev-parse main)"

PROBE="cd \"$APP\" && BUILD_CMD='node --check server.mjs' SERVE_CMD='node server.mjs'"
NEWC="cd \"$APP\" && BASE_PORT=$PORT_BASE \"$NEW\""
DATA_PORT=$((PORT_BASE + 1))

check_pass "建任务 01 data（独占 src/db）" "已创建" "$NEWC 01 data src/db"
check_pass "归属表自动分端口" "$DATA_PORT" "cat \"$APP/docs/tasks/ownership.md\""

check_block "重叠边界：02 想动 src/db" "冲突" "$NEWC 02 collide src/db/schema.sql"
check_absent "被拒任务没留下 worktree" "$TMP/wk-collide"

check_block "把冻结文件写进独占清单" "冻结" "$NEWC 03 lock package-lock.json"
check_absent "被拒任务没留下任务书" "$APP/docs/tasks/task-03-lock.md"

check_pass "建任务 02 search（独占 search.js）" "已创建" "$NEWC 02 search src/api/search.js"
check_pass "两个 worktree 各自独立" "wk-data" "ls -d \"$TMP\"/wk-data \"$TMP\"/wk-search"

# 注入一：只加注释没实现契约，接口实测该抓
printf '\n// TODO: 校验稍后补\n' >> "$TMP/wk-search/src/api/search.js"
git -C "$TMP/wk-search" commit -qam "search: 加注释"
check_block "契约未实现：边界用例仍 200" "期望 4xx" "$PROBE \"$GATE\" feature/search"

# 注入二：越界改到在跑任务 02 的文件
printf 'scope creep\n' >> "$TMP/wk-data/src/api/search.js"
git -C "$TMP/wk-data" commit -qam "data: 顺手改了 search"
check_block "侵入在跑任务 02 的边界" "侵入了其他在跑任务" "$PROBE \"$GATE\" feature/data"
git -C "$TMP/wk-data" reset -q --hard "$BASE_SHA"

# 注入三：动冻结的 package.json
printf '# extra\n' >> "$TMP/wk-data/package.json"
git -C "$TMP/wk-data" commit -qam "data: 动 package.json"
check_block "动冻结文件" "冻结文件" "$PROBE \"$GATE\" feature/data"
git -C "$TMP/wk-data" reset -q --hard "$BASE_SHA"

# 注入四：改动没 commit 就想收工
printf 'uncommitted\n' >> "$TMP/wk-data/src/db/schema.sql"
check_block "worktree 有未提交改动" "未提交" "$PROBE \"$GATE\" feature/data"
git -C "$TMP/wk-data" checkout -q -- src/db/schema.sql

# 注入五：绕过 new-task 自己开分支
git -C "$APP" branch rogue/no-owner "$BASE_SHA"
check_block "未登记归属表的分支" "不在归属表" "$PROBE \"$GATE\" rogue/no-owner"

# 注入一之补：带着 3 项未验证想过关，REQUIRE_FULL 该拒
check_block "未配置实测就想放行（REQUIRE_FULL=1）" "不构成完整通过" \
  "cd \"$APP\" && REQUIRE_FULL=1 \"$GATE\" feature/search"

# 合规：真正实现契约，要求全绿且不许有 SKIP
cp "$FIX/search-implemented.js" "$TMP/wk-search/src/api/search.js"
git -C "$TMP/wk-search" commit -qam "search: 按契约校验非法分页"
check_pass "合规分支 REQUIRE_FULL 全绿" "闸门通过" \
  "cd \"$APP\" && REQUIRE_FULL=1 BUILD_CMD='node --check server.mjs' \
   SERVE_CMD='node server.mjs' TEST_CMD='node src/api/__tests__/search.test.js' \
   \"$GATE\" feature/search"
check_pass "全绿输出里零 SKIP" "SKIP 0" \
  "cd \"$APP\" && REQUIRE_FULL=1 BUILD_CMD='node --check server.mjs' \
   SERVE_CMD='node server.mjs' TEST_CMD='node src/api/__tests__/search.test.js' \
   \"$GATE\" feature/search"

# 注入六：端口上站着别人的服务 —— 这是 CI 的 ubuntu runner 抓出来的真实事故
# 闸门原先"发现端口有人就借用"，于是拿上一轮遗留、根本没跑本分支代码的进程做实测，
# 结论可以是假的。现在占用即失败。
SEARCH_PORT=$((PORT_BASE + 2))
( cd "$APP" && exec env PORT="$SEARCH_PORT" node server.mjs >/dev/null 2>&1 ) &
FOREIGN_PID=$!
for _ in $(seq 1 40); do
  curl -fsS --max-time 1 "http://127.0.0.1:$SEARCH_PORT/api/health" >/dev/null 2>&1 && break
  sleep 0.25
done
check_block "端口被外来服务占用，拒绝借用" "已有服务" "$PROBE \"$GATE\" feature/search"
kill "$FOREIGN_PID" >/dev/null 2>&1 || true
wait "$FOREIGN_PID" >/dev/null 2>&1 || true
FOREIGN_PID=""

# ---------------------------------------------------------------- 场景二
group "场景二：master 仓库（没有 main 分支）"

OLD="$TMP/legacy/repo"
make_repo "$OLD" master
check_pass "基线分支自动探测 master" "已创建" \
  "cd \"$OLD\" && BASE_PORT=$((PORT_BASE + 50)) \"$NEW\" 01 data src/db"

# ---------------------------------------------------------------- 结论
echo ""
printf '%s违规注入 %d 次 → 拦下 %d 次；正向断言 %d 项。%s\n' \
  "$c_d" "$INJECTED" "$BLOCKED" "$OK_COUNT" "$c_0"

if [ "$FAILED" -gt 0 ] || [ "$BLOCKED" -ne "$INJECTED" ]; then
  printf '%s测试失败: %d 项断言未过，%d/%d 违规漏网%s\n' \
    "$c_r" "$FAILED" "$((INJECTED - BLOCKED))" "$INJECTED" "$c_0"
  exit 1
fi

printf '%s全部通过: %d 次违规全部拦下，合规分支真实跑绿（起服务 + curl 实测 + 契约测试）。%s\n' \
  "$c_g" "$BLOCKED" "$c_0"
