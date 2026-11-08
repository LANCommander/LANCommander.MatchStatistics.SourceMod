// The match: one per map. Opened once the server is configured and has
// players, ended at game over (by a game module) or when the map changes.

int GameTimeMs()
{
    if (!g_Match)
        return 0;

    float elapsed = GetGameTime() - g_MatchStartGameTime;
    return elapsed > 0.0 ? RoundToFloor(elapsed * 1000.0) : 0;
}

bool IsRecording()
{
    return g_Match != 0 && (!g_Warmup || g_cvRecordWarmup.BoolValue);
}

// The automatic start: on a configured server with enough players, once per
// map, unless an integration holds it.
void TryStartMatch()
{
    if (g_Match || g_MatchHeld || g_MatchDoneThisMap || !g_ConfigApplied || !ReportingEnabled())
        return;

    if (CountHumans() < g_cvMinPlayers.IntValue)
        return;

    StartMatch("", "", null, true);
}

// The default external id: this server, this map, and when the map started,
// so a plugin reload on the same map carries on with the same match.
void DefaultExternalId(char[] id, int maxlength)
{
    char address[64], map[PLATFORM_MAX_PATH];
    GetServerAddress(address, sizeof(address));
    GetCurrentMap(map, sizeof(map));

    // Workshop maps are paths: keep the id one clean token.
    ReplaceString(map, sizeof(map), "/", "_");
    ReplaceString(address, sizeof(address), ":", "_");

    FormatEx(id, maxlength, "%s-%s-%d", address, map, g_MapStartUnix);
}

// "ctf" for ctf_2fort, workshop paths included; "" for a map without one.
void MapPrefixMode(char[] mode, int maxlength)
{
    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));

    int slash = FindCharInString(map, '/', true);
    int start = slash >= 0 ? slash + 1 : 0;
    int underscore = FindCharInString(map[start], '_');

    mode[0] = '\0';

    if (underscore > 0 && underscore < maxlength)
    {
        strcopy(mode, underscore + 1, map[start]);
        StringToLowerCase(mode);
    }
}

void StringToLowerCase(char[] text)
{
    for (int i = 0; text[i]; i++)
        text[i] = CharToLower(text[i]);
}

void GetServerAddress(char[] address, int maxlength)
{
    ConVar hostip   = FindConVar("hostip");
    ConVar hostport = FindConVar("hostport");

    int ip   = hostip != null ? hostip.IntValue : 0;
    int port = hostport != null ? hostport.IntValue : 27015;

    FormatEx(address, maxlength, "%d.%d.%d.%d:%d",
        (ip >>> 24) & 0xFF, (ip >>> 16) & 0xFF, (ip >>> 8) & 0xFF, ip & 0xFF, port);
}

