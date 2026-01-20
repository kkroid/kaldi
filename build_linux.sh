#!/usr/bin/env bash

# Linux 本地构建脚本（使用本仓库的 submodule 依赖）
# 参考：Dockerfile.linux 与 build_windows_mingw.sh 的结构
# 目标：
#  - 构建并安装依赖：OpenBLAS, CLAPACK, OpenFST 到本地临时前缀
#  - 使用这些依赖编译 Kaldi (shared + static)，构建 online2 与 rnnlm
#  - 安装 Kaldi 的库、头文件、可执行文件到本地可重定位的安装目录

set -euo pipefail

echo "=========================================="
echo "Kaldi Linux 本地构建脚本"
echo "=========================================="

#-----------------------------
# 解析命令行参数
#-----------------------------
CLEAN_DEPS=false
CLEAN_ALL=false
SKIP_DEPS=false
SKIP_KALDI=false
SKIP_BINARIES=false
JOBS="$(nproc || echo 4)"

while [[ $# -gt 0 ]]; do
  case $1 in
    -j|--jobs)
      JOBS="${2:-$JOBS}"; shift 2;;
    -j[0-9]*)
      JOBS="${1#-j}"; shift;;
    --jobs=*)
      JOBS="${1#--jobs=}"; shift;;
    --clean-deps)
      CLEAN_DEPS=true; shift;;
    --clean-all)
      CLEAN_ALL=true; CLEAN_DEPS=true; shift;;
    --skip-deps)
      SKIP_DEPS=true; shift;;
    --skip-kaldi)
      SKIP_KALDI=true; shift;;
    --skip-binaries)
      SKIP_BINARIES=true; shift;;
    -h|--help)
    cat <<EOF
使用方法: $0 [选项]
选项:
  -j N | -jN | --jobs N | --jobs=N  并行编译任务数 (默认: nproc)
  --clean-deps        清理依赖编译/安装目录（重新编译依赖）
  --clean-all         完全清理（依赖与 Kaldi 全部重来）
  --skip-deps         跳过依赖编译
  --skip-kaldi        跳过 Kaldi 编译
  --skip-binaries     跳过可执行文件安装
  -h, --help          显示本帮助
默认行为: 若依赖已存在则复用，仅重新编译 Kaldi。
EOF
      exit 0;;
    *)
      echo "未知选项: $1"; exit 1;;
  esac
done

#-----------------------------
# 路径与目录布局
#-----------------------------
# PROJECT_ROOT=$(pwd)
PROJECT_ROOT=/home/kkroid/github/kaldi-vosk
DEPS_BUILD_DIR=".build_deps"
KALDI_INSTALL_DIR=".install_linux"
DEPS_PREFIX="$PROJECT_ROOT/$DEPS_BUILD_DIR"
KALDI_PREFIX="$PROJECT_ROOT/$KALDI_INSTALL_DIR"

# 子模块路径
OPENBLAS_DIR="$PROJECT_ROOT/external/openblas"
CLAPACK_DIR="$PROJECT_ROOT/external/clapack"
OPENFST_DIR="$PROJECT_ROOT/external/openfst"
KALDI_SRC_DIR="$PROJECT_ROOT/src"

#-----------------------------
# 先验检查
#-----------------------------
need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1"; return 1
  fi
}

MISSING=()
for c in gcc g++ make cmake autoreconf libtool pkg-config; do
  need_cmd "$c" || MISSING+=("$c")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "错误: 需要以下构建工具，但未找到: ${MISSING[*]}"
  echo "提示(基于 Debian/Ubuntu): sudo apt update && sudo apt install -y build-essential autoconf automake libtool cmake pkg-config"
  exit 1
fi

# 规范化工具链：强制使用本机 gcc/g++，避免误用 MinGW 交叉编译器
# 在 set -u 下不要直接引用未设置变量
_CXX_PATH=""
if [[ -n "${CXX:-}" ]]; then
  _CXX_PATH=$(command -v "$CXX" 2>/dev/null || true)
