cmake_minimum_required(VERSION 3.14)

# OpenFST auto-compilation configuration
# This will automatically download, configure, compile and install OpenFST

include(ExternalProject)

set(OPENFST_VERSION "1.8.0.1")
set(OPENFST_URL "http://www.openfst.org/twiki/pub/FST/FstDownload/openfst-${OPENFST_VERSION}.tar.gz")
set(OPENFST_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/external/openfst")
set(OPENFST_INSTALL_DIR "${CMAKE_CURRENT_BINARY_DIR}/openfst_install")

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
    # Download and compile OpenFST
    ExternalProject_Add(openfst_external
        URL ${OPENFST_URL}
        PREFIX ${OPENFST_PREFIX}
        CONFIGURE_COMMAND <SOURCE_DIR>/configure ${OPENFST_CONFIGURE_ARGS}
        BUILD_COMMAND make -j${CMAKE_BUILD_PARALLEL_LEVEL}
        INSTALL_COMMAND make install
        BUILD_IN_SOURCE 0
        LOG_DOWNLOAD ON
        LOG_CONFIGURE ON
        LOG_BUILD ON
        LOG_INSTALL ON
    )
    
    # Set variables for later use
    set(OPENFST_ROOT ${OPENFST_INSTALL_DIR})
    set(OPENFST_LIBRARIES ${OPENFST_INSTALL_DIR}/lib/libfst.so)
    set(OPENFST_INCLUDE_DIRS ${OPENFST_INSTALL_DIR}/include)
    
    # Create imported targets after build
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
