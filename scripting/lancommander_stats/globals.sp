// State shared across the core plugin's files.

#define LC_MAX_KEY   80      // matches LCSTATS_MAX_KEY in lancommander_stats.inc
#define LC_MAX_TEAMS 32      // the engine's MAX_TEAMS

// ── The match ─────────────────────────────────────────────────────────────────

int   g_Match;                       // the open match's handle, 0 when none
char  g_MatchExternalId[192];
float g_MatchStartGameTime;          // GetGameTime() when it started
bool  g_MatchHeld;                   // an integration is holding the automatic start
bool  g_MatchDoneThisMap;            // ended at game over: no other match on this map
int   g_MapStartUnix;                // part of the default external id
int   g_Round;                       // counted from round_start events, 0 before the first
bool  g_Warmup;                      // set by game modules (LCStats_SetWarmup)
bool  g_ModuleOwnsRounds;            // set by game modules (LCStats_SetOwnRounds)

// ── Players ───────────────────────────────────────────────────────────────────

char  g_PlayerKey[MAXPLAYERS + 1][LC_MAX_KEY];   // "" = not recorded
bool  g_PlayerInMatch[MAXPLAYERS + 1];           // joined to g_Match
float g_PlayerJoinedAt[MAXPLAYERS + 1];          // GetGameTime() when joined to g_Match

// Players who left the open match: key -> [frags, team], for their results.
StringMap g_LeftPlayers;

// ── Results set by other plugins, which the core's own must not replace ────────

bool      g_TeamResultSet[LC_MAX_TEAMS];
StringMap g_PlayerResultSet;          // key -> true

char g_TeamNameOverride[LC_MAX_TEAMS][64];

// ── Forwards ──────────────────────────────────────────────────────────────────

GlobalForward g_fwdMatchStarting;
GlobalForward g_fwdMatchStarted;
GlobalForward g_fwdMatchEnding;
GlobalForward g_fwdMatchEnded;
GlobalForward g_fwdEvent;
