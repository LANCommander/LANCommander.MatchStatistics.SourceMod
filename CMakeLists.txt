cmake_minimum_required(VERSION 3.25)

project(LANCommander.SourceMod.MatchStatistics VERSION 1.0.0 LANGUAGES C CXX)

if(NOT WIN32 AND NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
    message(FATAL_ERROR "The extension builds for Windows and Linux, as srcds runs on them.")
endif()

# The two source dependencies. Both default to the git submodules under
# external/; point LANCOMMANDER_INTERPOSER_DIR at a working copy of the
# Interposer to build against unreleased changes to it.
set(SOURCEMOD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/sourcemod"
    CACHE PATH "A SourceMod source tree (1.12 or later)")
set(LANCOMMANDER_INTERPOSER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/LANCommander.Interposer"
    CACHE PATH "A LANCommander.Interposer source tree")

foreach(required IN ITEMS "${SOURCEMOD_DIR}/public/smsdk_ext.cpp" "${LANCOMMANDER_INTERPOSER_DIR}/CMakeLists.txt")
    if(NOT EXISTS "${required}")
        message(FATAL_ERROR "${required} not found. Run: git submodule update --init --recursive")
    endif()
endforeach()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/$<CONFIG>")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/$<CONFIG>")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib/$<CONFIG>")

if(MSVC)
    # The static CRT, as SourceMod's own extensions and the Interposer's vcpkg
    # triplets (windows-static) use.
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# The Interposer, for LANCommander::Interposer::Embedded. EXCLUDE_FROM_ALL: only
# what the extension links is built, not the Interposer's DLL, tests or plugins.
add_subdirectory("${LANCOMMANDER_INTERPOSER_DIR}" interposer EXCLUDE_FROM_ALL)

add_subdirectory(extension)

include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
