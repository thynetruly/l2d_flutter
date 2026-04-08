cmake_minimum_required(VERSION 3.10)

project(l2d_flutter_plugin_library VERSION 0.0.1 LANGUAGES C)

# Path to the Cubism Core SDK relative to this CMakeLists.txt
set(CUBISM_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../Core")

# Create our plugin shared library (empty stub, just links Core)
add_library(l2d_flutter_plugin SHARED
  "l2d_flutter_plugin.c"
)

# Include the Cubism Core header
target_include_directories(l2d_flutter_plugin PRIVATE
  "${CUBISM_CORE_DIR}/include"
)

set_target_properties(l2d_flutter_plugin PROPERTIES
  PUBLIC_HEADER l2d_flutter_plugin.h
  OUTPUT_NAME "l2d_flutter_plugin"
)

target_compile_definitions(l2d_flutter_plugin PUBLIC DART_SHARED_LIB)

# Platform-specific linking to the prebuilt Cubism Core library
if(ANDROID)
  # Android: link against the prebuilt .so for the current ABI
  add_library(Live2DCubismCore SHARED IMPORTED)
  set_target_properties(Live2DCubismCore PROPERTIES
    IMPORTED_LOCATION "${CUBISM_CORE_DIR}/dll/android/${ANDROID_ABI}/libLive2DCubismCore.so"
  )
  target_link_libraries(l2d_flutter_plugin Live2DCubismCore)
  # Support Android 15 16k page size
  target_link_options(l2d_flutter_plugin PRIVATE "-Wl,-z,max-page-size=16384")

elseif(WIN32)
  # Windows: link against the import library
  if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(CUBISM_WIN_ARCH "x86_64")
  else()
    set(CUBISM_WIN_ARCH "x86")
  endif()
  add_library(Live2DCubismCore SHARED IMPORTED)
  set_target_properties(Live2DCubismCore PROPERTIES
    IMPORTED_LOCATION "${CUBISM_CORE_DIR}/dll/windows/${CUBISM_WIN_ARCH}/Live2DCubismCore.dll"
    IMPORTED_IMPLIB "${CUBISM_CORE_DIR}/dll/windows/${CUBISM_WIN_ARCH}/Live2DCubismCore.lib"
  )
  target_link_libraries(l2d_flutter_plugin Live2DCubismCore)

elseif(APPLE)
  if(IOS)
    # iOS: link against static library
    add_library(Live2DCubismCore STATIC IMPORTED)
    set_target_properties(Live2DCubismCore PROPERTIES
      IMPORTED_LOCATION "${CUBISM_CORE_DIR}/lib/ios/Release-iphoneos/libLive2DCubismCore.a"
    )
  else()
    # macOS: link against dylib
    add_library(Live2DCubismCore SHARED IMPORTED)
    set_target_properties(Live2DCubismCore PROPERTIES
      IMPORTED_LOCATION "${CUBISM_CORE_DIR}/dll/macos/libLive2DCubismCore.dylib"
    )
  endif()
  target_link_libraries(l2d_flutter_plugin Live2DCubismCore)

else()
  # Linux: link against the prebuilt .so
  add_library(Live2DCubismCore SHARED IMPORTED)
  set_target_properties(Live2DCubismCore PROPERTIES
    IMPORTED_LOCATION "${CUBISM_CORE_DIR}/dll/linux/x86_64/libLive2DCubismCore.so"
  )
  target_link_libraries(l2d_flutter_plugin Live2DCubismCore)
endif()
