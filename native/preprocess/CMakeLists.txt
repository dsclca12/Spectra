# CMakeLists.txt for nchw_preprocess native library
# 
# Build:
#   mkdir build && cd build
#   cmake .. -DCMAKE_BUILD_TYPE=Release
#   cmake --build .
#
# Output:
#   Windows: build/Release/nchw_preprocess.dll
#   Linux:   build/libnchw_preprocess.so
cmake_minimum_required(VERSION 3.16)
project(nchw_preprocess LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Optimize for speed
if(MSVC)
    add_compile_options(/O2 /arch:AVX2 /fp:fast)
else()
    add_compile_options(-O3 -march=native -ffast-math)
endif()

add_library(nchw_preprocess SHARED
    nchw_preprocess.c
)

target_include_directories(nchw_preprocess PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

# Platform-specific properties
if(MSVC)
    set_target_properties(nchw_preprocess PROPERTIES
        WINDOWS_EXPORT_ALL_SYMBOLS TRUE
    )
endif()

# Set output name consistently across platforms
set_target_properties(nchw_preprocess PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)

# Install to Flutter runner directory
if(WIN32)
    install(TARGETS nchw_preprocess
        RUNTIME DESTINATION ${CMAKE_SOURCE_DIR}/../../build/windows/x64/runner/Release
    )
elseif(UNIX AND NOT APPLE)
    install(TARGETS nchw_preprocess
        LIBRARY DESTINATION ${CMAKE_SOURCE_DIR}/../../build/linux/x64/runner/bundle/lib
    )
endif()
