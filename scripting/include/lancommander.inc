/**
 * LANCommander Match Statistics: the extension (lancommander.ext).
 *
 * The low-level API: the LANCommander Interposer's InterposerMatch* functions,
 * one native each, plus LCPayload to build the JSON they take. Most plugins
 * want lancommander_stats.inc instead -- the core plugin's API, which knows the
 * current match, player keys and game time, and fills them in.
 *
 * Strings are UTF-8. An empty string for an optional argument means "not
 * given". Calls return false only for a mistake by the caller (an unknown
 * match, a missing key, a change after the end), never because LANCommander
 * cannot be reached: delivery happens in the background, and unsent reports
 * are kept on disk (addons/sourcemod/extensions/.interposer/Matches/) until
 * they are delivered.
 */

#if defined _lancommander_included
 #endinput
#endif
#define _lancommander_included

/** Where a match's reports go, decided when it starts (InterposerMatchStatus.sink). */
enum LCSink
{
    LCSink_None     = 0,   /**< Logged, and passed to LC_OnMatchReport, only. */
    LCSink_Http     = 1,   /**< Sent to the LANCommander server by the extension. */
    LCSink_Launcher = 2    /**< Sent by LANCommander's launcher (a listen server it started). */
};

/** How a player or team finished (InterposerMatchResult.status). */
enum LCResultStatus
{
    LCResult_Finished     = 0,
    LCResult_DidNotFinish = 1,
    LCResult_Disqualified = 2,
    LCResult_Defeated     = 3,
    LCResult_Forfeited    = 4
};

/** What an attached file holds. */
enum LCAttachmentKind
{
    LCAttachment_Demo       = 0,
    LCAttachment_Replay     = 1,
    LCAttachment_Log        = 2,
    LCAttachment_Screenshot = 3,
    LCAttachment_Other      = 4
};

/**
 * A JSON object or array, built a value at a time, for event payloads,
 * results and match settings. Close it with delete when done; the natives that
 * take one copy its contents, so it may be deleted (or reused) right after.
 *
 * Keys keep the order they were first set in; setting a key again replaces its
 * value in place. Text is UTF-8; any invalid byte becomes U+FFFD rather than
 * spoiling the event. LANCommander takes payloads up to 16 KB.
 */
methodmap LCPayload < Handle
{
    /**
     * @param isArray   true for a JSON array (the Push methods), false for an
     *                  object (the Set methods).
     */
    public native LCPayload(bool isArray = false);

    // Objects
    public native bool SetInt(const char[] key, int value);
    public native bool SetFloat(const char[] key, float value);
    public native bool SetBool(const char[] key, bool value);
    public native bool SetString(const char[] key, const char[] value);
    public native bool SetNull(const char[] key);
    /** As an array of three numbers, [x, y, z]. */
    public native bool SetVector(const char[] key, const float value[3]);
    /** Nests a copy of another payload, as it is now. */
    public native bool SetObject(const char[] key, LCPayload value);
    public native bool Remove(const char[] key);
    public native bool HasKey(const char[] key);

    // Arrays
    public native bool PushInt(int value);
    public native bool PushFloat(float value);
    public native bool PushBool(bool value);
    public native bool PushString(const char[] value);
    public native bool PushVector(const float value[3]);
    public native bool PushObject(LCPayload value);

    /** Empties the object or array. */
    public native void Clear();

    /**
     * Writes the JSON text.
     *
     * @return          Bytes written.
     */
    public native int ToString(char[] buffer, int maxlength);

    /** Keys in an object, items in an array. */
    property int Size {
        public native get();
    }

    property bool IsArray {
        public native get();
    }
}

