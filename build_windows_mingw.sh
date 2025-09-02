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
        -h|--help)
            echo "使用方法: $0 [选项]"
            echo "选项:"
            echo "  --clean-deps    清理依赖编译目录（重新编译所有依赖）"
            echo "  --clean-all     清理所有编译结果（完全重新开始）"
            echo "  -h, --help      显示此帮助信息"
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
mkdir -p "$PROJECT_ROOT/$KALDI_INSTALL_DIR/lib/static" "$PROJECT_ROOT/$KALDI_INSTALL_DIR/lib/dynamic" "$PROJECT_ROOT/$KALDI_INSTALL_DIR/include" "$PROJECT_ROOT/$KALDI_INSTALL_DIR/bin"

# 设置路径变量
DEPS_PREFIX="$PROJECT_ROOT/$DEPS_BUILD_DIR"
KALDI_PREFIX="$PROJECT_ROOT/$KALDI_INSTALL_DIR"

echo "目录说明:"
echo "  - $DEPS_PREFIX/         (依赖库临时编译目录)"
echo "  - $KALDI_PREFIX/lib/static/   (Kaldi静态库)"
echo "  - $KALDI_PREFIX/lib/dynamic/  (Kaldi动态库)"
echo "  - $KALDI_PREFIX/include/      (Kaldi头文件)"
echo "  - $KALDI_PREFIX/bin/          (Kaldi可执行文件)"

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

if [ "$OPENFST_EXISTS" = true ] && [ "$CLEAN_DEPS" = false ]; then
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

echo ""
echo "=========================================="
echo "5. 安装 Kaldi 到 $KALDI_PREFIX"
echo "=========================================="

echo "安装 Kaldi 静态库..."
find "$PROJECT_ROOT/src" -name "kaldi-*.a" -exec cp -v {} "$KALDI_PREFIX/lib/static/" \;

echo ""
echo "安装 Kaldi 动态库..."
find "$PROJECT_ROOT/src" -name "libkaldi-*.dll" -exec cp -v {} "$KALDI_PREFIX/lib/dynamic/" \; 2>/dev/null || true

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

echo ""
echo "安装 Kaldi 可执行文件..."
for bindir in $(find "$PROJECT_ROOT/src" -name "*bin" -type d); do
    if [ -d "$bindir" ]; then
        echo "  从 $bindir 安装可执行文件..."
        find "$bindir" -type f -executable -name "*.exe" -exec cp {} "$KALDI_PREFIX/bin/" \; 2>/dev/null || true
        # 对于没有.exe扩展名的可执行文件，也尝试复制（MinGW有时不加扩展名）
        find "$bindir" -type f -executable ! -name "*.cc" ! -name "*.h" ! -name "Makefile*" ! -name "CMake*" \
            -exec file {} \; | grep -i "PE32.*executable" | cut -d: -f1 | xargs -I {} cp {} "$KALDI_PREFIX/bin/" 2>/dev/null || true
    fi
done

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
echo "  - 静态库: $KALDI_PREFIX/lib/static/"
echo "  - 动态库: $KALDI_PREFIX/lib/dynamic/" 
echo "  - 头文件: $KALDI_PREFIX/include/kaldi/"
echo "  - 可执行文件: $KALDI_PREFIX/bin/"
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
