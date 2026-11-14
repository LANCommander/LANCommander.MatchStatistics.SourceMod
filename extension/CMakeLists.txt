# lancommander.ext.dll / lancommander.ext.so: the SourceMod extension, with the
# Interposer linked in whole (LANCommander::Interposer::Embedded).

# The payload builder on its own, so the unit tests link it without SourceMod.
add_library(lancommander_payload STATIC payload.cpp)
target_include_directories(lancommander_payload PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
set_target_properties(lancommander_payload PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(lancommander.ext SHARED
    extension.cpp
    natives.cpp
    "${SOURCEMOD_DIR}/public/smsdk_ext.cpp"
)

# SourceMod looks for <name>.ext.<dll|so>, with no "lib" prefix.
set_target_properties(lancommander.ext PROPERTIES
    PREFIX                    ""
    OUTPUT_NAME               "lancommander.ext"
    C_VISIBILITY_PRESET       hidden
    CXX_VISIBILITY_PRESET     hidden
    VISIBILITY_INLINES_HIDDEN ON)

target_include_directories(lancommander.ext PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${SOURCEMOD_DIR}/public"
    "${SOURCEMOD_DIR}/public/extensions"
    "${SOURCEMOD_DIR}/sourcepawn/include"
    "${SOURCEMOD_DIR}/public/amtl"
    "${SOURCEMOD_DIR}/public/amtl/amtl")

target_compile_definitions(lancommander.ext PRIVATE
    LC_EXTENSION_VERSION="${PROJECT_VERSION}"
    SOURCEMOD_BUILD)

target_link_libraries(lancommander.ext PRIVATE lancommander_payload LANCommander::Interposer::Embedded)

if(WIN32)
    target_compile_definitions(lancommander.ext PRIVATE
        WIN32 _WINDOWS _CRT_SECURE_NO_WARNINGS _CRT_NONSTDC_NO_DEPRECATE)
    target_compile_options(lancommander.ext PRIVATE /W3 /EHsc)
    target_link_options(lancommander.ext PRIVATE /DEBUG "$<$<CONFIG:Release>:/OPT:REF;/OPT:ICF>")

    # Not interposer_ship_target: its YY-Thunks and XP subsystem settings exist
    # for games on Windows XP, and srcds needs a far newer Windows anyway.
else()
    target_compile_definitions(lancommander.ext PRIVATE
        _LINUX POSIX GNUC HAVE_STDINT_H
        stricmp=strcasecmp _stricmp=strcasecmp _snprintf=snprintf _vsnprintf=vsnprintf)
    target_compile_options(lancommander.ext PRIVATE
        -Wall -Wno-unused -Wno-non-virtual-dtor -Wno-overloaded-virtual -Wno-delete-non-virtual-dtor)

    # As the Interposer's own .so: the C++ runtime is linked in and hidden, since
    # srcds ships a libstdc++ of its own, and the dynamic symbol table is
    # GetSMExtAPI plus Interposer* (exports.map explains why those).
    target_link_options(lancommander.ext PRIVATE
        -static-libstdc++ -static-libgcc
        # Not ALL: that would hide the embedded Interposer's archive too, and a
        # symbol --exclude-libs hides the version script cannot make global again.
        "LINKER:--exclude-libs,libstdc++.a:libgcc.a:libgcc_eh.a:libyaml-cpp.a:libyaml-cppd.a"
        "LINKER:--no-undefined"
        "LINKER:--version-script=${CMAKE_CURRENT_SOURCE_DIR}/exports.map")
    set_property(TARGET lancommander.ext APPEND PROPERTY
        LINK_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/exports.map")
endif()

# Where SourceMod wants the binary: extensions/ for 32-bit, extensions/x64/ for 64-bit.
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(LC_EXTENSION_SUBDIR "addons/sourcemod/extensions/x64")
else()
    set(LC_EXTENSION_SUBDIR "addons/sourcemod/extensions")
endif()

install(TARGETS lancommander.ext
    RUNTIME DESTINATION "${LC_EXTENSION_SUBDIR}"
    LIBRARY DESTINATION "${LC_EXTENSION_SUBDIR}")
