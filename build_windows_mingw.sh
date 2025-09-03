#!/bin/bash

# MinGW交叉编译脚本，参考Dockerfile的方法构建Windows版本

set -e

echo "=========================================="
echo "Kaldi MinGW 交叉编译脚本"
echo "=========================================="

# 检查MinGW是否安装
if ! command -v x86_64-w64-mingw32-gcc &> /dev/null; then
    echo "错误: 未找到MinGW-w64工具链"
    echo ""
    echo "请先安装MinGW-w64:"
    echo ""
    echo "Ubuntu/Debian:"
    echo "  sudo apt update"
    echo "  sudo apt install g++-mingw-w64-x86-64"
    echo ""
    echo "安装完成后重新运行此脚本"
    exit 1
fi

echo "✓ MinGW-w64 已安装: $(x86_64-w64-mingw32-gcc --version | head -n1)"

# 设置变量
KALDI_INSTALL_DIR=".install_win"
DEPS_BUILD_DIR=".build_deps"
PROJECT_ROOT=$(pwd)

# 解析命令行参数
CLEAN_DEPS=false
CLEAN_ALL=false
SKIP_DEPS=false
SKIP_KALDI=false
SKIP_BINARIES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean-deps)
            CLEAN_DEPS=true
            shift
            ;;
        --clean-all)
            CLEAN_ALL=true
            CLEAN_DEPS=true
            shift
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --skip-kaldi)
            SKIP_KALDI=true
            shift
            ;;
        --skip-binaries)
            SKIP_BINARIES=true
            shift
            ;;
        -h|--help)
            echo "使用方法: $0 [选项]"
            echo "选项:"
            echo "  --clean-deps     清理依赖编译目录（重新编译所有依赖）"
            echo "  --clean-all      清理所有编译结果（完全重新开始）"
            echo "  --skip-deps      跳过依赖编译步骤"
            echo "  --skip-kaldi     跳过Kaldi编译步骤"
            echo "  --skip-binaries  跳过可执行文件安装"
            echo "  -h, --help       显示此帮助信息"
            echo ""
            echo "默认行为: 保留依赖编译目录，只重新编译 Kaldi"
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 $0 --help 查看帮助"
            exit 1
            ;;
    esac
done

echo ""
echo "=========================================="
echo "0. 清理编译结果"
echo "=========================================="

echo "清理 Kaldi 安装目录..."
rm -rf "$PROJECT_ROOT/$KALDI_INSTALL_DIR"

if [ "$CLEAN_DEPS" = true ]; then
    echo "清理依赖编译目录..."
    rm -rf "$PROJECT_ROOT/$DEPS_BUILD_DIR"
else
    echo "保留依赖编译目录 (使用 --clean-deps 可强制重新编译依赖)"
fi

if [ "$CLEAN_ALL" = true ]; then
    echo "清理 Kaldi 编译结果..."
    cd "$PROJECT_ROOT/src"
    make clean 2>/dev/null || true

    echo "清理依赖库编译结果..."
    cd "$PROJECT_ROOT/external/openfst"
    make clean 2>/dev/null || true

    cd "$PROJECT_ROOT/external/openblas"
    make clean 2>/dev/null || true

    cd "$PROJECT_ROOT/external/clapack"
    rm -rf BUILD

    cd "$PROJECT_ROOT"
else
    echo "保留源码编译缓存 (使用 --clean-all 可完全重新开始)"
fi

# 创建目录结构
echo "创建目录结构..."
mkdir -p "$PROJECT_ROOT/$DEPS_BUILD_DIR/lib" "$PROJECT_ROOT/$DEPS_BUILD_DIR/include"
mkdir -p "$PROJECT_ROOT/$KALDI_INSTALL_DIR/lib/kaldi" "$PROJECT_ROOT/$KALDI_INSTALL_DIR/lib/deps" "$PROJECT_ROOT/$KALDI_INSTALL_DIR/lib/dynamic"
mkdir -p "$PROJECT_ROOT/$KALDI_INSTALL_DIR/include/kaldi" "$PROJECT_ROOT/$KALDI_INSTALL_DIR/include/deps"
mkdir -p "$PROJECT_ROOT/$KALDI_INSTALL_DIR/bin" "$PROJECT_ROOT/$KALDI_INSTALL_DIR/cmake"

# 设置路径变量
DEPS_PREFIX="$PROJECT_ROOT/$DEPS_BUILD_DIR"
KALDI_PREFIX="$PROJECT_ROOT/$KALDI_INSTALL_DIR"