fi
if [[ -z "$_CXX_PATH" ]]; then
  _CXX_PATH=$(command -v g++ 2>/dev/null || command -v c++ 2>/dev/null || true)
fi
if [[ "$_CXX_PATH" == *mingw* || "$_CXX_PATH" == *w64* ]]; then
  echo "检测到 MinGW 交叉编译器 ($_CXX_PATH)，改用系统 g++/gcc"
  export CC=gcc
  export CXX=g++
else
  export CC=${CC:-gcc}
  export CXX=${CXX:-g++}
fi
export AR=${AR:-ar}
export RANLIB=${RANLIB:-ranlib}
export LD=${LD:-ld}
echo "使用编译器: CC=$(command -v "$CC" 2>/dev/null) CXX=$(command -v "$CXX" 2>/dev/null)"

# 子模块存在性检查
for d in "$OPENBLAS_DIR" "$CLAPACK_DIR" "$OPENFST_DIR"; do
  if [[ ! -d "$d" ]]; then
    echo "错误: 未找到子模块目录: $d"
    echo "请先初始化子模块: git submodule update --init --recursive"
    exit 1
  fi
done

#-----------------------------
# 清理
#-----------------------------
echo "=========================================="
echo "0. 清理"
echo "=========================================="

rm -rf "$KALDI_PREFIX"
if [[ "$CLEAN_DEPS" == true ]]; then
  echo "清理依赖目录: $DEPS_PREFIX"
  rm -rf "$DEPS_PREFIX"
else
  echo "保留依赖目录 (使用 --clean-deps 可强制重新编译依赖)"
fi

if [[ "$CLEAN_ALL" == true ]]; then
  echo "清理 Kaldi 源码内的编译产物"
  (cd "$KALDI_SRC_DIR" && make clean || true)
fi

#-----------------------------
# 目录结构
#-----------------------------
echo "创建目录结构..."
mkdir -p "$DEPS_PREFIX"/{lib,include,bin}
mkdir -p "$KALDI_PREFIX"/{lib/static,lib/deps,lib/dynamic,include/kaldi,include/deps,bin,cmake}

echo "目录说明:"
echo "  - 依赖前缀: $DEPS_PREFIX"
echo "  - 安装前缀: $KALDI_PREFIX"

#-----------------------------
# 检查依赖是否已编译
#-----------------------------
OPENFST_EXISTS=false
OPENBLAS_EXISTS=false
CLAPACK_EXISTS=false

[[ -f "$DEPS_PREFIX/lib/libfst.a" || -f "$DEPS_PREFIX/lib/libfst.so" ]] && OPENFST_EXISTS=true && echo "✓ 发现 OpenFST"
[[ -f "$DEPS_PREFIX/lib/libopenblas.a" || -f "$DEPS_PREFIX/lib/libopenblas.so" ]] && OPENBLAS_EXISTS=true && echo "✓ 发现 OpenBLAS"
[[ -f "$DEPS_PREFIX/lib/liblapack.a" && -f "$DEPS_PREFIX/lib/libblas.a" ]] && CLAPACK_EXISTS=true && echo "✓ 发现 CLAPACK"

#-----------------------------
# 1. 构建 OpenFST
#-----------------------------
echo "=========================================="
echo "1. 构建 OpenFST"
echo "=========================================="
if [[ "$SKIP_DEPS" == true ]]; then
  echo "跳过依赖编译 (--skip-deps)"
elif [[ "$OPENFST_EXISTS" == true && "$CLEAN_DEPS" == false ]]; then
  echo "跳过 OpenFST (已存在)"
