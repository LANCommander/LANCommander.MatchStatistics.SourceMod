/**
 * LANCommander Match Statistics: Day of Defeat: Source.
 *
 * Flag captures and blocks, bomb plants, defusals and explosions, planters
 * and defusers stopped, round wins, and the match's end at game over. Loads
 * only on DoD:S.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Day of Defeat: Source",
    author      = "LANCommander",
    description = "DoD:S objectives and round results for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    return GetEngineVersion() == Engine_DODS ? APLRes_Success : APLRes_SilentFailure;
}

// player_death's dominated/revenge, for the "kill" that follows.
bool g_KillDominated, g_KillRevenge;

static const char g_ClassNames[][] = { "rifleman", "assault", "support", "sniper", "machinegunner", "rocket" };

public void OnPluginStart()
{
    // Rounds come from dod_round_start / dod_round_win, not the shared events.
    LCStats_SetOwnRounds();

    LCStats_HookEvent("dod_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    LCStats_HookEvent("dod_round_win", Event_RoundWin);
    LCStats_HookEvent("dod_game_over", Event_GameOver);
    LCStats_HookEvent("dod_warmup_begins", Event_WarmupBegins, EventHookMode_PostNoCopy);
    LCStats_HookEvent("dod_warmup_ends", Event_WarmupEnds, EventHookMode_PostNoCopy);

    LCStats_HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
    LCStats_HookEvent("player_changeclass", Event_ChangeClass);

    // DoD:S has no weapon_fire: its own stats event counts shots.
    LCStats_HookEvent("dod_stats_weapon_attack", Event_WeaponAttack);

    LCStats_HookEvent("dod_point_captured", Event_PointCaptured);
    LCStats_HookEvent("dod_capture_blocked", Event_CaptureBlocked);

    LCStats_HookEvent("dod_bomb_planted", Event_BombPlanted);
    LCStats_HookEvent("dod_bomb_defused", Event_BombDefused);
    LCStats_HookEvent("dod_bomb_exploded", Event_BombExploded);
    LCStats_HookEvent("dod_kill_planter", Event_KillPlanter);
    LCStats_HookEvent("dod_kill_defuser", Event_KillDefuser);
}

public Action LCStats_OnMatchStarting(char[] externalId, int externalIdLength, char[] mode, int modeLength, LCPayload metadata)
{
    if (mode[0])
        return Plugin_Continue;

    // Detonation maps have bomb targets; the rest are flag maps.
    strcopy(mode, modeLength, FindEntityByClassname(-1, "dod_bomb_target") != -1 ? "detonation" : "flags");
    return Plugin_Changed;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    LCStats_Event("round_start");
}

public void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
    int team = event.GetInt("team");

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "winner", team);
    LCStats_Event("round_end", 0, 0, payload);
    delete payload;

    if (team >= 2)
        LCStats_AddTeamStat(team, "rounds_won");
}

// dod_game_over: reason is why ("timelimit", "winlimit", ...).
public void Event_GameOver(Event event, const char[] name, bool dontBroadcast)
{
    char reason[64];
    event.GetString("reason", reason, sizeof(reason));

    LCPayload payload = new LCPayload();

    if (reason[0])
        payload.SetString("reason", reason);

    LCStats_Event("game_end", 0, 0, payload);
    delete payload;

    LCStats_EndMatch("game_over");
}

public void Event_WarmupBegins(Event event, const char[] name, bool dontBroadcast)
{
    LCStats_SetWarmup(true);
}

public void Event_WarmupEnds(Event event, const char[] name, bool dontBroadcast)
{
    LCStats_SetWarmup(false);
}

// player_death: dominated, revenge (bool); there is no headshot or assister.
public Action Event_PlayerDeathPre(Event event, const char[] name, bool dontBroadcast)
{
    g_KillDominated = event.GetBool("dominated");
    g_KillRevenge   = event.GetBool("revenge");
    return Plugin_Continue;
}

public Action LCStats_OnEvent(const char[] type, int actor, int subject, LCPayload payload)
{
    if (!StrEqual(type, "kill"))
        return Plugin_Continue;

    if (g_KillDominated)
        payload.SetBool("domination", true);

    if (g_KillRevenge)
        payload.SetBool("revenge", true);

    if (actor > 0)
    {
        if (g_KillDominated) LCStats_AddStat(actor, "dominations");
        if (g_KillRevenge)   LCStats_AddStat(actor, "revenges");
    }

    g_KillDominated = g_KillRevenge = false;
    return Plugin_Changed;
}

// player_changeclass: userid, class (0 rifleman .. 5 rocket).
public void Event_ChangeClass(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int index  = event.GetInt("class");

    if (client < 1 || index < 0 || index >= sizeof(g_ClassNames))
        return;

    LCPayload payload = new LCPayload();
    payload.SetString("class", g_ClassNames[index]);
    LCStats_Event("class_change", client, 0, payload);
    delete payload;
}

// dod_stats_weapon_attack: attacker (userid), weapon.
public void Event_WeaponAttack(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("attacker"));

    if (client > 0)
        LCStats_AddStat(client, "shots");
}

public void Event_PointCaptured(Event event, const char[] name, bool dontBroadcast)
{
    char pointName[64], cappers[MAXPLAYERS + 1];
    event.GetString("cpname", pointName, sizeof(pointName));
    event.GetString("cappers", cappers, sizeof(cappers));

    LCPayload payload = new LCPayload();
    payload.SetInt("point", event.GetInt("cp"));
    payload.SetString("point_name", pointName);

    if (event.GetBool("bomb"))
        payload.SetBool("by_bomb", true);

    // Each character of cappers is a capturing client's index.
    LCPayload capperKeys = new LCPayload(true);
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
            capperKeys.PushString(key);

        LCStats_AddStat(client, "captures");
    }

    payload.SetObject("cappers", capperKeys);
    delete capperKeys;

    if (first > 0)
        LCStats_AddTeam(payload, "team", GetClientTeam(first));

    LCStats_Event("point_captured", first, 0, payload);
    delete payload;

    if (first > 0)
        LCStats_AddTeamStat(GetClientTeam(first), "captures");
}

public void Event_CaptureBlocked(Event event, const char[] name, bool dontBroadcast)
{
    int blocker = event.GetInt("blocker");

    if (blocker < 1 || blocker > MaxClients || !IsClientInGame(blocker))
        return;

    char pointName[64];
    event.GetString("cpname", pointName, sizeof(pointName));

    LCPayload payload = new LCPayload();
    payload.SetInt("point", event.GetInt("cp"));
    payload.SetString("point_name", pointName);

    // dod_capture_blocked: cp, cpname, blocker (a client index), bomb.
    if (event.GetBool("bomb"))
        payload.SetBool("bomb", true);

    LCStats_Event("capture_blocked", blocker, 0, payload);
    delete payload;

    LCStats_AddStat(blocker, "defenses");
}

// The point a bomb event is at: cp and cpname, in every dod_bomb_* event.
LCPayload BombPayload(Event event, int client)
{
    char pointName[64];
    event.GetString("cpname", pointName, sizeof(pointName));

    LCPayload payload = new LCPayload();
    payload.SetInt("point", event.GetInt("cp"));

    if (pointName[0])
        payload.SetString("point_name", pointName);

    LCStats_AddPosition(payload, "player", client);
    return payload;
}

// dod_bomb_planted: cp, cpname, userid, team.
public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = BombPayload(event, client);
    LCStats_AddTeam(payload, "team", event.GetInt("team"));
    LCStats_Event("bomb_planted", client, 0, payload);
    delete payload;

    if (client > 0)
        LCStats_AddStat(client, "bomb_plants");
}

// dod_bomb_defused: cp, cpname, userid, team.
public void Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = BombPayload(event, client);
    LCStats_AddTeam(payload, "team", event.GetInt("team"));
    LCStats_Event("bomb_defused", client, 0, payload);
    delete payload;

    if (client > 0)
        LCStats_AddStat(client, "bomb_defuses");
}

// dod_bomb_exploded: cp, cpname, userid (the planter). No team field.
public void Event_BombExploded(Event event, const char[] name, bool dontBroadcast)
{
    int planter = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = BombPayload(event, 0);

    if (planter > 0)
        LCStats_AddTeam(payload, "team", GetClientTeam(planter));

    LCStats_Event("bomb_exploded", planter, 0, payload);
    delete payload;

    if (planter > 0)
        LCStats_AddStat(planter, "bomb_explosions");
}

public void Event_KillPlanter(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victimid"));

    LCStats_Event("planter_killed", client, victim);

    if (client > 0)
        LCStats_AddStat(client, "planters_killed");
}

public void Event_KillDefuser(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victimid"));

    LCStats_Event("defuser_killed", client, victim);

    if (client > 0)
        LCStats_AddStat(client, "defusers_killed");
}