echo "目录说明:"
echo "  - $DEPS_PREFIX/         (依赖库临时编译目录)"
echo "  - $KALDI_PREFIX/lib/kaldi/    (Kaldi静态库)"
echo "  - $KALDI_PREFIX/lib/deps/     (依赖静态库)"
echo "  - $KALDI_PREFIX/lib/dynamic/  (Kaldi动态库)"
echo "  - $KALDI_PREFIX/include/kaldi/ (Kaldi头文件)"
echo "  - $KALDI_PREFIX/include/deps/  (依赖头文件)"
echo "  - $KALDI_PREFIX/bin/          (Kaldi可执行文件)"
echo "  - $KALDI_PREFIX/cmake/        (CMake配置文件)"

# 检查依赖是否已编译
OPENFST_EXISTS=false
OPENBLAS_EXISTS=false
CLAPACK_EXISTS=false

if [ -f "$DEPS_PREFIX/lib/libfst.a" ]; then
    OPENFST_EXISTS=true
    echo "✓ 发现已编译的 OpenFST"
fi

if [ -f "$DEPS_PREFIX/lib/libopenblas.a" ]; then
    OPENBLAS_EXISTS=true
    echo "✓ 发现已编译的 OpenBLAS"
fi

if [ -f "$DEPS_PREFIX/lib/libblas.a" ] && [ -f "$DEPS_PREFIX/lib/liblapack.a" ]; then
    CLAPACK_EXISTS=true
    echo "✓ 发现已编译的 CLAPACK"
fi

echo ""
echo "=========================================="
echo "1. 构建 OpenFST"
echo "=========================================="

if [ "$SKIP_DEPS" = true ]; then
    echo "跳过依赖编译 (--skip-deps)"
elif [ "$OPENFST_EXISTS" = true ] && [ "$CLEAN_DEPS" = false ]; then
    echo "跳过 OpenFST 编译 (已存在，使用 --clean-deps 强制重新编译)"
else
    cd "$PROJECT_ROOT/external/openfst"

    echo "运行 autoreconf..."
    autoreconf -i

    echo "配置 OpenFST..."
    CXX=x86_64-w64-mingw32-g++-posix CXXFLAGS="-O3 -ftree-vectorize -DFST_NO_DYNAMIC_LINKING" \
        ./configure --prefix="$DEPS_PREFIX" \
        --enable-shared --enable-static --with-pic --disable-bin \
        --enable-lookahead-fsts --enable-ngram-fsts --host=x86_64-w64-mingw32

    echo "编译 OpenFST..."
    make -j$(nproc)

    echo "安装 OpenFST 到依赖目录..."
    make install
fi

echo ""
echo "=========================================="
echo "2. 构建 OpenBLAS"
echo "=========================================="

if [ "$OPENBLAS_EXISTS" = true ] && [ "$CLEAN_DEPS" = false ]; then
    echo "跳过 OpenBLAS 编译 (已存在，使用 --clean-deps 强制重新编译)"
else
    cd "$PROJECT_ROOT/external/openblas"

    echo "编译 OpenBLAS..."
    make HOSTCC=gcc BINARY=64 CC=x86_64-w64-mingw32-gcc ONLY_CBLAS=1 \
        DYNAMIC_ARCH=1 TARGET=NEHALEM USE_LOCKING=1 USE_THREAD=0 -j$(nproc)

    echo "安装 OpenBLAS 到依赖目录..."
    make PREFIX="$DEPS_PREFIX" install
fi

echo ""
echo "=========================================="
echo "3. 构建 CLAPACK"
echo "=========================================="

if [ "$CLAPACK_EXISTS" = true ] && [ "$CLEAN_DEPS" = false ]; then
    echo "跳过 CLAPACK 编译 (已存在，使用 --clean-deps 强制重新编译)"
else
    cd "$PROJECT_ROOT/external/clapack"

    # 清理之前的构建
    rm -rf BUILD
    mkdir BUILD
    cd BUILD

    echo "配置 CLAPACK..."
    cmake -DCMAKE_C_COMPILER_TARGET=x86_64-w64-mingw32 \
        -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix \
        -DCMAKE_SYSTEM_NAME=Windows \
        -DCMAKE_CROSSCOMPILING=True ..

    echo "编译 CLAPACK..."
    make -C F2CLIBS/libf2c
    make -C BLAS
    make -C SRC

    echo "安装 CLAPACK 到依赖目录..."
    find . -name "*.a" -exec cp {} "$DEPS_PREFIX/lib/" \;
