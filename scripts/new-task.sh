#!/usr/bin/env bash
#
# 建一个并行任务：worktree + 分支 + 任务书骨架
#
# 用法:
#   ./new-task.sh <任务号> <名称> <独占文件...>
#
# 例:
#   ./new-task.sh 01 data src/db migrations
#   ./new-task.sh 02 search src/api/search.ts
#
# 说明:
#   - 必须在 git 仓库内执行，且 main 分支存在
#   - worktree 建在仓库的同级目录: ../wk-<名称>
#   - 任务书写到 <repo>/docs/tasks/task-<任务号>-<名称>.md
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

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "错误: 当前目录不在 git 仓库内" >&2
  exit 1
}

git rev-parse --verify main >/dev/null 2>&1 || {
  echo "错误: 仓库里没有 main 分支" >&2
  exit 1
}

WORKTREE="$(dirname "$ROOT")/wk-$NAME"
BRANCH="feature/$NAME"
TASK_DOC="$ROOT/docs/tasks/task-$ID-$NAME.md"
CONTRACT_SHA="$(git -C "$ROOT" rev-parse --short main)"

if [ -e "$WORKTREE" ]; then
  echo "错误: worktree 已存在 -> $WORKTREE" >&2
  exit 1
fi

if git -C "$ROOT" rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  echo "错误: 分支已存在 -> $BRANCH" >&2
  exit 1
fi

git -C "$ROOT" worktree add "$WORKTREE" -b "$BRANCH" main >/dev/null

mkdir -p "$ROOT/docs/tasks"

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

## 目标
<一句话说清"做完之后能多什么能力">

## 独占文件
$FILE_LIST
## 不要动
- 锁文件（package-lock.json / pnpm-lock.yaml / poetry.lock）
- 共享类型（src/types/**、shared/**）
- 迁移目录（migrations/**）
- 主文档（README、docs/**）
- 编排文件（docker-compose.yml、Dockerfile、CI 配置）
- 其他任务的 worktree

## 步骤
> 环境：依赖已由主控预装；不要自己起服务、不要抢端口。

1. 
2. 

## 验收标准
- [ ] \`<命令>\` → <期望输出>
- [ ] \`<命令>\` → <期望输出>
- [ ] \`git diff main -- <既有模块>/\` 为空（既有行为零改动）

## 注意
- 新增依赖必须成熟且许可宽松（MIT / Apache-2.0）；能不新增就不新增
- 验收由主控在干净栈执行
- 完工必须产出交付契约（见 templates/task-book.example.md 末尾）

## 交付契约（完工后填写）
- 改动文件：
- 自测命令与结果：
- 对契约的实现情况：
- 遗留隐患：
- 下游须知：
EOF

echo ""
echo "已创建"
echo "  分支      $BRANCH"
echo "  worktree  $WORKTREE"
echo "  任务书    $TASK_DOC"
echo ""
echo "下一步:"
echo "  1. 编辑任务书，补齐 波次 / 前置 / 步骤 / 验收标准"
echo "  2. 在主控侧预装依赖:  (cd \"$WORKTREE\" && <install>)"
echo "  3. 新开一个 AI 窗口，只给它 项目文档 + 契约 + 这份任务书"