else
  pushd "$OPENFST_DIR" >/dev/null
  # 强制清理 OpenFST 构建目录
  echo "清理 OpenFST 构建目录..."
  make distclean || true

  echo "运行 autoreconf..."
  autoreconf -i

  echo "配置 OpenFST..."
  CFLAGS="-O3 -ftree-vectorize" ./configure \
    --prefix="$DEPS_PREFIX" \
    --enable-static \
    --enable-shared \
    --enable-far \
    --enable-ngram-fsts \
    --enable-lookahead-fsts \
    --with-pic \
    --disable-bin

  echo "编译 OpenFST (禁用并行)..."
  make

  echo "安装 OpenFST..."
  make install
  popd >/dev/null
fi

#-----------------------------
# 2. 构建 OpenBLAS
#-----------------------------
echo "=========================================="
echo "2. 构建 OpenBLAS"
echo "=========================================="
if [[ "$OPENBLAS_EXISTS" == true && "$CLEAN_DEPS" == false ]]; then
  echo "跳过 OpenBLAS (已存在)"
else
  pushd "$OPENBLAS_DIR" >/dev/null
  echo "编译 OpenBLAS..."
  make ONLY_CBLAS=1 DYNAMIC_ARCH=1 TARGET=NEHALEM USE_LOCKING=1 USE_THREAD=0 -j"$JOBS"
  echo "安装 OpenBLAS..."
  make PREFIX="$DEPS_PREFIX" install
  popd >/dev/null
fi

#-----------------------------
# 3. 构建 CLAPACK
#-----------------------------
echo "=========================================="
echo "3. 构建 CLAPACK"
echo "=========================================="
if [[ "$CLAPACK_EXISTS" == true && "$CLEAN_DEPS" == false ]]; then
  echo "跳过 CLAPACK (已存在)"
else
  pushd "$CLAPACK_DIR" >/dev/null
  # 仅构建必要静态库，跳过测试可执行文件，避免链接冲突
  rm -rf BUILD && mkdir -p BUILD && cd BUILD
  echo "配置 CLAPACK (生成 Makefile 但不构建测试)..."
  cmake ..
  echo "编译 libf2c/BLAS/LAPACK 源码..."
  make -C F2CLIBS/libf2c -j"$JOBS"
  make -C BLAS -j"$JOBS"
  make -C SRC -j"$JOBS"
  echo "安装 CLAPACK 归档库到依赖前缀..."
  find F2CLIBS/libf2c BLAS SRC -name "*.a" -exec cp -v {} "$DEPS_PREFIX/lib/" \;
  popd >/dev/null
fi

#-----------------------------
# 4. 构建 Kaldi
#-----------------------------
echo "=========================================="
echo "4. 构建 Kaldi"
echo "=========================================="
if [[ "$SKIP_KALDI" == true ]]; then
  echo "跳过 Kaldi 编译 (--skip-kaldi)"
else
  pushd "$KALDI_SRC_DIR" >/dev/null
  echo "配置 Kaldi..."
  # 先清理，避免混入其他平台的 .o
  make clean || true
  CXXFLAGS="-O3 -ftree-vectorize" CC="$CC" CXX="$CXX" ./configure \
    --mathlib=OPENBLAS_CLAPACK \
    --shared \
    --use-cuda=no \
  --openblas-clapack-root="$DEPS_PREFIX" \
  --fst-root="$DEPS_PREFIX" \
  --fst-version=1.8.0

  # 升级优化等级（对旧默认 -O1 情况）
  if [[ -f kaldi.mk ]]; then
    sed -i 's/ -O1 / -O3 /g' kaldi.mk || true
  fi

  echo "生成依赖..."
  make depend -j"$JOBS" || true

  echo "编译 online2 与 rnnlm..."
  make -j"$JOBS" online2 rnnlm CC="$CC" CXX="$CXX"
  popd >/dev/null
fi

