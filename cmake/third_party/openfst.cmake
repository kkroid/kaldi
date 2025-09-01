cmake_minimum_required(VERSION 3.14)

# Use pre-compiled OpenFST 1.8.0.1
set(OPENFST_ROOT "/home/kkroid/kaldi")

# Find the installed OpenFST
find_library(OPENFST_LIB fst PATHS ${OPENFST_ROOT}/lib NO_DEFAULT_PATH)
find_path(OPENFST_INCLUDE_DIR fst/fst.h PATHS ${OPENFST_ROOT}/include NO_DEFAULT_PATH)

if(NOT OPENFST_LIB OR NOT OPENFST_INCLUDE_DIR)
    message(FATAL_ERROR "OpenFST not found at ${OPENFST_ROOT}. Please ensure it's compiled and installed.")
endif()

# Create imported target
add_library(fst SHARED IMPORTED)
set_target_properties(fst PROPERTIES
    IMPORTED_LOCATION ${OPENFST_LIB}
    INTERFACE_INCLUDE_DIRECTORIES ${OPENFST_INCLUDE_DIR}
)

# Include directories for direct use
include_directories(${OPENFST_INCLUDE_DIR})

message(STATUS "Using OpenFST from: ${OPENFST_ROOT}")
message(STATUS "OpenFST library: ${OPENFST_LIB}")
message(STATUS "OpenFST headers: ${OPENFST_INCLUDE_DIR}")

# Optional: Find additional OpenFST libraries if needed
find_library(OPENFST_SCRIPT_LIB fstscript PATHS ${OPENFST_ROOT}/lib NO_DEFAULT_PATH)
if(OPENFST_SCRIPT_LIB)
    add_library(fstscript SHARED IMPORTED)
    set_target_properties(fstscript PROPERTIES
        IMPORTED_LOCATION ${OPENFST_SCRIPT_LIB}
        INTERFACE_INCLUDE_DIRECTORIES ${OPENFST_INCLUDE_DIR}
    )
    message(STATUS "Found OpenFST script library: ${OPENFST_SCRIPT_LIB}")
endif()

# Install headers and libraries (only if building with CONDA_ROOT)
if(CONDA_ROOT)
    install(DIRECTORY ${OPENFST_INCLUDE_DIR}/ DESTINATION include/
            FILES_MATCHING PATTERN "*.h")
    
    install(FILES ${OPENFST_LIB} DESTINATION ${CMAKE_INSTALL_LIBDIR}
            COMPONENT kaldi)
    
    if(OPENFST_SCRIPT_LIB)
        install(FILES ${OPENFST_SCRIPT_LIB} DESTINATION ${CMAKE_INSTALL_LIBDIR}
                COMPONENT kaldi)
    endif()
endif()
