#!/usr/bin/env bash
#
# 建一个并行任务：worktree + 分支 + 任务书 + 归属表登记
#
# 用法:
#   ./new-task.sh <任务号> <名称> <独占文件...>
#
# 例:
#   ./new-task.sh 01 data src/db migrations
#   ./new-task.sh 02 search src/api/search.ts src/api/__tests__/search.test.ts
#
# 可选环境变量:
#   BASE_BRANCH  基线分支            默认自动探测 main / master
#   BASE_PORT    端口起点            默认 3100，任务号决定偏移
#   WK_PARENT    worktree 的父目录    默认仓库同级目录
#
# 说明:
#   - 必须在 git 仓库内执行
#   - 独占文件清单会写进 docs/tasks/ownership.md，gate.sh 据此拦越界改动
#   - 与在跑任务的边界或冻结清单冲突时直接拒绝建任务
#   - 本脚本不安装依赖，装依赖由主控单独做（见 README）

set -euo pipefail

if [ $# -lt 3 ]; then
  echo "用法: new-task.sh <任务号> <名称> <独占文件...>" >&2
  echo "例:   new-task.sh 01 data src/db migrations" >&2
  exit 1
fi

ID="$1"
NAME="$2"
shift 2
FILES=("$@")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/parallel-lib.sh"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "错误: 当前目录不在 git 仓库内" >&2
  exit 1
}

[[ "$ID" =~ ^[0-9]+$ ]] || { echo "错误: 任务号要是纯数字，例如 01、02" >&2; exit 1; }
[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "错误: 名称只能用字母数字和 . _ -（不要用空格或斜杠）" >&2; exit 1; }

BASE="${BASE_BRANCH:-$(p_detect_base "$ROOT")}" || {
  echo "错误: 找不到基线分支（试过 main / master），用 BASE_BRANCH 指定" >&2
  exit 1
}

git -C "$ROOT" rev-parse --verify --quiet "$BASE" >/dev/null || {
  echo "错误: 基线分支不存在: $BASE" >&2
  exit 1
}

OWNERSHIP="$(p_ownership_path "$ROOT")"
FROZEN="$(p_frozen_path "$ROOT")"
mkdir -p "$(dirname "$OWNERSHIP")"

if [ ! -f "$FROZEN" ]; then
  p_frozen_defaults > "$FROZEN"
  echo "已生成冻结清单 $FROZEN（按项目改它，改完 commit 到 $BASE）"
fi

if [ ! -f "$OWNERSHIP" ]; then
  cat > "$OWNERSHIP" <<'EOF'
# 归属表

> 由 `scripts/new-task.sh` 维护，`scripts/gate.sh` 依据本表拦截越界改动。
> 手工改动请保持列顺序；状态取 active / merged / abandoned。

| 任务 | 分支 | worktree | 波次 | 端口 | 独占文件 | 状态 |
|---|---|---|---|---|---|---|
EOF
fi

BRANCH="feature/$NAME"
WORKTREE="${WK_PARENT:-$(dirname "$ROOT")}/wk-$NAME"
TASK_DOC="$ROOT/docs/tasks/task-$ID-$NAME.md"
CONTRACT_SHA="$(git -C "$ROOT" rev-parse --short "$BASE")"

if [ -e "$WORKTREE" ]; then
  echo "错误: worktree 已存在 -> $WORKTREE" >&2
  exit 1
fi
if git -C "$ROOT" rev-parse --verify --quiet "$BRANCH" >/dev/null; then
  echo "错误: 分支已存在 -> $BRANCH" >&2
  exit 1
fi
if [ -e "$TASK_DOC" ]; then
  echo "错误: 任务书已存在 -> $TASK_DOC（重做请开新任务号，不要覆盖）" >&2
  exit 1
fi
if p_row_of_branch "$ROOT" "$BRANCH" >/dev/null; then
  echo "错误: 归属表里已有 $BRANCH" >&2
  exit 1
fi

NEW_PATTERNS="${FILES[*]}"

COLLIDERS=""
while IFS=$'\t' read -r row_task row_branch _row_wt _row_wave _row_port row_patterns _row_status; do
  hits="$(p_overlaps "$NEW_PATTERNS" "$row_patterns" || true)"
  if [ -n "$hits" ]; then
    COLLIDERS="${COLLIDERS}${row_task} (${row_branch}): ${hits//$'\n'/, }
