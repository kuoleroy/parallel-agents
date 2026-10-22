#!/usr/bin/env bash
#
# 合并闸门 —— 分支合并回基线之前跑的全部检查，任一步红即非零退出
#
# 用法:
#   ./gate.sh <分支名>
#   ./gate.sh feature/search
#
# 可选环境变量:
#   BASE_BRANCH   基线分支          默认自动探测 main / master
#   EXCLUSIVE     手工给独占清单     默认从 docs/tasks/ownership.md 按分支查
#   BUILD_CMD     构建命令          默认空=跳过并如实标 SKIP
#   TEST_CMD      测试命令          默认空=跳过并如实标 SKIP
#   SERVE_CMD     启动服务命令      闸门在该任务 worktree 里带 PORT=<分配端口> 起服务，
#                 探完立刻收掉。端口若已被别的服务占着，闸门判失败而不是借用它——
#                 借来的服务跑的不是本分支代码，实测结论就是假的。
#   HEALTH_URL    显式指定实测对象   设了它就不自己起服务（闸门会 WARN：无法确认来源）
#   HEALTH_PATH   健康端点          默认 /api/health
#   BAD_CASE_PATH 边界用例(应 4xx)   默认 /api/items?page=abc
#   WAIT_SECS     等服务就绪上限     默认 20
#   ALLOW_DIRTY   设 1 跳过 worktree 未提交检查
#   REQUIRE_FULL  设 1 时任何 SKIP 都算失败（CI 用）
#
# 边界与冻结检查依赖 docs/tasks/ownership.md 和 docs/tasks/frozen.patterns，
# 由 scripts/new-task.sh 生成。没登记就建分支的，闸门直接拒。

set -uo pipefail

BRANCH="${1:-}"
if [ -z "$BRANCH" ]; then
  echo "用法: gate.sh <分支名>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/parallel-lib.sh"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "错误: 当前目录不在 git 仓库内" >&2
  exit 1
}

BUILD_CMD="${BUILD_CMD:-}"
TEST_CMD="${TEST_CMD:-}"
SERVE_CMD="${SERVE_CMD:-}"
HEALTH_PATH="${HEALTH_PATH:-/api/health}"
BAD_CASE_PATH="${BAD_CASE_PATH:-/api/items?page=abc}"
WAIT_SECS="${WAIT_SECS:-20}"
ALLOW_DIRTY="${ALLOW_DIRTY:-0}"
REQUIRE_FULL="${REQUIRE_FULL:-0}"

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
N_OK=0; N_FAIL=0; N_SKIP=0
SERVE_PID=""
SERVE_LOG=""

# 停掉闸门自己起的测试服务，并确认端口真的放开了——
# 下一轮实测必须面对一个干净的端口，否则会拿旧进程的结果当本分支的结论。
stop_serve() {
  [ -n "$SERVE_PID" ] || return 0
  kill "$SERVE_PID" >/dev/null 2>&1 || true
  wait "$SERVE_PID" >/dev/null 2>&1 || true
  if [ -n "${SERVE_PROBE_URL:-}" ]; then
    local _i
    for _i in $(seq 1 40); do
      reachable "$SERVE_PROBE_URL" || break
      sleep 0.25
    done
  fi
  SERVE_PID=""
}

cleanup() {
  [ -z "$SERVE_PID" ] || stop_serve
}
trap cleanup EXIT INT TERM

fail() { printf '%s  FAIL  %s%s\n' "$RED" "$1" "$RST"; N_FAIL=$((N_FAIL + 1)); summary; exit 1; }
ok()   { printf '%s  OK    %s%s\n' "$GRN" "$1" "$RST"; N_OK=$((N_OK + 1)); }
skip() { printf '%s  SKIP  %s%s\n' "$YEL" "$1" "$RST"; N_SKIP=$((N_SKIP + 1)); }
step() { printf '%s-- %s%s\n' "$DIM" "$1" "$RST"; }
warn() { printf '%s  WARN  %s%s\n' "$YEL" "$1" "$RST"; }

