#!/usr/bin/env bash
# =============================================================================
# Project Nomad - Godot 4.6 Double Precision + VoxelTools 빌드 스크립트
# =============================================================================
#
# 이 스크립트는 Godot 4.6을 double precision 모드로 빌드하고
# Zylann VoxelTools 모듈을 통합합니다.
#
# 사전 요구사항:
#   - Python 3.6+
#   - SCons 빌드 시스템 (pip install scons)
#   - C++ 컴파일러 (gcc/g++ 또는 clang)
#   - Git
#   - 약 10GB 디스크 여유공간
#
# 사용법:
#   chmod +x tools/build_double_precision.sh
#   ./tools/build_double_precision.sh [--jobs N]
#
# 참고:
#   - WSL2 환경에서 테스트됨
#   - 빌드 시간: 약 20-40분 (8코어 기준)
#   - 결과물은 godot-builds/ 디렉토리에 생성됨
# =============================================================================

set -euo pipefail

# --- 설정 ---
GODOT_VERSION="4.6-stable"
VOXELTOOLS_BRANCH="godot4.6"
BUILD_DIR="$(pwd)/godot-builds"
GODOT_SOURCE_DIR="${BUILD_DIR}/godot"
VOXEL_MODULE_DIR="${GODOT_SOURCE_DIR}/modules/voxel"
NUM_JOBS="${1:-$(nproc)}"

# jobs 인자 파싱
if [[ "${1:-}" == "--jobs" ]]; then
    NUM_JOBS="${2:-$(nproc)}"
fi

echo "============================================"
echo "Project Nomad - Godot Double Precision Build"
echo "============================================"
echo "Godot version:   ${GODOT_VERSION}"
echo "VoxelTools:      ${VOXELTOOLS_BRANCH}"
echo "Build jobs:      ${NUM_JOBS}"
echo "Build directory: ${BUILD_DIR}"
echo ""

# --- 의존성 확인 ---
echo "[1/6] 의존성 확인..."
MISSING_DEPS=()

command -v git    >/dev/null 2>&1 || MISSING_DEPS+=("git")
command -v scons  >/dev/null 2>&1 || MISSING_DEPS+=("scons (pip install scons)")
command -v g++    >/dev/null 2>&1 || MISSING_DEPS+=("g++")
command -v python3 >/dev/null 2>&1 || MISSING_DEPS+=("python3")

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo "ERROR: 다음 의존성이 누락되었습니다:"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - ${dep}"
    done
    echo ""
    echo "Ubuntu/Debian: sudo apt install build-essential scons pkg-config \\"
    echo "  libx11-dev libxcursor-dev libxinerama-dev libgl1-mesa-dev \\"
    echo "  libglu1-mesa-dev libasound2-dev libpulse-dev libdbus-1-dev \\"
    echo "  libudev-dev libxi-dev libxrandr-dev libwayland-dev"
    exit 1
fi
echo "  모든 의존성 확인 완료."

# --- Godot 소스 클론 ---
echo ""
echo "[2/6] Godot 소스 코드 준비..."
mkdir -p "${BUILD_DIR}"

if [[ -d "${GODOT_SOURCE_DIR}" ]]; then
    echo "  기존 소스 디렉토리 발견. 업데이트 중..."
    cd "${GODOT_SOURCE_DIR}"
    git fetch origin
    git checkout "${GODOT_VERSION}"
    git pull origin "${GODOT_VERSION}" || true
else
    echo "  Godot ${GODOT_VERSION} 클론 중..."
    git clone --depth 1 --branch "${GODOT_VERSION}" \
        https://github.com/godotengine/godot.git "${GODOT_SOURCE_DIR}"
fi

# --- VoxelTools 모듈 클론 ---
echo ""
echo "[3/6] VoxelTools 모듈 준비..."

if [[ -d "${VOXEL_MODULE_DIR}" ]]; then
    echo "  기존 VoxelTools 디렉토리 발견. 업데이트 중..."
    cd "${VOXEL_MODULE_DIR}"
    git fetch origin
    git checkout "${VOXELTOOLS_BRANCH}"
    git pull origin "${VOXELTOOLS_BRANCH}" || true
else
    echo "  VoxelTools 클론 중..."
    git clone --depth 1 --branch "${VOXELTOOLS_BRANCH}" \
        https://github.com/Zylann/godot_voxel.git "${VOXEL_MODULE_DIR}"
fi

# --- 에디터 빌드 (Double Precision) ---
echo ""
echo "[4/6] Godot 에디터 빌드 (double precision)..."
cd "${GODOT_SOURCE_DIR}"

scons \
    platform=linuxbsd \
    target=editor \
    precision=double \
    module_voxel_enabled=yes \
    use_llvm=no \
    linker=default \
    -j"${NUM_JOBS}"

# --- 내보내기 템플릿 빌드 (선택사항) ---
echo ""
echo "[5/6] 내보내기 템플릿 빌드 (debug + release)..."
echo "  (이 단계는 시간이 오래 걸립니다. 필요 없으면 Ctrl+C로 건너뛸 수 있습니다)"

# Debug 템플릿
scons \
    platform=linuxbsd \
    target=template_debug \
    precision=double \
    module_voxel_enabled=yes \
    -j"${NUM_JOBS}" || echo "  Debug 템플릿 빌드 실패 (선택사항이므로 계속 진행)"

# Release 템플릿
scons \
    platform=linuxbsd \
    target=template_release \
    precision=double \
    module_voxel_enabled=yes \
    -j"${NUM_JOBS}" || echo "  Release 템플릿 빌드 실패 (선택사항이므로 계속 진행)"

# --- 결과 정리 ---
echo ""
echo "[6/6] 빌드 결과 정리..."

EDITOR_BIN=$(find "${GODOT_SOURCE_DIR}/bin" -name "godot.linuxbsd.editor.double*" -type f | head -1)

if [[ -n "${EDITOR_BIN}" ]]; then
    echo ""
    echo "============================================"
    echo "빌드 성공!"
    echo "============================================"
    echo "에디터 바이너리: ${EDITOR_BIN}"
    echo ""
    echo "실행 방법:"
    echo "  ${EDITOR_BIN} --path $(pwd)/../project/"
    echo ""
    echo "별칭 설정 (선택):"
    echo "  alias godot-nomad='${EDITOR_BIN}'"
    echo ""
    echo "Windows에서 실행 (WSL2):"
    echo "  Windows 탐색기에서 .exe 파일을 직접 실행하세요."
    echo "  WSL 경로: \\\\wsl$\\Ubuntu$(dirname "${EDITOR_BIN}")"
else
    echo "WARNING: 에디터 바이너리를 찾을 수 없습니다."
    echo "bin/ 디렉토리를 직접 확인하세요:"
    ls -la "${GODOT_SOURCE_DIR}/bin/" 2>/dev/null || echo "  bin/ 디렉토리 없음"
    exit 1
fi