// Starts a match. automatic: the core's own start, which plugins may hold
// through LCStats_OnMatchStarting; LCStats_StartMatch is not offered to them.
bool StartMatch(const char[] externalIdIn, const char[] modeIn, LCPayload extraMetadata, bool automatic)
{
    if (g_Match || !ReportingEnabled())
        return false;

    char externalId[192], mode[64];

    if (externalIdIn[0])
        strcopy(externalId, sizeof(externalId), externalIdIn);
    else
        DefaultExternalId(externalId, sizeof(externalId));

    if (modeIn[0])
        strcopy(mode, sizeof(mode), modeIn);
    else
        g_cvMode.GetString(mode, sizeof(mode));

    LCPayload metadata = BuildMetadata();

    if (extraMetadata != null)
        metadata.SetObject("extra", extraMetadata);

    if (automatic)
    {
        Action result = Plugin_Continue;

        Call_StartForward(g_fwdMatchStarting);
        // STRING_COPY: without it the handlers see an empty buffer, and copy it back.
        Call_PushStringEx(externalId, sizeof(externalId), SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
        Call_PushCell(sizeof(externalId));
        Call_PushStringEx(mode, sizeof(mode), SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
        Call_PushCell(sizeof(mode));
        Call_PushCell(metadata);
        Call_Finish(result);

        if (result >= Plugin_Handled)
        {
            g_MatchHeld = true;
            delete metadata;
            return false;
        }
    }

    // No mode from lc_mode or a module: the map's prefix (ctf_, bt_, tp_ ...),
    // which most Source games name their modes by.
    if (!mode[0])
        MapPrefixMode(mode, sizeof(mode));

    LCPayload settings = BuildSettings();

    char map[PLATFORM_MAX_PATH], displayMap[PLATFORM_MAX_PATH], hostname[128], address[64];
    GetCurrentMap(map, sizeof(map));

    if (!GetMapDisplayName(map, displayMap, sizeof(displayMap)))
        strcopy(displayMap, sizeof(displayMap), map);

    if (g_cvHostname != null)
        g_cvHostname.GetString(hostname, sizeof(hostname));

    GetServerAddress(address, sizeof(address));

    char gameVersion[32];
    GetGameVersion(gameVersion, sizeof(gameVersion));

    int match = LC_MatchStart(externalId, displayMap, mode, gameVersion, hostname, address, settings, metadata, 0);

    delete settings;
    delete metadata;

    if (!match)
    {
        LogError("The LANCommander extension refused to start a match (external id \"%s\")", externalId);
        return false;
    }

    g_Match              = match;
    g_MatchHeld          = false;
    g_MatchStartGameTime = RecallMatchStartTime(externalId);
    strcopy(g_MatchExternalId, sizeof(g_MatchExternalId), externalId);

    g_LeftPlayers.Clear();
    g_PlayerResultSet.Clear();

    for (int team = 0; team < LC_MAX_TEAMS; team++)
        g_TeamResultSet[team] = false;

    JoinEveryone();

    Call_StartForward(g_fwdMatchStarted);
    Call_PushCell(g_Match);
    Call_PushString(g_MatchExternalId);
    Call_Finish();

    return true;
}

// The game time a match started at. A plugin reload carries on with the same
// match (the same external id), and its game time must carry on too rather
// than start again from 0, so it is kept in a hidden cvar, which outlives the
// plugin (see MapStartCvar).
float RecallMatchStartTime(const char[] externalId)
{
    ConVar cvar = FindConVar("lc_internal_match_start");

    if (cvar == null)
        cvar = CreateConVar("lc_internal_match_start", "", "Internal: the open match and when it started",
            FCVAR_DONTRECORD | FCVAR_UNLOGGED | FCVAR_HIDDEN);

    char value[256];
    cvar.GetString(value, sizeof(value));

    int bar = FindCharInString(value, '|');
    float now = GetGameTime();

    if (bar > 0 && StrEqual(value[bar + 1], externalId))
    {
        value[bar] = '\0';
        float started = StringToFloat(value);

        // Game time restarts with the map; a later start is a stale entry.
        if (started <= now)
            return started;
    }

    FormatEx(value, sizeof(value), "%.3f|%s", now, externalId);
    cvar.SetString(value);
    return now;
}

// Ends the open match: standings, then LCStats_OnMatchEnding, then the end.
bool EndMatch(const char[] reason, bool abandoned)
{
    if (!g_Match)
        return false;

    int match = g_Match;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_PlayerInMatch[client] && IsClientInGame(client))
        {
            AddTimePlayed(client);
            LC_MatchSetStatistic(match, g_PlayerKey[client], "", "score", float(GetClientFrags(client)));
        }
    }

    if (!abandoned)
        SetDefaultResults(match);

    Call_StartForward(g_fwdMatchEnding);
    Call_PushCell(match);
    Call_PushString(reason);
    Call_PushCell(abandoned);
    Call_Finish();

    LC_MatchEnd(match, reason, abandoned);

    g_Match = 0;
    g_MatchExternalId[0] = '\0';

    for (int client = 1; client <= MaxClients; client++)
        g_PlayerInMatch[client] = false;

    Call_StartForward(g_fwdMatchEnded);
    Call_PushCell(match);
    Call_PushString(reason);
    Call_PushCell(abandoned);
    Call_Finish();

    return true;
}

// ── Standings ────────────────────────────────────────────────────────────────
//
// Team games: teams ranked by score, every player taking their team's place
// (Finished for the winners, Defeated for the rest). Free-for-all: players
// ranked by frags. Players who left before the end did not finish. Results a
// module or integration has set are kept.

