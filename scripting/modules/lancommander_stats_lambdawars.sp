/**
 * LANCommander Match Statistics: Lambda Wars.
 *
 * Lambda Wars reports little of its RTS play as game events: units,
 * buildings and resources are not among them. What it does report is control
 * point fortification and unit control, recorded here, plus the shared
 * events the core records (kills, spawns, teams, rounds, game_end). Loads
 * only on Lambda Wars (game folder "lambdawars"), whose dedicated server runs
 * on Windows only, on the Alien Swarm engine branch.
 *
 * Event and field names are from lambdawars/pak01's resource/modevents.res.
 * Whether SourceMod and Metamod:Source run on Lambda Wars has not been
 * confirmed; SourceMod ships no gamedata for it.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Lambda Wars",
    author      = "LANCommander",
    description = "Lambda Wars control points and unit control for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    char folder[32];
    GetGameFolderName(folder, sizeof(folder));
    return StrEqual(folder, "lambdawars", false) ? APLRes_Success : APLRes_SilentFailure;
}

public void OnPluginStart()
{
    // wars_start_fortification_cp / wars_fortified_cp: userid, entindex (the point).
    LCStats_HookEvent("wars_start_fortification_cp", Event_Fortification);
    LCStats_HookEvent("wars_fortified_cp", Event_Fortification);
    // player_changeclass: userid, class.
    LCStats_HookEvent("player_changeclass", Event_ChangeClass);
}

public void Event_Fortification(Event event, const char[] name, bool dontBroadcast)
{
    int client   = GetClientOfUserId(event.GetInt("userid"));
    bool finished = StrEqual(name, "wars_fortified_cp");

    LCPayload payload = new LCPayload();
    payload.SetInt("point", event.GetInt("entindex"));
    LCStats_Event(finished ? "control_point_fortified" : "control_point_fortifying", client, 0, payload);
    delete payload;

    if (client > 0 && finished)
    {
        LCStats_AddStat(client, "fortifications");
        LCStats_AddTeamStat(GetClientTeam(client), "fortifications");
    }
}

public void Event_ChangeClass(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();
    payload.SetInt("class", event.GetInt("class"));
    LCStats_Event("class_change", client, 0, payload);
    delete payload;
}