#-----------------------------
# 5. 安装 Kaldi 到本地前缀
#-----------------------------
echo "=========================================="
echo "5. 安装 Kaldi 到 $KALDI_PREFIX"
echo "=========================================="
# 静态与动态库
echo "安装 Kaldi 静态库 (*.a)..."Single Navy reception. Go home charging. Purchase on the air. Hey, Cortana. Can I heard you a boy? Go home catching. Go home chatting. Wrong. Hey, Cortana. Hey, Cortana Mobile. I. Her chest only had an email and. At all young, I feel wrong. OK so take. I. Hey, Cortana. Hey, Cortana. I. Hey, Cortana. OK, yeah. 
find "$KALDI_SRC_DIR" -maxdepth 2 -name "kaldi-*.a" -print0 2>/dev/null | while IFS= read -r -d '' lib; do
  base=$(basename "$lib")
  cp -v "$lib" "$KALDI_PREFIX/lib/static/lib$base"
done
echo "安装 Kaldi 动态库 (*.so)..."
find "$KALDI_SRC_DIR" -maxdepth 2 -name "libkaldi-*.so*" -print0 2>/dev/null | while IFS= read -r -d '' so; do
  cp -v "$so" "$KALDI_PREFIX/lib/dynamic/"
done

# 依赖库
echo "安装依赖库到 $KALDI_PREFIX/lib/deps ..."
for lib in libopenblas.so libopenblas.a liblapack.a libblas.a libf2c.a; do
  if [[ -f "$DEPS_PREFIX/lib/$lib" ]]; then
    cp -v "$DEPS_PREFIX/lib/$lib" "$KALDI_PREFIX/lib/deps/"
  fi
done
for lib in libfst.so libfst.a libfstlookahead.* libfstngram.*; do
  if compgen -G "$DEPS_PREFIX/lib/$lib" >/dev/null; then
    cp -v $DEPS_PREFIX/lib/$lib "$KALDI_PREFIX/lib/deps/" || true
  fi
done

# 头文件
echo "安装 Kaldi 头文件..."
for dir in base util itf matrix feat transform gmm tree hmm lat decoder fstext lm \
           nnet nnet2 nnet3 rnnlm chain cudamatrix ivector online2; do
  if [[ -d "$KALDI_SRC_DIR/$dir" ]]; then
    mkdir -p "$KALDI_PREFIX/include/kaldi/$dir"
    find "$KALDI_SRC_DIR/$dir" -name "*.h" -exec cp {} "$KALDI_PREFIX/include/kaldi/$dir/" \;
  fi
done

echo "安装依赖头文件 (OpenFST 等)..."
if [[ -d "$DEPS_PREFIX/include/fst" ]]; then
  mkdir -p "$KALDI_PREFIX/include/deps"
  cp -r "$DEPS_PREFIX/include/fst" "$KALDI_PREFIX/include/deps/"
fi
find "$DEPS_PREFIX/include" -maxdepth 1 -name "*.h" -exec cp {} "$KALDI_PREFIX/include/deps/" \; 2>/dev/null || true

# 可执行文件
if [[ "$SKIP_BINARIES" == true ]]; then
  echo "跳过可执行文件安装 (--skip-binaries)"
else
  echo "安装 Kaldi 可执行文件..."
  find "$KALDI_SRC_DIR" -type d -name "*bin" | while read -r bindir; do
    find "$bindir" -maxdepth 1 -type f -executable \
      ! -name "*.cc" ! -name "*.h" ! -name "Makefile*" ! -name "CMake*" \
      -exec cp -v {} "$KALDI_PREFIX/bin/" \; 2>/dev/null || true
  done
fi

#-----------------------------
# 6. 生成 CMake 配置
#-----------------------------
echo "创建 CMake 配置..."
cat > "$KALDI_PREFIX/cmake/KaldiConfig.cmake" << 'EOF'
# Kaldi CMake Configuration File (Linux)
get_filename_component(KALDI_CMAKE_DIR "${CMAKE_CURRENT_LIST_FILE}" PATH)
get_filename_component(KALDI_ROOT "${KALDI_CMAKE_DIR}/.." ABSOLUTE)