summary() {
  echo ""
  printf '%s闸门结果:%s OK %d · SKIP %d · FAIL %d\n' "$DIM" "$RST" "$N_OK" "$N_SKIP" "$N_FAIL"
}

printf '\n%s闸门: %s%s\n\n' "$DIM" "$BRANCH" "$RST"

# ---------- 1. 前置：基线与归属登记 ----------
step "前置"

git rev-parse --verify --quiet "$BRANCH" >/dev/null || fail "分支不存在: $BRANCH"

BASE="${BASE_BRANCH:-$(p_detect_base "$ROOT")}"
[ -n "$BASE" ] || fail "找不到基线分支（试过 main / master），用 BASE_BRANCH 指定"
BASE="$(git rev-parse --abbrev-ref "$BASE")"
[ "$BASE" != "$BRANCH" ] || fail "基线分支不能就是被测分支"
ok "基线 $BASE"

ROW="$(p_row_of_branch "$ROOT" "$BRANCH")" || ROW=""
if [ -n "$ROW" ]; then
  IFS=$'\t' read -r TASK_NAME _ROW_BRANCH WORKTREE _WAVE PORT OWN_PATTERNS _STATUS <<< "$ROW"
  ok "归属表已登记: $TASK_NAME · 端口 $PORT"
elif [ -n "${EXCLUSIVE:-}" ]; then
  TASK_NAME="$BRANCH"; WORKTREE=""; PORT=""; OWN_PATTERNS="$EXCLUSIVE"
  warn "分支不在归属表，改用 EXCLUSIVE 手工清单（越界检查仍做，其他任务冲突检查降级）"
else
  fail "分支不在归属表里。用 scripts/new-task.sh 建任务，或临时指定 EXCLUSIVE=\"<通配>\""
fi

RUN_DIR="$ROOT"
if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
  RUN_DIR="$WORKTREE"
fi

CHANGED="$(git diff --name-only "$BASE"..."$BRANCH")"
if [ -z "$CHANGED" ]; then
  warn "与 $BASE 相比零改动，这个分支没交付任何东西"
fi
N_CHANGED="$(printf '%s\n' "$CHANGED" | grep -c . || true)"
step "改动 $N_CHANGED 个文件"

# ---------- 2. 体检 ----------
echo ""
step "体检"

if [ "$ALLOW_DIRTY" != "1" ] && [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
  [ -z "$(git -C "$WORKTREE" status --porcelain)" ] || fail "worktree 有未提交改动，改动没 commit 就进不了 diff"
  ok "worktree 干净"
fi

RESIDUE="$(git diff --name-only "$BASE"..."$BRANCH" | grep -E '(\.verify\.|\.tmp$|^Dockerfile\.tmp)' || true)"
[ -z "$RESIDUE" ] || fail "发现验证残留文件: $RESIDUE"
ok "无验证残留"

# ---------- 3. 边界：整套方法的立身之本 ----------
echo ""
step "边界检查（独占清单之外必须零改动）"

FROZEN_PATTERNS=""
if [ -f "$(p_frozen_path "$ROOT")" ]; then
  FROZEN_PATTERNS="$(grep -v '^[[:space:]]*#' "$(p_frozen_path "$ROOT")" | grep -v '^[[:space:]]*$' || true)"
fi

OUT_OF_SCOPE=""
IN_FROZEN=""
IN_OTHERS=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ -n "$OWN_PATTERNS" ] && p_file_in_patterns "$f" $OWN_PATTERNS; then
    continue
  fi
  OUT_OF_SCOPE="${OUT_OF_SCOPE}${f}"$'\n'
  for fp in $FROZEN_PATTERNS; do
    p_matches "$f" "$fp" && IN_FROZEN="${IN_FROZEN}${f} (冻结: ${fp})"$'\n'
  done
  while IFS=$'\t' read -r o_task o_branch _o_wt _o_wave _o_port o_patterns _o_status; do
    [ -n "${o_task:-}" ] || continue
    for op in $o_patterns; do
      if p_matches "$f" "$op"; then
        IN_OTHERS="${IN_OTHERS}${f} (属于 ${o_task} @ ${o_branch})"$'\n'
      fi
    done
  done < <(p_other_active "$ROOT" "$BRANCH")
