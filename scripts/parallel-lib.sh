#!/usr/bin/env bash
#
# parallel-lib.sh —— new-task.sh / gate.sh 共用的边界判定函数
# 不单独执行，由脚本 source 引入。
#
# 归属表格式（docs/tasks/ownership.md，一行一个任务）:
#   | 任务 | 分支 | worktree | 波次 | 端口 | 独占文件 | 状态 |
# 独占文件列内用空格分隔多条通配。状态: active / merged / abandoned

p_detect_base() {
  local b
  for b in main master; do
    git rev-parse --verify --quiet "$b" >/dev/null && { printf '%s\n' "$b"; return 0; }
  done
  b="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" || return 1
  printf '%s\n' "$b"
}

p_ownership_path() { printf '%s/docs/tasks/ownership.md\n' "$1"; }

p_frozen_path() { printf '%s/docs/tasks/frozen.patterns\n' "$1"; }

p_frozen_defaults() {
  cat <<'EOF'
# 冻结清单：任何任务分支不得改动，只由主控在基线分支上维护
# 一行一条通配，# 开头为注释。目录通配用 dir/**
docs/contracts/**
shared/types/**
src/types/**
migrations/**
package.json
package-lock.json
pnpm-lock.yaml
yarn.lock
poetry.lock
.env.example
docker-compose.yml
Dockerfile
EOF
}

# 把一行归属记录规范成 TAB 分隔输出: 任务 分支 worktree 波次 端口 独占文件 状态
p_rows() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk -F'|' '
    /^[[:space:]]*\|/ {
      for (i = 2; i <= 8; i++) {
        v = $i
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        a[i - 1] = v
      }
      if (a[2] ~ /^-+$/ || a[2] == "分支" || a[2] == "") next
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", a[1], a[2], a[3], a[4], a[5], a[6], a[7]
    }
  ' "$file"
}

p_row_of_branch() {
  p_rows "$(p_ownership_path "$1")" | awk -F'\t' -v b="$2" '$2 == b { print; found = 1 } END { exit !found }'
}

# 列出除指定分支之外的 active 任务
p_other_active() {
  p_rows "$(p_ownership_path "$1")" | awk -F'\t' -v b="$2" '$2 != b && $7 == "active"'
}

p_used_ports() {
  p_rows "$(p_ownership_path "$1")" | awk -F'\t' '$7 == "active" && $5 ~ /^[0-9]+$/ { print $5 }'
}

# 归一化通配为作用域：去掉尾部 /** 或 /* 与多余斜杠
p_scope() {
  local s="$1"
  s="${s%/\*\*}"
  s="${s%/\*}"
  s="${s%/\*\*}"
  s="${s%/}"
  printf '%s\n' "$s"
}

# 文件是否落在通配作用域内。0=命中
# 支持: 精确路径 / 裸目录 / dir/** / dir/* / 尾部单层 glob(*.ts)
p_matches() {
  local f="$1" p="$2" s
  case "$p" in
    *'/**'|'*/\*')
      s="$(p_scope "$p")"
      [[ "${f#$s/}" != "$f" ]] && return 0
      return 1
      ;;
  esac
  case "$p" in
    *'*'*)
      # shellcheck disable=SC2254
      [[ "$f" == $p ]] && return 0
      return 1
      ;;
  esac
  [[ "$f" == "$p" || "${f#$p/}" != "$f" ]] && return 0
  return 1
}

p_file_in_patterns() {
  local f="$1" p
  shift
  for p in "$@"; do
    [ -n "$p" ] || continue
    p_matches "$f" "$p" && return 0
  done
  return 1
}

# 两组通配是否作用域冲突：相等、互为目录前缀、或单层 glob 与具体路径互相覆盖
# 注意：这是启发式判定，不支持取反与花括号展开，冲突时宁可窄不可宽
# echo 冲突对 "A<=>B"，每行一对
p_overlaps() {
  local a b as bs
  for a in $1; do
    for b in $2; do
      as="$(p_scope "$a")"
      bs="$(p_scope "$b")"
      if [ "$as" = "$bs" ]; then
        printf '%s<=>%s\n' "$a" "$b"
        continue
      fi
      if [[ "$a" == *'*'* && "$b" != *'*'* ]] && p_matches "$b" "$a"; then
        printf '%s<=>%s\n' "$a" "$b"
        continue
      fi
      if [[ "$b" == *'*'* && "$a" != *'*'* ]] && p_matches "$a" "$b"; then
        printf '%s<=>%s\n' "$a" "$b"
        continue
      fi
      [[ "${bs#$as/}" != "$bs" ]] && printf '%s<=>%s\n' "$a" "$b"
      [[ "${as#$bs/}" != "$as" ]] && printf '%s<=>%s\n' "$a" "$b"
    done
  done
}
