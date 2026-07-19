# CMakeLists.txt for ort_bridge native library
#
# Build:
#   mkdir build && cd build
#   cmake .. -G "Visual Studio 17 2022" -A x64
#   cmake --build . --config Release
#
# Output: build/Release/ort_bridge.dll
cmake_minimum_required(VERSION 3.16)
project(ort_bridge LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Optimize for speed (same as nchw_preprocess)
if(MSVC)
    add_compile_options(/O2 /fp:fast)
endif()

add_library(ort_bridge SHARED
    ort_bridge.c
)

target_include_directories(ort_bridge PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# Export the API functions
target_compile_definitions(ort_bridge PRIVATE ORT_BRIDGE_EXPORTS)

# Link Windows system libraries
if(WIN32)
    # No need to link against onnxruntime.lib - we use LoadLibrary at runtime
endif()

# Windows: export all symbols
if(MSVC)
    set_target_properties(ort_bridge PROPERTIES
        WINDOWS_EXPORT_ALL_SYMBOLS OFF
    )
endif()