fi

echo ""
echo "=========================================="
echo "4. 构建 Kaldi"
echo "=========================================="

if [ "$SKIP_KALDI" = true ]; then
    echo "跳过 Kaldi 编译 (--skip-kaldi)"
else
    cd "$PROJECT_ROOT/src"

    echo "配置 Kaldi..."
    CXX=x86_64-w64-mingw32-g++-posix CXXFLAGS="-O3 -ftree-vectorize -DFST_NO_DYNAMIC_LINKING" \
        ./configure --shared --mingw=yes --use-cuda=no \
        --mathlib=OPENBLAS_CLAPACK \
        --host=x86_64-w64-mingw32 --openblas-clapack-root="$DEPS_PREFIX" \
        --fst-root="$DEPS_PREFIX" --fst-version=1.8.0

    echo "构建依赖..."
    make depend -j$(nproc)

    echo "编译 Kaldi (online2 和 rnnlm)..."
    make -j$(nproc) online2 rnnlm
fi

echo ""
echo "=========================================="
echo "5. 安装 Kaldi 到 $KALDI_PREFIX"
echo "=========================================="

# 安装 Kaldi 静态库
echo "安装 Kaldi 静态库..."
mkdir -p "$KALDI_PREFIX/lib/kaldi"
for kaldi_lib in $(find "$PROJECT_ROOT/src" -name "kaldi-*.a"); do
    lib_name=$(basename "$kaldi_lib")
    # 将 kaldi-xxx.a 重命名为 libkaldi-xxx.a
    new_name="lib${lib_name}"
    echo "  复制 $lib_name -> $new_name"
    cp "$kaldi_lib" "$KALDI_PREFIX/lib/kaldi/$new_name"
done

# 安装依赖库
echo ""
echo "安装依赖库..."
mkdir -p "$KALDI_PREFIX/lib/deps"

# 复制 OpenFST 库
echo "  复制 OpenFST 库..."
if [ -f "$DEPS_PREFIX/lib/libfst.a" ]; then
    cp -v "$DEPS_PREFIX/lib/libfst.a" "$KALDI_PREFIX/lib/deps/"
fi
if [ -f "$DEPS_PREFIX/lib/libfstlookahead.a" ]; then
    cp -v "$DEPS_PREFIX/lib/libfstlookahead.a" "$KALDI_PREFIX/lib/deps/"
fi
if [ -f "$DEPS_PREFIX/lib/libfstngram.a" ]; then
    cp -v "$DEPS_PREFIX/lib/libfstngram.a" "$KALDI_PREFIX/lib/deps/"
fi

# 复制数学库
echo "  复制数学库..."
for lib in libopenblas.a liblapack.a libblas.a libf2c.a; do
    if [ -f "$DEPS_PREFIX/lib/$lib" ]; then
        cp -v "$DEPS_PREFIX/lib/$lib" "$KALDI_PREFIX/lib/deps/"
    fi
done

# 安装 Kaldi 动态库
echo ""
echo "安装 Kaldi 动态库..."
mkdir -p "$KALDI_PREFIX/lib/dynamic"
find "$PROJECT_ROOT/src" -name "libkaldi-*.dll" -exec cp -v {} "$KALDI_PREFIX/lib/dynamic/" \; 2>/dev/null || true

# 安装 Kaldi 头文件
echo ""
echo "安装 Kaldi 头文件..."
mkdir -p "$KALDI_PREFIX/include/kaldi"
for dir in base util matrix feat transform gmm tree hmm lat decoder fstext lm \
           nnet nnet2 nnet3 rnnlm chain cudamatrix ivector online2; do
    if [ -d "$PROJECT_ROOT/src/$dir" ]; then
        echo "  安装 $dir 头文件..."
        mkdir -p "$KALDI_PREFIX/include/kaldi/$dir"
        find "$PROJECT_ROOT/src/$dir" -name "*.h" -exec cp {} "$KALDI_PREFIX/include/kaldi/$dir/" \;
    fi
done

# 安装依赖头文件
echo ""
echo "安装依赖头文件..."
mkdir -p "$KALDI_PREFIX/include/deps"

# 复制 OpenFST 头文件
if [ -d "$DEPS_PREFIX/include/fst" ]; then
    echo "  复制 OpenFST 头文件..."
    cp -r "$DEPS_PREFIX/include/fst" "$KALDI_PREFIX/include/deps/"
fi

