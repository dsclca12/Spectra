# CMakeLists.txt for ort_bridge native library
#
# Build:
#   mkdir build && cd build
#   cmake .. -DCMAKE_BUILD_TYPE=Release
#   cmake --build .
#
# Output:
#   Windows: build/Release/ort_bridge.dll
#   Linux:   build/libort_bridge.so
cmake_minimum_required(VERSION 3.16)
project(ort_bridge LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Optimize for speed
if(MSVC)
    add_compile_options(/O2 /fp:fast)
else()
    add_compile_options(-O2)
endif()

add_library(ort_bridge SHARED
    ort_bridge.c
)

target_include_directories(ort_bridge PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# Export the API functions
target_compile_definitions(ort_bridge PRIVATE ORT_BRIDGE_EXPORTS)

# Link system libraries
if(WIN32)
    # Windows: no extra libs needed - uses LoadLibrary at runtime
elseif(UNIX AND NOT APPLE)
    # Linux: link dl for dlopen/dlsym/dlclose
    target_link_libraries(ort_bridge PRIVATE ${CMAKE_DL_LIBS})
endif()

# Platform-specific properties
if(MSVC)
    set_target_properties(ort_bridge PROPERTIES
        WINDOWS_EXPORT_ALL_SYMBOLS OFF
    )
endif()

# Set output name consistently across platforms
set_target_properties(ort_bridge PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
