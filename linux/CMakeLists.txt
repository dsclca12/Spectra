cmake_minimum_required(VERSION 3.13)
project(spectra LANGUAGES CXX)

set(BINARY_NAME "spectra")
set(APPLICATION_ID "com.example.spectra")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Configure build for release/debug
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()

# Find system packages in main scope so PkgConfig:: targets are visible to
# the application and all plugins (required by CMake 4.2+).
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED gtk+-3.0)
pkg_check_modules(GLIB REQUIRED glib-2.0)
pkg_check_modules(GIO REQUIRED gio-2.0)

# Create alias targets for pkg-config modules so they are visible
# in all subdirectory scopes (CMake 4.2+ compat).
add_library(PkgConfig::GTK INTERFACE IMPORTED)
target_include_directories(PkgConfig::GTK INTERFACE ${GTK_INCLUDE_DIRS})
target_link_directories(PkgConfig::GTK INTERFACE ${GTK_LIBRARY_DIRS})
target_link_libraries(PkgConfig::GTK INTERFACE ${GTK_LIBRARIES})
target_compile_options(PkgConfig::GTK INTERFACE ${GTK_CFLAGS_OTHER})

add_library(PkgConfig::GLIB INTERFACE IMPORTED)
target_include_directories(PkgConfig::GLIB INTERFACE ${GLIB_INCLUDE_DIRS})
target_link_directories(PkgConfig::GLIB INTERFACE ${GLIB_LIBRARY_DIRS})
target_link_libraries(PkgConfig::GLIB INTERFACE ${GLIB_LIBRARIES})
target_compile_options(PkgConfig::GLIB INTERFACE ${GLIB_CFLAGS_OTHER})

add_library(PkgConfig::GIO INTERFACE IMPORTED)
target_include_directories(PkgConfig::GIO INTERFACE ${GIO_INCLUDE_DIRS})
target_link_directories(PkgConfig::GIO INTERFACE ${GIO_LIBRARY_DIRS})
target_link_libraries(PkgConfig::GIO INTERFACE ${GIO_LIBRARIES})
target_compile_options(PkgConfig::GIO INTERFACE ${GIO_CFLAGS_OTHER})

# Include Flutter's managed CMake (defines flutter library, flutter_assemble, etc.)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/flutter)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Application sources
add_executable(spectra
    main.cc
    my_application.cc
    my_application.h
)

# Add the generated plugin registrant (from flutter/ephemeral/.plugin_symlinks)
# if it exists, but don't fail if not yet generated
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flutter/generated_plugin_registrant.cc")
  target_sources(spectra PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/flutter/generated_plugin_registrant.cc"
  )
endif()

# Apply standard settings
apply_standard_settings(spectra)

# Add preprocessor definitions for the application ID
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Link Flutter library (propagates GTK/GLIB/GIO and include paths)
target_link_libraries(spectra PRIVATE flutter)
target_link_libraries(spectra PRIVATE PkgConfig::GTK)

# Include directories
target_include_directories(spectra PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(spectra flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(spectra
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${CMAKE_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS spectra RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