# 复制其他依赖头文件
if [ -d "$DEPS_PREFIX/include" ]; then
    echo "  复制其他依赖头文件..."
    find "$DEPS_PREFIX/include" -maxdepth 1 -name "*.h" -exec cp {} "$KALDI_PREFIX/include/deps/" \; 2>/dev/null || true
fi

echo ""
if [ "$SKIP_BINARIES" = true ]; then
    echo "跳过可执行文件安装 (--skip-binaries)"
else
    echo "安装 Kaldi 可执行文件..."
    mkdir -p "$KALDI_PREFIX/bin"
    for bindir in $(find "$PROJECT_ROOT/src" -name "*bin" -type d); do
        if [ -d "$bindir" ]; then
            echo "  从 $bindir 安装可执行文件..."
            find "$bindir" -type f -executable -name "*.exe" -exec cp {} "$KALDI_PREFIX/bin/" \; 2>/dev/null || true
            # 对于没有.exe扩展名的可执行文件，也尝试复制（MinGW有时不加扩展名）
            find "$bindir" -type f -executable ! -name "*.cc" ! -name "*.h" ! -name "Makefile*" ! -name "CMake*" \
                -exec file {} \; | grep -i "PE32.*executable" | cut -d: -f1 | xargs -I {} cp {} "$KALDI_PREFIX/bin/" 2>/dev/null || true
        fi
    done
fi

# 创建 CMake 配置文件
echo ""
echo "创建构建配置文件..."
mkdir -p "$KALDI_PREFIX/cmake"

# 创建 KaldiConfig.cmake
cat > "$KALDI_PREFIX/cmake/KaldiConfig.cmake" << 'EOF'
# Kaldi CMake Configuration File

get_filename_component(KALDI_CMAKE_DIR "${CMAKE_CURRENT_LIST_FILE}" PATH)
get_filename_component(KALDI_ROOT "${KALDI_CMAKE_DIR}/.." ABSOLUTE)

# 设置路径
set(KALDI_INCLUDE_DIRS "${KALDI_ROOT}/include")
set(KALDI_LIBRARY_DIRS "${KALDI_ROOT}/lib")

# Kaldi 库列表（链接器名称，不含lib前缀和.a后缀）
set(KALDI_LIBRARIES
    kaldi-base kaldi-util kaldi-matrix kaldi-feat kaldi-transform
    kaldi-gmm kaldi-tree kaldi-hmm kaldi-lat kaldi-decoder
    kaldi-fstext kaldi-lm kaldi-nnet kaldi-nnet2 kaldi-nnet3
    kaldi-rnnlm kaldi-chain kaldi-cudamatrix kaldi-ivector kaldi-online2
)

# 依赖库列表
set(KALDI_DEPENDENCIES
    fst openblas lapack blas f2c
)

# 设置库文件路径
foreach(lib ${KALDI_LIBRARIES})
    find_library(${lib}_LIBRARY
        NAMES ${lib}
        PATHS ${KALDI_LIBRARY_DIRS}/kaldi
        NO_DEFAULT_PATH
    )
    if(${lib}_LIBRARY)
        list(APPEND KALDI_LIBS ${${lib}_LIBRARY})
    endif()
endforeach()

foreach(dep ${KALDI_DEPENDENCIES})
    find_library(${dep}_LIBRARY
        NAMES ${dep} lib${dep}
        PATHS ${KALDI_LIBRARY_DIRS}/deps
        NO_DEFAULT_PATH
    )
    if(${dep}_LIBRARY)
        list(APPEND KALDI_DEPENDENCY_LIBS ${${dep}_LIBRARY})
    endif()
endforeach()

# 合并所有库
set(KALDI_ALL_LIBRARIES ${KALDI_LIBS} ${KALDI_DEPENDENCY_LIBS})

# 设置包含目录
set(KALDI_INCLUDE_DIRS
    ${KALDI_ROOT}/include/kaldi
    ${KALDI_ROOT}/include/deps
)

# 标记为找到
set(Kaldi_FOUND TRUE)
EOF

echo ""
echo "保留依赖编译目录以便下次快速编译..."
echo "(依赖库位于: $DEPS_BUILD_DIR)"

