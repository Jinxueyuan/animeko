#!/usr/bin/env bash
#
# 一次性设置: 在 fork 仓库里停用上游自带的 workflow。
#
# 上游的 Build / Release 等流水线依赖大量只有上游才有的密钥 (Apple 签名、AWS、Firebase),
# 在 fork 里运行只会长时间失败; Release 还会被 tag 推送触发。本仓库自己的发布由
# `Fork Android Release` 负责, 所以这里把上游那几条停用掉。
#
# 用法: bash scripts/fork/disable-upstream-workflows.sh [owner/repo]
# 需要已登录的 gh (gh auth login)。
set -euo pipefail

repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
echo "目标仓库: ${repo}"

workflows=(
    'Build'
    'Release'
    'Codex Agent'
    'PR Images'
    'Build ani_update'
    'Build datasource-test-mcp'
)

for name in "${workflows[@]}"; do
    if gh workflow disable "$name" --repo "$repo" 2>/dev/null; then
        echo "  已停用: ${name}"
    else
        echo "  跳过 (不存在或已停用): ${name}"
    fi
done

echo
echo "当前 workflow 状态:"
gh workflow list --repo "$repo" --all
