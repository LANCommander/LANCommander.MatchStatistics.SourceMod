/**
 * LANCommander Match Statistics: Dark Messiah of Might and Magic (multiplayer).
 *
 * Classes, capture-the-flag, the end-of-map tickets (map_stats) and campaign
 * progress (game_end's campaignover and end conditions), and Colliseum duels.
 * The match ends at game_end, which the core handles. Loads only on Dark
 * Messiah, whose dedicated server runs on Windows only.
 *
 * Event and field names are from the server's resource/modevents.res and
 * GameEvents.res. Dark Messiah's player_hurt has no damage amount and its
 * player_death no headshot, so neither is available.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Dark Messiah",
    author      = "LANCommander",
    description = "Dark Messiah multiplayer classes, CTF, tickets and Colliseum for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

// game_end: campaignover, winner, mapendcondition, campaignendcondition -- read
// before the core's own game_end hook ends the match.
bool g_CampaignOver;
int  g_MapEndCondition, g_CampaignEndCondition;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    return GetEngineVersion() == Engine_DarkMessiah ? APLRes_Success : APLRes_SilentFailure;
}

public void OnPluginStart()
{
    LCStats_HookEvent("game_end", Event_GameEndPre, EventHookMode_Pre);
    LCStats_HookEvent("player_class", Event_PlayerClass);
    LCStats_HookEvent("map_stats", Event_MapStats);

    LCStats_HookEvent("ctf_flag_taken", Event_Flag);
    LCStats_HookEvent("ctf_flag_dropped", Event_Flag);
    LCStats_HookEvent("ctf_flag_scored", Event_Flag);
    LCStats_HookEvent("ctf_flag_returned", Event_FlagReturned);

    LCStats_HookEvent("col_match_over", Event_ColliseumOver);
}

public Action Event_GameEndPre(Event event, const char[] name, bool dontBroadcast)
{
    g_CampaignOver         = event.GetBool("campaignover");
    g_MapEndCondition      = event.GetInt("mapendcondition");
    g_CampaignEndCondition = event.GetInt("campaignendcondition");
    return Plugin_Continue;
}

public Action LCStats_OnEvent(const char[] type, int actor, int subject, LCPayload payload)
{
    if (!StrEqual(type, "game_end"))
        return Plugin_Continue;

    payload.SetBool("campaign_over", g_CampaignOver);
    payload.SetInt("map_end_condition", g_MapEndCondition);
    payload.SetInt("campaign_end_condition", g_CampaignEndCondition);
    return Plugin_Changed;
}

// player_class: userid, class (a name).
public void Event_PlayerClass(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    char class[32];
    event.GetString("class", class, sizeof(class));

    LCPayload payload = new LCPayload();
    payload.SetString("class", class);
    LCStats_Event("class_change", client, 0, payload);
    delete payload;
}

// map_stats: MapName, TimeTaken, WinnerTickets, LoserTickets, Winners.
public void Event_MapStats(Event event, const char[] name, bool dontBroadcast)
{
    int winners = event.GetInt("Winners");

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "winner", winners);
    payload.SetFloat("time_taken", event.GetFloat("TimeTaken"));
    payload.SetInt("winner_tickets", event.GetInt("WinnerTickets"));
    payload.SetInt("loser_tickets", event.GetInt("LoserTickets"));
    LCStats_Event("map_stats", 0, 0, payload);
    delete payload;
}

// ctf_flag_taken / ctf_flag_dropped: userid. ctf_flag_scored: userid, pos_x/y/z.
public void Event_Flag(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    char type[32];
    strcopy(type, sizeof(type), name[4]);   // flag_taken, flag_dropped, flag_scored

    LCPayload payload = new LCPayload();
    LCStats_AddPosition(payload, "player", client);
    LCStats_Event(type, client, 0, payload);
    delete payload;

    if (client > 0 && StrEqual(name, "ctf_flag_scored"))
    {
        LCStats_AddStat(client, "flag_captures");
        LCStats_AddTeamStat(GetClientTeam(client), "flag_captures");
    }
}

// ctf_flag_returned: teamid, pos_x/y/z.
public void Event_FlagReturned(Event event, const char[] name, bool dontBroadcast)
{
    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "team", event.GetInt("teamid"));
    LCStats_Event("flag_returned", 0, 0, payload);
    delete payload;
}

// col_match_over: player1 .. player32, each 1 won, 2 lost, 0 did not fight.
public void Event_ColliseumOver(Event event, const char[] name, bool dontBroadcast)
{
    char field[16];

    for (int client = 1; client <= MaxClients && client <= 32; client++)
    {
        FormatEx(field, sizeof(field), "player%d", client);
        int outcome = event.GetInt(field);

        if (outcome != 1 && outcome != 2 || !IsClientInGame(client))
            continue;

        LCPayload payload = new LCPayload();
        payload.SetBool("won", outcome == 1);
        LCStats_Event("colliseum_duel", client, 0, payload);
        delete payload;

        LCStats_AddStat(client, outcome == 1 ? "colliseum_wins" : "colliseum_losses");
    }
}
