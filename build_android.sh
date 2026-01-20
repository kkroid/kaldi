#!/usr/bin/env bash

# Android 交叉编译脚本（使用本仓库的 submodule 依赖）
# 参考：build_linux.sh 与 build_windows_mingw.sh 的结构
# 目标：
#  - 使用 Android NDK 工具链交叉编译依赖：OpenBLAS, CLAPACK, OpenFST
#  - 使用这些依赖编译 Kaldi (shared + static)，构建 online2 与 rnnlm
#  - 安装 Kaldi 的库、头文件到本地可重定位的安装目录
#
# 目标架构: arm64-v8a (64位 ARM)

set -euo pipefail

echo "=========================================="
echo "Kaldi Android 交叉编译脚本 (arm64-v8a)"
echo "=========================================="

#-----------------------------
# 解析命令行参数
#-----------------------------
CLEAN_DEPS=false
CLEAN_ALL=false
SKIP_DEPS=false
SKIP_KALDI=false
SKIP_BINARIES=true  # Android 默认跳过可执行文件
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# Android NDK 配置
ANDROID_NDK="${ANDROID_NDK:-${ANDROID_NDK_HOME:-${NDK_ROOT:-}}}"
ANDROID_API=21

while [[ $# -gt 0 ]]; do
  case $1 in
    -j|--jobs)
      JOBS="${2:-$JOBS}"; shift 2;;
    -j[0-9]*)
      JOBS="${1#-j}"; shift;;
    --jobs=*)
      JOBS="${1#--jobs=}"; shift;;
    --ndk=*)
      ANDROID_NDK="${1#--ndk=}"; shift;;
    --api=*)
      ANDROID_API="${1#--api=}"; shift;;
    --clean-deps)
      CLEAN_DEPS=true; shift;;
    --clean-all)
      CLEAN_ALL=true; CLEAN_DEPS=true; shift;;
    --skip-deps)
      SKIP_DEPS=true; shift;;
    --skip-kaldi)
      SKIP_KALDI=true; shift;;
    --with-binaries)
      SKIP_BINARIES=false; shift;;
    -h|--help)
    cat <<EOF
使用方法: $0 [选项]

Android NDK 选项:
  --ndk=PATH            Android NDK 路径 (也可设置 ANDROID_NDK 环境变量)
  --api=LEVEL           Android API 级别 (默认: 21)

编译选项:
  -j N | -jN | --jobs N | --jobs=N  并行编译任务数 (默认: nproc)
  --clean-deps          清理依赖编译/安装目录（重新编译依赖）
  --clean-all           完全清理（依赖与 Kaldi 全部重来）
  --skip-deps           跳过依赖编译
  --skip-kaldi          跳过 Kaldi 编译
  --with-binaries       编译可执行文件（默认跳过）
  -h, --help            显示本帮助

示例:
  $0 --ndk=/path/to/ndk
  ANDROID_NDK=/path/to/ndk $0

默认行为: 若依赖已存在则复用，仅重新编译 Kaldi。
EOF
      exit 0;;
    *)
      echo "未知选项: $1"; exit 1;;
  esac
done

#-----------------------------
# 验证 Android NDK
#-----------------------------
if [[ -z "$ANDROID_NDK" ]]; then
  echo "错误: 未找到 Android NDK"
  echo ""
  echo "请通过以下方式之一指定 NDK 路径:"
  echo "  1. 设置环境变量: export ANDROID_NDK=/path/to/ndk"
  echo "  2. 使用命令行参数: $0 --ndk=/path/to/ndk"
  echo ""
  echo "Android NDK 可从以下位置下载:"
  echo "  https://developer.android.com/ndk/downloads"
  exit 1
fi

if [[ ! -d "$ANDROID_NDK" ]]; then
  echo "错误: NDK 目录不存在: $ANDROID_NDK"
  exit 1
fi

# 检测 NDK 版本和工具链
if [[ -f "$ANDROID_NDK/source.properties" ]]; then
  NDK_VERSION=$(grep "Pkg.Revision" "$ANDROID_NDK/source.properties" | cut -d'=' -f2 | tr -d ' ')
  echo "✓ Android NDK 版本: $NDK_VERSION"
else
  echo "警告: 无法检测 NDK 版本"
fi

