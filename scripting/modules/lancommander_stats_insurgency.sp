/**
 * LANCommander Match Statistics: Insurgency (2014) and Day of Infamy.
 *
 * Control point captures and neutralisations, cache and objective
 * destruction, and the match's end at game_end. Rounds and kills come from
 * the core plugin. Loads only on Insurgency and Day of Infamy.
 *
 * Field names follow the games' modevents.res; any a version lacks read as
 * empty and are left out.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Insurgency",
    author      = "LANCommander",
    description = "Insurgency and Day of Infamy objectives for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    EngineVersion engine = GetEngineVersion();
    return engine == Engine_Insurgency || engine == Engine_DOI ? APLRes_Success : APLRes_SilentFailure;
}

public void OnPluginStart()
{
    HookEventEx("controlpoint_captured", Event_PointCaptured);
    HookEventEx("controlpoint_neutralized", Event_PointNeutralized);
    HookEventEx("object_destroyed", Event_ObjectDestroyed);
    HookEventEx("game_end", Event_GameEnd);
}

public Action LCStats_OnMatchStarting(char[] externalId, int externalIdLength, char[] mode, int modeLength, LCPayload metadata)
{
    if (mode[0])
        return Plugin_Continue;

    // Insurgency names its modes in mp_gamemode (push, checkpoint, firefight, ...).
    ConVar gameMode = FindConVar("mp_gamemode");

    if (gameMode == null)
        return Plugin_Continue;

    gameMode.GetString(mode, modeLength);
    return Plugin_Changed;
}

// The first capturing client, from the cappers string (one client index per character).
int FirstCapper(Event event, LCPayload payload)
{
    char cappers[MAXPLAYERS + 1];
    event.GetString("cappers", cappers, sizeof(cappers));

    LCPayload keys = new LCPayload(true);
    char key[LCSTATS_MAX_KEY];
    int first = 0;

    for (int i = 0; cappers[i]; i++)
    {
        int client = cappers[i];

        if (client < 1 || client > MaxClients || !IsClientInGame(client))
            continue;

        if (!first)
            first = client;

        if (LCStats_GetPlayerKey(client, key, sizeof(key)))
            keys.PushString(key);

        LCStats_AddStat(client, "captures");
    }

    if (keys.Size > 0)
        payload.SetObject("cappers", keys);

    delete keys;
    return first;
}

public void Event_PointCaptured(Event event, const char[] name, bool dontBroadcast)
{
    char pointName[64];
    event.GetString("cpname", pointName, sizeof(pointName));

    LCPayload payload = new LCPayload();
    payload.SetInt("point", event.GetInt("cp"));

    if (pointName[0])
        payload.SetString("point_name", pointName);

    int team = event.GetInt("team");
    LCStats_AddTeam(payload, "team", team);

    int first = FirstCapper(event, payload);
    LCStats_Event("point_captured", first, 0, payload);
    delete payload;

    if (team >= 2)
        LCStats_AddTeamStat(team, "captures");
}

public void Event_PointNeutralized(Event event, const char[] name, bool dontBroadcast)
{
    LCPayload payload = new LCPayload();
    payload.SetInt("point", event.GetInt("cp"));
    LCStats_AddTeam(payload, "team", event.GetInt("team"));

    int first = FirstCapper(event, payload);
    LCStats_Event("point_neutralized", first, 0, payload);
    delete payload;
}

public void Event_ObjectDestroyed(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int assister = GetClientOfUserId(event.GetInt("assister"));

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    LCPayload payload = new LCPayload();
    payload.SetInt("point", event.GetInt("cp"));

    if (weapon[0])
        payload.SetString("weapon", weapon);

    LCStats_AddPlayer(payload, "assister", assister);
    LCStats_AddTeam(payload, "team", event.GetInt("attackerteam"));

    LCStats_Event("objective_destroyed", attacker, 0, payload);
    delete payload;

    if (attacker > 0)
        LCStats_AddStat(attacker, "objectives_destroyed");
}

public void Event_GameEnd(Event event, const char[] name, bool dontBroadcast)
{
    int winner = event.GetInt("winner");

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "winner", winner);
    LCStats_Event("game_end", 0, 0, payload);
    delete payload;

    LCStats_EndMatch("game_over");
}
