# CMakeLists.txt for nchw_preprocess native library
# 
# Build:
#   mkdir build && cd build
#   cmake .. -G "Visual Studio 17 2022" -A x64
#   cmake --build . --config Release
#
# Output: build/Release/nchw_preprocess.dll
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

# Windows: export all symbols
if(MSVC)
    set_target_properties(nchw_preprocess PROPERTIES
        WINDOWS_EXPORT_ALL_SYMBOLS TRUE
    )
endif()

# Install to runner directory
install(TARGETS nchw_preprocess
    RUNTIME DESTINATION ${CMAKE_SOURCE_DIR}/../../build/windows/x64/runner/Release
)
