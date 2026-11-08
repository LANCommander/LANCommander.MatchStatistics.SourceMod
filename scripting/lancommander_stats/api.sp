// The API in lancommander_stats.inc, for game modules and integrations.

void CreateApi()
{
    CreateNative("LCStats_GetMatch",        Native_GetMatch);
    CreateNative("LCStats_IsRecording",     Native_IsRecording);
    CreateNative("LCStats_GetPlayerKey",    Native_GetPlayerKey);
    CreateNative("LCStats_GetGameTime",     Native_GetGameTime);
    CreateNative("LCStats_GetRound",        Native_GetRound);
    CreateNative("LCStats_SetRound",        Native_SetRound);
    CreateNative("LCStats_SetOwnRounds",    Native_SetOwnRounds);
    CreateNative("LCStats_Event",           Native_Event);
    CreateNative("LCStats_EventKeys",       Native_EventKeys);
    CreateNative("LCStats_AddDamage",       Native_AddDamage);
    CreateNative("LCStats_AddStat",         Native_AddStat);
    CreateNative("LCStats_SetStat",         Native_SetStat);
    CreateNative("LCStats_AddTeamStat",     Native_AddTeamStat);
    CreateNative("LCStats_SetTeamStat",     Native_SetTeamStat);
    CreateNative("LCStats_SetTeamResult",   Native_SetTeamResult);
    CreateNative("LCStats_SetPlayerResult", Native_SetPlayerResult);
    CreateNative("LCStats_GetTeamName",     Native_GetTeamName);
    CreateNative("LCStats_SetTeamName",     Native_SetTeamName);
    CreateNative("LCStats_SetWarmup",       Native_SetWarmup);
    CreateNative("LCStats_IsWarmup",        Native_IsWarmup);
    CreateNative("LCStats_StartMatch",      Native_StartMatch);
    CreateNative("LCStats_EndMatch",        Native_EndMatch);

    g_fwdMatchStarting = new GlobalForward("LCStats_OnMatchStarting", ET_Hook,
        Param_String, Param_Cell, Param_String, Param_Cell, Param_Cell);
    g_fwdMatchStarted = new GlobalForward("LCStats_OnMatchStarted", ET_Ignore, Param_Cell, Param_String);
    g_fwdMatchEnding  = new GlobalForward("LCStats_OnMatchEnding", ET_Ignore, Param_Cell, Param_String, Param_Cell);
    g_fwdMatchEnded   = new GlobalForward("LCStats_OnMatchEnded", ET_Ignore, Param_Cell, Param_String, Param_Cell);
    g_fwdEvent        = new GlobalForward("LCStats_OnEvent", ET_Hook, Param_String, Param_Cell, Param_Cell, Param_Cell);
}

// A client argument: 0 is allowed (none); anything else must be in game.
bool ClientArg(int param, int &client)
{
    client = GetNativeCell(param);

    if (client == 0)
        return true;

    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        ThrowNativeError(SP_ERROR_PARAM, "Client %d is not in game", client);
        return false;
    }

    return true;
}

bool TeamArg(int param, int &team)
{
    team = GetNativeCell(param);

    if (team < 0 || team >= LC_MAX_TEAMS)
    {
        ThrowNativeError(SP_ERROR_PARAM, "Team %d is out of range", team);
        return false;
    }

    return true;
}

public any Native_GetMatch(Handle plugin, int numParams)
{
    return g_Match;
}

public any Native_IsRecording(Handle plugin, int numParams)
{
    return IsRecording();
}

public any Native_GetPlayerKey(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int maxlength = GetNativeCell(3);

    char key[LC_MAX_KEY];
    bool found = client >= 1 && client <= MaxClients && IsClientInGame(client) && GetKey(client, key, sizeof(key));

    SetNativeString(2, key, maxlength);
    return found;
}

public any Native_GetGameTime(Handle plugin, int numParams)
{
    return GameTimeMs();
}

public any Native_GetRound(Handle plugin, int numParams)
{
    return g_Round;
}

public any Native_SetOwnRounds(Handle plugin, int numParams)
{
    g_ModuleOwnsRounds = GetNativeCell(1);
    return 0;
}

public any Native_SetRound(Handle plugin, int numParams)
{
    int round = GetNativeCell(1);
    g_Round = round > 0 ? round : 0;
    return 0;
}

public any Native_Event(Handle plugin, int numParams)
{
    int actor, subject;

    if (!ClientArg(2, actor) || !ClientArg(3, subject))
        return false;

    char type[64];
    GetNativeString(1, type, sizeof(type));

    return SendEvent(type, actor, subject, "", "", view_as<LCPayload>(GetNativeCell(4)));
}

public any Native_EventKeys(Handle plugin, int numParams)
{
    char type[64], actorKey[LC_MAX_KEY], subjectKey[LC_MAX_KEY];
    GetNativeString(1, type, sizeof(type));
    GetNativeString(2, actorKey, sizeof(actorKey));
    GetNativeString(3, subjectKey, sizeof(subjectKey));

    return SendEvent(type, 0, 0, actorKey, subjectKey, view_as<LCPayload>(GetNativeCell(4)));
}

