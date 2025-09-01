cmake_minimum_required(VERSION 3.14)

# OpenBLAS auto-compilation configuration
# This will automatically download, configure, compile and install OpenBLAS

include(ExternalProject)

set(OPENBLAS_VERSION "0.3.26")
set(OPENBLAS_URL "https://github.com/xianyi/OpenBLAS/archive/v${OPENBLAS_VERSION}.tar.gz")
set(OPENBLAS_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/external/openblas")
set(OPENBLAS_INSTALL_DIR "${CMAKE_CURRENT_BINARY_DIR}/openblas_install")

# Configure OpenBLAS build parameters
set(OPENBLAS_CMAKE_ARGS
    -DCMAKE_INSTALL_PREFIX=${OPENBLAS_INSTALL_DIR}
    -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
    -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
    -DCMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER}
    -DBUILD_SHARED_LIBS=ON
    -DBUILD_STATIC_LIBS=ON
    -DUSE_OPENMP=OFF
    -DUSE_THREAD=0
    -DNO_AFFINITY=1
    -DMAX_STACK_ALLOC=2048
)

# Check if OpenBLAS is already compiled
find_library(OPENBLAS_EXISTING_LIB openblas PATHS ${OPENBLAS_INSTALL_DIR}/lib NO_DEFAULT_PATH)
find_path(OPENBLAS_EXISTING_INCLUDE cblas.h PATHS ${OPENBLAS_INSTALL_DIR}/include NO_DEFAULT_PATH)

if(OPENBLAS_EXISTING_LIB AND OPENBLAS_EXISTING_INCLUDE)
    message(STATUS "Found existing OpenBLAS installation at ${OPENBLAS_INSTALL_DIR}")
    set(OPENBLAS_COMPILED TRUE)
else()
    message(STATUS "OpenBLAS not found, will compile from source")
    set(OPENBLAS_COMPILED FALSE)
endif()

if(NOT OPENBLAS_COMPILED)
    # Check for Fortran compiler
    enable_language(Fortran OPTIONAL)
    if(NOT CMAKE_Fortran_COMPILER)
        message(WARNING "No Fortran compiler found, OpenBLAS may not build correctly")
        list(REMOVE_ITEM OPENBLAS_CMAKE_ARGS "-DCMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER}")
    endif()

    # Download and compile OpenBLAS
    ExternalProject_Add(openblas_external
        URL ${OPENBLAS_URL}
        PREFIX ${OPENBLAS_PREFIX}
        CMAKE_ARGS ${OPENBLAS_CMAKE_ARGS}
        BUILD_COMMAND ${CMAKE_COMMAND} --build . --parallel ${CMAKE_BUILD_PARALLEL_LEVEL}
        INSTALL_COMMAND ${CMAKE_COMMAND} --build . --target install
        LOG_DOWNLOAD ON
        LOG_CONFIGURE ON
        LOG_BUILD ON
        LOG_INSTALL ON
    )
    
    # Set variables for later use
    set(OPENBLAS_ROOT ${OPENBLAS_INSTALL_DIR})
    set(OPENBLAS_LIBRARIES ${OPENBLAS_INSTALL_DIR}/lib/libopenblas.so)
    set(OPENBLAS_INCLUDE_DIRS ${OPENBLAS_INSTALL_DIR}/include)
    
    # Create imported target
    add_library(openblas SHARED IMPORTED GLOBAL)
    add_dependencies(openblas openblas_external)
    set_target_properties(openblas PROPERTIES
        IMPORTED_LOCATION ${OPENBLAS_LIBRARIES}
        INTERFACE_INCLUDE_DIRECTORIES ${OPENBLAS_INCLUDE_DIRS}
    )
else()
    # Use existing installation
    set(OPENBLAS_ROOT ${OPENBLAS_INSTALL_DIR})
    set(OPENBLAS_LIBRARIES ${OPENBLAS_EXISTING_LIB})
    set(OPENBLAS_INCLUDE_DIRS ${OPENBLAS_EXISTING_INCLUDE})
    
    add_library(openblas SHARED IMPORTED GLOBAL)
    set_target_properties(openblas PROPERTIES
        IMPORTED_LOCATION ${OPENBLAS_LIBRARIES}
        INTERFACE_INCLUDE_DIRECTORIES ${OPENBLAS_INCLUDE_DIRS}
    )
endif()

# Export variables for use in main CMakeLists.txt
set(OPENBLAS_FOUND TRUE PARENT_SCOPE)
set(OPENBLAS_ROOT ${OPENBLAS_ROOT} PARENT_SCOPE)
set(OPENBLAS_LIBRARIES ${OPENBLAS_LIBRARIES} PARENT_SCOPE)
set(OPENBLAS_INCLUDE_DIRS ${OPENBLAS_INCLUDE_DIRS} PARENT_SCOPE)

message(STATUS "OpenBLAS configuration:")
message(STATUS "  Root: ${OPENBLAS_ROOT}")
message(STATUS "  Libraries: ${OPENBLAS_LIBRARIES}")
message(STATUS "  Include dirs: ${OPENBLAS_INCLUDE_DIRS}")