/**
 * Sets where reports go. Call it before starting matches, typically from
 * OnConfigsExecuted with the values of the lc_* cvars; it may be called again
 * whenever they change. Settings apply to matches started afterwards (a match
 * already open keeps its game and server) and to every request from then on.
 * The first call that completes the server URL, token and game also sends any
 * matches a previous run left unsent.
 *
 * An empty serverId or reporterName clears it; reporterName empty means the
 * computer's name.
 *
 * @param enabled           false to stop sending (matches are only logged).
 * @param serverUrl         LANCommander's address, http:// or https://. On
 *                          Linux only http:// is supported.
 * @param token             A personal access token with the matches:report
 *                          scope. An administrator's token makes the reports
 *                          authoritative.
 * @param gameId            The LANCommander game (a GUID).
 * @param serverId          The LANCommander server (a GUID), or "".
 * @param reporterName      How this server is named in LANCommander.
 * @param flushIntervalMs   Milliseconds between batches, 100 to 600000; 0
 *                          leaves it as it is (2000 by default).
 * @return                  false, with nothing changed, if a value is
 *                          invalid (the Interposer's log says which).
 */
native bool LC_Configure(bool enabled, const char[] serverUrl, const char[] token, const char[] gameId,
                         const char[] serverId = "", const char[] reporterName = "", int flushIntervalMs = 0);

/**
 * Starts a match, or carries on with one: starting again under the same
 * external id -- in this process or after a restart -- continues it.
 *
 * @param externalId        The match's own id, or "" for a generated one.
 * @param settings          The rules played with (cvars), or null.
 * @param metadata          Anything else to keep with the match, or null.
 * @param startedOnUnix     When it started (Unix seconds), 0 for now.
 * @return                  The match handle, or 0 on bad arguments.
 */
native int LC_MatchStart(const char[] externalId, const char[] map, const char[] mode = "",
                         const char[] gameVersion = "", const char[] serverName = "",
                         const char[] serverAddress = "", LCPayload settings = null,
                         LCPayload metadata = null, int startedOnUnix = 0);

/**
 * A player joined, or changed name or team.
 *
 * @param playerKey         "steam:STEAM_0:1:123", "bot:Name", "name:Name".
 * @param gameTimeMs        Milliseconds since the match started, -1 if unknown.
 */
native bool LC_MatchPlayerJoined(int match, const char[] playerKey, const char[] displayName = "",
                                 const char[] team = "", int gameTimeMs = -1);

/** A player left. */
native bool LC_MatchPlayerLeft(int match, const char[] playerKey, int gameTimeMs = -1);

/**
 * Something happened.
 *
 * @param type              lowercase_with_underscores: "kill", "bomb_planted".
 * @param gameTimeMs        Milliseconds since the match started.
 * @param tick              The server tick, -1 for none.
 * @param actorKey          Who did it, or "".
 * @param subjectKey        Who it happened to (a kill's victim), or "".
 * @param payload           The detail, an LCPayload object, or null.
 */
native bool LC_MatchEvent(int match, const char[] type, int gameTimeMs, int tick = -1,
                          const char[] actorKey = "", const char[] subjectKey = "", LCPayload payload = null);

/**
 * An end-of-match total for a player (playerKey) or a team (team, playerKey
 * ""). Set replaces it; Add adds to the running total. Sent with the end.
 */
native bool LC_MatchSetStatistic(int match, const char[] playerKey, const char[] team, const char[] key, float value);
native bool LC_MatchAddStatistic(int match, const char[] playerKey, const char[] team, const char[] key, float delta);

/**
 * A player's or team's place in the final standings; setting the same one
 * again replaces it. Sent with the end.
 *
 * @param rank              1 for the winner; tied entries share a rank.
 * @param timeMs            A finishing time, for races; -1 for none.
 */
native bool LC_MatchSetResult(int match, const char[] playerKey, const char[] team, int rank,
                              LCResultStatus status = LCResult_Finished, bool hasScore = false,
                              float score = 0.0, int timeMs = -1, LCPayload payload = null);

/**
 * Ends the match, sending the standings and totals.
 *
 * @param reason            e.g. "completed", "map_change", "server_shutdown".
 * @param abandoned         Cut short: its results should not count.
 */
