# Kaldi 自动化构建系统

这是一个完全自动化的Kaldi构建系统，通过CMake管理所有依赖项，提供开箱即用的编译体验。

## 🔧 默认配置总览

本构建系统采用以下默认配置，确保最佳的开箱即用体验：

### 默认设置
- **数学库**: OpenBLAS (自动从源码编译)
- **CUDA支持**: 禁用 (可用 `-c` 或 `--cuda` 启用)
- **并行任务数**: 24个 (可用 `-j` 修改)
- **构建类型**: Release (可用 `-t` 修改)
- **系统库**: 优先使用自编译库而非系统库 (可用 `--system-libs` 改变)
- **安装**: 默认不安装 (可用 `--install` 启用)
- **安装目录**: `.install/` (项目根目录下)

## 🚀 快速开始

### 基本使用
```bash
# 最简单的构建（仅编译，不安装）
./build_kaldi.sh

# 构建并安装到默认目录
./build_kaldi.sh --install

# 完整构建（清理+安装+详细输出）
./build_kaldi.sh --clean --install --verbose
```

### 自定义构建
```bash
# 启用CUDA，使用16个并行任务，安装到自定义目录
./build_kaldi.sh -c -j16 -p /opt/kaldi

# 使用系统库优先，Debug模式
./build_kaldi.sh --system-libs -t Debug --install

# Intel MKL构建
export MKLROOT=/opt/intel/mkl
./build_kaldi.sh -m MKL --install
```

### 手动CMake配置
```bash
mkdir build && cd build

# 基本配置（默认不安装）
cmake .. -DMATHLIB=OpenBLAS -DKALDI_USE_CUDA=OFF

# 带安装的配置
cmake .. \
  -DMATHLIB=OpenBLAS \
  -DKALDI_USE_CUDA=OFF \
  -DCMAKE_INSTALL_PREFIX=../.install

# 完整自定义配置
cmake .. \
  -DMATHLIB=OpenBLAS \
  -DKALDI_USE_CUDA=OFF \
  -DKALDI_USE_SYSTEM_LIBS=OFF \
  -DKALDI_BUILD_DEPENDENCIES=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/opt/kaldi

# 构建
cmake --build . --parallel 24

# 安装（可选）
cmake --install .
```

## 📋 系统特性

### 自动化程度
- **完全自动化**: 一条命令完成所有依赖编译和安装
- **智能依赖管理**: 优先使用系统库，自动回退到源码编译  
- **固定编译参数**: OpenFST使用确定的configure参数确保兼容性
- **并行编译支持**: 自动检测CPU核心数，支持高效并行编译
- **跨平台兼容**: 支持Linux、macOS等不同平台
- **详细日志记录**: 完整的构建日志用于问题排查
- **增量编译**: 已编译的依赖不会重复编译
- **灵活配置**: 支持多种数学库和编译选项

## 📁 目录结构

构建完成后的目录结构：
```
kaldi-vosk/
├── build/                    # 构建目录
│   ├── src/                  # 编译的二进制文件和库
│   ├── external/             # 外部依赖源码
│   ├── openblas_install/     # OpenBLAS安装
│   └── openfst_install/      # OpenFST安装
├── .install/                 # 默认安装目录（使用 --install 时）
│   ├── bin/                  # 可执行文件
│   ├── lib/                  # 库文件
│   └── include/              # 头文件
├── cmake/                    # CMake配置文件
│   ├── dependencies.cmake   # 依赖管理
│   └── third_party/         # 第三方库配置
└── build_kaldi.sh            # 构建脚本
```

## 🔍 验证构建

构建完成后，可以运行以下命令验证：

```bash
# 测试matrix库
cd build && ./src/matrix/matrix-lib-test

# 测试fstext模块
cd build && ./src/fstext/deterministic-fst-test

# 查看编译的工具
find build/src -name "*bin*" -type d | head -5
```

## 📦 依赖管理详情