echo ""
echo "=========================================="
echo "Kaldi Windows 交叉编译完成!"
echo "=========================================="
echo "安装目录: $KALDI_PREFIX"
echo ""
echo "目录结构:"
echo "  - Kaldi 静态库: $KALDI_PREFIX/lib/kaldi/"
echo "  - 依赖静态库: $KALDI_PREFIX/lib/deps/"
echo "  - 动态库: $KALDI_PREFIX/lib/dynamic/"
echo "  - Kaldi 头文件: $KALDI_PREFIX/include/kaldi/"
echo "  - 依赖头文件: $KALDI_PREFIX/include/deps/"
echo "  - 可执行文件: $KALDI_PREFIX/bin/"
echo "  - CMake 配置: $KALDI_PREFIX/cmake/"

# 统计文件数量
KALDI_LIBS=$(find "$KALDI_PREFIX/lib/kaldi" -name "*.a" 2>/dev/null | wc -l)
DEP_LIBS=$(find "$KALDI_PREFIX/lib/deps" -name "*.a" 2>/dev/null | wc -l)
DYNAMIC_LIBS=$(find "$KALDI_PREFIX/lib/dynamic" -name "*.dll" 2>/dev/null | wc -l)
EXECUTABLES=$(find "$KALDI_PREFIX/bin" -type f -executable 2>/dev/null | wc -l)
HEADERS=$(find "$KALDI_PREFIX/include" -name "*.h" 2>/dev/null | wc -l)

echo "安装统计:"
echo "  - Kaldi 静态库: $KALDI_LIBS 个"
echo "  - 依赖静态库: $DEP_LIBS 个"
echo "  - 动态库: $DYNAMIC_LIBS 个"
echo "  - 可执行文件: $EXECUTABLES 个"
echo "  - 头文件: $HEADERS 个"
echo ""

echo "使用方法:"
echo "1. CMake 项目（推荐）:"
echo "   list(APPEND CMAKE_MODULE_PATH \"$KALDI_PREFIX/cmake\")"
echo "   find_package(Kaldi REQUIRED)"
echo "   target_link_libraries(your_target \${KALDI_ALL_LIBRARIES})"
echo ""
echo "2. 直接链接:"
echo "   x86_64-w64-mingw32-g++ \\"
echo "     -I$KALDI_PREFIX/include/kaldi \\"
echo "     -I$KALDI_PREFIX/include/deps \\"
echo "     -L$KALDI_PREFIX/lib/kaldi \\"
echo "     -L$KALDI_PREFIX/lib/deps \\"
echo "     your_code.cpp -lkaldi-online2 -lkaldi-matrix -lfst -lopenblas ..."
echo ""

# 计算总大小
if command -v du &> /dev/null; then
    TOTAL_SIZE=$(du -sh "$KALDI_PREFIX" 2>/dev/null | cut -f1)
    echo "总大小: $TOTAL_SIZE"
fi

echo ""
echo "💡 提示:"
echo "  - 使用 ./build_windows_mingw.sh --clean-deps 重新编译所有依赖"
echo "  - 使用 ./build_windows_mingw.sh --clean-all 完全重新开始编译"
echo "  - 默认会保留依赖编译缓存以加快后续编译"
echo "  - 所有依赖库已包含在 lib/deps/ 中，无需额外安装"
echo ""

# 显示安装的文件统计
echo "安装统计:"
kaldi_static_count=$(ls $KALDI_PREFIX/lib/static/kaldi-*.a 2>/dev/null | wc -l)
kaldi_dynamic_count=$(ls $KALDI_PREFIX/lib/dynamic/libkaldi-*.dll 2>/dev/null | wc -l)
kaldi_bin_count=$(ls $KALDI_PREFIX/bin/ 2>/dev/null | wc -l)
kaldi_headers_count=$(find $KALDI_PREFIX/include/kaldi -name "*.h" 2>/dev/null | wc -l)

echo "  - Kaldi 静态库: $kaldi_static_count 个"
echo "  - Kaldi 动态库: $kaldi_dynamic_count 个"
echo "  - 可执行文件: $kaldi_bin_count 个"
echo "  - 头文件: $kaldi_headers_count 个"
echo ""
echo "使用说明:"
echo "1. 静态链接: 链接 $KALDI_PREFIX/lib/static/kaldi-*.a"
echo "2. 动态链接: 链接 $KALDI_PREFIX/lib/dynamic/libkaldi-*.dll"
echo "3. 头文件路径: -I$KALDI_PREFIX/include"
echo ""
echo "目录大小: $(du -sh $KALDI_PREFIX | cut -f1)"
echo ""
echo "💡 提示:"
echo "  - 使用 $0 --clean-deps 重新编译所有依赖"
echo "  - 使用 $0 --clean-all 完全重新开始编译"
echo "  - 默认会保留依赖编译缓存以加快后续编译"