# 设置工具链路径 (NDK r19+ 使用统一工具链)
TOOLCHAIN="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64"
if [[ ! -d "$TOOLCHAIN" ]]; then
  # 尝试其他平台
  for platform in darwin-x86_64 windows-x86_64; do
    if [[ -d "$ANDROID_NDK/toolchains/llvm/prebuilt/$platform" ]]; then
      TOOLCHAIN="$ANDROID_NDK/toolchains/llvm/prebuilt/$platform"
      break
    fi
  done
fi

if [[ ! -d "$TOOLCHAIN" ]]; then
  echo "错误: 未找到 LLVM 工具链，请确保使用 NDK r19 或更高版本"
  exit 1
fi

echo "✓ 工具链路径: $TOOLCHAIN"

#-----------------------------
# arm64-v8a 编译参数
#-----------------------------
ANDROID_ABI="arm64-v8a"
TARGET_TRIPLE="aarch64-linux-android"
ARCH="arm64"
OPENBLAS_TARGET="ARMV8"

echo "目标架构: $ANDROID_ABI ($TARGET_TRIPLE)"
echo "API 级别: $ANDROID_API"

# 设置编译器
CC="$TOOLCHAIN/bin/${TARGET_TRIPLE}${ANDROID_API}-clang"
CXX="$TOOLCHAIN/bin/${TARGET_TRIPLE}${ANDROID_API}-clang++"
AR="$TOOLCHAIN/bin/llvm-ar"
RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
STRIP="$TOOLCHAIN/bin/llvm-strip"

# 验证编译器
if [[ ! -x "$CC" ]]; then
  echo "错误: 未找到 C 编译器: $CC"
  exit 1
fi
if [[ ! -x "$CXX" ]]; then
  echo "错误: 未找到 C++ 编译器: $CXX"
  exit 1
fi

echo "✓ C 编译器: $CC"
echo "✓ C++ 编译器: $CXX"

# Android sysroot
SYSROOT="$TOOLCHAIN/sysroot"
ANDROID_INCDIR="$SYSROOT/usr/include"

#-----------------------------
# 路径与目录布局
#-----------------------------
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_BUILD_DIR=".build_deps_android"
KALDI_INSTALL_DIR=".install_android"
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
for c in make cmake autoreconf libtool; do
  need_cmd "$c" || MISSING+=("$c")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "错误: 需要以下构建工具，但未找到: ${MISSING[*]}"
  echo "提示(基于 Debian/Ubuntu): sudo apt update && sudo apt install -y build-essential autoconf automake libtool cmake"
  exit 1
fi

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
mkdir -p "$KALDI_PREFIX"/{lib/static,lib/deps,lib/shared,include/kaldi,include/deps,jniLibs/arm64-v8a}

echo "目录说明:"
echo "  - 依赖前缀: $DEPS_PREFIX"
echo "  - 安装前缀: $KALDI_PREFIX"

#-----------------------------
# 检查依赖是否已编译
#-----------------------------
OPENFST_EXISTS=false
OPENBLAS_EXISTS=false
CLAPACK_EXISTS=false

[[ -f "$DEPS_PREFIX/lib/libfst.a" ]] && OPENFST_EXISTS=true && echo "✓ 发现 OpenFST"
[[ -f "$DEPS_PREFIX/lib/libopenblas.a" ]] && OPENBLAS_EXISTS=true && echo "✓ 发现 OpenBLAS"
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
  make distclean 2>/dev/null || true

  echo "运行 autoreconf..."
  autoreconf -i

  echo "配置 OpenFST..."
  CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
  CFLAGS="-O3 -fPIC -DFST_NO_DYNAMIC_LINKING" \
  CXXFLAGS="-O3 -fPIC -std=c++17 -DFST_NO_DYNAMIC_LINKING" \
  ./configure \
    --prefix="$DEPS_PREFIX" \
    --host="$TARGET_TRIPLE" \
    --enable-static \
    --disable-shared \
    --enable-far \
    --enable-ngram-fsts \
    --enable-lookahead-fsts \
    --with-pic \
    --disable-bin

  echo "编译 OpenFST..."
  make -j"$JOBS"

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
if [[ "$SKIP_DEPS" == true ]]; then
  echo "跳过依赖编译 (--skip-deps)"
elif [[ "$OPENBLAS_EXISTS" == true && "$CLEAN_DEPS" == false ]]; then
  echo "跳过 OpenBLAS (已存在)"
