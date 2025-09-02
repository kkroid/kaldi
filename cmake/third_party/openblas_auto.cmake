cmake_minimum_required(VERSION 3.14)

# OpenBLAS auto-compilation configuration
# This will automatically download, configure, compile and install OpenBLAS

include(ExternalProject)

set(OPENBLAS_VERSION "v0.3.26")
set(OPENBLAS_GIT_REPOSITORY "git@github.com:OpenMathLib/OpenBLAS.git")
set(OPENBLAS_GIT_TAG "${OPENBLAS_VERSION}")
set(OPENBLAS_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/external/openblas")
set(OPENBLAS_INSTALL_DIR "${CMAKE_CURRENT_BINARY_DIR}/kaldi_deps_openblas")

# Configure OpenBLAS build parameters
set(OPENBLAS_CMAKE_ARGS
    -DCMAKE_INSTALL_PREFIX=${OPENBLAS_INSTALL_DIR}
    -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
    -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
    -DBUILD_SHARED_LIBS=ON
    -DBUILD_STATIC_LIBS=ON
    -DUSE_OPENMP=OFF
    -DUSE_THREAD=0
    -DNO_AFFINITY=1
    -DMAX_STACK_ALLOC=2048
    -DDYNAMIC_ARCH=1
    -DUSE_LOCKING=1
    -DBUILD_LAPACK_DEPRECATED=ON
    -DBUILD_LAPACK=ON
    -DINTERFACE64=OFF
    -DNUMA=OFF
)

# Check if OpenBLAS is already compiled
find_library(OPENBLAS_EXISTING_LIB openblas PATHS ${OPENBLAS_INSTALL_DIR}/lib NO_DEFAULT_PATH)
find_path(OPENBLAS_EXISTING_INCLUDE openblas_config.h PATHS ${OPENBLAS_INSTALL_DIR}/include/openblas ${OPENBLAS_INSTALL_DIR}/include NO_DEFAULT_PATH)

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

    # Create install directory early
    file(MAKE_DIRECTORY ${OPENBLAS_INSTALL_DIR})
    file(MAKE_DIRECTORY ${OPENBLAS_INSTALL_DIR}/lib)
    file(MAKE_DIRECTORY ${OPENBLAS_INSTALL_DIR}/include)

    # Download and compile OpenBLAS using Git
    ExternalProject_Add(openblas_external
        GIT_REPOSITORY ${OPENBLAS_GIT_REPOSITORY}
        GIT_TAG ${OPENBLAS_GIT_TAG}
        GIT_SHALLOW ON
        PREFIX ${OPENBLAS_PREFIX}
        PATCH_COMMAND ${CMAKE_COMMAND} -E echo "Patching OpenBLAS CMake files..." 
                  COMMAND sed -i "s/cmake_minimum_required(VERSION 2\\.8\\.5)/cmake_minimum_required(VERSION 3.5)/g" <SOURCE_DIR>/CMakeLists.txt
                  COMMAND sed -i "s/get_filename_component(F_COMPILER \\\${CMAKE_Fortran_COMPILER} NAME_WE)/if(CMAKE_Fortran_COMPILER)\\n  get_filename_component(F_COMPILER \\\${CMAKE_Fortran_COMPILER} NAME_WE)\\nelse()\\n  set(F_COMPILER \"NONE\")\\nendif()/g" <SOURCE_DIR>/cmake/f_check.cmake
                  COMMAND ${CMAKE_COMMAND} -E echo "OpenBLAS CMake version and f_check patching completed"
        CMAKE_ARGS ${OPENBLAS_CMAKE_ARGS}
        BUILD_COMMAND ${CMAKE_COMMAND} --build . --parallel ${CMAKE_BUILD_PARALLEL_LEVEL}
        INSTALL_COMMAND ${CMAKE_COMMAND} --build . --target install
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different <SOURCE_DIR>/lapack-netlib/LAPACKE/include/lapack.h ${OPENBLAS_INSTALL_DIR}/include/
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different <SOURCE_DIR>/lapack-netlib/LAPACKE/include/lapacke.h ${OPENBLAS_INSTALL_DIR}/include/
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different <SOURCE_DIR>/lapack-netlib/LAPACKE/include/lapacke_config.h ${OPENBLAS_INSTALL_DIR}/include/
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different <SOURCE_DIR>/lapack-netlib/LAPACKE/include/lapacke_mangling.h ${OPENBLAS_INSTALL_DIR}/include/
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different <SOURCE_DIR>/lapack-netlib/LAPACKE/include/lapacke_utils.h ${OPENBLAS_INSTALL_DIR}/include/
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
    set(OPENBLAS_ROOT ${OPENBLAS_INSTALL_DIR})
    set(OPENBLAS_LIBRARIES ${OPENBLAS_INSTALL_DIR}/lib/libopenblas.so)
    set(OPENBLAS_INCLUDE_DIRS ${OPENBLAS_INSTALL_DIR}/include)
    
    # Create imported target with proper paths
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
    set(OPENBLAS_INCLUDE_DIRS ${OPENBLAS_INSTALL_DIR}/include)
    
    add_library(openblas SHARED IMPORTED GLOBAL)
    set_target_properties(openblas PROPERTIES
        IMPORTED_LOCATION ${OPENBLAS_LIBRARIES}
        INTERFACE_INCLUDE_DIRECTORIES ${OPENBLAS_INCLUDE_DIRS}
    )
endif()

# Export variables for use in main CMakeLists.txt
set(OPENBLAS_FOUND TRUE PARENT_SCOPE)
set(KALDI_OPENBLAS_ROOT ${OPENBLAS_ROOT} PARENT_SCOPE)
set(KALDI_OPENBLAS_LIBRARIES ${OPENBLAS_LIBRARIES} PARENT_SCOPE)
set(KALDI_OPENBLAS_INCLUDE_DIRS ${OPENBLAS_INCLUDE_DIRS} PARENT_SCOPE)

message(STATUS "OpenBLAS configuration:")
message(STATUS "  Root: ${OPENBLAS_ROOT}")
message(STATUS "  Libraries: ${OPENBLAS_LIBRARIES}")
message(STATUS "  Include dirs: ${OPENBLAS_INCLUDE_DIRS}")

# Compact status output
if(OPENBLAS_COMPILED)
    message(STATUS "✓ OpenBLAS: Using existing installation")
else()
    message(STATUS "⚙ OpenBLAS: Will build from source")
endif()
