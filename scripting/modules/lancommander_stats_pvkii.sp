/**
 * LANCommander Match Statistics: Pirates, Vikings and Knights II.
 *
 * Kill details (backstabs, crits, combos, specials, nemesis and revenge),
 * NPC and building kills, real damage amounts (PVKII's player_hurt has none),
 * classes, points, chests, flags, the grail, territory and payload, and the
 * match result by team wins. Loads only on PVKII.
 *
 * Event and field names are from PVKII's resource/ModEvents.res. Teams are
 * 2 Pirates, 3 Vikings, 4 Knights; the mode is the map prefix (the core's
 * default: bt, tw, tdm, lts, ctf, pl, ...).
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: PVKII",
    author      = "LANCommander",
    description = "Pirates, Vikings and Knights II combat and objectives for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

// player_death fields for the "kill" that follows (the core reads assistid,
// headshot and weapon itself).
bool  g_KillBackstab, g_KillCrit, g_KillSpecial, g_KillCharged, g_KillNemesis, g_KillRevenge, g_KillRicochet;
int   g_KillCombo;
float g_KillDamage;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    return GetEngineVersion() == Engine_PVKII ? APLRes_Success : APLRes_SilentFailure;
}

public void OnPluginStart()
{
    LCStats_HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
    LCStats_HookEvent("npc_death", Event_NpcDeath);
    LCStats_HookEvent("buildable_death", Event_BuildableDeath);
    LCStats_HookEvent("player_comp_stattrack", Event_Damage);
    LCStats_HookEvent("player_changeclass", Event_ChangeClass);
    LCStats_HookEvent("player_points", Event_Points);

    LCStats_HookEvent("chest_pickup", Event_Chest);
    LCStats_HookEvent("chest_capture", Event_Chest);
    LCStats_HookEvent("flag_pickup", Event_Flag);
    LCStats_HookEvent("flag_capture", Event_Flag);
    LCStats_HookEvent("grail_pickup", Event_GrailPickup);
    LCStats_HookEvent("gamemode_territory_capture", Event_TerritoryCapture);
    LCStats_HookEvent("gamemode_payload_deliver", Event_PayloadDeliver);

    LCStats_HookEvent("match_end", Event_MatchEnd);
    LCStats_HookEvent("match_end_ffa", Event_MatchEndFfa);
}

// ── Kills ────────────────────────────────────────────────────────────────────

// player_death: userid, attacker, assistid, weapon, special, grail, headshot,
// nemesis, revenge, backstab, ricochet, damage (float), combo, charged, crit ...
public Action Event_PlayerDeathPre(Event event, const char[] name, bool dontBroadcast)
{
    g_KillBackstab = event.GetBool("backstab");
    g_KillCrit     = event.GetBool("crit");
    g_KillSpecial  = event.GetBool("special");
    g_KillCharged  = event.GetBool("charged");
    g_KillNemesis  = event.GetBool("nemesis");
    g_KillRevenge  = event.GetBool("revenge");
    g_KillRicochet = event.GetBool("ricochet");
    g_KillCombo    = event.GetInt("combo");
    g_KillDamage   = event.GetFloat("damage");
    return Plugin_Continue;
}

public Action LCStats_OnEvent(const char[] type, int actor, int subject, LCPayload payload)
{
    // PVKII's round_end has only winner; the shared reason the core read is 0.
    if (StrEqual(type, "round_end"))
    {
        payload.Remove("reason");
        return Plugin_Changed;
    }

    if (!StrEqual(type, "kill"))
        return Plugin_Continue;

    if (g_KillBackstab) payload.SetBool("backstab", true);
    if (g_KillCrit)     payload.SetBool("crit", true);
    if (g_KillSpecial)  payload.SetBool("special", true);
    if (g_KillCharged)  payload.SetBool("charged", true);
    if (g_KillNemesis)  payload.SetBool("nemesis", true);
    if (g_KillRevenge)  payload.SetBool("revenge", true);
    if (g_KillRicochet) payload.SetBool("ricochet", true);

    if (g_KillCombo > 0)
        payload.SetInt("combo", g_KillCombo);

    if (g_KillDamage > 0.0)
        payload.SetFloat("damage", g_KillDamage);

    if (actor > 0)
    {
        if (g_KillBackstab) LCStats_AddStat(actor, "backstabs");
        if (g_KillCrit)     LCStats_AddStat(actor, "crits");
        if (g_KillSpecial)  LCStats_AddStat(actor, "special_kills");
        if (g_KillNemesis)  LCStats_AddStat(actor, "nemesis");
        if (g_KillRevenge)  LCStats_AddStat(actor, "revenges");
    }

    g_KillBackstab = g_KillCrit = g_KillSpecial = g_KillCharged = g_KillNemesis = g_KillRevenge = g_KillRicochet = false;
    g_KillCombo  = 0;
    g_KillDamage = 0.0;
    return Plugin_Changed;
}

// npc_death: userid, attacker, weapon, special, type.
public void Event_NpcDeath(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    char type[64], weapon[64];
    event.GetString("type", type, sizeof(type));
    event.GetString("weapon", weapon, sizeof(weapon));

    LCPayload payload = new LCPayload();
    payload.SetString("npc", type);
    payload.SetString("weapon", weapon);
    LCStats_Event("npc_killed", attacker, 0, payload);
    delete payload;

    if (attacker > 0)
        LCStats_AddStat(attacker, "npc_kills");
}

// buildable_death: userid (the owner), attacker, weapon, special, building.
public void Event_BuildableDeath(Event event, const char[] name, bool dontBroadcast)
{
    int owner    = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    char building[64], weapon[64];
    event.GetString("building", building, sizeof(building));
    event.GetString("weapon", weapon, sizeof(weapon));

    LCPayload payload = new LCPayload();
    payload.SetString("building", building);
    payload.SetString("weapon", weapon);
    LCStats_Event("building_destroyed", attacker != owner ? attacker : 0, owner, payload);
    delete payload;

    if (attacker > 0 && attacker != owner)
        LCStats_AddStat(attacker, "buildings_destroyed");
}

// player_comp_stattrack: attacker, victim, damage (float), headshot, friendlyfire.
// PVKII's player_hurt carries no amount; this is where damage totals come from.
public void Event_Damage(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim   = GetClientOfUserId(event.GetInt("victim"));
    int damage   = RoundToNearest(event.GetFloat("damage"));

    if (victim > 0 && damage > 0)
        LCStats_AddDamage(attacker, victim, damage);
}

// player_changeclass: userid, old_class, new_class (class numbers).
public void Event_ChangeClass(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();
    payload.SetInt("from", event.GetInt("old_class"));
    payload.SetInt("to", event.GetInt("new_class"));
    LCStats_Event("class_change", client, 0, payload);
    delete payload;
}

// player_points: userid, points (float), sid.
public void Event_Points(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    float points = event.GetFloat("points");

    if (client > 0 && points != 0.0)
        LCStats_AddStat(client, "points", points);
}

// ── Objectives ───────────────────────────────────────────────────────────────

// chest_pickup: userid, chestid, last_owner, captured. chest_capture: userid, cappers, chestid, last_owner.
public void Event_Chest(Event event, const char[] name, bool dontBroadcast)
{
    int client  = GetClientOfUserId(event.GetInt("userid"));
    bool capture = StrEqual(name, "chest_capture");

    LCPayload payload = new LCPayload();
    payload.SetInt("chest", event.GetInt("chestid"));
    LCStats_AddPosition(payload, "player", client);
    LCStats_Event(capture ? "chest_captured" : "chest_pickup", client, 0, payload);
    delete payload;

    if (client > 0 && capture)
    {
        LCStats_AddStat(client, "chest_captures");
        LCStats_AddTeamStat(GetClientTeam(client), "chest_captures");
    }
}

// flag_pickup: team, userid. flag_capture: userid, flagid.
public void Event_Flag(Event event, const char[] name, bool dontBroadcast)
{
    int client  = GetClientOfUserId(event.GetInt("userid"));
    bool capture = StrEqual(name, "flag_capture");

    LCPayload payload = new LCPayload();
    LCStats_AddPosition(payload, "player", client);
    LCStats_Event(capture ? "flag_captured" : "flag_pickup", client, 0, payload);
    delete payload;

    if (client > 0 && capture)
    {
        LCStats_AddStat(client, "flag_captures");
        LCStats_AddTeamStat(GetClientTeam(client), "flag_captures");
    }
}

// grail_pickup: team, userid, victim, assistid, initial.
public void Event_GrailPickup(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victim"));

    LCPayload payload = new LCPayload();
    payload.SetBool("initial", event.GetBool("initial"));
    LCStats_Event("grail_pickup", client, victim, payload);
    delete payload;

    if (client > 0)
        LCStats_AddStat(client, "grail_pickups");
}

// gamemode_territory_capture: userids, team, tindex, territory, pcontrol, vcontrol, kcontrol, event_id.
public void Event_TerritoryCapture(Event event, const char[] name, bool dontBroadcast)
{
    int team = event.GetInt("team");

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "team", team);
    payload.SetInt("territory", event.GetInt("territory"));
    LCStats_Event("territory_captured", 0, 0, payload);
    delete payload;

    if (team >= 2)
        LCStats_AddTeamStat(team, "territories_captured");
}

// gamemode_payload_deliver: userids, team, final.
public void Event_PayloadDeliver(Event event, const char[] name, bool dontBroadcast)
{
    int team = event.GetInt("team");

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "team", team);
    payload.SetBool("final", event.GetBool("final"));
    LCStats_Event("payload_delivered", 0, 0, payload);
    delete payload;

    if (team >= 2)
        LCStats_AddTeamStat(team, "payloads_delivered");
}

// ── The match ────────────────────────────────────────────────────────────────

// match_end: winner, wins_p, wins_v, wins_k -- the teams ranked by rounds won.
public void Event_MatchEnd(Event event, const char[] name, bool dontBroadcast)
{
    int wins[3];
    wins[0] = event.GetInt("wins_p");
    wins[1] = event.GetInt("wins_v");
    wins[2] = event.GetInt("wins_k");

    for (int i = 0; i < 3; i++)
    {
        int team = i + 2;

        if (team >= GetTeamCount() || GetTeamClientCount(team) == 0)
            continue;

        int rank = 1;

        for (int j = 0; j < 3; j++)
        {
            if (wins[j] > wins[i])
                rank++;
        }

        LCStats_SetTeamStat(team, "rounds_won", float(wins[i]));
        LCStats_SetTeamResult(team, rank, rank == 1 ? LCResult_Finished : LCResult_Defeated, true, float(wins[i]));
    }

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "winner", event.GetInt("winner"));
    LCStats_Event("match_end", 0, 0, payload);
    delete payload;

    LCStats_EndMatch("game_over");
}

// match_end_ffa: winner. The core ranks free-for-all players by frags.
public void Event_MatchEndFfa(Event event, const char[] name, bool dontBroadcast)
{
    LCStats_EndMatch("game_over");
}
