/**
 * LANCommander Match Statistics: Empires.
 *
 * Points captured and neutralised, commander elections, research, vehicles
 * bought and destroyed, revives, the score Empires awards (player_score), and
 * the round result (empires_round_over). Loads only on Empires (game folder
 * "empires").
 *
 * Event and field names are from empires/resource/modevents.res, which marks
 * player_class, player_join, player_score and player_revive as "for stats
 * plugins". Two kinds of field are recorded as they come, not interpreted:
 *  - point_captured / point_neutral declare team as a bool, which does not
 *    say how it maps onto the two teams' indexes: kept as team_bit.
 *  - Ids declared byte (vehicle_purchase userid, player_revive) may be userids
 *    or client indexes: tried as a userid first, then as an index.
 * Empires' player_hurt has no damage amount, so only hits are counted.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Empires",
    author      = "LANCommander",
    description = "Empires commanders, research, vehicles and points for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    char folder[32];
    GetGameFolderName(folder, sizeof(folder));
    return StrEqual(folder, "empires", false) ? APLRes_Success : APLRes_SilentFailure;
}

public void OnPluginStart()
{
    LCStats_HookEvent("point_captured", Event_Point);
    LCStats_HookEvent("point_neutral", Event_Point);
    LCStats_HookEvent("commander_elected_player", Event_CommanderElected);
    LCStats_HookEvent("emp_research_completed", Event_ResearchCompleted);
    LCStats_HookEvent("vehicle_purchase", Event_VehiclePurchase);
    LCStats_HookEvent("vehicle_death", Event_VehicleDeath);
    LCStats_HookEvent("player_revive", Event_Revive);
    LCStats_HookEvent("player_score", Event_Score);
    LCStats_HookEvent("empires_round_over", Event_RoundOver);
}

// A player from an id that may be a userid or a client index.
int ClientFromId(int id)
{
    int client = GetClientOfUserId(id);

    if (client < 1 && id >= 1 && id <= MaxClients && IsClientInGame(id))
        client = id;

    return client;
}

// point_captured / point_neutral: team (bool), location.
public void Event_Point(Event event, const char[] name, bool dontBroadcast)
{
    LCPayload payload = new LCPayload();
    payload.SetInt("location", event.GetInt("location"));
    payload.SetInt("team_bit", event.GetInt("team"));
    LCStats_Event(StrEqual(name, "point_captured") ? "point_captured" : "point_neutralized", 0, 0, payload);
    delete payload;
}

// commander_elected_player: elected_nf_comm_id, elected_be_comm_id.
public void Event_CommanderElected(Event event, const char[] name, bool dontBroadcast)
{
    static const char fields[][] = { "elected_nf_comm_id", "elected_be_comm_id" };

    for (int i = 0; i < sizeof(fields); i++)
    {
        int commander = ClientFromId(event.GetInt(fields[i]));

        if (commander < 1)
            continue;

        LCPayload payload = new LCPayload();
        LCStats_AddTeam(payload, "team", GetClientTeam(commander));
        LCStats_Event("commander_elected", commander, 0, payload);
        delete payload;

        LCStats_AddStat(commander, "commander_elections");
    }
}

// emp_research_completed: team, researchIndex, researchName (all local).
public void Event_ResearchCompleted(Event event, const char[] name, bool dontBroadcast)
{
    int team = event.GetInt("team");

    char research[64];
    event.GetString("researchName", research, sizeof(research));

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "team", team);
    payload.SetInt("research", event.GetInt("researchIndex"));

    if (research[0])
        payload.SetString("research_name", research);

    LCStats_Event("research_completed", 0, 0, payload);
    delete payload;

    if (team >= 2)
        LCStats_AddTeamStat(team, "research_completed");
}

// vehicle_purchase: userid (byte), recustomized, cost, chassis, builtfromwages.
public void Event_VehiclePurchase(Event event, const char[] name, bool dontBroadcast)
{
    int client = ClientFromId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();
    payload.SetInt("cost", event.GetInt("cost"));
    payload.SetInt("chassis", event.GetInt("chassis"));
    payload.SetBool("from_wages", event.GetBool("builtfromwages"));
    LCStats_Event("vehicle_purchased", client, 0, payload);
    delete payload;

    if (client > 0)
    {
        LCStats_AddStat(client, "vehicles_purchased");
        LCStats_AddStat(client, "vehicle_spending", float(event.GetInt("cost")));
    }
}

// vehicle_death: vehicleid (entity), lastplayeruserid, lastexittime.
public void Event_VehicleDeath(Event event, const char[] name, bool dontBroadcast)
{
    int lastDriver = GetClientOfUserId(event.GetInt("lastplayeruserid"));

    LCStats_Event("vehicle_destroyed", 0, lastDriver);

    if (lastDriver > 0)
        LCStats_AddStat(lastDriver, "vehicles_lost");
}

// player_revive: reviver_userid, revivee_userid (byte).
public void Event_Revive(Event event, const char[] name, bool dontBroadcast)
{
    int reviver = ClientFromId(event.GetInt("reviver_userid"));
    int revivee = ClientFromId(event.GetInt("revivee_userid"));

    LCStats_Event("revive", reviver, revivee);

    if (reviver > 0 && reviver != revivee)
        LCStats_AddStat(reviver, "revives");
}

// player_score: userid, amount, reason (local) -- the points Empires awards.
public void Event_Score(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int amount = event.GetInt("amount");

    if (client > 0 && amount != 0)
        LCStats_AddStat(client, "points", float(amount));
}

// empires_round_over: winner (local, a team index). The round is the match.
public void Event_RoundOver(Event event, const char[] name, bool dontBroadcast)
{
    int winner = event.GetInt("winner");

    LCPayload payload = new LCPayload();
    LCStats_AddTeam(payload, "winner", winner);
    LCStats_Event("round_end", 0, 0, payload);
    delete payload;

    if (winner >= 2 && winner < GetTeamCount())
    {
        for (int team = 2; team < GetTeamCount(); team++)
            LCStats_SetTeamResult(team, team == winner ? 1 : 2, team == winner ? LCResult_Finished : LCResult_Defeated);
    }

    LCStats_EndMatch("game_over");
}
