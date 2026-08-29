#!/bin/bash
# =============================================================================
# GitHub 仓库初始化与发布脚本 - Xiaomi Pad 8 Pro
#
# 用法:
#   ./setup-github.sh init          # 初始化并推送
#   ./setup-github.sh release v0.1  # 打 tag 触发 Release
#   ./setup-github.sh status        # 查看 Actions 状态
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPO_NAME="${REPO_NAME:-xiaomi-pad8pro-linux}"
DEFAULT_BRANCH="main"

do_init() {
    info "=== 初始化 GitHub 仓库 ==="
    command -v git &>/dev/null || error "git 未安装"

    if [ ! -d ".git" ]; then
        git init
        git checkout -b "$DEFAULT_BRANCH"
        ok "Git 仓库已初始化"
    fi

    git add -A
    git status --short

    if ! git log --oneline -1 &>/dev/null; then
        git commit -m "Initial commit: Linux for Xiaomi Pad 8 Pro (piano / SM8750)

- Device configuration (device/)
- Kernel config fragment (device/kernel.config.fragment)
- Kernel config (device/sm8750.config)
- Device tree (dt/sm8750-piano.dts)
- Firmware (firmware/)
- Build scripts (scripts/)
- CI/CD workflows (.github/workflows/)
- DTB extraction script (extract-dtb.sh)
- Documentation (docs/)"
        ok "首次提交完成"
    fi

    if command -v gh &>/dev/null && gh auth status &>/dev/null; then
        if ! gh repo view "$REPO_NAME" &>/dev/null; then
            gh repo create "$REPO_NAME" --public \
                --description "Linux for Xiaomi Pad 8 Pro (piano / SM8750)" \
                --source=. --remote=origin --push
            ok "仓库已创建并推送"
        else
            git remote add origin "https://github.com/$(gh api user --jq .login)/$REPO_NAME.git" 2>/dev/null || true
            git push -u origin "$DEFAULT_BRANCH"
            ok "代码已推送"
        fi
    else
        warn "gh CLI 未登录，请手动创建仓库并推送："
        echo "  git remote add origin https://github.com/<user>/$REPO_NAME.git"
        echo "  git push -u origin $DEFAULT_BRANCH"
    fi

    echo ""
    ok "初始化完成！下一步："
    echo "  1. 确认 Actions 已触发"
    echo "  2. 打 tag 发布: ./setup-github.sh release v0.1.0"
}

do_release() {
    local version="${1:-}"
    [ -z "$version" ] && error "请指定版本号: ./setup-github.sh release v0.1.0"
    [[ ! "$version" =~ ^v ]] && version="v$version"

    info "=== 发布 $version ==="

    if [ -n "$(git status --porcelain)" ]; then
        git add -A
        git commit -m "Prepare release $version" || true
    fi

    git tag -l | grep -q "^$version$" && error "Tag $version 已存在"

    git tag -a "$version" -m "Release $version - Linux for Xiaomi Pad 8 Pro"
    git push origin "$DEFAULT_BRANCH"
    git push origin "$version"
    ok "Tag $version 已推送，Actions 将自动构建 Release"
}

do_status() {
    info "=== GitHub Actions 状态 ==="
    if command -v gh &>/dev/null && gh auth status &>/dev/null; then
        gh run list --limit 10
    else
        warn "需要 gh CLI，请手动访问 Actions 页面"
    fi
}

main() {
    local cmd="${1:-help}"
    shift || true
    case "$cmd" in
        init)       do_init "$@" ;;
        release)    do_release "$@" ;;
        status)     do_status "$@" ;;
        help|-h|--help)
            echo "用法: $0 {init|release <version>|status}" ;;
        *)          error "未知命令: $cmd" ;;
    esac
}

main "$@"
