/**
 * LANCommander Match Statistics: Half-Life 2: Deathmatch.
 *
 * HL2:DM's events are the shared ones, which the core records (kills, hits,
 * spawns, teams, game_end). This module only names the mode: "teamplay" when
 * mp_teamplay is on, "deathmatch" otherwise. HL2:DM's player_hurt has no
 * damage amount, so damage totals are not available. Loads only on HL2:DM.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Half-Life 2: Deathmatch",
    author      = "LANCommander",
    description = "HL2:DM mode for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    return GetEngineVersion() == Engine_HL2DM ? APLRes_Success : APLRes_SilentFailure;
}

public Action LCStats_OnMatchStarting(char[] externalId, int externalIdLength, char[] mode, int modeLength, LCPayload metadata)
{
    if (mode[0])
        return Plugin_Continue;

    ConVar teamplay = FindConVar("mp_teamplay");
    strcopy(mode, modeLength, teamplay != null && teamplay.BoolValue ? "teamplay" : "deathmatch");
    return Plugin_Changed;
}