done <<< "$CHANGED"

if [ -n "$IN_FROZEN" ]; then
  printf '%s' "$IN_FROZEN" | grep . | sed 's/^/      /' >&2
  fail "动了冻结文件，只能由主控在 $BASE 上改"
fi
if [ -n "$IN_OTHERS" ]; then
  printf '%s' "$IN_OTHERS" | grep . | sed 's/^/      /' >&2
  fail "侵入了其他在跑任务的边界，两边会互相覆盖"
fi
if [ -n "$OUT_OF_SCOPE" ]; then
  printf '%s' "$OUT_OF_SCOPE" | grep . | sed 's/^/      /' >&2
  fail "越界改动（不在独占清单内）"
fi
ok "零越界 · 零侵入 · 零动冻结"

# ---------- 4. 任务书保护区 ----------
echo ""
step "任务书「不要动」复核"

BOOK=""
if [ -n "$TASK_NAME" ]; then
  BOOK="$(grep -l -F "分支：$BRANCH" "$ROOT"/docs/tasks/task-*.md 2>/dev/null | head -1 || true)"
fi
if [ -z "$BOOK" ] || [ ! -f "$BOOK" ]; then
  skip "找不到对应任务书，保护区复核跳过"
else
  PROTECT="$(awk '/^## 不要动/{on=1;next} /^## /{on=0} on&&/^- /{sub(/^- /,"");sub(/[（(].*/,"");gsub(/[[:space:]]/,"");print}' "$BOOK" || true)"
  HIT=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    for pp in $PROTECT; do
      p_matches "$f" "$pp" && HIT="${HIT}${f} (不要动: ${pp})"$'\n'
    done
  done <<< "$CHANGED"
  if [ -n "$HIT" ]; then
    printf '%s' "$HIT" | grep . | sed 's/^/      /' >&2
    fail "动了任务书写明不许动的路径"
  fi
  ok "保护区零改动 ($(printf '%s\n' "$PROTECT" | grep -c . || true) 条)"
fi

# ---------- 5. 构建 ----------
echo ""
step "构建"
if [ -z "$BUILD_CMD" ]; then
  skip "未配置 BUILD_CMD"
else
  printf '    %s (在 %s)%s\n' "$BUILD_CMD" "$RUN_DIR" "$RST"
  if ! (cd "$RUN_DIR" && eval "$BUILD_CMD"); then
    fail "构建失败"
  fi
  ok "构建通过"
fi

# ---------- 6. 接口实测 ----------
echo ""
step "接口实测"

PORT="${PORT:-}"
USER_HEALTH_URL="${HEALTH_URL:-}"
HEALTH_URL="${USER_HEALTH_URL}"
BAD_URL="${BAD_CASE_URL:-}"
if [ -z "$HEALTH_URL" ] && [ -n "$PORT" ]; then
  HEALTH_URL="http://127.0.0.1:${PORT}${HEALTH_PATH}"
  BAD_URL="http://127.0.0.1:${PORT}${BAD_CASE_PATH}"
fi

reachable() { curl -fsS --max-time 2 "$1" >/dev/null 2>&1; }

PROBING=0
if [ -z "$HEALTH_URL" ]; then
  skip "无端口信息（归属表缺端口列且没给 HEALTH_URL），接口实测跳过"
elif [ -n "$USER_HEALTH_URL" ]; then
  warn "实测对象是人工指定的 HEALTH_URL，闸门无法确认它跑的是本分支代码"
  if ! reachable "$HEALTH_URL"; then
    fail "指定的 HEALTH_URL 连不上: $HEALTH_URL"
  fi
  PROBING=1
elif [ -z "$PORT" ]; then
  skip "无端口信息，接口实测跳过"
elif reachable "$HEALTH_URL"; then
  # 每个任务的端口是独占的。端口上站着别的服务，闸门无从判断它跑的是哪份代码，
  # 拿它做实测等于替一个不是本分支的进程背书——所以这是失败，不是警告。
  fail "端口 $PORT 上已有服务，闸门无法确认它跑的是本分支代码。停掉它再跑；确实要测外部服务就显式设 HEALTH_URL"