void SetDefaultResults(int match)
{
    int teamRank[LC_MAX_TEAMS];
    bool teamGame = RankTeams(match, teamRank);

    // Everyone who played: in game now, and those who left.
    ArrayList keys   = new ArrayList(ByteCountToCells(LC_MAX_KEY));
    ArrayList frags  = new ArrayList();
    ArrayList teams  = new ArrayList();
    ArrayList finish = new ArrayList();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_PlayerInMatch[client] || !IsClientInGame(client))
            continue;

        keys.PushString(g_PlayerKey[client]);
        frags.Push(GetClientFrags(client));
        teams.Push(GetClientTeam(client));
        finish.Push(true);
    }

    StringMapSnapshot left = g_LeftPlayers.Snapshot();
    char key[LC_MAX_KEY];

    for (int i = 0; i < left.Length; i++)
    {
        left.GetKey(i, key, sizeof(key));

        int info[2];
        g_LeftPlayers.GetArray(key, info, sizeof(info));

        keys.PushString(key);
        frags.Push(info[0]);
        teams.Push(info[1]);
        finish.Push(false);
    }

    delete left;

    for (int i = 0; i < keys.Length; i++)
    {
        keys.GetString(i, key, sizeof(key));

        bool alreadySet;
        if (g_PlayerResultSet.GetValue(key, alreadySet))
            continue;

        int  playerFrags = frags.Get(i);
        int  team        = teams.Get(i);
        bool finished    = finish.Get(i);
        int  rank;
        LCResultStatus status;

        if (teamGame)
        {
            // Spectators and the unassigned took no place.
            if (team < 2 || team >= LC_MAX_TEAMS || teamRank[team] == 0)
                continue;

            rank   = teamRank[team];
            status = rank == 1 ? LCResult_Finished : LCResult_Defeated;
        }
        else
        {
            rank = 1;

            for (int j = 0; j < keys.Length; j++)
            {
                if (frags.Get(j) > playerFrags)
                    rank++;
            }

            status = LCResult_Finished;
        }

        if (!finished)
            status = LCResult_DidNotFinish;

        char teamName[64];
        if (teamGame)
            GetReportedTeamName(team, teamName, sizeof(teamName));

        LC_MatchSetResult(match, key, teamName, rank, status, true, float(playerFrags));
    }

    delete keys;
    delete frags;
    delete teams;
    delete finish;
}

// Ranks the playing teams by score into teamRank (0 = not ranked). Returns
// whether this is a team game: two or more playing teams with players.
bool RankTeams(int match, int teamRank[LC_MAX_TEAMS])
{
    int teamCount = GetTeamCount();

    if (teamCount > LC_MAX_TEAMS)
        teamCount = LC_MAX_TEAMS;

    int playing = 0;

    for (int team = 2; team < teamCount; team++)
    {
        if (TeamHadPlayers(team))
            playing++;
    }

    if (playing < 2)
        return false;

    char teamName[64];

    for (int team = 2; team < teamCount; team++)
    {
        if (!TeamHadPlayers(team))
            continue;

        int score = GetTeamScore(team);
        int rank = 1;

        for (int other = 2; other < teamCount; other++)
        {
            if (other != team && TeamHadPlayers(other) && GetTeamScore(other) > score)
                rank++;
        }

        teamRank[team] = rank;

        GetReportedTeamName(team, teamName, sizeof(teamName));
        LC_MatchSetStatistic(match, "", teamName, "score", float(score));

        if (!g_TeamResultSet[team])
            LC_MatchSetResult(match, "", teamName, rank, rank == 1 ? LCResult_Finished : LCResult_Defeated, true, float(score));
    }

    return true;
}

// A team with players now, or with a player who left during the match.
bool TeamHadPlayers(int team)
{
    if (GetTeamClientCount(team) > 0)
        return true;

    StringMapSnapshot left = g_LeftPlayers.Snapshot();
    char key[LC_MAX_KEY];
    bool found = false;

    for (int i = 0; i < left.Length && !found; i++)
    {
        left.GetKey(i, key, sizeof(key));

        int info[2];
        g_LeftPlayers.GetArray(key, info, sizeof(info));
        found = info[1] == team;
    }

    delete left;
    return found;
}

