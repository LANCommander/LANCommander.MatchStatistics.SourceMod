/**
 * LANCommander Match Statistics: Military Conflict: Vietnam.
 *
 * MCV is built on the CS:GO code base, with modes of its own. This module
 * records kill details (penetration, backblast, kill distance, wipes,
 * dominations), damage amounts, bomb plants and defusals, grenades, MVPs,
 * Conquest flag captures, CTF and demolition actions, and airstrike calls.
 * Loads only on MCV.
 *
 * Event and field names are from vietnam/pak01's resource/modevents.res. Two
 * things come from MCV's own events rather than the shared ones:
 *  - MCV's player_hurt has no damage amount; character_hurt carries dmg_health.
 *  - The *_action events' actionid is recorded as a number, since the files do
 *    not say what each value means.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Military Conflict: Vietnam",
    author      = "LANCommander",
    description = "MCV objectives and combat for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

// player_death: userid, attacker, assister, assistedflash, weapon, headshot,
// backblast, dominated, revenge, wipe, penetrated, killdistance, othertype ...
bool  g_KillBackblast, g_KillAssistedFlash;
int   g_KillDominated, g_KillRevenge, g_KillWipe, g_KillPenetrated;
float g_KillDistance;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    return GetEngineVersion() == Engine_MCV ? APLRes_Success : APLRes_SilentFailure;
}

public void OnPluginStart()
{
    LCStats_HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
    LCStats_HookEvent("character_hurt", Event_CharacterHurt);

    LCStats_HookEvent("bomb_planted", Event_Bomb);
    LCStats_HookEvent("bomb_defused", Event_Bomb);
    LCStats_HookEvent("bomb_exploded", Event_Bomb);
    LCStats_HookEvent("hegrenade_detonate", Event_Grenade);
    LCStats_HookEvent("flashbang_detonate", Event_Grenade);
    LCStats_HookEvent("smokegrenade_detonate", Event_Grenade);
    LCStats_HookEvent("molotov_detonate", Event_Grenade);
    LCStats_HookEvent("round_mvp", Event_RoundMvp);

    LCStats_HookEvent("conquest_flag_captured", Event_ConquestCapture);
    LCStats_HookEvent("ctf_flag_action", Event_ObjectiveAction);
    LCStats_HookEvent("demolition_target_action", Event_ObjectiveAction);
    LCStats_HookEvent("ob_action", Event_ObjectiveAction);
    LCStats_HookEvent("airstrike_location", Event_Airstrike);

    // The final scoreboard, as in CS:GO. The core's game_end hook ends the
    // match too if MCV fires that; whichever comes first ends it.
    LCStats_HookEvent("cs_win_panel_match", Event_GameOver, EventHookMode_PostNoCopy);
}

public void Event_GameOver(Event event, const char[] name, bool dontBroadcast)
{
    LCStats_EndMatch("game_over");
}

// ── Combat ───────────────────────────────────────────────────────────────────

public Action Event_PlayerDeathPre(Event event, const char[] name, bool dontBroadcast)
{
    g_KillBackblast     = event.GetBool("backblast");
    g_KillAssistedFlash = event.GetBool("assistedflash");
    g_KillDominated     = event.GetInt("dominated");
    g_KillRevenge       = event.GetInt("revenge");
    g_KillWipe          = event.GetInt("wipe");
    g_KillPenetrated    = event.GetInt("penetrated");
    g_KillDistance      = event.GetFloat("killdistance");
    return Plugin_Continue;
}

public Action LCStats_OnEvent(const char[] type, int actor, int subject, LCPayload payload)
{
    if (!StrEqual(type, "kill"))
        return Plugin_Continue;

    if (g_KillBackblast)       payload.SetBool("backblast", true);
    if (g_KillAssistedFlash)   payload.SetBool("assisted_flash", true);
    if (g_KillPenetrated > 0)  payload.SetBool("penetrated", true);
    if (g_KillWipe > 0)        payload.SetBool("wipe", true);
    if (g_KillDominated > 0)   payload.SetBool("domination", true);
    if (g_KillRevenge > 0)     payload.SetBool("revenge", true);

    if (g_KillDistance > 0.0)
        payload.SetFloat("kill_distance", g_KillDistance);

    if (actor > 0)
    {
        if (g_KillDominated > 0) LCStats_AddStat(actor, "dominations");
        if (g_KillRevenge > 0)   LCStats_AddStat(actor, "revenges");
    }

    g_KillBackblast = g_KillAssistedFlash = false;
    g_KillDominated = g_KillRevenge = g_KillWipe = g_KillPenetrated = 0;
    g_KillDistance = 0.0;
    return Plugin_Changed;
}

// character_hurt: userid, attacker, health, armor, weapon, dmg_health, dmg_armor, hitgroup, damagetype.
public void Event_CharacterHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int damage   = event.GetInt("dmg_health");

    if (victim > 0 && damage > 0)
        LCStats_AddDamage(attacker, victim, damage);
}

// round_mvp: userid, reason, musickitmvps, nomusic.
public void Event_RoundMvp(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();
    payload.SetInt("reason", event.GetInt("reason"));
    LCStats_Event("round_mvp", client, 0, payload);
    delete payload;

    if (client > 0)
        LCStats_AddStat(client, "mvps");
}

// ── Objectives ───────────────────────────────────────────────────────────────

// bomb_planted / bomb_defused / bomb_exploded: userid, site.
public void Event_Bomb(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();
    payload.SetInt("site", event.GetInt("site"));
    LCStats_AddPosition(payload, "player", client);
    LCStats_Event(name, StrEqual(name, "bomb_exploded") ? 0 : client, 0, payload);
    delete payload;

    if (client < 1)
        return;

    if (StrEqual(name, "bomb_planted"))
        LCStats_AddStat(client, "bomb_plants");
    else if (StrEqual(name, "bomb_defused"))
        LCStats_AddStat(client, "bomb_defuses");
}

// *_detonate: userid, (entityid,) x, y, z.
public void Event_Grenade(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    char grenade[32];
    strcopy(grenade, sizeof(grenade), name);
    ReplaceString(grenade, sizeof(grenade), "_detonate", "");

    float position[3];
    position[0] = event.GetFloat("x");
    position[1] = event.GetFloat("y");
    position[2] = event.GetFloat("z");

    LCPayload payload = new LCPayload();
    payload.SetString("grenade", grenade);
    payload.SetVector("position", position);
    LCStats_Event("grenade_detonate", client, 0, payload);
    delete payload;

    if (client > 0)
        LCStats_AddStat(client, "grenades_thrown");
}

// conquest_flag_captured: userid, userid2, userid3 (the capturers), entindex,
// newteam, flagletter, capturer, capturemsg.
public void Event_ConquestCapture(Event event, const char[] name, bool dontBroadcast)
{
    static const char capturerFields[][] = { "userid", "userid2", "userid3" };

    int team = event.GetInt("newteam");

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "team", team);
    payload.SetInt("flag", event.GetInt("flagletter"));

    LCPayload capturers = new LCPayload(true);
    char key[LCSTATS_MAX_KEY];
    int first = 0;

    for (int i = 0; i < sizeof(capturerFields); i++)
    {
        int client = GetClientOfUserId(event.GetInt(capturerFields[i]));

        if (client < 1)
            continue;

        if (!first)
            first = client;

        if (LCStats_GetPlayerKey(client, key, sizeof(key)))
            capturers.PushString(key);

        LCStats_AddStat(client, "captures");
    }

    payload.SetObject("capturers", capturers);
    delete capturers;

    LCStats_Event("flag_captured", first, 0, payload);
    delete payload;

    if (team >= 2)
        LCStats_AddTeamStat(team, "captures");
}

// ctf_flag_action: userid, team, actionid. demolition_target_action: entindex,
// userid, bombtargetID, actionid, extra. ob_action: entindex, userid, team, actionid.
public void Event_ObjectiveAction(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    char type[48];
    strcopy(type, sizeof(type), name);
    ReplaceString(type, sizeof(type), "_action", "");

    LCPayload payload = new LCPayload();
    payload.SetString("objective", type);
    payload.SetInt("action", event.GetInt("actionid"));

    if (StrEqual(name, "demolition_target_action"))
        payload.SetInt("target", event.GetInt("bombtargetID"));
    else
        LCStats_AddTeam(payload, "team", event.GetInt("team"));

    LCStats_AddPosition(payload, "player", client);
    LCStats_Event("objective_action", client, 0, payload);
    delete payload;
}

// airstrike_location: team, x, y, z, type, timeduration, calleridx (a client index).
public void Event_Airstrike(Event event, const char[] name, bool dontBroadcast)
{
    int caller = event.GetInt("calleridx");

    if (caller < 1 || caller > MaxClients || !IsClientInGame(caller))
        caller = 0;

    float position[3];
    position[0] = event.GetFloat("x");
    position[1] = event.GetFloat("y");
    position[2] = event.GetFloat("z");

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "team", event.GetInt("team"));
    payload.SetInt("type", event.GetInt("type"));
    payload.SetVector("position", position);
    LCStats_Event("airstrike", caller, 0, payload);
    delete payload;

    if (caller > 0)
        LCStats_AddStat(caller, "airstrikes_called");
}
