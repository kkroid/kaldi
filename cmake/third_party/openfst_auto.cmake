cmake_minimum_required(VERSION 3.14)

# OpenFST auto-compilation configuration
# This will automatically download, configure, compile and install OpenFST

include(ExternalProject)

set(OPENFST_VERSION "orig/1.8.0.1")
set(OPENFST_SOURCE_DIR "${CMAKE_SOURCE_DIR}/external/openfst")
set(OPENFST_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/external/openfst")
set(OPENFST_INSTALL_DIR "${CMAKE_CURRENT_BINARY_DIR}/kaldi_deps_openfst")

# Configure OpenFST build parameters
set(OPENFST_CONFIGURE_ARGS
    --prefix=${OPENFST_INSTALL_DIR}
    --enable-shared
    --enable-static
    --with-pic
    --disable-bin
    --enable-lookahead-fsts
    --enable-ngram-fsts
    --disable-dependency-tracking
    CXX=${CMAKE_CXX_COMPILER}
    CXXFLAGS=-std=c++17\ -fPIC
)

# Check if OpenFST is already compiled
find_library(OPENFST_EXISTING_LIB fst PATHS ${OPENFST_INSTALL_DIR}/lib NO_DEFAULT_PATH)
find_path(OPENFST_EXISTING_INCLUDE fst/fst.h PATHS ${OPENFST_INSTALL_DIR}/include NO_DEFAULT_PATH)

if(OPENFST_EXISTING_LIB AND OPENFST_EXISTING_INCLUDE)
    message(STATUS "Found existing OpenFST installation at ${OPENFST_INSTALL_DIR}")
    set(OPENFST_COMPILED TRUE)
else()
    message(STATUS "OpenFST not found, will compile from source")
    set(OPENFST_COMPILED FALSE)
endif()

if(NOT OPENFST_COMPILED)
    # Create install directory early
    file(MAKE_DIRECTORY ${OPENFST_INSTALL_DIR})
    file(MAKE_DIRECTORY ${OPENFST_INSTALL_DIR}/lib)
    file(MAKE_DIRECTORY ${OPENFST_INSTALL_DIR}/include)

    # Download and compile OpenFST using Git
    ExternalProject_Add(openfst_external
        SOURCE_DIR ${OPENFST_SOURCE_DIR}
        PREFIX ${OPENFST_PREFIX}
        CONFIGURE_COMMAND <SOURCE_DIR>/configure ${OPENFST_CONFIGURE_ARGS}
        BUILD_COMMAND make -j${CMAKE_BUILD_PARALLEL_LEVEL}
        INSTALL_COMMAND make install
        BUILD_IN_SOURCE 0
        # Print logs directly to console instead of log files
        LOG_DOWNLOAD OFF
        LOG_CONFIGURE OFF
        LOG_BUILD OFF
        LOG_INSTALL OFF
        USES_TERMINAL_DOWNLOAD ON
        USES_TERMINAL_CONFIGURE ON
        USES_TERMINAL_BUILD ON
        USES_TERMINAL_INSTALL ON
    )
    
    # Set variables for later use
    set(OPENFST_ROOT ${OPENFST_INSTALL_DIR})
    set(OPENFST_LIBRARIES ${OPENFST_INSTALL_DIR}/lib/libfst.so)
    set(OPENFST_INCLUDE_DIRS ${OPENFST_INSTALL_DIR}/include)
    
    # Create imported targets with proper paths
    add_library(fst SHARED IMPORTED GLOBAL)
    add_dependencies(fst openfst_external)
    set_target_properties(fst PROPERTIES
        IMPORTED_LOCATION ${OPENFST_LIBRARIES}
        INTERFACE_INCLUDE_DIRECTORIES ${OPENFST_INCLUDE_DIRS}
    )
else()
    # Use existing installation
    set(OPENFST_ROOT ${OPENFST_INSTALL_DIR})
    set(OPENFST_LIBRARIES ${OPENFST_EXISTING_LIB})
    set(OPENFST_INCLUDE_DIRS ${OPENFST_EXISTING_INCLUDE})
    
    add_library(fst SHARED IMPORTED GLOBAL)
    set_target_properties(fst PROPERTIES
        IMPORTED_LOCATION ${OPENFST_LIBRARIES}
        INTERFACE_INCLUDE_DIRECTORIES ${OPENFST_INCLUDE_DIRS}
    )
endif()

# Set global include directories
include_directories(${OPENFST_INCLUDE_DIRS})

# Export variables for use in main CMakeLists.txt
set(OPENFST_FOUND TRUE PARENT_SCOPE)
set(OPENFST_ROOT ${OPENFST_ROOT} PARENT_SCOPE)
set(OPENFST_LIBRARIES ${OPENFST_LIBRARIES} PARENT_SCOPE)
set(OPENFST_INCLUDE_DIRS ${OPENFST_INCLUDE_DIRS} PARENT_SCOPE)

message(STATUS "OpenFST configuration:")
message(STATUS "  Root: ${OPENFST_ROOT}")
message(STATUS "  Libraries: ${OPENFST_LIBRARIES}")
message(STATUS "  Include dirs: ${OPENFST_INCLUDE_DIRS}")

# Compact status output
if(OPENFST_COMPILED)
    message(STATUS "✓ OpenFST: Using existing installation")
else()
    message(STATUS "⚙ OpenFST: Will build from source")
endif()