set(KALDI_INCLUDE_DIRS
  ${KALDI_ROOT}/include/kaldi
  ${KALDI_ROOT}/include/deps
)
set(KALDI_LIBRARY_DIRS ${KALDI_ROOT}/lib)

set(KALDI_LIBRARIES
  # Link order: high-level first -> base/util last (for static libs)
  kaldi-online2 kaldi-ivector kaldi-nnet3 kaldi-chain kaldi-nnet2
  kaldi-decoder kaldi-lat kaldi-hmm kaldi-tree kaldi-gmm
  kaldi-transform kaldi-feat kaldi-fstext kaldi-lm kaldi-rnnlm
  kaldi-matrix kaldi-util kaldi-base
)
set(KALDI_DEPENDENCIES fst openblas lapack blas f2c)

unset(KALDI_LIBS)
foreach(lib ${KALDI_LIBRARIES})
  find_library(${lib}_STATIC NAMES ${lib} PATHS ${KALDI_LIBRARY_DIRS}/kaldi NO_DEFAULT_PATH)
  if(${lib}_STATIC)
    list(APPEND KALDI_LIBS ${${lib}_STATIC})
  endif()
endforeach()

unset(KALDI_DEPENDENCY_LIBS)
foreach(dep ${KALDI_DEPENDENCIES})
  find_library(${dep}_LIB NAMES ${dep} lib${dep} PATHS ${KALDI_LIBRARY_DIRS}/deps NO_DEFAULT_PATH)
  if(${dep}_LIB)
    list(APPEND KALDI_DEPENDENCY_LIBS ${${dep}_LIB})
  endif()
endforeach()

set(KALDI_ALL_LIBRARIES ${KALDI_LIBS} ${KALDI_DEPENDENCY_LIBS})
set(Kaldi_FOUND TRUE)
EOF

#-----------------------------
# 7. 统计与说明
#-----------------------------
KALDI_A=$(find "$KALDI_PREFIX/lib/static" -name "*.a" 2>/dev/null | wc -l)
KALDI_SO=$(find "$KALDI_PREFIX/lib/dynamic" -name "*.so*" 2>/dev/null | wc -l)
DEP_LIBS=$(find "$KALDI_PREFIX/lib/deps" -name "*.a" -o -name "*.so*" 2>/dev/null | wc -l)
BINS=$(find "$KALDI_PREFIX/bin" -type f 2>/dev/null | wc -l)
HEADERS=$(find "$KALDI_PREFIX/include" -name "*.h" 2>/dev/null | wc -l)

echo "安装统计:"
echo "  - Kaldi 静态库: $KALDI_A 个"
echo "  - Kaldi 动态库: $KALDI_SO 个"
echo "  - 依赖库: $DEP_LIBS 个"
echo "  - 可执行文件: $BINS 个"
echo "  - 头文件: $HEADERS 个"

if command -v du >/dev/null 2>&1; then
  echo "目录大小: $(du -sh "$KALDI_PREFIX" | cut -f1)"
fi

echo "使用方法:"
echo "1) CMake 项目 (推荐):"
echo "   list(APPEND CMAKE_MODULE_PATH \"$KALDI_PREFIX/cmake\")"
echo "   find_package(Kaldi REQUIRED)"
echo "   target_link_libraries(your_target PRIVATE \${KALDI_ALL_LIBRARIES} pthread dl)"
echo ""
echo "提示:"
echo "  - 使用 $0 --clean-deps 重新编译所有依赖"
echo "  - 使用 $0 --clean-all 彻底清理并重建"
echo "  - 使用 -j N 控制并行任务数"

# 清理中间 .o（可选）
find "$PROJECT_ROOT" -name "*.o" -type f -delete 2>/dev/null || true

echo "=========================================="
echo "Kaldi Linux 本地构建完成"
echo "安装前缀: $KALDI_PREFIX"
echo "=========================================="
