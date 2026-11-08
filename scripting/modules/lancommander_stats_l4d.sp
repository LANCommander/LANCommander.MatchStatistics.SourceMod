/**
 * LANCommander Match Statistics: Left 4 Dead and Left 4 Dead 2.
 *
 * Special infected attacks (pounces, pulls, rides, charges, bile), tanks and
 * witches, incapacitations, revives, heals and defibrillations, common
 * infected killed (as a total), awards, the safe room and the finale. The
 * mode comes from mp_gamemode. Loads only on L4D and L4D2.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Left 4 Dead",
    author      = "LANCommander",
    description = "L4D and L4D2 teamwork, special infected and finales for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    EngineVersion engine = GetEngineVersion();
    return engine == Engine_Left4Dead || engine == Engine_Left4Dead2 ? APLRes_Success : APLRes_SilentFailure;
}

public void OnPluginStart()
{
    // A special infected's attack on a survivor: userid is the attacker, victim the survivor.
    LCStats_HookEvent("lunge_pounce", Event_SpecialAttack);
    LCStats_HookEvent("tongue_grab", Event_SpecialAttack);
    HookEventEx("jockey_ride", Event_SpecialAttack);
    HookEventEx("charger_carry_start", Event_SpecialAttack);
    HookEventEx("charger_pummel_start", Event_SpecialAttack);
    LCStats_HookEvent("player_now_it", Event_Biled);

    LCStats_HookEvent("tank_spawn", Event_TankSpawn);
    LCStats_HookEvent("tank_killed", Event_TankKilled);
    LCStats_HookEvent("witch_killed", Event_WitchKilled);

    LCStats_HookEvent("player_incapacitated", Event_Incapacitated);
    LCStats_HookEvent("revive_success", Event_Revive);
    LCStats_HookEvent("heal_success", Event_Heal);
    HookEventEx("defibrillator_used", Event_Defib);

    LCStats_HookEvent("infected_death", Event_InfectedDeath);
    LCStats_HookEvent("award_earned", Event_Award);

    // friendly_fire: attacker, victim, guilty (userids), type. Both games.
    LCStats_HookEvent("friendly_fire", Event_FriendlyFire);
    // pills_used: userid, subject (L4D1 and L4D2); adrenaline_used: userid (L4D2).
    LCStats_HookEvent("pills_used", Event_Consumable);
    HookEventEx("adrenaline_used", Event_Consumable);
    // survivor_rescued: rescuer, victim (userids) -- a closet rescue.
    LCStats_HookEvent("survivor_rescued", Event_SurvivorRescued);
    // gascan_pour_completed: userid (L4D2 scavenge).
    HookEventEx("gascan_pour_completed", Event_GascanPoured);

    LCStats_HookEvent("map_transition", Event_MapTransition, EventHookMode_PostNoCopy);
    LCStats_HookEvent("finale_win", Event_FinaleWin);
    LCStats_HookEvent("mission_lost", Event_MissionLost, EventHookMode_PostNoCopy);
    HookEventEx("finale_vehicle_leaving", Event_VehicleLeaving);
}

public Action LCStats_OnMatchStarting(char[] externalId, int externalIdLength, char[] mode, int modeLength, LCPayload metadata)
{
    ConVar difficulty = FindConVar("z_difficulty");

    if (difficulty != null)
    {
        char value[32];
        difficulty.GetString(value, sizeof(value));
        metadata.SetString("difficulty", value);
    }

    if (!mode[0])
    {
        ConVar gameMode = FindConVar("mp_gamemode");

        if (gameMode != null)
            gameMode.GetString(mode, modeLength);
    }

    return Plugin_Changed;
}

// ── Special infected ─────────────────────────────────────────────────────────

public void Event_SpecialAttack(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("userid"));
    int victim   = GetClientOfUserId(event.GetInt("victim"));

    char type[48];

    if (StrEqual(name, "lunge_pounce"))              strcopy(type, sizeof(type), "hunter_pounce");
    else if (StrEqual(name, "tongue_grab"))          strcopy(type, sizeof(type), "smoker_pull");
    else if (StrEqual(name, "jockey_ride"))          strcopy(type, sizeof(type), "jockey_ride");
    else if (StrEqual(name, "charger_carry_start"))  strcopy(type, sizeof(type), "charger_carry");
    else                                             strcopy(type, sizeof(type), "charger_pummel");

    LCPayload payload = new LCPayload();

    if (StrEqual(name, "lunge_pounce"))
    {
        payload.SetInt("distance", event.GetInt("distance"));
        payload.SetInt("damage", event.GetInt("damage"));
    }

    LCStats_AddPosition(payload, "victim", victim);
    LCStats_Event(type, attacker, victim, payload);
    delete payload;

    if (attacker > 0)
        LCStats_AddStat(attacker, "special_attacks");
}

public void Event_Biled(Event event, const char[] name, bool dontBroadcast)
{
    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    LCPayload payload = new LCPayload();
    payload.SetBool("exploded", event.GetBool("exploded"));
    LCStats_Event("biled", attacker, victim, payload);
    delete payload;
}

// ── Bosses ───────────────────────────────────────────────────────────────────

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int tank = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();
    LCStats_AddPosition(payload, "tank", tank);
    LCStats_Event("tank_spawn", tank, 0, payload);
    delete payload;
}

public void Event_TankKilled(Event event, const char[] name, bool dontBroadcast)
{
    int tank     = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    LCPayload payload = new LCPayload();
    payload.SetBool("solo", event.GetBool("solo"));

    // tank_killed: userid, attacker, solo; L4D2 adds melee_only, l4d1_only.
    if (GetEngineVersion() == Engine_Left4Dead2)
        payload.SetBool("melee_only", event.GetBool("melee_only"));
    LCStats_Event("tank_killed", attacker, tank, payload);
    delete payload;

    if (attacker > 0)
        LCStats_AddStat(attacker, "tank_kills");
}

public void Event_WitchKilled(Event event, const char[] name, bool dontBroadcast)
{
    int killer = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();
    payload.SetBool("one_shot", event.GetBool("oneshot"));
    LCStats_AddPosition(payload, "killer", killer);
    LCStats_Event("witch_killed", killer, 0, payload);
    delete payload;

    if (killer > 0)
    {
        LCStats_AddStat(killer, "witch_kills");

        if (event.GetBool("oneshot"))
            LCStats_AddStat(killer, "witch_crowns");
    }
}

// ── Survivors ────────────────────────────────────────────────────────────────

public void Event_Incapacitated(Event event, const char[] name, bool dontBroadcast)
{
    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    LCPayload payload = new LCPayload();

    if (weapon[0])
        payload.SetString("weapon", weapon);

    LCStats_AddPosition(payload, "victim", victim);
    LCStats_Event("incapacitated", attacker != victim ? attacker : 0, victim, payload);
    delete payload;

    if (victim > 0)
        LCStats_AddStat(victim, "incapacitations");
}

public void Event_Revive(Event event, const char[] name, bool dontBroadcast)
{
    int reviver = GetClientOfUserId(event.GetInt("userid"));
    int subject = GetClientOfUserId(event.GetInt("subject"));

    LCPayload payload = new LCPayload();
    payload.SetBool("ledge", event.GetBool("ledge_hang"));
    payload.SetBool("last_life", event.GetBool("lastlife"));
    LCStats_Event("revive", reviver, subject, payload);
    delete payload;

    if (reviver > 0 && reviver != subject)
        LCStats_AddStat(reviver, "revives");
}

public void Event_Heal(Event event, const char[] name, bool dontBroadcast)
{
    int healer  = GetClientOfUserId(event.GetInt("userid"));
    int subject = GetClientOfUserId(event.GetInt("subject"));
    int amount  = event.GetInt("health_restored");

    LCPayload payload = new LCPayload();
    payload.SetInt("health_restored", amount);
    LCStats_Event("heal", healer, subject, payload);
    delete payload;

    if (healer > 0 && healer != subject)
        LCStats_AddStat(healer, "teammates_healed");
}

public void Event_Defib(Event event, const char[] name, bool dontBroadcast)
{
    int user    = GetClientOfUserId(event.GetInt("userid"));
    int subject = GetClientOfUserId(event.GetInt("subject"));

    LCStats_Event("defibrillated", user, subject);

    if (user > 0)
        LCStats_AddStat(user, "defibs");
}

// Commons die by the hundred: a total, not an event each.
public void Event_InfectedDeath(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (attacker < 1)
        return;

    LCStats_AddStat(attacker, "common_kills");

    if (event.GetBool("headshot"))
        LCStats_AddStat(attacker, "common_headshots");
}

public void Event_Award(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();
    payload.SetInt("award", event.GetInt("award"));
    LCStats_Event("award", client, 0, payload);
    delete payload;
}

public void Event_FriendlyFire(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim   = GetClientOfUserId(event.GetInt("victim"));
    int guilty   = GetClientOfUserId(event.GetInt("guilty"));

    LCPayload payload = new LCPayload();
    LCStats_AddPlayer(payload, "guilty", guilty);
    LCStats_Event("friendly_fire", attacker, victim, payload);
    delete payload;

    if (guilty > 0)
        LCStats_AddStat(guilty, "friendly_fire_incidents");
}

public void Event_Consumable(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    char type[32];
    strcopy(type, sizeof(type), name);   // pills_used, adrenaline_used

    LCStats_Event(type, client);

    if (client > 0)
        LCStats_AddStat(client, type);
}

public void Event_SurvivorRescued(Event event, const char[] name, bool dontBroadcast)
{
    int rescuer = GetClientOfUserId(event.GetInt("rescuer"));
    int victim  = GetClientOfUserId(event.GetInt("victim"));

    LCStats_Event("survivor_rescued", rescuer, victim);

    if (rescuer > 0)
        LCStats_AddStat(rescuer, "survivors_rescued");
}

public void Event_GascanPoured(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCStats_Event("gascan_poured", client);

    if (client > 0)
    {
        LCStats_AddStat(client, "gascans_poured");
        LCStats_AddTeamStat(GetClientTeam(client), "gascans_poured");
    }
}

// ── The campaign ─────────────────────────────────────────────────────────────

public void Event_MapTransition(Event event, const char[] name, bool dontBroadcast)
{
    LCStats_Event("safe_room_reached");
    LCStats_EndMatch("map_completed");
}

public void Event_FinaleWin(Event event, const char[] name, bool dontBroadcast)
{
    LCPayload payload = new LCPayload();
    payload.SetInt("difficulty", event.GetInt("difficulty"));
    LCStats_Event("finale_win", 0, 0, payload);
    delete payload;

    LCStats_EndMatch("finale_win");
}

// The survivors died; the map restarts and the same match goes on.
public void Event_MissionLost(Event event, const char[] name, bool dontBroadcast)
{
    LCStats_Event("mission_lost");
}

public void Event_VehicleLeaving(Event event, const char[] name, bool dontBroadcast)
{
    LCPayload payload = new LCPayload();
    payload.SetInt("survivors", event.GetInt("survivorcount"));
    LCStats_Event("rescue_vehicle_leaving", 0, 0, payload);
    delete payload;
}
