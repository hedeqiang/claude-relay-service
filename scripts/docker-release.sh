#!/bin/bash

set -euo pipefail

# Claude Relay Service Docker 发布脚本
# 默认读取 VERSION 文件并推送：
#   <repo>:<version>
#   <repo>:latest

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_IMAGE_REPO="hedeqiang/claude-relay-service"
DEFAULT_PLATFORMS="linux/amd64,linux/arm64"
DEFAULT_BUILDER="crs-multiarch"

IMAGE_REPO="${IMAGE_REPO:-$DEFAULT_IMAGE_REPO}"
PLATFORMS="${PLATFORMS:-$DEFAULT_PLATFORMS}"
BUILDER="${DOCKER_BUILDER:-$DEFAULT_BUILDER}"
VERSION_OVERRIDE=""
PUSH_LATEST="true"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat <<EOF
用法: $(basename "$0") [选项]

选项:
  --version <ver>     指定版本号，默认读取 VERSION 文件
  --repo <repo>       指定镜像仓库，默认: ${DEFAULT_IMAGE_REPO}
  --platform <list>   指定平台，默认: ${DEFAULT_PLATFORMS}
  --builder <name>    指定 buildx builder，默认: ${DEFAULT_BUILDER}
  --no-latest         只推送版本标签，不推送 latest
  -h, --help          显示帮助

环境变量:
  IMAGE_REPO          覆盖默认镜像仓库
  PLATFORMS           覆盖默认平台列表
  DOCKER_BUILDER      覆盖默认 builder

示例:
  bash scripts/docker-release.sh
  bash scripts/docker-release.sh --version 1.1.298
  bash scripts/docker-release.sh --repo hedeqiang/claude-relay-service
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_error "缺少命令: $1"
        exit 1
    fi
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --version)
                VERSION_OVERRIDE="${2:-}"
                shift 2
                ;;
            --repo)
                IMAGE_REPO="${2:-}"
                shift 2
                ;;
            --platform)
                PLATFORMS="${2:-}"
                shift 2
                ;;
            --builder)
                BUILDER="${2:-}"
                shift 2
                ;;
            --no-latest)
                PUSH_LATEST="false"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "未知参数: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done
}

validate_args() {
    if [ -z "$IMAGE_REPO" ]; then
        print_error "镜像仓库不能为空"
        exit 1
    fi

    if [ -z "$PLATFORMS" ]; then
        print_error "平台列表不能为空"
        exit 1
    fi

    if [ -z "$BUILDER" ]; then
        print_error "builder 名称不能为空"
        exit 1
    fi
}

get_version() {
    if [ -n "$VERSION_OVERRIDE" ]; then
        echo "$VERSION_OVERRIDE"
        return 0
    fi

    if [ ! -f "${PROJECT_ROOT}/VERSION" ]; then
        print_error "VERSION 文件不存在: ${PROJECT_ROOT}/VERSION"
        exit 1
    fi

    local version
    version="$(tr -d '[:space:]' < "${PROJECT_ROOT}/VERSION")"

    if [ -z "$version" ]; then
        print_error "VERSION 文件为空"
        exit 1
    fi

    echo "$version"
}

ensure_builder() {
    if docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
        print_info "使用现有 buildx builder: ${BUILDER}"
    else
        print_warning "buildx builder ${BUILDER} 不存在，自动创建..."
        docker buildx create --name "$BUILDER" --driver docker-container --use >/dev/null
    fi

    docker buildx use "$BUILDER" >/dev/null
    docker buildx inspect "$BUILDER" --bootstrap >/dev/null
}

build_and_push() {
    local version="$1"
    local tags=("-t" "${IMAGE_REPO}:${version}")

    if [ "$PUSH_LATEST" = "true" ]; then
        tags+=("-t" "${IMAGE_REPO}:latest")
    fi

    print_info "项目目录: ${PROJECT_ROOT}"
    print_info "镜像仓库: ${IMAGE_REPO}"
    print_info "版本标签: ${version}"
    print_info "平台列表: ${PLATFORMS}"
    print_info "Builder: ${BUILDER}"

    if [ "$PUSH_LATEST" = "true" ]; then
        print_info "附加标签: latest"
    fi

    docker buildx build \
        --builder "$BUILDER" \
        --platform "$PLATFORMS" \
        --progress=plain \
        "${tags[@]}" \
        --push \
        "$PROJECT_ROOT"
}

verify_remote() {
    local version="$1"

    print_info "验证远端标签: ${IMAGE_REPO}:${version}"
    docker buildx imagetools inspect "${IMAGE_REPO}:${version}"

    if [ "$PUSH_LATEST" = "true" ]; then
        print_info "验证远端标签: ${IMAGE_REPO}:latest"
        docker buildx imagetools inspect "${IMAGE_REPO}:latest"
    fi
}

main() {
    parse_args "$@"
    validate_args

    require_command docker

    local version
    version="$(get_version)"

    ensure_builder
    build_and_push "$version"
    verify_remote "$version"

    print_success "Docker 镜像构建并推送完成"
    print_success "版本标签: ${IMAGE_REPO}:${version}"

    if [ "$PUSH_LATEST" = "true" ]; then
        print_success "最新标签: ${IMAGE_REPO}:latest"
    fi
}

main "$@"