### 数学库支持
- **OpenBLAS**: 默认选择，版本0.3.26，自动从源码编译
- **Intel MKL**: 当设置MKLROOT环境变量时使用
- **Apple Accelerate**: macOS系统的默认选择

### 第三方库
- **OpenFST**: 版本1.8.0.1，总是从源码编译并使用特定配置
- **线程库**: 使用系统线程库

### 自动编译详情

#### OpenBLAS自动编译
- 版本: 0.3.26
- 配置: 共享库，无线程，优化
- 构建系统: CMake
- 位置: `build/openblas_install/`

#### OpenFST自动编译
- 版本: 1.8.0.1
- 配置: 共享/静态库，启用lookahead和ngram FSTs
- 构建系统: Autotools (configure/make)
- 位置: `build/openfst_install/`

## ⚙️ 配置选项

### CMake选项
- `MATHLIB`: 数学库选择 (OpenBLAS|MKL|Accelerate)
- `KALDI_USE_CUDA`: 启用CUDA支持 (ON|OFF)
- `KALDI_USE_SYSTEM_LIBS`: 优先使用系统库 (ON|OFF)
- `KALDI_BUILD_DEPENDENCIES`: 自动构建依赖 (ON|OFF)
- `CMAKE_BUILD_TYPE`: 构建类型 (Release|Debug|RelWithDebInfo)

### 构建脚本选项
查看所有可用选项：
```bash
./build_kaldi.sh --help
```

### 环境变量
- `MKLROOT`: Intel MKL安装目录
- `CONDA_ROOT`: Conda环境根目录（自动检测）

## 🏗️ 构建流程

1. **依赖检测**: 检查系统库可用性
2. **源码下载**: 需要时下载依赖源码
3. **配置**: 使用适当标志配置每个依赖
4. **并行编译**: 并行构建依赖项
5. **集成**: 将依赖链接到Kaldi构建
6. **最终构建**: 编译完整的Kaldi项目

## 🐛 故障排除

### 常见问题

#### 构建失败
- 检查 `build/cmake_config.log` 和 `build/build.log` 中的构建日志
- 确保安装了所有必需的系统工具
- 尝试使用 `--clean` 选项进行清理构建

#### 依赖问题
- 使用 `--system-libs` 优先使用系统库
- 使用 `--no-auto-deps` 禁用自动构建
- 检查 `build/external/` 中的特定依赖日志

#### CUDA问题
- 确保CUDA工具包正确安装
- 如果自动检测失败，检查CUDA_TOOLKIT_ROOT_DIR
- 如果不需要，使用 `-DKALDI_USE_CUDA=OFF` 禁用CUDA

### 系统要求

#### 必需工具
- CMake 3.14+
- 支持C++17的GCC/Clang编译器
- Make
- Git（用于下载依赖）

#### 可选工具
- Fortran编译器（用于OpenBLAS优化）
- CUDA工具包（用于GPU支持）
- pkg-config（用于系统库检测）

## 🎯 设计理念

此构建系统的核心设计理念：

1. **零配置**: 默认设置适合大多数用户需求
2. **自包含**: 不依赖系统库，确保构建一致性
3. **高性能**: 默认Release模式和优化的并行构建
4. **灵活性**: 丰富的配置选项满足不同使用场景
5. **可靠性**: 固定的依赖版本和编译参数
6. **可维护性**: 清晰的模块化CMake配置

## 📝 示例用法

### 开发构建
```bash
./build_kaldi.sh -t Debug --verbose --system-libs
```

### 生产构建
```bash
./build_kaldi.sh -t Release --clean --install
```

### Conda环境构建
```bash
# 激活conda环境后
./build_kaldi.sh --system-libs --install
```

### 自定义安装
```bash
./build_kaldi.sh -p /opt/kaldi --clean -j$(nproc)
```

---

> **提示**: 对于大多数用户，简单运行 `./build_kaldi.sh --install` 即可获得完整的Kaldi安装。