"
  fi
done < <(p_other_active "$ROOT" "$BRANCH")

if [ -n "$COLLIDERS" ]; then
  echo "错误: 独占文件与在跑任务冲突，边界必须互不相交" >&2
  printf '%s' "$COLLIDERS" | sed 's/^/  /' >&2
  echo "处置: 收窄清单，或把两件事并成一个任务；确属同文件请先合并对方分支" >&2
  exit 1
fi

for f in "${FILES[@]}"; do
  if p_file_in_patterns "$f" $(cat "$FROZEN" | grep -v '^#' | grep -v '^[[:space:]]*$' || true); then
    echo "错误: $f 属于冻结文件，只能由主控在 $BASE 上改" >&2
    exit 1
  fi
done

NUM=$((10#$ID))
PORT_BASE="${BASE_PORT:-3100}"
PORT=$((PORT_BASE + NUM))
while grep -qx "$PORT" <(p_used_ports "$ROOT"); do
  PORT=$((PORT + 1))
done

git -C "$ROOT" worktree add "$WORKTREE" -b "$BRANCH" "$BASE" >/dev/null

FROZEN_LIST=""
while read -r pat; do
  FROZEN_LIST="${FROZEN_LIST}- ${pat}（冻结）
"
done < <(grep -v '^[[:space:]]*#' "$FROZEN" | grep -v '^[[:space:]]*$' || true)

FILE_LIST=""
for f in "${FILES[@]}"; do
  FILE_LIST="${FILE_LIST}- ${f}
"
done

cat > "$TASK_DOC" <<EOF
# 任务书 $ID · $NAME

- 分支：$BRANCH
- worktree：$WORKTREE
- 波次：<1 / 2 / 3>
- 前置：<依赖哪些任务/契约，或"无硬依赖">
- 上游契约：docs/contracts/ @ $CONTRACT_SHA
- 分配端口：$PORT（起服务只用这个端口，别抢 3000/5432 这类公共端口）

## 目标

<一句话说清"做完之后能多什么能力">

## 独占文件

$FILE_LIST
## 不要动

$FROZEN_LIST- 其他任务的 worktree 与它们的独占文件

## 步骤

> 环境：依赖已由主控预装；不要自己起服务、不要抢端口。验收时用分配到的 $PORT。

1. 
2. 

## 验收标准

- [ ] \`<命令>\` → <期望输出>
- [ ] \`curl -s "localhost:$PORT/<端点>"\` → <契约规定的响应>
- [ ] \`git diff $BASE -- <既有模块>/\` 为空（既有行为零改动）
- [ ] 归属表里的独占清单之外，零改动

## 注意

- 新增依赖必须成熟且许可宽松（MIT / Apache-2.0）；能不新增就不新增
- 依赖由主控预装；要加依赖就回报主控，别自己装
- 验收由主控在干净栈执行
- 完工必须产出交付契约（见 templates/task-book.example.md 末尾）

## 交付契约（完工后填写）

- 改动文件：
- 自测命令与结果：
- 对契约的实现情况：
- 遗留隐患：
- 下游须知：
EOF

printf '| %s %s | %s | %s | <波次> | %s | %s | active |\n' \
  "$ID" "$NAME" "$BRANCH" "$WORKTREE" "$PORT" "$NEW_PATTERNS" >> "$OWNERSHIP"

echo ""
echo "已创建"
echo "  分支      $BRANCH"
echo "  worktree  $WORKTREE"
echo "  任务书    $TASK_DOC"
echo "  端口      $PORT"
echo "  归属表    $OWNERSHIP（已登记，波次列待补）"
echo ""
echo "下一步:"
echo "  1. 编辑任务书，补齐 波次 / 前置 / 步骤 / 验收标准，并把归属表里的 <波次> 填上"
echo "  2. 主控侧预装依赖:  (cd \"$WORKTREE\" && <install>)"
echo "  3. 新开一个 AI 窗口，只给它 项目文档 + 契约 + 这份任务书"
echo "  4. 收口跑闸门:  $SCRIPT_DIR/gate.sh $BRANCH"
echo ""
echo "提示: 任务书与归属表目前是 $BASE 上未提交的文件，建议 commit，让文档成为共享事实源"
