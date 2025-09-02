# Kaldi Dependencies Auto-Configuration
# This file manages all external dependencies for Kaldi

option(KALDI_BUILD_DEPENDENCIES "Automatically build dependencies from source" ON)
option(KALDI_USE_SYSTEM_LIBS "Try to use system libraries first" OFF)

# Set number of parallel jobs for building
if(NOT CMAKE_BUILD_PARALLEL_LEVEL)
    include(ProcessorCount)
    ProcessorCount(N)
    if(NOT N EQUAL 0)
        set(CMAKE_BUILD_PARALLEL_LEVEL ${N})
    else()
        set(CMAKE_BUILD_PARALLEL_LEVEL 12)
    endif()
endif()

message(STATUS "Using ${CMAKE_BUILD_PARALLEL_LEVEL} parallel jobs for building dependencies")

# Function to check and configure math library
function(configure_math_library)
    if(KALDI_USE_SYSTEM_LIBS)
        # Try system libraries first
        if(MATHLIB STREQUAL "OpenBLAS")
            find_package(PkgConfig QUIET)
            if(PkgConfig_FOUND)
                pkg_check_modules(OpenBLAS QUIET openblas)
                if(OpenBLAS_FOUND)
                    message(STATUS "Using system OpenBLAS")
                    include_directories(${OpenBLAS_INCLUDE_DIRS})
                    link_directories(${OpenBLAS_LIBRARY_DIRS})
                    link_libraries(${OpenBLAS_LIBRARIES})
                    add_definitions(-DHAVE_OPENBLAS=1)
                    return()
                endif()
            endif()
        endif()
    endif()
    
    # Fall back to building from source
    if(KALDI_BUILD_DEPENDENCIES AND MATHLIB STREQUAL "OpenBLAS")
        message(STATUS "Building OpenBLAS from source")
        include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/third_party/openblas_auto.cmake)
        
        message(STATUS "Building CLAPACK from source")
        include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/third_party/clapack_auto.cmake)
        
        # Get include directories directly from imported targets
        get_target_property(OPENBLAS_INCLUDE_DIRS openblas INTERFACE_INCLUDE_DIRECTORIES)
        get_target_property(CLAPACK_INCLUDE_DIRS clapack INTERFACE_INCLUDE_DIRECTORIES)
        
        include_directories(${OPENBLAS_INCLUDE_DIRS})
        include_directories(${CLAPACK_INCLUDE_DIRS})
        link_directories(${KALDI_OPENBLAS_ROOT}/lib)
        link_directories(${KALDI_CLAPACK_ROOT}/lib)
        # Use OpenBLAS for BLAS/CBLAS and CLAPACK for LAPACK functions
        link_libraries(openblas)
        link_libraries(${KALDI_CLAPACK_LIBRARIES})
        add_definitions(-DHAVE_OPENBLAS=1)
        add_definitions(-DHAVE_CLAPACK=1)
    else()
        message(FATAL_ERROR "No suitable math library found and auto-build is disabled")
    endif()
endfunction()

# Function to check and configure OpenFST
function(configure_openfst)
    if(KALDI_USE_SYSTEM_LIBS)
        # Try to find system OpenFST
        find_library(SYSTEM_FST_LIB fst)
        find_path(SYSTEM_FST_INCLUDE fst/fst.h)
        
        if(SYSTEM_FST_LIB AND SYSTEM_FST_INCLUDE)
            message(STATUS "Using system OpenFST")
            add_library(fst SHARED IMPORTED GLOBAL)
            set_target_properties(fst PROPERTIES
                IMPORTED_LOCATION ${SYSTEM_FST_LIB}
                INTERFACE_INCLUDE_DIRECTORIES ${SYSTEM_FST_INCLUDE}
            )
            include_directories(${SYSTEM_FST_INCLUDE})
            return()
        endif()
    endif()
    
    # Fall back to building from source
    if(KALDI_BUILD_DEPENDENCIES)
        message(STATUS "Building OpenFST from source")
        include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/third_party/openfst_auto.cmake)
    else()
        message(FATAL_ERROR "No suitable OpenFST found and auto-build is disabled")
    endif()
endfunction()

# Configure dependencies based on environment
if(CONDA_ROOT)
    message(STATUS "Using Conda environment for dependencies")
    # Use conda-provided libraries
    find_package(BLAS REQUIRED)
    find_package(LAPACK REQUIRED)
    link_libraries(BLAS::BLAS LAPACK::LAPACK)
    add_definitions(-DHAVE_OPENBLAS=1)
    
    # Still need OpenFST
    configure_openfst()
else()
    message(STATUS "Configuring dependencies for standalone build")
    configure_math_library()
    configure_openfst()
endif()

# Additional useful definitions
# add_definitions(-DHAVE_CLAPACK=1)
