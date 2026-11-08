/**
 * LANCommander Match Statistics: PugSetup (splewis/csgo-pug-setup).
 *
 * Once a PUG is set up, the match starts when it goes live rather than at map
 * start, ends when PugSetup declares it over, and is abandoned if an admin
 * force-ends it. Team names come from mp_teamname_1/2 through the
 * Counter-Strike module; the demo PugSetup records is attached by the core
 * plugin. Without PugSetup loaded this plugin does nothing.
 *
 * PugSetup's forwards are implemented without its include; their signatures
 * are from pugsetup.inc (scripting/include/pugsetup.inc in csgo-pug-setup).
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: PugSetup",
    author      = "LANCommander",
    description = "Records PugSetup matches as LANCommander matches",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

// A PUG is set up and not yet over: hold the core's automatic start.
bool g_PugPending;

public void OnMapStart()
{
    // PugSetup keeps a PUG across the map change to the chosen map.
    if (!LibraryExists("pugsetup"))
        g_PugPending = false;
}

public Action LCStats_OnMatchStarting(char[] externalId, int externalIdLength, char[] mode, int modeLength, LCPayload metadata)
{
    return g_PugPending ? Plugin_Handled : Plugin_Continue;
}

// forward void PugSetup_OnSetup();
public void PugSetup_OnSetup()
{
    g_PugPending = true;

    // What was recorded until now was warmup.
    if (LCStats_GetMatch() != 0)
        LCStats_EndMatch("pug_setup", true);
}

// forward void PugSetup_OnLive();
public void PugSetup_OnLive()
{
    g_PugPending = true;

    if (LCStats_GetMatch() != 0)
        LCStats_EndMatch("pug_going_live", true);

    char map[PLATFORM_MAX_PATH], externalId[192];
    GetCurrentMap(map, sizeof(map));
    ReplaceString(map, sizeof(map), "/", "_");
    FormatEx(externalId, sizeof(externalId), "pug-%s-%d", map, GetTime());

    LCStats_SetWarmup(false);

    if (!LCStats_StartMatch(externalId, "pug"))
        LogError("Could not start a LANCommander match for the PUG");
}

// forward void PugSetup_OnMatchOver(bool hasDemo, const char[] demoFileName);
public void PugSetup_OnMatchOver(bool hasDemo, const char[] demoFileName)
{
    g_PugPending = false;
    LCStats_EndMatch("pug_over");
}

// forward void PugSetup_OnForceEnd(int client);
public void PugSetup_OnForceEnd(int client)
{
    g_PugPending = false;
    LCStats_EndMatch("pug_force_ended", true);
}
