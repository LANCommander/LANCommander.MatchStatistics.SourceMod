#ifndef LANCOMMANDER_SMSDK_CONFIG_H
#define LANCOMMANDER_SMSDK_CONFIG_H

// Stamped in by CMake from the project version.
#ifndef LC_EXTENSION_VERSION
#define LC_EXTENSION_VERSION "0.0.0"
#endif

#define SMEXT_CONF_NAME        "LANCommander Match Statistics"
#define SMEXT_CONF_DESCRIPTION "Reports matches to a LANCommander server through the LANCommander Interposer"
#define SMEXT_CONF_VERSION     LC_EXTENSION_VERSION
#define SMEXT_CONF_AUTHOR      "LANCommander"
#define SMEXT_CONF_URL         "https://github.com/LANCommander"
#define SMEXT_CONF_LOGTAG      "LANCOMMANDER"
#define SMEXT_CONF_LICENSE     "GPL"
#define SMEXT_CONF_DATESTRING  __DATE__

#define SMEXT_LINK(name) SDKExtension *g_pExtensionIface = name;

// No Metamod and no game SDK: the extension only bridges natives to the
// Interposer, so one binary per OS and architecture serves every game.

#define SMEXT_ENABLE_FORWARDSYS
#define SMEXT_ENABLE_HANDLESYS

#endif // LANCOMMANDER_SMSDK_CONFIG_H