else
  pushd "$OPENBLAS_DIR" >/dev/null
  
  # 清理之前的构建
  make clean 2>/dev/null || true
  
  echo "编译 OpenBLAS for Android ($ANDROID_ABI)..."
  
  # OpenBLAS Android 编译参数
  make \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    HOSTCC=gcc \
    TARGET="$OPENBLAS_TARGET" \
    ONLY_CBLAS=1 \
    NO_LAPACK=1 \
    NO_LAPACKE=1 \
    NO_FORTRAN=1 \
    USE_THREAD=0 \
    USE_OPENMP=0 \
    NO_SHARED=1 \
    -j"$JOBS"

  echo "安装 OpenBLAS..."
  make PREFIX="$DEPS_PREFIX" NO_SHARED=1 install
  popd >/dev/null
fi

#-----------------------------
# 3. 构建 CLAPACK
#-----------------------------
echo "=========================================="
echo "3. 构建 CLAPACK"
echo "=========================================="
if [[ "$SKIP_DEPS" == true ]]; then
  echo "跳过依赖编译 (--skip-deps)"
elif [[ "$CLAPACK_EXISTS" == true && "$CLEAN_DEPS" == false ]]; then
  echo "跳过 CLAPACK (已存在)"
else
  pushd "$CLAPACK_DIR" >/dev/null
  
  rm -rf BUILD && mkdir -p BUILD && cd BUILD
  
  echo "配置 CLAPACK for Android..."
  cmake \
    -DCMAKE_SYSTEM_NAME=Android \
    -DCMAKE_SYSTEM_VERSION="$ANDROID_API" \
    -DCMAKE_ANDROID_ARCH_ABI="$ANDROID_ABI" \
    -DCMAKE_ANDROID_NDK="$ANDROID_NDK" \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_C_FLAGS="-fPIC" \
    -DCMAKE_CROSSCOMPILING=True \
    ..

  echo "编译 CLAPACK..."
  make -C F2CLIBS/libf2c -j"$JOBS"
  make -C BLAS -j"$JOBS"
  make -C SRC -j"$JOBS"
  
  echo "安装 CLAPACK..."
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
  
  echo "清理之前的编译..."
  make clean 2>/dev/null || true
  
  echo "配置 Kaldi for Android..."
  CXX="$CXX" \
  CXXFLAGS="-O3 -fPIC -DFST_NO_DYNAMIC_LINKING -DANDROID_BUILD" \
  AR="$AR" \
  RANLIB="$RANLIB" \
  ./configure \
    --static \
    --use-cuda=no \
    --mathlib=OPENBLAS \
    --host="$TARGET_TRIPLE" \
    --openblas-root="$DEPS_PREFIX" \
    --fst-root="$DEPS_PREFIX" \
    --fst-version=1.8.0 \
    --android-incdir="$ANDROID_INCDIR"

  # 修改优化等级
  if [[ -f kaldi.mk ]]; then
    sed -i 's/ -O1 / -O3 /g' kaldi.mk || true
  fi

  echo "生成依赖..."
  make depend -j"$JOBS" || true

  echo "编译 Kaldi (online2 与 rnnlm)..."
  make -j"$JOBS" online2 rnnlm
  
  popd >/dev/null
fi

#-----------------------------
# 5. 安装 Kaldi 到本地前缀
#-----------------------------
echo "=========================================="
echo "5. 安装 Kaldi 到 $KALDI_PREFIX"
echo "=========================================="

# 静态库
echo "安装 Kaldi 静态库 (*.a)..."
find "$KALDI_SRC_DIR" -maxdepth 2 -name "kaldi-*.a" -print0 2>/dev/null | while IFS= read -r -d '' lib; do
  base=$(basename "$lib")
  cp -v "$lib" "$KALDI_PREFIX/lib/static/lib$base"
done

# 动态库 (如果有)
echo "安装 Kaldi 动态库 (*.so)..."
find "$KALDI_SRC_DIR" -maxdepth 2 -name "libkaldi-*.so*" -print0 2>/dev/null | while IFS= read -r -d '' so; do
  cp -v "$so" "$KALDI_PREFIX/lib/shared/"
  # 同时复制到 jniLibs 方便 Android Studio 使用
  cp -v "$so" "$KALDI_PREFIX/jniLibs/arm64-v8a/"
done

# 依赖库
echo "安装依赖库..."
for lib in libopenblas.a liblapack.a libblas.a libf2c.a; do
  if [[ -f "$DEPS_PREFIX/lib/$lib" ]]; then
    cp -v "$DEPS_PREFIX/lib/$lib" "$KALDI_PREFIX/lib/deps/"
  fi