public any Native_AddDamage(Handle plugin, int numParams)
{
    int attacker, victim;

    if (!ClientArg(1, attacker) || !ClientArg(2, victim) || victim == 0 || !IsRecording())
        return false;

    RecordDamage(attacker, victim, GetNativeCell(3));
    return true;
}

public any Native_AddStat(Handle plugin, int numParams)
{
    int client;

    if (!ClientArg(1, client) || client == 0)
        return false;

    char key[64];
    GetNativeString(2, key, sizeof(key));

    return AddPlayerStat(client, key, GetNativeCell(3));
}

public any Native_SetStat(Handle plugin, int numParams)
{
    int client;
    char playerKey[LC_MAX_KEY];

    if (!ClientArg(1, client) || client == 0 || !IsRecording() || !GetKey(client, playerKey, sizeof(playerKey)))
        return false;

    char key[64];
    GetNativeString(2, key, sizeof(key));

    return LC_MatchSetStatistic(g_Match, playerKey, "", key, GetNativeCell(3));
}

bool TeamStat(bool add)
{
    int team;
    char teamName[64], key[64];

    if (!TeamArg(1, team) || !IsRecording())
        return false;

    GetReportedTeamName(team, teamName, sizeof(teamName));

    if (!teamName[0])
        return false;

    GetNativeString(2, key, sizeof(key));
    float value = GetNativeCell(3);

    return add ? LC_MatchAddStatistic(g_Match, "", teamName, key, value)
               : LC_MatchSetStatistic(g_Match, "", teamName, key, value);
}

public any Native_AddTeamStat(Handle plugin, int numParams)
{
    return TeamStat(true);
}

public any Native_SetTeamStat(Handle plugin, int numParams)
{
    return TeamStat(false);
}

public any Native_SetTeamResult(Handle plugin, int numParams)
{
    int team;
    char teamName[64];

    if (!TeamArg(1, team) || !g_Match)
        return false;

    GetReportedTeamName(team, teamName, sizeof(teamName));

    if (!teamName[0])
        return false;

    g_TeamResultSet[team] = true;

    return LC_MatchSetResult(g_Match, "", teamName, GetNativeCell(2), GetNativeCell(3), GetNativeCell(4), GetNativeCell(5));
}

public any Native_SetPlayerResult(Handle plugin, int numParams)
{
    int client;
    char playerKey[LC_MAX_KEY], teamName[64];

    if (!ClientArg(1, client) || client == 0 || !g_Match || !GetKey(client, playerKey, sizeof(playerKey)))
        return false;

    g_PlayerResultSet.SetValue(playerKey, true);
    GetReportedTeamName(GetClientTeam(client), teamName, sizeof(teamName));

    return LC_MatchSetResult(g_Match, playerKey, teamName, GetNativeCell(2), GetNativeCell(3), GetNativeCell(4), GetNativeCell(5));
}

public any Native_GetTeamName(Handle plugin, int numParams)
{
    char name[64];
    GetReportedTeamName(GetNativeCell(1), name, sizeof(name));
    SetNativeString(2, name, GetNativeCell(3));
    return 0;
}

public any Native_SetTeamName(Handle plugin, int numParams)
{
    int team;

    if (!TeamArg(1, team))
        return 0;

    GetNativeString(2, g_TeamNameOverride[team], sizeof(g_TeamNameOverride[]));

    // Players already in the match are on the renamed team now.
    if (g_Match)
    {
        for (int client = 1; client <= MaxClients; client++)
        {
            if (g_PlayerInMatch[client] && IsClientInGame(client) && GetClientTeam(client) == team)
                JoinMatch(client);
        }
    }

    return 0;
}

public any Native_SetWarmup(Handle plugin, int numParams)
{
    bool warmup = GetNativeCell(1);

    if (warmup == g_Warmup)
        return 0;

    // Leaving warmup: the rounds played so far did not count.
    if (!warmup && !g_cvRecordWarmup.BoolValue)
        g_Round = 0;

    g_Warmup = warmup;
    return 0;
}

public any Native_IsWarmup(Handle plugin, int numParams)
{
    return g_Warmup;
}

public any Native_StartMatch(Handle plugin, int numParams)
{
    char externalId[192], mode[64];
    GetNativeString(1, externalId, sizeof(externalId));
    GetNativeString(2, mode, sizeof(mode));

    g_MatchDoneThisMap = false;
    return StartMatch(externalId, mode, view_as<LCPayload>(GetNativeCell(3)), false);
}

public any Native_EndMatch(Handle plugin, int numParams)
{
    char reason[64];
    GetNativeString(1, reason, sizeof(reason));

    if (!EndMatch(reason, GetNativeCell(2)))
        return false;

    // At game over the server sits in intermission until the map changes:
    // no new match until then.
    g_MatchDoneThisMap = true;
    return true;
}
