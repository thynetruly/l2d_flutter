cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "l2d_flutter_plugin")
project(${PROJECT_NAME} LANGUAGES CXX)

# Invoke the build for native code shared with the other target platforms.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# Bundle both our plugin wrapper AND the prebuilt Cubism Core shared library.
set(l2d_flutter_plugin_bundled_libraries
  $<TARGET_FILE:l2d_flutter_plugin>
  "${CMAKE_CURRENT_SOURCE_DIR}/../Core/dll/linux/x86_64/libLive2DCubismCore.so"
  PARENT_SCOPE
)
