/**
 * LANCommander Match Statistics: Team Fortress 2.
 *
 * Control point captures and blocks, flags, buildings, teleports, ÜberCharges
 * and healing, dominations, revenges, backstabs and headshots, classes, round
 * wins and stalemates, Mann vs. Machine waves, and the match's end at game
 * over. Feigned deaths (the Dead Ringer) are not recorded. Loads only on TF2.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Team Fortress 2",
    author      = "LANCommander",
    description = "TF2 objectives, classes and support play for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

// player_death's death_flags.
#define DEATHFLAG_DOMINATION           (1 << 0)
#define DEATHFLAG_ASSISTER_DOMINATION  (1 << 1)
#define DEATHFLAG_REVENGE              (1 << 2)
#define DEATHFLAG_ASSISTER_REVENGE     (1 << 3)
#define DEATHFLAG_FIRST_BLOOD          (1 << 4)
#define DEATHFLAG_DEAD_RINGER          (1 << 5)

// player_death's customkill.
#define CUSTOMKILL_HEADSHOT            1
#define CUSTOMKILL_BACKSTAB            2
#define CUSTOMKILL_HEADSHOT_DECAP      51

static const char g_ClassNames[][] =
{
    "unknown", "scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer"
};

static const char g_ObjectNames[][] = { "dispenser", "teleporter", "sentry", "sapper" };

// What the next "kill" carries, from player_death (Pre).
int  g_KillCustom;
int  g_KillFlags;
int  g_KillCrit;
int  g_KillStreak;
char g_KillWeaponLog[64];
int  g_KillAttacker;
int  g_KillAssister;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    return GetEngineVersion() == Engine_TF2 ? APLRes_Success : APLRes_SilentFailure;
}

public void OnPluginStart()
{
    // Rounds come from teamplay_round_start / teamplay_round_win.
    LCStats_SetOwnRounds();

    LCStats_HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);

    LCStats_HookEvent("teamplay_round_start", Event_RoundStart);
    LCStats_HookEvent("teamplay_round_win", Event_RoundWin);
    LCStats_HookEvent("teamplay_round_stalemate", Event_RoundStalemate);
    LCStats_HookEvent("teamplay_game_over", Event_GameOver);
    LCStats_HookEvent("tf_game_over", Event_GameOver);

    LCStats_HookEvent("teamplay_point_captured", Event_PointCaptured);
    LCStats_HookEvent("teamplay_capture_blocked", Event_CaptureBlocked);
    LCStats_HookEvent("teamplay_flag_event", Event_FlagEvent);

    LCStats_HookEvent("player_builtobject", Event_BuiltObject);
    LCStats_HookEvent("object_destroyed", Event_ObjectDestroyed);
    LCStats_HookEvent("player_teleported", Event_Teleported);

    LCStats_HookEvent("player_chargedeployed", Event_ChargeDeployed);
    LCStats_HookEvent("medic_death", Event_MedicDeath);
    LCStats_HookEvent("player_healed", Event_Healed);

    LCStats_HookEvent("player_changeclass", Event_ChangeClass);

    HookEventEx("mvm_wave_complete", Event_MvM);
    HookEventEx("mvm_wave_failed", Event_MvM);
    HookEventEx("mvm_mission_complete", Event_MvMMission);
}

// ── The match ────────────────────────────────────────────────────────────────

public Action LCStats_OnMatchStarting(char[] externalId, int externalIdLength, char[] mode, int modeLength, LCPayload metadata)
{
    if (mode[0])
        return Plugin_Continue;

    GetMode(mode, modeLength);
    return Plugin_Changed;
}

void GetMode(char[] mode, int maxlength)
{
    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));

    int slash = FindCharInString(map, '/', true);
    int start = slash >= 0 ? slash + 1 : 0;

    static const char prefixes[][][] =
    {
        { "ctf_", "capture_the_flag" }, { "cp_", "control_points" }, { "pl_", "payload" },
        { "plr_", "payload_race" }, { "koth_", "king_of_the_hill" }, { "arena_", "arena" },
        { "mvm_", "mann_vs_machine" }, { "pd_", "player_destruction" }, { "sd_", "special_delivery" },
        { "rd_", "robot_destruction" }, { "tc_", "territorial_control" }, { "pass_", "passtime" },
        { "tr_", "training" }, { "mge_", "mge" }, { "ultiduo_", "ultiduo" }
    };

    for (int i = 0; i < sizeof(prefixes); i++)
    {
        if (StrContains(map[start], prefixes[i][0], false) == 0)
        {
            strcopy(mode, maxlength, prefixes[i][1]);
            return;
        }
    }

    strcopy(mode, maxlength, "other");
}

// teamplay_game_over and tf_game_over both fire; the second finds no match.
public void Event_GameOver(Event event, const char[] name, bool dontBroadcast)
{
    LCStats_EndMatch("game_over");
}

// ── Rounds ───────────────────────────────────────────────────────────────────

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    LCPayload payload = new LCPayload();
    payload.SetBool("full_reset", event.GetBool("full_reset"));
    LCStats_Event("round_start", 0, 0, payload);
    delete payload;
}

public void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
    int team = event.GetInt("team");

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "winner", team);
    payload.SetInt("reason", event.GetInt("winreason"));
    payload.SetBool("full_round", event.GetInt("full_round") != 0);
    payload.SetFloat("round_time", event.GetFloat("round_time"));
    payload.SetBool("sudden_death", event.GetBool("was_sudden_death"));

    LCStats_Event("round_end", 0, 0, payload);
    delete payload;

    if (team >= 2)
        LCStats_AddTeamStat(team, "rounds_won");
}

public void Event_RoundStalemate(Event event, const char[] name, bool dontBroadcast)
{
    LCPayload payload = new LCPayload();
    payload.SetBool("stalemate", true);
    payload.SetInt("reason", event.GetInt("reason"));
    LCStats_Event("round_end", 0, 0, payload);
    delete payload;
}

// ── Kills ────────────────────────────────────────────────────────────────────

public Action Event_PlayerDeathPre(Event event, const char[] name, bool dontBroadcast)
{
    g_KillCustom   = event.GetInt("customkill");
    g_KillFlags    = event.GetInt("death_flags");
    g_KillCrit     = event.GetInt("crit_type");
    g_KillStreak   = event.GetInt("kill_streak_total");
    g_KillAttacker = GetClientOfUserId(event.GetInt("attacker"));
    g_KillAssister = GetClientOfUserId(event.GetInt("assister"));
    event.GetString("weapon_logclassname", g_KillWeaponLog, sizeof(g_KillWeaponLog));
    return Plugin_Continue;
}

public Action LCStats_OnEvent(const char[] type, int actor, int subject, LCPayload payload)
{
    if (StrEqual(type, "kill"))
        return DescribeKill(payload);

    if (StrEqual(type, "spawn") && actor > 0)
    {
        payload.SetString("class", ClassName(actor));
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

Action DescribeKill(LCPayload payload)
{
    // The Dead Ringer: the spy is not dead.
    if (g_KillFlags & DEATHFLAG_DEAD_RINGER)
        return Plugin_Handled;

    if (g_KillCustom)
        payload.SetInt("custom_kill", g_KillCustom);

    if (g_KillWeaponLog[0])
        payload.SetString("weapon_log", g_KillWeaponLog);

    if (g_KillCrit == 1)
        payload.SetBool("mini_crit", true);
    else if (g_KillCrit == 2)
        payload.SetBool("crit", true);

    if (g_KillStreak > 0)
        payload.SetInt("kill_streak", g_KillStreak);

    bool headshot = g_KillCustom == CUSTOMKILL_HEADSHOT || g_KillCustom == CUSTOMKILL_HEADSHOT_DECAP;
    bool backstab = g_KillCustom == CUSTOMKILL_BACKSTAB;

    if (headshot)
        payload.SetBool("headshot", true);

    if (backstab)
        payload.SetBool("backstab", true);

    if (g_KillFlags & DEATHFLAG_DOMINATION)  payload.SetBool("domination", true);
    if (g_KillFlags & DEATHFLAG_REVENGE)     payload.SetBool("revenge", true);
    if (g_KillFlags & DEATHFLAG_FIRST_BLOOD) payload.SetBool("first_blood", true);

    int attacker = g_KillAttacker;

    if (attacker > 0)
    {
        payload.SetString("attacker_class", ClassName(attacker));

        if (headshot)                              LCStats_AddStat(attacker, "headshots");
        if (backstab)                              LCStats_AddStat(attacker, "backstabs");
        if (g_KillFlags & DEATHFLAG_DOMINATION)    LCStats_AddStat(attacker, "dominations");
        if (g_KillFlags & DEATHFLAG_REVENGE)       LCStats_AddStat(attacker, "revenges");
    }

    if (g_KillAssister > 0)
    {
        if (g_KillFlags & DEATHFLAG_ASSISTER_DOMINATION) LCStats_AddStat(g_KillAssister, "dominations");
        if (g_KillFlags & DEATHFLAG_ASSISTER_REVENGE)    LCStats_AddStat(g_KillAssister, "revenges");
    }

    return Plugin_Changed;
}

char[] ClassName(int client)
{
    char name[16] = "unknown";

    if (client > 0 && IsClientInGame(client))
    {
        int index = view_as<int>(TF2_GetPlayerClass(client));

        if (index >= 0 && index < sizeof(g_ClassNames))
            strcopy(name, sizeof(name), g_ClassNames[index]);
    }

    return name;
}

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

// ── Objectives ───────────────────────────────────────────────────────────────

public void Event_PointCaptured(Event event, const char[] name, bool dontBroadcast)
{
    int team = event.GetInt("team");

    char pointName[64], cappers[MAXPLAYERS + 1];
    event.GetString("cpname", pointName, sizeof(pointName));
    event.GetString("cappers", cappers, sizeof(cappers));

    LCPayload payload = new LCPayload();
    payload.SetInt("point", event.GetInt("cp"));
    payload.SetString("point_name", pointName);
    LCStats_AddTeam(payload, "team", team);

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

    LCStats_Event("point_captured", first, 0, payload);
    delete payload;

    if (team >= 2)
        LCStats_AddTeamStat(team, "captures");
}

public void Event_CaptureBlocked(Event event, const char[] name, bool dontBroadcast)
{
    int blocker = event.GetInt("blocker");
    int victim  = event.GetInt("victim");

    if (blocker < 1 || blocker > MaxClients || !IsClientInGame(blocker))
        return;

    if (victim < 1 || victim > MaxClients || !IsClientInGame(victim))
        victim = 0;

    char pointName[64];
    event.GetString("cpname", pointName, sizeof(pointName));

    LCPayload payload = new LCPayload();
    payload.SetInt("point", event.GetInt("cp"));
    payload.SetString("point_name", pointName);
    LCStats_Event("capture_blocked", blocker, victim, payload);
    delete payload;

    LCStats_AddStat(blocker, "defenses");
}

public void Event_FlagEvent(Event event, const char[] name, bool dontBroadcast)
{
    static const char types[][] = { "", "flag_pickup", "flag_captured", "flag_defended", "flag_dropped", "flag_returned" };

    int type    = event.GetInt("eventtype");
    int player  = event.GetInt("player");
    int carrier = event.GetInt("carrier");

    if (type < 1 || type >= sizeof(types))
        return;

    if (player < 1 || player > MaxClients || !IsClientInGame(player))
        player = 0;

    if (carrier < 1 || carrier > MaxClients || !IsClientInGame(carrier) || carrier == player)
        carrier = 0;

    LCPayload payload = new LCPayload();
    LCStats_AddPosition(payload, "player", player);

    // A defence stops a carrier: they are the subject.
    LCStats_Event(types[type], player, type == 3 ? carrier : 0, payload);
    delete payload;

    if (player == 0)
        return;

    if (type == 2)
    {
        LCStats_AddStat(player, "flag_captures");
        LCStats_AddTeamStat(GetClientTeam(player), "flag_captures");
    }
    else if (type == 3)
        LCStats_AddStat(player, "flag_defenses");
}

// ── Buildings ────────────────────────────────────────────────────────────────

void SetObjectName(LCPayload payload, int type)
{
    if (type >= 0 && type < sizeof(g_ObjectNames))
        payload.SetString("object", g_ObjectNames[type]);
}

public void Event_BuiltObject(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();
    SetObjectName(payload, event.GetInt("object"));
    LCStats_AddPosition(payload, "player", client);
    LCStats_Event("building_built", client, 0, payload);
    delete payload;

    if (client > 0)
        LCStats_AddStat(client, "buildings_built");
}

public void Event_ObjectDestroyed(Event event, const char[] name, bool dontBroadcast)
{
    int owner    = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int assister = GetClientOfUserId(event.GetInt("assister"));

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    LCPayload payload = new LCPayload();
    SetObjectName(payload, event.GetInt("objecttype"));
    payload.SetString("weapon", weapon);
    payload.SetBool("was_building", event.GetBool("was_building"));
    LCStats_AddPlayer(payload, "assister", assister);

    LCStats_Event("building_destroyed", attacker != owner ? attacker : 0, owner, payload);
    delete payload;

    if (attacker > 0 && attacker != owner)
        LCStats_AddStat(attacker, "buildings_destroyed");
}

public void Event_Teleported(Event event, const char[] name, bool dontBroadcast)
{
    int player  = GetClientOfUserId(event.GetInt("userid"));
    int builder = GetClientOfUserId(event.GetInt("builderid"));

    if (builder < 1 || builder == player)
        return;

    LCStats_Event("teleported", builder, player);
    LCStats_AddStat(builder, "teleports");
}

// ── Medics ───────────────────────────────────────────────────────────────────

public void Event_ChargeDeployed(Event event, const char[] name, bool dontBroadcast)
{
    int medic  = GetClientOfUserId(event.GetInt("userid"));
    int target = GetClientOfUserId(event.GetInt("targetid"));

    LCStats_Event("ubercharge", medic, target);

    if (medic > 0)
        LCStats_AddStat(medic, "ubercharges");
}

public void Event_MedicDeath(Event event, const char[] name, bool dontBroadcast)
{
    int medic    = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    bool charged = event.GetBool("charged");

    LCPayload payload = new LCPayload();
    payload.SetBool("charged", charged);
    payload.SetInt("healing", event.GetInt("healing"));
    LCStats_Event("medic_killed", attacker != medic ? attacker : 0, medic, payload);
    delete payload;

    if (charged && medic > 0)
        LCStats_AddStat(medic, "ubercharges_dropped");
}

public void Event_Healed(Event event, const char[] name, bool dontBroadcast)
{
    int patient = GetClientOfUserId(event.GetInt("patient"));
    int healer  = GetClientOfUserId(event.GetInt("healer"));
    int amount  = event.GetInt("amount");

    if (amount <= 0)
        return;

    if (healer > 0 && healer != patient)
        LCStats_AddStat(healer, "healing", float(amount));

    if (patient > 0)
        LCStats_AddStat(patient, "healing_received", float(amount));
}

// ── Mann vs. Machine ─────────────────────────────────────────────────────────

public void Event_MvM(Event event, const char[] name, bool dontBroadcast)
{
    LCStats_Event(name);
}

public void Event_MvMMission(Event event, const char[] name, bool dontBroadcast)
{
    char mission[64];
    event.GetString("mission", mission, sizeof(mission));

    LCPayload payload = new LCPayload();
    payload.SetString("mission", mission);
    LCStats_Event("mvm_mission_complete", 0, 0, payload);
    delete payload;

    LCStats_EndMatch("mission_complete");
}
