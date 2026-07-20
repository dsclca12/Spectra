cmake_minimum_required(VERSION 3.13)
project(spectra LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Configure build for release/debug
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()

# Include Flutter's generated CMake
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/flutter)

# Application sources
add_executable(spectra
    main.cc
    my_application.cc
    my_application.h
)

# Link Flutter library
target_link_libraries(spectra PRIVATE flutter)

# Link system libraries
target_link_libraries(spectra PRIVATE
    PkgConfig::GTK
    PkgConfig::GLIB
)

# Include directories
target_include_directories(spectra PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${FLUTTER_ENGINE_INCLUDE_DIR}
)

# Install rules
install(TARGETS spectra DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES ${FLUTTER_LIBRARY} DESTINATION ${CMAKE_INSTALL_LIBDIR})
