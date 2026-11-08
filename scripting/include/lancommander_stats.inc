/**
 * LANCommander Match Statistics: the core plugin's API (lancommander_stats.smx).
 *
 * The core plugin owns the match: one per map, started once the server is
 * configured and has players, ended at game over or when the map changes. It
 * reports players, kills, deaths, damage, rounds and the final standings for
 * every Source game. Game modules (lancommander_stats_<game>.smx) and
 * integrations with other plugins add to it through this API: events in the
 * game's own terms, statistics, results, and control over when the match
 * starts and ends.
 *
 * Players are passed as client indexes; the core turns them into LANCommander
 * player keys ("steam:STEAM_0:1:123", "bot:Name", "name:Name"). Teams are
 * passed as team indexes and reported by name. Game time and the server tick
 * are filled in.
 */

#if defined _lancommander_stats_included
 #endinput
#endif
#define _lancommander_stats_included

#include <lancommander>

#define LCSTATS_LIBRARY "lancommander_stats"

/** Longest player key the core produces, terminator included. */
#define LCSTATS_MAX_KEY 80

/**
 * The current match's handle (for the LC_Match* natives), or 0 when none is
 * open.
 */
native int LCStats_GetMatch();

/** Whether a match is open and events are being recorded (false in warmup unless lc_record_warmup). */
native bool LCStats_IsRecording();

/**
 * A client's player key.
 *
 * @return          false for a client that is not in game, or not recorded
 *                  (SourceTV, the replay bot, a bot with lc_record_bots 0).
 */
native bool LCStats_GetPlayerKey(int client, char[] key, int maxlength);

/** Milliseconds of game time since the current match started; 0 when none is open. */
native int LCStats_GetGameTime();

/** The current round, counted from 1 at the first round_start event; 0 before it. */
native int LCStats_GetRound();

/**
 * Sets the round counter; the next round_start event counts on from it. 0
 * starts the count again: for a game restart (CS's "Game Commencing"), or
 * the round before the one a backup restores.
 */
native void LCStats_SetRound(int round);

/**
 * The module reports rounds itself (from dod_round_start, teamplay_round_win,
 * ...): the core stops recording the shared round_start and round_end, which
 * some games fire as well and which would then be recorded twice. Call it
 * from OnPluginStart.
 */
native void LCStats_SetOwnRounds(bool own = true);

/**
 * Records an event in the current match. Does nothing (returns false) when no
 * match is recording.
 *
 * The core adds "round" (when rounds are counted) to the payload unless it is
 * already set, then calls LCStats_OnEvent, then sends it -- unless the
 * server's lc_events_include / lc_events_exclude filter leaves this type out.
 *
 * @return          true when the event was recorded or the server's filter
 *                  left it out (its statistics should still be counted);
 *                  false when no match is recording or a plugin dropped it.
 *
 * @param type      lowercase_with_underscores: "bomb_planted".
 * @param actor     The client who did it, 0 for none (the world).
 * @param subject   The client it happened to, 0 for none.
 * @param payload   The detail, or null. Not closed by the call.
 */
native bool LCStats_Event(const char[] type, int actor = 0, int subject = 0, LCPayload payload = null);

/** LCStats_Event with player keys rather than clients, for players no longer in game. */
native bool LCStats_EventKeys(const char[] type, const char[] actorKey = "", const char[] subjectKey = "", LCPayload payload = null);

/**
 * Damage dealt: damage_taken for the victim, and damage_dealt (or team_damage)
 * for the attacker. Only for games whose player_hurt carries no amount (PVKII,
 * HL2:DM, DAB, Empires): the core already counts player_hurt's dmg_health,
 * damageamount or damage, and would count it twice.
 *
 * @param attacker  The client who dealt it, 0 for the world.
 */
native bool LCStats_AddDamage(int attacker, int victim, int amount);

/** Adds to a player's end-of-match total ("plants", "ubercharges"). */
native bool LCStats_AddStat(int client, const char[] key, float delta = 1.0);

/** Sets a player's end-of-match total. */
native bool LCStats_SetStat(int client, const char[] key, float value);

/** Adds to a team's end-of-match total. */
native bool LCStats_AddTeamStat(int team, const char[] key, float delta = 1.0);

/** Sets a team's end-of-match total. */
native bool LCStats_SetTeamStat(int team, const char[] key, float value);

/**
 * Sets a team's place in the final standings, replacing what the core works
 * out from the team scores. Call it from LCStats_OnMatchEnding, or before
 * LCStats_EndMatch.
 */
native bool LCStats_SetTeamResult(int team, int rank, LCResultStatus status = LCResult_Finished,
                                  bool hasScore = false, float score = 0.0);

/** Sets a player's place in the final standings, replacing the core's (by frags). */
native bool LCStats_SetPlayerResult(int client, int rank, LCResultStatus status = LCResult_Finished,
                                    bool hasScore = false, float score = 0.0);

/**
 * The name a team is reported under: the game's own (GetTeamName), unless a
 * module renamed it with LCStats_SetTeamName. Empty for team 0 (unassigned).
 */
native void LCStats_GetTeamName(int team, char[] name, int maxlength);

/**
 * Reports a team under another name from now on -- the team names Get5 or a
 * PUG plugin uses rather than "TERRORIST". "" goes back to the game's own.
 */
native void LCStats_SetTeamName(int team, const char[] name);

/**
 * Marks warmup on or off. While it is on, nothing is recorded unless
 * lc_record_warmup is set (and then events carry "warmup": true).
 */
native void LCStats_SetWarmup(bool warmup);

/** Whether the server is in warmup, as last set with LCStats_SetWarmup. */
native bool LCStats_IsWarmup();

