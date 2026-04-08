cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "l2d_flutter_plugin")
project(${PROJECT_NAME} LANGUAGES CXX)

# Invoke the build for native code shared with the other target platforms.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# Determine Windows architecture for prebuilt library path
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  set(CUBISM_WIN_ARCH "x86_64")
else()
  set(CUBISM_WIN_ARCH "x86")
endif()

# Bundle both our plugin wrapper AND the prebuilt Cubism Core DLL.
set(l2d_flutter_plugin_bundled_libraries
  $<TARGET_FILE:l2d_flutter_plugin>
  "${CMAKE_CURRENT_SOURCE_DIR}/../Core/dll/windows/${CUBISM_WIN_ARCH}/Live2DCubismCore.dll"
  PARENT_SCOPE
)
