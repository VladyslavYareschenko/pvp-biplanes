cmake_minimum_required(VERSION 3.20)
project(pvp-biplanes CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

# SDL2 is only needed for the desktop client.
# When cross-compiling for iOS, skip it.
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    find_package(SDL2 REQUIRED)
endif()

include(FetchContent)
FetchContent_Declare(
    nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG        v3.11.3
)
FetchContent_MakeAvailable(nlohmann_json)

# ---------------------------------------------------------------------------
# Shared libraries (built on ALL platforms including iOS)
# ---------------------------------------------------------------------------
add_subdirectory(core)
add_subdirectory(common)

# ---------------------------------------------------------------------------
# Desktop-only targets
# ---------------------------------------------------------------------------
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    add_subdirectory(server)
    add_subdirectory(client)
endif()