elif [ -z "$SERVE_CMD" ]; then
  skip "服务没起且未配置 SERVE_CMD"
else
  SERVE_LOG="$(mktemp)"
  SERVE_PROBE_URL="$HEALTH_URL"
  ( cd "$RUN_DIR" && exec env PORT="$PORT" sh -c "$SERVE_CMD" ) >"$SERVE_LOG" 2>&1 &
  SERVE_PID=$!
  READY=0
  for _ in $(seq 1 "$((WAIT_SECS * 2))"); do
    if reachable "$HEALTH_URL"; then READY=1; break; fi
    sleep 0.5
  done
  if [ "$READY" != "1" ]; then
    sed 's/^/      /' "$SERVE_LOG" >&2 || true
    fail "服务没起来（等了 ${WAIT_SECS}s），日志见上"
  fi
  ok "服务已启动 (pid $SERVE_PID, port $PORT)"
  PROBING=1
fi

if [ "$PROBING" = "1" ]; then
  ok "健康检查 $HEALTH_URL"
  if [ -z "$BAD_URL" ]; then
    skip "未给 BAD_CASE_URL，边界用例跳过"
  else
    CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BAD_URL" 2>/dev/null || true)"
    [ -n "$CODE" ] || CODE=000
    case "$CODE" in
      4*) ok "边界用例 $BAD_URL 返回 $CODE" ;;
      000) fail "边界用例无响应: $BAD_URL" ;;
      *)   fail "边界用例期望 4xx，实际 $CODE" ;;
    esac
  fi
fi

# 实测一结束立刻收掉自己起的服务：不留僵尸进程污染下一次运行
if [ -n "$SERVE_PID" ]; then
  stop_serve
  ok "测试服务已停，端口 $PORT 已释放"
fi

# ---------- 7. 回归 ----------
echo ""
step "回归"
if [ -z "$TEST_CMD" ]; then
  skip "未配置 TEST_CMD"
else
  printf '    %s (在 %s)%s\n' "$TEST_CMD" "$RUN_DIR" "$RST"
  if ! (cd "$RUN_DIR" && eval "$TEST_CMD"); then
    fail "测试失败"
  fi
  ok "测试通过"
fi

MOD=""
NEW=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if git cat-file -e "$BASE:$f" 2>/dev/null; then
    MOD="${MOD}${f}"$'\n'
  else
    NEW="${NEW}${f}"$'\n'
  fi
done <<< "$CHANGED"
printf '    改既有 %d 个 · 新增 %d 个\n' \
  "$(printf '%s\n' "$MOD" | grep -c . || true)" "$(printf '%s\n' "$NEW" | grep -c . || true)"
if [ -n "$MOD" ]; then
  printf '%s' "$MOD" | grep . | sed 's/^/      ~ /'
  warn "上面这些是既有文件，人工确认调用方与行为未被改动打穿"
fi

# ---------- 8. 必须人工过的一栏 ----------
echo ""
step "人工清单（闸门不代答）"
cat <<'EOF'
      [ ] 安全：硬编码密钥 / 未校验入参 / 越权 / 拼串 SQL / 日志里 PII
      [ ] 清理：落地 main 前删掉自测用的临时文件与脚本
EOF

if [ "$N_SKIP" -gt 0 ] && [ "$REQUIRE_FULL" = "1" ]; then
  fail "REQUIRE_FULL=1：有 $N_SKIP 项未验证，不构成完整通过"
fi

summary
if [ "$N_SKIP" -gt 0 ]; then
  printf '%s闸门通过，但有 %d 项没真验证，别当成全绿。%s\n\n' "$YEL" "$N_SKIP" "$RST"
else
  printf '%s闸门通过: %s%s\n\n' "$GRN" "$BRANCH" "$RST"
fi

echo "下一步:"
echo "  git checkout $BASE && git merge --no-ff $BRANCH"
echo "  其余在跑 worktree: git merge $BASE   # 重新对齐契约"
if [ -n "$ROW" ]; then
  echo "  归属表把 ${TASK_NAME} 的状态改成 merged，释放它的端口"
fi
echo ""
