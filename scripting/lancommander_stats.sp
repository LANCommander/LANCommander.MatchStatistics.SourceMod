/**
 * LANCommander Match Statistics: the core plugin.
 *
 * Reports every map played on this server to LANCommander as a match: who
 * played, what happened (kills, damage, rounds, chat, admin actions), and how
 * it ended. Works on any Source game on its own; the game modules
 * (lancommander_stats_<game>.smx) add each game's objectives, and the
 * integrations add what popular plugins know (Get5, PUG plugins, SourceBans).
 *
 * Configured with cvars, in cfg/sourcemod/lancommander.cfg (written on first
 * load). Delivery -- batching, retrying, keeping unsent reports on disk -- is
 * the LANCommander Interposer's, inside the lancommander extension.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <lancommander>

#define PLUGIN_VERSION "1.0.0"

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics",
    author      = "LANCommander",
    description = "Reports matches, players and events to a LANCommander server",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/LANCommander"
};

#include "lancommander_stats/globals.sp"
#include "lancommander_stats/config.sp"
#include "lancommander_stats/players.sp"
#include "lancommander_stats/match.sp"
#include "lancommander_stats/events.sp"
#include "lancommander_stats/eventmap.sp"
#include "lancommander_stats/demos.sp"
#include "lancommander_stats/commands.sp"
#include "lancommander_stats/api.sp"

// Loaded while a map was running: SourceMod calls OnMapStart anyway, and that
// first call is not a new map.
bool g_LateLoad;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_LateLoad = late;
    RegPluginLibrary("lancommander_stats");
    CreateApi();
    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations("common.phrases");

    g_LeftPlayers = new StringMap();
    g_PlayerResultSet = new StringMap();

    CreateConfig();
    LoadGameModule();
    HookGenericEvents();
    RegisterCommands();
    RegisterDemoListeners();

    // A late load: the map is already running and players are in. A reload
    // finds when this map started where the previous load left it, so it
    // carries on with the same match (the external id includes it).
    g_MapStartUnix = RecallMapStart();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && IsClientAuthorized(client))
            OnClientPostAdminCheck(client);
    }
}

public void OnPluginEnd()
{
    // Not ended: a plugin reload starts the same match again (the same
    // external id) and carries on with it, and at a server shutdown
    // LANCommander abandons a match nobody ends. Send what we have.
    if (g_Match)
        LC_MatchFlush(g_Match, 1500);
}

public void OnMapStart()
{
    if (g_LateLoad)
    {
        g_LateLoad     = false;
        g_MapStartUnix = RecallMapStart();
    }
    else
    {
        g_MapStartUnix = GetTime();
        RememberMapStart(g_MapStartUnix);
    }

    g_MatchDoneThisMap = false;
    g_MatchHeld        = false;
    g_Round            = 0;
    g_Warmup           = false;

    for (int team = 0; team < LC_MAX_TEAMS; team++)
        g_TeamNameOverride[team][0] = '\0';

    AttachPendingDemo();
}

// The module for this game. Source SDK 2013 and Alien Swarm mods share an
// engine, so those are told apart by game folder; the rest by engine.
bool GetGameModuleName(char[] module, int maxlength)
{
    char folder[64];
    GetGameFolderName(folder, sizeof(folder));

    static const char byFolder[][] = { "fof", "dab", "empires", "lambdawars" };

    for (int i = 0; i < sizeof(byFolder); i++)
    {
        if (StrEqual(folder, byFolder[i], false))
        {
            FormatEx(module, maxlength, "lancommander_stats_%s", byFolder[i]);
            return true;
        }
    }

    switch (GetEngineVersion())
    {
        case Engine_CSS, Engine_CSGO:             strcopy(module, maxlength, "lancommander_stats_cstrike");
        case Engine_TF2:                          strcopy(module, maxlength, "lancommander_stats_tf2");
        case Engine_DODS:                         strcopy(module, maxlength, "lancommander_stats_dods");
        case Engine_Left4Dead, Engine_Left4Dead2: strcopy(module, maxlength, "lancommander_stats_l4d");
        case Engine_Insurgency, Engine_DOI:       strcopy(module, maxlength, "lancommander_stats_insurgency");
        case Engine_PVKII:                        strcopy(module, maxlength, "lancommander_stats_pvkii");
        case Engine_MCV:                          strcopy(module, maxlength, "lancommander_stats_mcv");
        case Engine_DarkMessiah:                  strcopy(module, maxlength, "lancommander_stats_darkmessiah");
        case Engine_HL2DM:                        strcopy(module, maxlength, "lancommander_stats_hl2dm");
        default:                                  return false;
    }

    return true;
}

// The game modules ship in plugins/disabled/, so SourceMod does not try every
// one on every game (a module refusing another game still logs an error). The
// core loads the one for this game. One placed in plugins/ by hand loads
// itself as usual, and is not loaded twice.
void LoadGameModule()
{
    char module[64];

    if (!GetGameModuleName(module, sizeof(module)))
        return;

    char file[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
    FormatEx(file, sizeof(file), "%s.smx", module);

    if (FindPluginByFile(file) != null)
        return;

    BuildPath(Path_SM, path, sizeof(path), "plugins/disabled/%s", file);

    // Now rather than on the next frame, so the module is in before the first
    // match starts and can name its mode and teams.
    if (FileExists(path))
    {
        InsertServerCommand("sm plugins load disabled/%s", file);
        ServerExecute();
    }
}

// The map and when it started, in a hidden cvar: the engine keeps a plugin's
// cvar, value included, after the plugin unloads. Found rather than created
// when it exists, since CreateConVar on a reload resets it to its default.
ConVar MapStartCvar()
{
    ConVar cvar = FindConVar("lc_internal_map_start");

    if (cvar == null)
        cvar = CreateConVar("lc_internal_map_start", "", "Internal: the map and when it started",
            FCVAR_DONTRECORD | FCVAR_UNLOGGED | FCVAR_HIDDEN);

    return cvar;
}

void RememberMapStart(int unix)
{
    char map[PLATFORM_MAX_PATH], value[PLATFORM_MAX_PATH + 16];
    GetCurrentMap(map, sizeof(map));
    FormatEx(value, sizeof(value), "%d|%s", unix, map);
    MapStartCvar().SetString(value);
}

int RecallMapStart()
{
    char value[PLATFORM_MAX_PATH + 16], map[PLATFORM_MAX_PATH];
    MapStartCvar().GetString(value, sizeof(value));
    GetCurrentMap(map, sizeof(map));

    int bar = FindCharInString(value, '|');

    if (bar > 0 && StrEqual(value[bar + 1], map))
    {
        value[bar] = '\0';
        return StringToInt(value);
    }

    // First load on this map: as near its start as can be known.
    int unix = GetTime() - RoundToFloor(GetGameTime());
    RememberMapStart(unix);
    return unix;
}

public void OnConfigsExecuted()
{
    ApplyConfig();
    LoadEventFilter();
    LoadEventMap();
    TryStartMatch();
}

public void OnMapEnd()
{
    EndMatch("map_change", false);
}
