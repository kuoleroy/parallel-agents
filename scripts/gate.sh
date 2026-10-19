#!/usr/bin/env bash
#
# 合并闸门 —— 对一个分支跑完全部检查，任一步失败即以非零退出
#
# 用法:
#   ./gate.sh <分支名>
#   ./gate.sh feature/search
#
# 按项目改写下面这组环境变量，或直接在项目里 export:
#   BUILD_CMD        构建命令            默认 pnpm -w build
#   HEALTH_URL       健康检查端点        默认 http://localhost:3000/api/health
#   BAD_CASE_URL     边界用例（应返回 4xx）默认 http://localhost:3000/api/items?page=abc
#   BASE_BRANCH      对比基线            默认 main
#   ALLOW_DIRTY      设为 1 跳过工作区检查
#
# 对应 README 里的闸门步骤: 体检 / 构建 / 接口实测 / 回归

set -uo pipefail

BRANCH="${1:-}"
if [ -z "$BRANCH" ]; then
  echo "用法: gate.sh <分支名>" >&2
  exit 1
fi

BUILD_CMD="${BUILD_CMD:-pnpm -w build}"
HEALTH_URL="${HEALTH_URL:-http://localhost:3000/api/health}"
BAD_CASE_URL="${BAD_CASE_URL:-http://localhost:3000/api/items?page=abc}"
BASE_BRANCH="${BASE_BRANCH:-main}"
ALLOW_DIRTY="${ALLOW_DIRTY:-0}"

RED=$'\033[31m'; GRN=$'\033[32m'; DIM=$'\033[2m'; RST=$'\033[0m'
fail() { printf '%s  FAIL  %s%s\n' "$RED" "$1" "$RST"; exit 1; }
ok()   { printf '%s  OK    %s%s\n' "$GRN" "$1" "$RST"; }
step() { printf '%s-- %s%s\n' "$DIM" "$1" "$RST"; }

printf '\n%s闸门: %s (base: %s)%s\n\n' "$DIM" "$BRANCH" "$BASE_BRANCH" "$RST"

# ---------- 1. 体检 ----------
step "体检"

git rev-parse --verify "$BRANCH" >/dev/null 2>&1 || fail "分支不存在: $BRANCH"
git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1 || fail "基线分支不存在: $BASE_BRANCH"

if [ "$ALLOW_DIRTY" != "1" ]; then
  [ -z "$(git status --porcelain)" ] || fail "工作区不干净，先 commit 或 stash"
fi
ok "工作区干净"

LEAK="$(git diff --name-only "$BASE_BRANCH"..."$BRANCH" | grep -E '(\.verify\.|\.tmp$|^Dockerfile\.tmp)' || true)"
[ -z "$LEAK" ] || fail "发现验证残留文件: $LEAK"
ok "无验证残留"

echo ""
printf '%s  本次改动:%s\n' "$DIM" "$RST"
git diff --stat "$BASE_BRANCH"..."$BRANCH" | sed 's/^/    /'

# ---------- 2. 构建 ----------
echo ""
step "构建: $BUILD_CMD"
if ! eval "$BUILD_CMD"; then
  fail "构建失败"
fi
ok "构建通过"

# ---------- 3. 接口实测 ----------
echo ""
step "接口实测"

if curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null 2>&1; then
  ok "健康检查 $HEALTH_URL"
else
  fail "健康检查失败: $HEALTH_URL（服务起了吗？）"
fi

CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BAD_CASE_URL" 2>/dev/null || echo 000)"
case "$CODE" in
  4*) ok "边界用例返回 $CODE" ;;
  000) fail "边界用例无响应: $BAD_CASE_URL" ;;
  *)   fail "边界用例期望 4xx，实际 $CODE" ;;
esac

# ---------- 4. 回归 ----------
echo ""
step "回归"
echo "    手动确认既有行为零改动。自动部分:"
echo "    git diff $BASE_BRANCH -- <既有模块>/ 应当为空"
echo ""

printf '%s闸门通过: %s%s\n\n' "$GRN" "$BRANCH" "$RST"
echo "下一步:"
echo "  git checkout $BASE_BRANCH"
echo "  git merge --no-ff $BRANCH"
echo "  其余 worktree: git merge $BASE_BRANCH"
echo ""
