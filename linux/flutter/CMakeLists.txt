cmake_minimum_required(VERSION 3.13)

# This CMake file manages the Flutter engine library and plugin registration.

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")
set(GENERATED_DIR "${EPHEMERAL_DIR}")

# Locate the Flutter engine library
set(FLUTTER_LIBRARY "${EPHEMERAL_DIR}/libflutter_linux_gtk.so")

# Locate the Flutter engine header
set(FLUTTER_ENGINE_INCLUDE_DIR "${EPHEMERAL_DIR}")

# Include generated plugin configuration
include(${CMAKE_CURRENT_SOURCE_DIR}/generated_plugins.cmake OPTIONAL)

# Add the Flutter engine as an imported shared library
add_library(flutter SHARED IMPORTED)
set_target_properties(flutter PROPERTIES
    IMPORTED_LOCATION "${FLUTTER_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${FLUTTER_ENGINE_INCLUDE_DIR}"
)

# Find required system packages
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED gtk+-3.0)
pkg_check_modules(GLIB REQUIRED glib-2.0)

# Add pkg-config dependencies to the flutter target
target_link_libraries(flutter INTERFACE
    PkgConfig::GTK
    PkgConfig::GLIB
)

# Plugin targets will be added by generated_plugins.cmake