/**
 * Starts a match now, if none is open: for a plugin that held the automatic
 * start in LCStats_OnMatchStarting until play goes live.
 *
 * @param externalId    The match's id, "" for the core's default (server, map
 *                      and map start time). Starting again under the same id
 *                      continues that match.
 * @param mode          The game mode, "" for the core's (lc_mode or a module's).
 * @param metadata      Extra metadata merged over the core's, or null.
 * @return              false if a match is already open or reporting is off.
 */
native bool LCStats_StartMatch(const char[] externalId = "", const char[] mode = "", LCPayload metadata = null);

/**
 * Ends the current match now: the core works out the standings, calls
 * LCStats_OnMatchEnding, and ends it.
 *
 * @param reason        "game_over", "map_change", "forfeit", ...
 * @param abandoned     Cut short: its results should not count.
 * @return              false if no match was open.
 */
native bool LCStats_EndMatch(const char[] reason = "game_over", bool abandoned = false);

/**
 * Before the automatic start of a match. Change externalId, mode or metadata
 * and return Plugin_Changed; return Plugin_Handled to hold the start (a
 * competitive plugin waiting for the match to go live), then call
 * LCStats_StartMatch when it should begin.
 */
forward Action LCStats_OnMatchStarting(char[] externalId, int externalIdLength, char[] mode, int modeLength, LCPayload metadata);

/** A match has started. */
forward void LCStats_OnMatchStarted(int match, const char[] externalId);

/**
 * A match is about to end, with the core's standings set: the last chance to
 * set results and statistics.
 */
forward void LCStats_OnMatchEnding(int match, const char[] reason, bool abandoned);

/** A match has ended. */
forward void LCStats_OnMatchEnded(int match, const char[] reason, bool abandoned);

/**
 * Before an event is sent, from the core or any other plugin. Add to the
 * payload (it is never null here) and return Plugin_Changed, or return
 * Plugin_Handled to drop the event.
 *
 * @param actor     The acting client, 0 for none or when given by key only.
 * @param subject   The subject client, 0 likewise.
 */
forward Action LCStats_OnEvent(const char[] type, int actor, int subject, LCPayload payload);

/**
 * Hooks a game event the module expects the game to have. Unlike HookEvent,
 * an event the game does not have (a game update renamed or removed it) is
 * not an error that stops the module from loading: it is logged once, and
 * only that event's data is lost. For events that only some versions of a
 * game have, use HookEventEx and say nothing.
 *
 * @return          Whether the event exists and was hooked.
 */
stock bool LCStats_HookEvent(const char[] name, EventHook callback, EventHookMode mode = EventHookMode_Post)
{
    if (HookEventEx(name, callback, mode))
        return true;

    LogMessage("This game has no \"%s\" event; it is not recorded. A game update may have renamed it.", name);
    return false;
}

/**
 * Sets "<prefix>_position" to a client's origin, for an event's payload. Does
 * nothing when lc_record_positions is off.
 */
stock void LCStats_AddPosition(LCPayload payload, const char[] prefix, int client)
{
    static ConVar positions = null;

    if (positions == null)
        positions = FindConVar("lc_record_positions");

    if (positions != null && !positions.BoolValue)
        return;

    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        return;

    float origin[3];
    GetClientAbsOrigin(client, origin);

    char key[64];
    FormatEx(key, sizeof(key), "%s_position", prefix);
    payload.SetVector(key, origin);
}

/** Sets key to a client's player key, when it has one. */
stock void LCStats_AddPlayer(LCPayload payload, const char[] key, int client)
{
    char playerKey[LCSTATS_MAX_KEY];

    if (client > 0 && LCStats_GetPlayerKey(client, playerKey, sizeof(playerKey)))
        payload.SetString(key, playerKey);
}

/** Sets key to a team's reported name. */
stock void LCStats_AddTeam(LCPayload payload, const char[] key, int team)
{
    char name[64];
    LCStats_GetTeamName(team, name, sizeof(name));

    if (name[0])
        payload.SetString(key, name);
}

public SharedPlugin __pl_lancommander_stats =
{
    name = LCSTATS_LIBRARY,
    file = "lancommander_stats.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_lancommander_stats_SetNTVOptional()
{
    MarkNativeAsOptional("LCStats_GetMatch");
    MarkNativeAsOptional("LCStats_IsRecording");
    MarkNativeAsOptional("LCStats_GetPlayerKey");
    MarkNativeAsOptional("LCStats_GetGameTime");
    MarkNativeAsOptional("LCStats_GetRound");
    MarkNativeAsOptional("LCStats_SetRound");
    MarkNativeAsOptional("LCStats_SetOwnRounds");
    MarkNativeAsOptional("LCStats_Event");
    MarkNativeAsOptional("LCStats_EventKeys");
    MarkNativeAsOptional("LCStats_AddDamage");
    MarkNativeAsOptional("LCStats_AddStat");
    MarkNativeAsOptional("LCStats_SetStat");
    MarkNativeAsOptional("LCStats_AddTeamStat");
    MarkNativeAsOptional("LCStats_SetTeamStat");
    MarkNativeAsOptional("LCStats_SetTeamResult");
    MarkNativeAsOptional("LCStats_SetPlayerResult");
    MarkNativeAsOptional("LCStats_GetTeamName");
    MarkNativeAsOptional("LCStats_SetTeamName");
    MarkNativeAsOptional("LCStats_SetWarmup");
    MarkNativeAsOptional("LCStats_IsWarmup");
    MarkNativeAsOptional("LCStats_StartMatch");
    MarkNativeAsOptional("LCStats_EndMatch");
}
#endif