done
for lib in libfst.a libfstlookahead.a libfstngram.a libfstfar.a; do
  if [[ -f "$DEPS_PREFIX/lib/$lib" ]]; then
    cp -v "$DEPS_PREFIX/lib/$lib" "$KALDI_PREFIX/lib/deps/"
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

echo "安装依赖头文件..."
if [[ -d "$DEPS_PREFIX/include/fst" ]]; then
  mkdir -p "$KALDI_PREFIX/include/deps"
  cp -r "$DEPS_PREFIX/include/fst" "$KALDI_PREFIX/include/deps/"
fi
find "$DEPS_PREFIX/include" -maxdepth 1 -name "*.h" -exec cp {} "$KALDI_PREFIX/include/deps/" \; 2>/dev/null || true

# 可执行文件 (默认跳过)
if [[ "$SKIP_BINARIES" == true ]]; then
  echo "跳过可执行文件安装 (默认行为，使用 --with-binaries 可安装)"
else
  echo "安装 Kaldi 可执行文件..."
  mkdir -p "$KALDI_PREFIX/bin"
  find "$KALDI_SRC_DIR" -type d -name "*bin" | while read -r bindir; do
    find "$bindir" -maxdepth 1 -type f -executable \
      ! -name "*.cc" ! -name "*.h" ! -name "Makefile*" ! -name "CMake*" \
      -exec cp -v {} "$KALDI_PREFIX/bin/" \; 2>/dev/null || true
  done
fi

#-----------------------------
# 6. 生成配置文件
#-----------------------------
echo "创建 CMake 配置..."
cat > "$KALDI_PREFIX/KaldiConfig.cmake" << EOF
# Kaldi CMake Configuration File (Android arm64-v8a)
# Auto-generated by build_android.sh

get_filename_component(KALDI_ROOT "\${CMAKE_CURRENT_LIST_FILE}" PATH)

set(KALDI_ABI "arm64-v8a")
set(KALDI_API_LEVEL $ANDROID_API)

set(KALDI_INCLUDE_DIRS
  \${KALDI_ROOT}/include/kaldi
  \${KALDI_ROOT}/include/deps
)
set(KALDI_LIBRARY_DIRS 
  \${KALDI_ROOT}/lib/static
  \${KALDI_ROOT}/lib/deps
)

# Kaldi 库列表（按链接顺序：高级模块优先）
set(KALDI_LIBRARIES
  kaldi-online2 kaldi-ivector kaldi-nnet3 kaldi-chain kaldi-nnet2
  kaldi-decoder kaldi-lat kaldi-hmm kaldi-tree kaldi-gmm
  kaldi-transform kaldi-feat kaldi-fstext kaldi-lm kaldi-rnnlm
  kaldi-matrix kaldi-util kaldi-base
)
set(KALDI_DEPENDENCIES fst fstngram fstlookahead fstfar openblas lapack blas f2c)

unset(KALDI_LIBS)
foreach(lib \${KALDI_LIBRARIES})
  find_library(\${lib}_STATIC NAMES lib\${lib} \${lib} PATHS \${KALDI_LIBRARY_DIRS} NO_DEFAULT_PATH)
  if(\${lib}_STATIC)
    list(APPEND KALDI_LIBS \${\${lib}_STATIC})
  endif()
endforeach()

unset(KALDI_DEPENDENCY_LIBS)
foreach(dep \${KALDI_DEPENDENCIES})
  find_library(\${dep}_LIB NAMES lib\${dep} \${dep} PATHS \${KALDI_ROOT}/lib/deps NO_DEFAULT_PATH)
  if(\${dep}_LIB)
    list(APPEND KALDI_DEPENDENCY_LIBS \${\${dep}_LIB})
  endif()
endforeach()

set(KALDI_ALL_LIBRARIES \${KALDI_LIBS} \${KALDI_DEPENDENCY_LIBS})
set(Kaldi_FOUND TRUE)
EOF

# 创建 Android.mk 供 ndk-build 使用
cat > "$KALDI_PREFIX/Android.mk" << EOF
# Kaldi Android.mk for ndk-build
# Auto-generated by build_android.sh

LOCAL_PATH := \$(call my-dir)

# Kaldi 静态库
KALDI_LIBS := kaldi-online2 kaldi-ivector kaldi-nnet3 kaldi-chain kaldi-nnet2 \\
              kaldi-decoder kaldi-lat kaldi-hmm kaldi-tree kaldi-gmm \\
              kaldi-transform kaldi-feat kaldi-fstext kaldi-lm kaldi-rnnlm \\
              kaldi-matrix kaldi-util kaldi-base

