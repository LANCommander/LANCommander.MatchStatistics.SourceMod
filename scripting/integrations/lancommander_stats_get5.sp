/**
 * LANCommander Match Statistics: Get5.
 *
 * While Get5 runs a match, a LANCommander match is one map of the series. It
 * starts when Get5 goes live (not during warmup, the veto or the knife round),
 * is identified by Get5's server and match ids and the map number, and keeps
 * the series with it: match id, map number, series length and team names.
 * Pauses and backup restores are recorded as events.
 *
 * Team names come from mp_teamname_1/2, which the Counter-Strike module
 * reports. Get5's demos are recorded with tv_record and attached by the core
 * plugin. Without Get5 loaded this plugin does nothing.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <lancommander_stats>

#undef REQUIRE_PLUGIN
#include <get5>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Get5",
    author      = "LANCommander",
    description = "Records Get5 series maps as LANCommander matches",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

bool g_Get5;

// From Get5_OnSeriesInit, for the metadata of each map's match.
int  g_SeriesLength;
char g_Team1[64];
char g_Team2[64];

public void OnAllPluginsLoaded()
{
    g_Get5 = LibraryExists("get5");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "get5"))
        g_Get5 = true;
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "get5"))
        g_Get5 = false;
}

// A match configured in Get5: the core's automatic start waits for it to go live.
bool Get5MatchConfigured()
{
    return g_Get5 && Get5_GetGameState() != Get5State_None;
}

public Action LCStats_OnMatchStarting(char[] externalId, int externalIdLength, char[] mode, int modeLength, LCPayload metadata)
{
    return Get5MatchConfigured() ? Plugin_Handled : Plugin_Continue;
}

public void Get5_OnSeriesInit(const Get5SeriesStartedEvent event)
{
    g_SeriesLength = event.NumberOfMaps;
    event.Team1.GetName(g_Team1, sizeof(g_Team1));
    event.Team2.GetName(g_Team2, sizeof(g_Team2));

    // Warmup on a map a match was already being recorded on: that was not it.
    if (LCStats_GetMatch() != 0)
        LCStats_EndMatch("get5_series_loaded", true);
}

public void Get5_OnGoingLive(const Get5GoingLiveEvent event)
{
    char matchId[64], serverId[64];
    event.GetMatchId(matchId, sizeof(matchId));
    Get5_GetServerID(serverId, sizeof(serverId));

    int mapNumber = event.MapNumber;

    // One LANCommander match per map; the same id again (a restore after a
    // crash) carries on with it.
    char externalId[192];
    FormatEx(externalId, sizeof(externalId), "get5-%s-%s-map%d", serverId, matchId, mapNumber + 1);

    LCPayload metadata = new LCPayload();
    metadata.SetString("get5_match_id", matchId);
    metadata.SetString("get5_server_id", serverId);
    metadata.SetInt("map_number", mapNumber + 1);

    if (g_SeriesLength > 0)
        metadata.SetInt("series_length", g_SeriesLength);

    if (g_Team1[0])
        metadata.SetString("team1", g_Team1);

    if (g_Team2[0])
        metadata.SetString("team2", g_Team2);

    // Anything recorded since the map loaded was warmup.
    if (LCStats_GetMatch() != 0)
        LCStats_EndMatch("get5_going_live", true);

    LCStats_SetWarmup(false);

    if (!LCStats_StartMatch(externalId, "competitive", metadata))
        LogError("Could not start a LANCommander match for Get5 match %s map %d", matchId, mapNumber + 1);

    delete metadata;
}

public void Get5_OnMatchPaused(const Get5MatchPausedEvent event)
{
    RecordPause("paused", event.Team, event.PauseType);
}

public void Get5_OnMatchUnpaused(const Get5MatchUnpausedEvent event)
{
    RecordPause("unpaused", event.Team, event.PauseType);
}

void RecordPause(const char[] type, Get5Team team, Get5PauseType pauseType)
{
    static const char pauseNames[][] = { "none", "technical", "tactical", "admin", "backup" };

    LCPayload payload = new LCPayload();
    int index = view_as<int>(pauseType);

    if (index >= 0 && index < sizeof(pauseNames))
        payload.SetString("pause_type", pauseNames[index]);

    if (team == Get5Team_1 || team == Get5Team_2)
        LCStats_AddTeam(payload, "team", Get5_Get5TeamToCSTeam(team));

    LCStats_Event(type, 0, 0, payload);
    delete payload;
}

public void Get5_OnBackupRestore(const Get5BackupRestoredEvent event)
{
    char file[PLATFORM_MAX_PATH];
    event.GetFileName(file, sizeof(file));

    LCPayload payload = new LCPayload();
    payload.SetInt("to_round", event.RoundNumber + 1);
    payload.SetString("file", file);
    LCStats_Event("backup_restored", 0, 0, payload);
    delete payload;

    // The restored round is played again: the next round_start is its number.
    LCStats_SetRound(event.RoundNumber);
}

public void Get5_OnSeriesResult(const Get5SeriesResultEvent event)
{
    g_SeriesLength = 0;
    g_Team1[0] = '\0';
    g_Team2[0] = '\0';
}
