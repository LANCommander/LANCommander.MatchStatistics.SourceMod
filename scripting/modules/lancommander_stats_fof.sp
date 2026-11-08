/**
 * LANCommander Match Statistics: Fistful of Frags.
 *
 * Kill penetration, shots (FoF has no weapon_fire), its own round_end (team
 * scores, winner, MVP), and the trick-shot events: hat shots, chain
 * reactions, the Unforgiven, dynamite detonations and defusals, and course
 * completions. The match ends at game_end, which the core handles. Loads only
 * on Fistful of Frags (game folder "fof").
 *
 * Event and field names are from fof/resource/modevents.res. The core reads
 * player_death's assist and headshot, and player_hurt's damage, itself.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Fistful of Frags",
    author      = "LANCommander",
    description = "Fistful of Frags rounds and trick shots for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

// player_death's penetration, for the "kill" that follows.
bool g_KillPenetration;

// round_end: LScr, OScr, LRnd, TWinner, MVP_Index, MVP_Score -- FoF's own fields,
// not the shared winner/reason/message.
int  g_RoundWinner, g_RoundMvp, g_RoundMvpScore, g_RoundScoreA, g_RoundScoreB;
bool g_RoundLast;

// The trick-shot events; each names a player by entity index.
static const char g_Tricks[][][] =
{
    // event                      field                    statistic
    { "hatshot",                 "entindex_hatshot",      "hat_shots" },
    { "chain_reaction",          "entindex_thrower",      "chain_reactions" },
    { "unforgiven",              "entindex_unforgiven",   "unforgiven" },
    { "detonator",               "entindex_detonator",    "detonations" },
    { "defuser",                 "entindex_defuser",      "defusals" },
    { "course_mobile_completed", "entindex_player",       "courses_completed" }
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    char folder[32];
    GetGameFolderName(folder, sizeof(folder));
    return StrEqual(folder, "fof", false) ? APLRes_Success : APLRes_SilentFailure;
}

public void OnPluginStart()
{
    LCStats_HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
    LCStats_HookEvent("player_shoot", Event_PlayerShoot);
    LCStats_HookEvent("round_end", Event_RoundEndPre, EventHookMode_Pre);
    LCStats_HookEvent("tp_teamobj", Event_TeamObjective);

    for (int i = 0; i < sizeof(g_Tricks); i++)
        LCStats_HookEvent(g_Tricks[i][0], Event_Trick);
}

// player_death: userid, attacker, weapon, headshot, assist, damagebits, penetration, weapon_index.
public Action Event_PlayerDeathPre(Event event, const char[] name, bool dontBroadcast)
{
    g_KillPenetration = event.GetBool("penetration");
    return Plugin_Continue;
}

// round_end, before the core's own hook reads it.
public Action Event_RoundEndPre(Event event, const char[] name, bool dontBroadcast)
{
    g_RoundWinner   = event.GetInt("TWinner");
    g_RoundMvp      = event.GetInt("MVP_Index");
    g_RoundMvpScore = event.GetInt("MVP_Score");
    g_RoundScoreA   = event.GetInt("LScr");
    g_RoundScoreB   = event.GetInt("OScr");
    g_RoundLast     = event.GetBool("LRnd");
    return Plugin_Continue;
}

public Action LCStats_OnEvent(const char[] type, int actor, int subject, LCPayload payload)
{
    if (StrEqual(type, "kill"))
    {
        if (!g_KillPenetration)
            return Plugin_Continue;

        payload.SetBool("penetration", true);
        g_KillPenetration = false;
        return Plugin_Changed;
    }

    if (StrEqual(type, "round_end"))
    {
        // The shared fields do not exist here: the core read 0 and "".
        payload.Remove("reason");

        if (g_RoundWinner >= 2)
            LCStats_AddTeam(payload, "winner", g_RoundWinner);

        payload.SetInt("score_l", g_RoundScoreA);
        payload.SetInt("score_o", g_RoundScoreB);

        if (g_RoundLast)
            payload.SetBool("last_round", true);

        int mvp = g_RoundMvp;

        if (mvp >= 1 && mvp <= MaxClients && IsClientInGame(mvp))
        {
            LCStats_AddPlayer(payload, "mvp", mvp);
            payload.SetInt("mvp_score", g_RoundMvpScore);
            LCStats_AddStat(mvp, "mvps");
        }

        return Plugin_Changed;
    }

    return Plugin_Continue;
}

// player_shoot: userid, weapon, mode (0 normal, 1 iron sights, 2 fanning), pellets.
public void Event_PlayerShoot(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client > 0)
        LCStats_AddStat(client, "shots");
}

// tp_teamobj: team, obj.
public void Event_TeamObjective(Event event, const char[] name, bool dontBroadcast)
{
    int team = event.GetInt("team");

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "team", team);
    payload.SetInt("objective", event.GetInt("obj"));
    LCStats_Event("team_objective", 0, 0, payload);
    delete payload;

    if (team >= 2)
        LCStats_AddTeamStat(team, "objectives");
}

public void Event_Trick(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 0; i < sizeof(g_Tricks); i++)
    {
        if (!StrEqual(name, g_Tricks[i][0]))
            continue;

        int client = event.GetInt(g_Tricks[i][1]);

        if (client < 1 || client > MaxClients || !IsClientInGame(client))
            return;

        LCPayload payload = new LCPayload();
        LCStats_AddPosition(payload, "player", client);
        LCStats_Event(name, client, 0, payload);
        delete payload;

        LCStats_AddStat(client, g_Tricks[i][2]);
        return;
    }
}
