#!/bin/bash

# Kaldi Auto-Build Script
# This script provides a complete automated build of Kaldi with all dependencies

set -e  # Exit on any error

# Default values
BUILD_TYPE="Release"
MATHLIB="OpenBLAS"
USE_CUDA="OFF"
BUILD_JOBS=24
BUILD_DIR="build"
INSTALL_PREFIX=""
DEFAULT_INSTALL_DIR=".install"
ENABLE_INSTALL=false
CLEAN_BUILD=false
VERBOSE=false
USE_SYSTEM_LIBS=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automated build script for Kaldi with all dependencies.

OPTIONS:
    -h, --help              Show this help message
    -j, --jobs JOBS         Number of parallel build jobs (default: $BUILD_JOBS)
    -t, --type TYPE         Build type: Release|Debug|RelWithDebInfo (default: $BUILD_TYPE)
    -m, --mathlib LIB       Math library: OpenBLAS|MKL|Accelerate (default: $MATHLIB)
    -c, --cuda              Enable CUDA support (default: disabled)
    -p, --prefix PATH       Installation prefix (default: no installation)
    --install               Enable installation to default directory (.install)
    -b, --build-dir DIR     Build directory (default: $BUILD_DIR)
    --clean                 Clean build directory before building
    --verbose               Enable verbose output
    --system-libs           Try to use system libraries first
    --no-auto-deps          Disable automatic dependency building

EXAMPLES:
    $0                      # Basic build with OpenBLAS (no installation)
    $0 -j8 -c              # Build with 8 jobs and CUDA enabled
    $0 -m MKL --clean      # Clean build with Intel MKL
    $0 --system-libs       # Try system libraries first
    $0 --install           # Build and install to .install directory
    $0 -p /opt/kaldi       # Build and install to custom directory

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_usage
            exit 0
            ;;
        -j|--jobs)
            BUILD_JOBS="$2"
            shift 2
            ;;
        -t|--type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        -m|--mathlib)
            MATHLIB="$2"
            shift 2
            ;;
        -c|--cuda)
            USE_CUDA="ON"
            shift
            ;;
        -p|--prefix)
            INSTALL_PREFIX="$2"
            ENABLE_INSTALL=true
            shift 2
            ;;
        --install)
            ENABLE_INSTALL=true
            shift
            ;;
        -b|--build-dir)
            BUILD_DIR="$2"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --system-libs)
            USE_SYSTEM_LIBS=true
            shift
            ;;
        --no-auto-deps)
            NO_AUTO_DEPS=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Set default install directory if enabled but no custom prefix
if [[ "$ENABLE_INSTALL" == true && -z "$INSTALL_PREFIX" ]]; then
    INSTALL_PREFIX="$SCRIPT_DIR/$DEFAULT_INSTALL_DIR"
fi

log_info "Kaldi Auto-Build Configuration:"
log_info "  Build Type: $BUILD_TYPE"
log_info "  Math Library: $MATHLIB"
log_info "  CUDA Support: $USE_CUDA"
log_info "  Build Jobs: $BUILD_JOBS"
log_info "  Build Directory: $BUILD_DIR"
log_info "  Clean Build: $CLEAN_BUILD"
if [[ "$ENABLE_INSTALL" == true ]]; then
    log_info "  Installation: Enabled"
    log_info "  Install Directory: $INSTALL_PREFIX"
else
    log_info "  Installation: Disabled"
fi

# Validate build type
case $BUILD_TYPE in
    Release|Debug|RelWithDebInfo|MinSizeRel)
        ;;
    *)
        log_error "Invalid build type: $BUILD_TYPE"
        exit 1
        ;;
esac

# Validate math library
case $MATHLIB in
    OpenBLAS|MKL|Accelerate)
        ;;
    *)
        log_error "Invalid math library: $MATHLIB"
        exit 1
        ;;
esac

# Check for required tools
log_info "Checking for required tools..."
REQUIRED_TOOLS="cmake make gcc g++"
for tool in $REQUIRED_TOOLS; do
    if ! command -v $tool &> /dev/null; then
        log_error "Required tool '$tool' not found"
        exit 1
    fi
done

# Special checks for math libraries
if [[ "$MATHLIB" == "MKL" ]]; then
    if [[ -z "$MKLROOT" ]]; then
        log_error "MKL selected but MKLROOT environment variable not set"
        exit 1
    fi
    log_info "Using MKL from: $MKLROOT"
fi

# Clean build directory if requested
if [[ "$CLEAN_BUILD" == true ]]; then
    log_info "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Prepare CMake arguments
CMAKE_ARGS=(
    "-DCMAKE_BUILD_TYPE=$BUILD_TYPE"
    "-DMATHLIB=$MATHLIB"
    "-DKALDI_USE_CUDA=$USE_CUDA"
    "-DCMAKE_BUILD_PARALLEL_LEVEL=$BUILD_JOBS"
)

if [[ -n "$INSTALL_PREFIX" && "$ENABLE_INSTALL" == true ]]; then
    CMAKE_ARGS+=("-DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX")
fi

if [[ "$USE_SYSTEM_LIBS" == true ]]; then
    CMAKE_ARGS+=("-DKALDI_USE_SYSTEM_LIBS=ON")
