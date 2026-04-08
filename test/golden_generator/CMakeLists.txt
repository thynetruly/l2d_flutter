cmake_minimum_required(VERSION 3.10)
project(cubism_golden_generator CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../Core")
set(FW_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../Framework/src")

# Gather all Framework source files (excluding Rendering subdirectories
# that need platform graphics APIs)
file(GLOB_RECURSE FW_SOURCES
  "${FW_SRC}/*.cpp"
)
# Remove rendering backend implementations (they need OpenGL/D3D/Metal/Vulkan)
list(FILTER FW_SOURCES EXCLUDE REGEX ".*/Rendering/(OpenGL|D3D|Metal|Vulkan|D3D9|D3D11)/.*")

add_library(CubismFramework STATIC ${FW_SOURCES})

target_include_directories(CubismFramework
  PUBLIC
    ${FW_SRC}
    ${CORE_DIR}/include
)

# Link against the Core static library
target_link_libraries(CubismFramework
  PUBLIC
    ${CORE_DIR}/lib/linux/x86_64/libLive2DCubismCore.a
)

# Build the golden generator
add_executable(golden_generator main.cpp renderer_stub.cpp)

target_include_directories(golden_generator PRIVATE ${FW_SRC})

target_link_libraries(golden_generator PRIVATE CubismFramework)
