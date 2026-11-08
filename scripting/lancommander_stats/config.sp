// The cvars, in cfg/sourcemod/lancommander.cfg, and handing the connection
// settings to the extension.

ConVar g_cvEnabled;
ConVar g_cvServerUrl;
ConVar g_cvToken;
ConVar g_cvGameId;
ConVar g_cvServerId;
ConVar g_cvReporterName;
ConVar g_cvFlushInterval;

ConVar g_cvMinPlayers;
ConVar g_cvMode;
ConVar g_cvSettingsCvars;

ConVar g_cvRecordBots;
ConVar g_cvRecordWarmup;
ConVar g_cvRecordDamage;
ConVar g_cvRecordSpawns;
ConVar g_cvRecordChat;
ConVar g_cvRecordPositions;
ConVar g_cvRecordWeaponFire;
ConVar g_cvAttachDemos;
ConVar g_cvEventsInclude;
ConVar g_cvEventsExclude;

// lc_events_include / lc_events_exclude, split into patterns.
ArrayList g_EventsInclude;
ArrayList g_EventsExclude;

ConVar g_cvHostname;

void CreateConfig()
{
    CreateConVar("lc_version", PLUGIN_VERSION, "LANCommander Match Statistics version",
        FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_SPONLY);

    // Where reports go.
    g_cvEnabled = CreateConVar("lc_enabled", "1",
        "Report matches to LANCommander. 0 records nothing.", _, true, 0.0, true, 1.0);
    g_cvServerUrl = CreateConVar("lc_server_url", "",
        "The LANCommander server, e.g. http://lancommander.lan:1337. On Linux only http:// is supported.");
    g_cvToken = CreateConVar("lc_token", "",
        "A LANCommander personal access token with the \"Report matches\" (matches:report) scope. An administrator's token makes reports authoritative. %VARIABLE% reads an environment variable.",
        FCVAR_PROTECTED);
    g_cvGameId = CreateConVar("lc_game_id", "",
        "The game's id in LANCommander (a GUID, from the game's page).");
    g_cvServerId = CreateConVar("lc_server_id", "",
        "This server's id in LANCommander (a GUID), when LANCommander manages it. Optional.");
    g_cvReporterName = CreateConVar("lc_reporter_name", "",
        "How this server is named in LANCommander. Empty uses the hostname.");
    g_cvFlushInterval = CreateConVar("lc_flush_interval", "2000",
        "Milliseconds between batches of events sent to LANCommander.", _, true, 100.0, true, 600000.0);

    // What a match is.
    g_cvMinPlayers = CreateConVar("lc_min_players", "1",
        "Human players needed before a match is opened on a new map (bots do not count).", _, true, 0.0);
    g_cvMode = CreateConVar("lc_mode", "",
        "The game mode reported for matches. Empty lets the game module decide (e.g. defusal, ctf).");
    g_cvSettingsCvars = CreateConVar("lc_settings_cvars",
        "mp_timelimit,mp_fraglimit,mp_maxrounds,mp_winlimit,mp_roundtime,mp_freezetime,mp_friendlyfire,mp_teamplay,mp_autoteambalance,sv_gravity,sv_cheats,tf_gamemode_arena,game_type,game_mode",
        "Comma-separated cvars whose values are kept with each match as its settings.");

    // What is recorded.
    g_cvRecordBots = CreateConVar("lc_record_bots", "1",
        "Record bots as players (key bot:<name>).", _, true, 0.0, true, 1.0);
    g_cvRecordWarmup = CreateConVar("lc_record_warmup", "0",
        "Record events during warmup (marked warmup:true).", _, true, 0.0, true, 1.0);
    g_cvRecordDamage = CreateConVar("lc_record_damage", "0",
        "Record every hit as a damage event. Damage totals are kept either way.", _, true, 0.0, true, 1.0);
    g_cvRecordSpawns = CreateConVar("lc_record_spawns", "1",
        "Record player spawns.", _, true, 0.0, true, 1.0);
    g_cvRecordChat = CreateConVar("lc_record_chat", "0",
        "Record chat messages.", _, true, 0.0, true, 1.0);
    g_cvRecordPositions = CreateConVar("lc_record_positions", "1",
        "Include player positions in kill, spawn and objective events.", _, true, 0.0, true, 1.0);
    g_cvRecordWeaponFire = CreateConVar("lc_record_weapon_fire", "0",
        "Record every shot as an event (very many). Shot totals are kept either way.", _, true, 0.0, true, 1.0);
    g_cvAttachDemos = CreateConVar("lc_attach_demos", "1",
        "Upload SourceTV demos recorded with tv_record to the match they cover.", _, true, 0.0, true, 1.0);

    // Which events are recorded, by type. Statistics, standings and players are
    // recorded whatever these say.
    g_cvEventsInclude = CreateConVar("lc_events_include", "",
        "Record only these event types: comma-separated, * as a wildcard (e.g. \"kill,bomb_*,round_*\"). Empty records every type. Statistics and results are kept either way.");
    g_cvEventsExclude = CreateConVar("lc_events_exclude", "",
        "Never record these event types: comma-separated, * as a wildcard (e.g. \"spawn,damage,grenade_*\"). Applied after lc_events_include. Statistics and results are kept either way.");

    g_EventsInclude = new ArrayList(ByteCountToCells(64));
    g_EventsExclude = new ArrayList(ByteCountToCells(64));
    g_cvEventsInclude.AddChangeHook(OnEventFilterChanged);
    g_cvEventsExclude.AddChangeHook(OnEventFilterChanged);

    AutoExecConfig(true, "lancommander");

    g_cvHostname = FindConVar("hostname");

    g_cvEnabled.AddChangeHook(OnConnectionCvarChanged);
    g_cvServerUrl.AddChangeHook(OnConnectionCvarChanged);
    g_cvToken.AddChangeHook(OnConnectionCvarChanged);
    g_cvGameId.AddChangeHook(OnConnectionCvarChanged);
    g_cvServerId.AddChangeHook(OnConnectionCvarChanged);
    g_cvReporterName.AddChangeHook(OnConnectionCvarChanged);
    g_cvFlushInterval.AddChangeHook(OnConnectionCvarChanged);
}