else
    CMAKE_ARGS+=("-DKALDI_USE_SYSTEM_LIBS=OFF")
fi

if [[ "$NO_AUTO_DEPS" == true ]]; then
    CMAKE_ARGS+=("-DKALDI_BUILD_DEPENDENCIES=OFF")
fi

if [[ "$VERBOSE" == true ]]; then
    CMAKE_ARGS+=("-DCMAKE_VERBOSE_MAKEFILE=ON")
fi

# Configure
log_info "Configuring Kaldi..."
if [[ "$VERBOSE" == true ]]; then
    cmake .. "${CMAKE_ARGS[@]}"
else
    cmake .. "${CMAKE_ARGS[@]}" > cmake_config.log 2>&1
    if [[ $? -ne 0 ]]; then
        log_error "CMake configuration failed. See cmake_config.log for details."
        tail -20 cmake_config.log
        exit 1
    fi
fi

log_success "Configuration completed successfully"

# Build
log_info "Building Kaldi (this may take a while)..."
BUILD_CMD="cmake --build . --parallel $BUILD_JOBS --config $BUILD_TYPE"

if [[ "$VERBOSE" == true ]]; then
    $BUILD_CMD
else
    # Start build and monitor dependency logs
    $BUILD_CMD > build.log 2>&1 &
    BUILD_PID=$!
    
    # Function to monitor dependency build logs
    monitor_deps() {
        local log_shown_openfst=false
        local log_shown_openblas=false
        
        while kill -0 $BUILD_PID 2>/dev/null; do
            # Check OpenFST logs
            if [[ -f "external/openfst/src/openfst_external-stamp/openfst_external-download-out.log" && "$log_shown_openfst" == false ]]; then
                log_info "OpenFST download log:"
                cat external/openfst/src/openfst_external-stamp/openfst_external-download-*.log 2>/dev/null || true
                log_shown_openfst=true
            fi
            
            if [[ -f "external/openfst/src/openfst_external-stamp/openfst_external-configure-out.log" ]]; then
                log_info "OpenFST configure log (last 20 lines):"
                tail -20 external/openfst/src/openfst_external-stamp/openfst_external-configure-*.log 2>/dev/null || true
            fi
            
            # Check OpenBLAS logs  
            if [[ -f "external/openblas/src/openblas_external-stamp/openblas_external-download-out.log" && "$log_shown_openblas" == false ]]; then
                log_info "OpenBLAS download log:"
                cat external/openblas/src/openblas_external-stamp/openblas_external-download-*.log 2>/dev/null || true
                log_shown_openblas=true
            fi
            
            if [[ -f "external/openblas/src/openblas_external-stamp/openblas_external-configure-out.log" ]]; then
                log_info "OpenBLAS configure log (last 20 lines):"
                tail -20 external/openblas/src/openblas_external-stamp/openblas_external-configure-*.log 2>/dev/null || true
            fi
            
            sleep 5
        done
    }
    
    # Start monitoring in background
    monitor_deps &
    MONITOR_PID=$!
    
    # Wait for build to complete
    wait $BUILD_PID
    BUILD_RESULT=$?
    
    # Stop monitoring
    kill $MONITOR_PID 2>/dev/null || true
    
    if [[ $BUILD_RESULT -ne 0 ]]; then
        log_error "Build failed. See build.log for details."
        tail -50 build.log
        
        # Show dependency error logs if they exist
        if [[ -f "external/openfst/src/openfst_external-stamp/openfst_external-download-err.log" ]]; then
            log_error "OpenFST download errors:"
            cat external/openfst/src/openfst_external-stamp/openfst_external-download-err.log
        fi
        
        if [[ -f "external/openblas/src/openblas_external-stamp/openblas_external-configure-err.log" ]]; then
            log_error "OpenBLAS configure errors:"
            cat external/openblas/src/openblas_external-stamp/openblas_external-configure-err.log
        fi
        
        exit 1
    fi
fi

log_success "Build completed successfully"

# Test (if available)
if [[ -f "CTestTestfile.cmake" ]]; then
    log_info "Running basic tests..."
    if ctest --output-on-failure -j $BUILD_JOBS > test.log 2>&1; then
        log_success "Tests passed"
    else
        log_warning "Some tests failed. See test.log for details."
    fi
fi

# Install (if enabled and prefix specified)
if [[ "$ENABLE_INSTALL" == true && -n "$INSTALL_PREFIX" ]]; then
    log_info "Installing to $INSTALL_PREFIX..."
    cmake --install . --config $BUILD_TYPE
    log_success "Installation completed"
fi

# Summary
log_success "Kaldi build completed successfully!"
log_info "Build artifacts are in: $BUILD_DIR"
if [[ "$ENABLE_INSTALL" == true && -n "$INSTALL_PREFIX" ]]; then
    log_info "Installation location: $INSTALL_PREFIX"
else
    log_info "No installation performed (use --install or -p to enable)"
fi

# Show some useful binaries
log_info "Sample built executables:"
find . -name "*bin*" -type d | head -3 | while read dir; do
    ls "$dir" | head -3 | while read exe; do
        echo "  $dir/$exe"
    done
done
