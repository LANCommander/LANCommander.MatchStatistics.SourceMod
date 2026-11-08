/**
 * LANCommander Match Statistics: Double Action: Boogaloo.
 *
 * Brawl and grenade kills, character changes, and the stunts Double Action
 * reports (dive punches, sky punches, "Dodge this" ...) as stunt events with a
 * total per stunt. The match ends at game_end, which the core handles. Loads
 * only on Double Action (game folder "dab"), whose server runs on Windows only.
 *
 * Event and field names are from dab/resource/modevents.res. DAB's player_hurt
 * has no damage or health, so only hits are counted.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Double Action",
    author      = "LANCommander",
    description = "Double Action: Boogaloo stunts and kills for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

// The stunt events; each has only userid.
static const char g_Stunts[][] =
{
    "DIVEPUNCHKILL", "DIVEAWAYFROMEXPLOSION", "DIVEAWAYFROMEXPLOSION_250", "DODGETHIS", "SKYPUNCH",
    "BETRAYED", "PENGUIN", "MAC_DADDYD", "VINDICATED", "HORSE_WHISPERER", "VIGILANT", "PERSUADED",
    "BLACK_MAGICKED", "UNDERTAKEN", "FALL_GUY", "SUPERFALL_SHARPSHOOTER", "SUPERFALL_KING",
    "STEADY_EDDIE", "POTSHOTTER", "SLOWPRO", "SPECIALDELIVERY", "NO_YOU_DONT", "GET_BANNED",
    "SOMEBODY_STOP_ME", "DISCOSTU", "HARDBOILED"
};

// player_death: userid, attacker, weapon, brawl, grenade.
bool g_KillBrawl, g_KillGrenade;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    char folder[32];
    GetGameFolderName(folder, sizeof(folder));
    return StrEqual(folder, "dab", false) ? APLRes_Success : APLRes_SilentFailure;
}

public void OnPluginStart()
{
    LCStats_HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
    LCStats_HookEvent("player_changeclass", Event_ChangeClass);

    for (int i = 0; i < sizeof(g_Stunts); i++)
        LCStats_HookEvent(g_Stunts[i], Event_Stunt);
}

public Action Event_PlayerDeathPre(Event event, const char[] name, bool dontBroadcast)
{
    g_KillBrawl   = event.GetBool("brawl");
    g_KillGrenade = event.GetBool("grenade");
    return Plugin_Continue;
}

public Action LCStats_OnEvent(const char[] type, int actor, int subject, LCPayload payload)
{
    if (!StrEqual(type, "kill") || (!g_KillBrawl && !g_KillGrenade))
        return Plugin_Continue;

    if (g_KillBrawl)
    {
        payload.SetBool("brawl", true);

        if (actor > 0)
            LCStats_AddStat(actor, "brawl_kills");
    }

    if (g_KillGrenade)
        payload.SetBool("grenade", true);

    g_KillBrawl = g_KillGrenade = false;
    return Plugin_Changed;
}

// player_changeclass: userid, class (the character).
public void Event_ChangeClass(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();
    payload.SetInt("class", event.GetInt("class"));
    LCStats_Event("class_change", client, 0, payload);
    delete payload;
}

public void Event_Stunt(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client < 1)
        return;

    char stunt[64], statistic[80];
    strcopy(stunt, sizeof(stunt), name);

    for (int i = 0; stunt[i]; i++)
        stunt[i] = CharToLower(stunt[i]);

    LCPayload payload = new LCPayload();
    payload.SetString("stunt", stunt);
    LCStats_AddPosition(payload, "player", client);
    LCStats_Event("stunt", client, 0, payload);
    delete payload;

    FormatEx(statistic, sizeof(statistic), "stunt_%s", stunt);
    LCStats_AddStat(client, statistic);
    LCStats_AddStat(client, "stunts");
}