bool g_ConfigApplied;

public void OnConnectionCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    // Before OnConfigsExecuted the config file is still being read: apply it
    // once, complete, rather than a value at a time.
    if (g_ConfigApplied)
        ApplyConfig();
}

// Hands the connection settings to the extension. The settings apply to
// matches started afterwards.
void ApplyConfig()
{
    char url[256], token[256], gameId[64], serverId[64], reporter[128];

    g_cvServerUrl.GetString(url, sizeof(url));
    g_cvToken.GetString(token, sizeof(token));
    g_cvGameId.GetString(gameId, sizeof(gameId));
    g_cvServerId.GetString(serverId, sizeof(serverId));
    g_cvReporterName.GetString(reporter, sizeof(reporter));

    TrimString(url);
    TrimString(token);
    TrimString(gameId);
    TrimString(serverId);

    if (!reporter[0] && g_cvHostname != null)
        g_cvHostname.GetString(reporter, sizeof(reporter));

    g_ConfigApplied = true;

    if (!LC_Configure(g_cvEnabled.BoolValue, url, token, gameId, serverId, reporter, g_cvFlushInterval.IntValue))
    {
        LogError("LANCommander settings were refused: check lc_server_url (http:// or https://), lc_game_id and lc_server_id (GUIDs). The extension's log in addons/sourcemod/extensions/.interposer/Logs/ names the value.");
        return;
    }

    if (g_cvEnabled.BoolValue && (!url[0] || !token[0] || !gameId[0]))
        LogMessage("lc_server_url, lc_token and lc_game_id are not all set: matches are recorded but not sent to LANCommander.");
}

public void OnEventFilterChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    LoadEventFilter();
}

// Splits the two filter cvars into their patterns. Called when either
// changes and once the config files have run.
void LoadEventFilter()
{
    SplitPatterns(g_cvEventsInclude, g_EventsInclude);
    SplitPatterns(g_cvEventsExclude, g_EventsExclude);
}

void SplitPatterns(ConVar cvar, ArrayList patterns)
{
    patterns.Clear();

    char list[1024];
    cvar.GetString(list, sizeof(list));

    char parts[64][64];
    int count = ExplodeString(list, ",", parts, sizeof(parts), sizeof(parts[]));

    for (int i = 0; i < count; i++)
    {
        TrimString(parts[i]);

        if (parts[i][0])
            patterns.PushString(parts[i]);
    }
}

// Whether the filter keeps an event of this type out of the match.
bool IsEventFiltered(const char[] type)
{
    char pattern[64];

    if (g_EventsInclude.Length)
    {
        bool included = false;

        for (int i = 0; i < g_EventsInclude.Length && !included; i++)
        {
            g_EventsInclude.GetString(i, pattern, sizeof(pattern));
            included = WildcardMatch(type, pattern);
        }

        if (!included)
            return true;
    }

    for (int i = 0; i < g_EventsExclude.Length; i++)
    {
        g_EventsExclude.GetString(i, pattern, sizeof(pattern));

        if (WildcardMatch(type, pattern))
            return true;
    }

    return false;
}

// Case-insensitive match of text against a pattern where * stands for any
// run of characters, including none.
bool WildcardMatch(const char[] text, const char[] pattern)
{
    int t = 0, p = 0, star = -1, resume = 0;

    while (text[t])
    {
        if (pattern[p] == '*')
        {
            star = p++;
            resume = t;
        }
        else if (pattern[p] && CharToLower(pattern[p]) == CharToLower(text[t]))
        {
            p++;
            t++;
        }
        else if (star != -1)
        {
            p = star + 1;
            t = ++resume;
        }
        else
            return false;
    }

    while (pattern[p] == '*')
        p++;

    return !pattern[p];
}

// Whether matches should be recorded at all.
bool ReportingEnabled()
{
    return g_cvEnabled.BoolValue;
}
