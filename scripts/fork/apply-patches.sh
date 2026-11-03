#!/usr/bin/env bash
#
# 把 patches/*.patch 按文件名顺序应用到当前工作区。
#
# 补丁是相对上游 tag 生成的, 每次上游发布新版本后由 fork 的发布流水线重新应用,
# 因此每个补丁都要尽量小、只改动最少几行, 让上游重构代码时仍然能应用。
# 上游改到同一处代码时这里会失败, 此时需要更新对应的补丁文件。
#
# 用法: bash scripts/fork/apply-patches.sh
#
# 注意: --3way 回退会读写 git 索引, 必须在 git 工作区内执行 (不能只在导出目录里跑)。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

shopt -s nullglob
patches=(patches/*.patch)
if [ ${#patches[@]} -eq 0 ]; then
    echo "没有找到 patches/*.patch, 无需应用"
    exit 0
fi

for patch in "${patches[@]}"; do
    echo "==> 应用 ${patch}"
    # 优先精确应用; 上游调整了邻近代码时退化为减少上下文匹配, 再退化为三方合并.
    if git apply --check "${patch}" 2>/dev/null; then
        git apply "${patch}"
    elif git apply --check -C1 --recount "${patch}" 2>/dev/null; then
        echo "    上下文有变动, 使用 -C1 应用"
        git apply -C1 --recount "${patch}"
    elif git apply --3way "${patch}" 2>/dev/null; then
        echo "    使用三方合并应用"
    else
        echo "::error::无法应用 ${patch}: 上游可能改动了同一处代码, 需要更新补丁"
        echo "----- 第一次尝试的输出 -----"
        git apply "${patch}" 2>&1 | head -20 || true
        echo "----- 补丁内容 -----"
        head -20 "${patch}" || true
        echo "--------------------------"
        echo "修复方式: 基于新的上游 tag 重新实现这处改动, 用 git diff 重新生成该补丁 (见 FORK.md)"
        exit 1
    fi
done

if git diff --quiet && git diff --cached --quiet; then
    echo "::error::补丁全部执行完毕但工作区没有任何改动, 补丁内容可能已失效"
    exit 1
fi

echo "==> 补丁应用完成"
git diff --stat