\$(foreach lib,\$(KALDI_LIBS),\\
  \$(eval include \$(CLEAR_VARS)) \\
  \$(eval LOCAL_MODULE := \$(lib)) \\
  \$(eval LOCAL_SRC_FILES := lib/static/lib\$(lib).a) \\
  \$(eval LOCAL_EXPORT_C_INCLUDES := \$(LOCAL_PATH)/include/kaldi \$(LOCAL_PATH)/include/deps) \\
  \$(eval include \$(PREBUILT_STATIC_LIBRARY)) \\
)

# 依赖库
KALDI_DEPS := fst fstngram fstlookahead fstfar openblas lapack blas f2c

\$(foreach dep,\$(KALDI_DEPS),\\
  \$(eval include \$(CLEAR_VARS)) \\
  \$(eval LOCAL_MODULE := \$(dep)) \\
  \$(eval LOCAL_SRC_FILES := lib/deps/lib\$(dep).a) \\
  \$(eval include \$(PREBUILT_STATIC_LIBRARY)) \\
)

# 使用示例:
# include \$(CLEAR_VARS)
# LOCAL_MODULE := your_jni_lib
# LOCAL_STATIC_LIBRARIES := \$(KALDI_LIBS) \$(KALDI_DEPS)
# LOCAL_LDLIBS := -llog -lm
# include \$(BUILD_SHARED_LIBRARY)
EOF

# 记录编译配置
cat > "$KALDI_PREFIX/build_info.txt" << EOF
Kaldi Android Build Information
================================
Build Date: $(date)
Android ABI: arm64-v8a
Android API Level: $ANDROID_API
NDK Path: $ANDROID_NDK
NDK Version: ${NDK_VERSION:-unknown}
Target Triple: $TARGET_TRIPLE
Compiler: $CXX
EOF

#-----------------------------
# 7. 统计与说明
#-----------------------------
KALDI_A=$(find "$KALDI_PREFIX/lib/static" -name "*.a" 2>/dev/null | wc -l)
KALDI_SO=$(find "$KALDI_PREFIX/lib/shared" -name "*.so*" 2>/dev/null | wc -l)
DEP_LIBS=$(find "$KALDI_PREFIX/lib/deps" -name "*.a" 2>/dev/null | wc -l)
HEADERS=$(find "$KALDI_PREFIX/include" -name "*.h" 2>/dev/null | wc -l)

echo ""
echo "=========================================="
echo "Kaldi Android 编译完成!"
echo "=========================================="
echo ""
echo "目标: arm64-v8a (API $ANDROID_API)"
echo "安装目录: $KALDI_PREFIX"
echo ""
echo "目录结构:"
echo "  - lib/static/     Kaldi 静态库"
echo "  - lib/deps/       依赖静态库"
echo "  - lib/shared/     Kaldi 动态库 (如有)"
echo "  - jniLibs/arm64-v8a/  JNI 库 (直接用于 Android Studio)"
echo "  - include/kaldi/  Kaldi 头文件"
echo "  - include/deps/   依赖头文件"
echo ""
echo "安装统计:"
echo "  - Kaldi 静态库: $KALDI_A 个"
echo "  - Kaldi 动态库: $KALDI_SO 个"
echo "  - 依赖库: $DEP_LIBS 个"
echo "  - 头文件: $HEADERS 个"
echo ""

if command -v du >/dev/null 2>&1; then
  echo "目录大小: $(du -sh "$KALDI_PREFIX" | cut -f1)"
fi

echo ""
echo "使用方法:"
echo ""
echo "1. CMake (推荐):"
echo "   set(KALDI_ROOT \"$KALDI_PREFIX\")"
echo "   include(\${KALDI_ROOT}/KaldiConfig.cmake)"
echo "   target_include_directories(your_target PRIVATE \${KALDI_INCLUDE_DIRS})"
echo "   target_link_libraries(your_target PRIVATE \${KALDI_ALL_LIBRARIES} log m)"
echo ""
echo "2. ndk-build:"
echo "   在 Android.mk 中添加:"
echo "   include $KALDI_PREFIX/Android.mk"
echo ""
echo "3. Android Studio:"
echo "   将 jniLibs/arm64-v8a/ 目录复制到 app/src/main/jniLibs/"
echo ""
echo "💡 提示:"
echo "  - 使用 $0 --clean-deps 重新编译所有依赖"
echo "  - 使用 $0 --clean-all 彻底清理并重建"
echo ""
echo "=========================================="