native bool LC_MatchEnd(int match, const char[] reason = "", bool abandoned = false);

/**
 * Attaches a file (a SourceTV demo, a log), uploaded in the background. The
 * file must stay in place until it is uploaded. Allowed after the end.
 *
 * @param path              Relative to the game directory, or absolute.
 * @param startMs           Game time the file starts at, -1 if unknown.
 * @param endMs             Game time it ends at, -1 if unknown.
 */
native bool LC_MatchAttachFile(int match, const char[] path, LCAttachmentKind kind = LCAttachment_Demo,
                               int startMs = -1, int endMs = -1);

/**
 * Waits up to timeoutMs for the server to take everything recorded so far.
 * BLOCKS THE SERVER while it waits: only for a server about to shut down.
 *
 * @return                  true when nothing is left waiting.
 */
native bool LC_MatchFlush(int match, int timeoutMs);

/**
 * How delivery of a match is going.
 *
 * @return                  false for an unknown match.
 */
native bool LC_MatchGetStatus(int match, LCSink &sink, int &pendingEvents, int &rejectedEvents,
                              int &pendingAttachments, bool &ended, bool &delivered,
                              char[] matchId, int matchIdLength, char[] lastError, int lastErrorLength);

/**
 * Every step of every match, whoever reported it: kind is "START",
 * "PARTICIPANT", "EVENT", "END" or "ATTACH", and json describes it.
 */
forward void LC_OnMatchReport(const char[] kind, int match, const char[] json);

public Extension __ext_lancommander =
{
    name = "LANCommander Match Statistics",
    file = "lancommander.ext",
#if defined AUTOLOAD_EXTENSIONS
    autoload = 1,
#else
    autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_EXTENSIONS
public void __ext_lancommander_SetNTVOptional()
{
    MarkNativeAsOptional("LC_Configure");
    MarkNativeAsOptional("LC_MatchStart");
    MarkNativeAsOptional("LC_MatchPlayerJoined");
    MarkNativeAsOptional("LC_MatchPlayerLeft");
    MarkNativeAsOptional("LC_MatchEvent");
    MarkNativeAsOptional("LC_MatchSetStatistic");
    MarkNativeAsOptional("LC_MatchAddStatistic");
    MarkNativeAsOptional("LC_MatchSetResult");
    MarkNativeAsOptional("LC_MatchEnd");
    MarkNativeAsOptional("LC_MatchAttachFile");
    MarkNativeAsOptional("LC_MatchFlush");
    MarkNativeAsOptional("LC_MatchGetStatus");
    MarkNativeAsOptional("LCPayload.LCPayload");
    MarkNativeAsOptional("LCPayload.SetInt");
    MarkNativeAsOptional("LCPayload.SetFloat");
    MarkNativeAsOptional("LCPayload.SetBool");
    MarkNativeAsOptional("LCPayload.SetString");
    MarkNativeAsOptional("LCPayload.SetNull");
    MarkNativeAsOptional("LCPayload.SetVector");
    MarkNativeAsOptional("LCPayload.SetObject");
    MarkNativeAsOptional("LCPayload.Remove");
    MarkNativeAsOptional("LCPayload.HasKey");
    MarkNativeAsOptional("LCPayload.PushInt");
    MarkNativeAsOptional("LCPayload.PushFloat");
    MarkNativeAsOptional("LCPayload.PushBool");
    MarkNativeAsOptional("LCPayload.PushString");
    MarkNativeAsOptional("LCPayload.PushVector");
    MarkNativeAsOptional("LCPayload.PushObject");
    MarkNativeAsOptional("LCPayload.Clear");
    MarkNativeAsOptional("LCPayload.ToString");
    MarkNativeAsOptional("LCPayload.Size.get");
    MarkNativeAsOptional("LCPayload.IsArray.get");
}
#endif
