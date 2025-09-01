cmake_minimum_required(VERSION 3.14)

# CLAPACK auto-compilation configuration
# This will automatically download, configure, compile and install CLAPACK

include(ExternalProject)

set(CLAPACK_VERSION "v3.2.1")
set(CLAPACK_GIT_REPOSITORY "git@github.com:alphacep/clapack.git")
set(CLAPACK_GIT_TAG "${CLAPACK_VERSION}")
set(CLAPACK_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/external/clapack")
set(CLAPACK_INSTALL_DIR "${CMAKE_CURRENT_BINARY_DIR}/clapack_install")

# Check if CLAPACK is already compiled
find_library(CLAPACK_EXISTING_LIB f2c PATHS ${CLAPACK_INSTALL_DIR}/lib NO_DEFAULT_PATH)
find_path(CLAPACK_EXISTING_INCLUDE f2c.h PATHS ${CLAPACK_INSTALL_DIR}/include NO_DEFAULT_PATH)

if(CLAPACK_EXISTING_LIB AND CLAPACK_EXISTING_INCLUDE)
    message(STATUS "Found existing CLAPACK installation at ${CLAPACK_INSTALL_DIR}")
    set(CLAPACK_COMPILED TRUE)
else()
    message(STATUS "CLAPACK not found, will compile from source")
    set(CLAPACK_COMPILED FALSE)
endif()

if(NOT CLAPACK_COMPILED)
    # Create install directory early
    file(MAKE_DIRECTORY ${CLAPACK_INSTALL_DIR})
    file(MAKE_DIRECTORY ${CLAPACK_INSTALL_DIR}/lib)
    file(MAKE_DIRECTORY ${CLAPACK_INSTALL_DIR}/include)

    # Download and compile CLAPACK using cmake and make
    ExternalProject_Add(clapack_external
        GIT_REPOSITORY ${CLAPACK_GIT_REPOSITORY}
        GIT_TAG ${CLAPACK_GIT_TAG}
        GIT_SHALLOW ON
        PREFIX ${CLAPACK_PREFIX}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} <SOURCE_DIR>
        BUILD_COMMAND ${CMAKE_COMMAND} -E chdir <BINARY_DIR> make -C F2CLIBS/libf2c
              COMMAND ${CMAKE_COMMAND} -E chdir <BINARY_DIR> make -C BLAS  
              COMMAND ${CMAKE_COMMAND} -E chdir <BINARY_DIR> make -C SRC
        INSTALL_COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/F2CLIBS/libf2c/libf2c.a ${CLAPACK_INSTALL_DIR}/lib/
                COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/SRC/liblapack.a ${CLAPACK_INSTALL_DIR}/lib/
                COMMAND ${CMAKE_COMMAND} -E copy <BINARY_DIR>/BLAS/SRC/libblas.a ${CLAPACK_INSTALL_DIR}/lib/
                COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/INCLUDE/f2c.h ${CLAPACK_INSTALL_DIR}/include/
                COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/INCLUDE/clapack.h ${CLAPACK_INSTALL_DIR}/include/
        BUILD_BYPRODUCTS ${CLAPACK_INSTALL_DIR}/lib/libf2c.a 
                         ${CLAPACK_INSTALL_DIR}/lib/liblapack.a 
                         ${CLAPACK_INSTALL_DIR}/lib/libblas.a 
                         ${CLAPACK_INSTALL_DIR}/include/f2c.h
                         ${CLAPACK_INSTALL_DIR}/include/clapack.h
        LOG_DOWNLOAD ON
        LOG_CONFIGURE ON
        LOG_BUILD ON
        LOG_INSTALL ON
    )
    
    # Set variables for later use
    set(CLAPACK_ROOT ${CLAPACK_INSTALL_DIR})
    set(CLAPACK_LIBRARIES "${CLAPACK_INSTALL_DIR}/lib/libf2c.a;${CLAPACK_INSTALL_DIR}/lib/libblas.a;${CLAPACK_INSTALL_DIR}/lib/liblapack.a")
    set(CLAPACK_INCLUDE_DIRS ${CLAPACK_INSTALL_DIR}/include)
    
    # Create imported target with proper paths
    add_library(clapack STATIC IMPORTED GLOBAL)
    add_dependencies(clapack clapack_external)
    set_target_properties(clapack PROPERTIES
        IMPORTED_LOCATION ${CLAPACK_LIBRARIES}
        INTERFACE_INCLUDE_DIRECTORIES ${CLAPACK_INCLUDE_DIRS}
    )
else()
    # Use existing installation
    set(CLAPACK_ROOT ${CLAPACK_INSTALL_DIR})
    set(CLAPACK_LIBRARIES "${CLAPACK_EXISTING_LIB};${CLAPACK_INSTALL_DIR}/lib/libblas.a;${CLAPACK_INSTALL_DIR}/lib/liblapack.a")
    set(CLAPACK_INCLUDE_DIRS ${CLAPACK_EXISTING_INCLUDE})
    
    add_library(clapack STATIC IMPORTED GLOBAL)
    set_target_properties(clapack PROPERTIES
        IMPORTED_LOCATION ${CLAPACK_LIBRARIES}
        INTERFACE_INCLUDE_DIRECTORIES ${CLAPACK_INCLUDE_DIRS}
    )
endif()

# Export variables for use in main CMakeLists.txt
set(CLAPACK_FOUND TRUE PARENT_SCOPE)
set(CLAPACK_ROOT ${CLAPACK_ROOT} PARENT_SCOPE)
set(CLAPACK_LIBRARIES ${CLAPACK_LIBRARIES} PARENT_SCOPE)
set(CLAPACK_INCLUDE_DIRS ${CLAPACK_INCLUDE_DIRS} PARENT_SCOPE)

message(STATUS "CLAPACK configuration:")
message(STATUS "  Root: ${CLAPACK_ROOT}")
message(STATUS "  Libraries: ${CLAPACK_LIBRARIES}")
message(STATUS "  Include dirs: ${CLAPACK_INCLUDE_DIRS}")