// ── What is kept with the match ───────────────────────────────────────────────

LCPayload BuildSettings()
{
    LCPayload settings = new LCPayload();

    char list[1024];
    g_cvSettingsCvars.GetString(list, sizeof(list));

    char names[64][64];
    int count = ExplodeString(list, ",", names, sizeof(names), sizeof(names[]));

    char value[256];

    for (int i = 0; i < count; i++)
    {
        TrimString(names[i]);

        if (!names[i][0])
            continue;

        ConVar cvar = FindConVar(names[i]);

        if (cvar == null)
            continue;

        cvar.GetString(value, sizeof(value));
        settings.SetString(names[i], value);
    }

    return settings;
}

LCPayload BuildMetadata()
{
    LCPayload metadata = new LCPayload();

    char text[PLATFORM_MAX_PATH];

    GetGameFolderName(text, sizeof(text));
    metadata.SetString("game_folder", text);

    GetEngineName(text, sizeof(text));
    metadata.SetString("engine", text);

    GetCurrentMap(text, sizeof(text));
    metadata.SetString("map_path", text);

    metadata.SetString("sourcemod_version", SOURCEMOD_VERSION);
    metadata.SetString("plugin_version", PLUGIN_VERSION);
    metadata.SetInt("max_players", MaxClients);
    metadata.SetInt("tickrate", RoundToNearest(1.0 / GetTickInterval()));

    return metadata;
}

void GetEngineName(char[] name, int maxlength)
{
    switch (GetEngineVersion())
    {
        case Engine_Original:      strcopy(name, maxlength, "original");
        case Engine_SourceSDK2006: strcopy(name, maxlength, "sdk2006");
        case Engine_SourceSDK2007: strcopy(name, maxlength, "sdk2007");
        case Engine_Left4Dead:     strcopy(name, maxlength, "left4dead");
        case Engine_DarkMessiah:   strcopy(name, maxlength, "darkmessiah");
        case Engine_Left4Dead2:    strcopy(name, maxlength, "left4dead2");
        case Engine_AlienSwarm:    strcopy(name, maxlength, "alienswarm");
        case Engine_BloodyGoodTime: strcopy(name, maxlength, "bloodygoodtime");
        case Engine_EYE:           strcopy(name, maxlength, "eye");
        case Engine_Portal2:       strcopy(name, maxlength, "portal2");
        case Engine_CSGO:          strcopy(name, maxlength, "csgo");
        case Engine_CSS:           strcopy(name, maxlength, "css");
        case Engine_DOTA:          strcopy(name, maxlength, "dota");
        case Engine_HL2DM:         strcopy(name, maxlength, "hl2dm");
        case Engine_DODS:          strcopy(name, maxlength, "dods");
        case Engine_TF2:           strcopy(name, maxlength, "tf2");
        case Engine_NuclearDawn:   strcopy(name, maxlength, "nucleardawn");
        case Engine_SDK2013:       strcopy(name, maxlength, "sdk2013");
        case Engine_Blade:         strcopy(name, maxlength, "blade");
        case Engine_Insurgency:    strcopy(name, maxlength, "insurgency");
        case Engine_Contagion:     strcopy(name, maxlength, "contagion");
        case Engine_BlackMesa:     strcopy(name, maxlength, "blackmesa");
        case Engine_DOI:           strcopy(name, maxlength, "doi");
        case Engine_PVKII:         strcopy(name, maxlength, "pvkii");
        case Engine_MCV:           strcopy(name, maxlength, "mcv");
        default:                   strcopy(name, maxlength, "unknown");
    }
}

// The game's version from steam.inf (PatchVersion=...), "" if it has none.
void GetGameVersion(char[] version, int maxlength)
{
    version[0] = '\0';

    File inf = OpenFile("steam.inf", "r", true);

    if (inf == null)
        return;

    char line[128];

    while (inf.ReadLine(line, sizeof(line)))
    {
        TrimString(line);

        if (StrContains(line, "PatchVersion=", false) == 0)
        {
            strcopy(version, maxlength, line[13]);
            break;
        }
    }

    delete inf;
}
