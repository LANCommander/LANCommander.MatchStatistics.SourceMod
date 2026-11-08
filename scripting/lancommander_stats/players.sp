// Players: their keys, and joining and leaving the open match.
//
// A player key names a player to LANCommander for the whole match:
//   steam:STEAM_0:1:123   a Steam account (STEAM_1 from CS:GO is normalised to 0)
//   bot:<name>            a bot
//   name:<name>           anyone without a Steam id -- sv_lan 1 at a LAN party
// It is worked out once the player is authorized and kept until they leave,
// so a rename does not split a player in two.

bool BuildPlayerKey(int client, char[] key, int maxlength)
{
    key[0] = '\0';

    if (!IsClientInGame(client) && !IsClientConnected(client))
        return false;

    if (IsClientSourceTV(client) || IsClientReplay(client))
        return false;

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));

    if (IsFakeClient(client))
    {
        if (!g_cvRecordBots.BoolValue)
            return false;

        FormatEx(key, maxlength, "bot:%s", name);
        return true;
    }

    char auth[64];

    if (GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true) &&
        strncmp(auth, "STEAM_", 6) == 0 && auth[6] >= '0' && auth[6] <= '9' && auth[7] == ':')
    {
        auth[6] = '0';
        FormatEx(key, maxlength, "steam:%s", auth);
        return true;
    }

    // STEAM_ID_LAN, STEAM_ID_PENDING, or no Steam at all.
    FormatEx(key, maxlength, "name:%s", name);
    return true;
}

// The key a client is recorded under, or false when it is not recorded.
bool GetKey(int client, char[] key, int maxlength)
{
    key[0] = '\0';

    if (client < 1 || client > MaxClients)
        return false;

    if (g_PlayerKey[client][0])
    {
        strcopy(key, maxlength, g_PlayerKey[client]);
        return true;
    }

    // Not authorized yet (an event before OnClientPostAdminCheck): work it out
    // now, but do not keep it, so the Steam id still wins once it arrives.
    return IsClientInGame(client) && BuildPlayerKey(client, key, maxlength);
}

void GetReportedTeamName(int team, char[] name, int maxlength)
{
    name[0] = '\0';

    if (team <= 0 || team >= LC_MAX_TEAMS)
        return;

    if (g_TeamNameOverride[team][0])
    {
        strcopy(name, maxlength, g_TeamNameOverride[team]);
        return;
    }

    if (team < GetTeamCount())
        GetTeamName(team, name, maxlength);
}

// Two clients on the same playing team (not unassigned or spectating).
bool SameTeam(int a, int b)
{
    if (a < 1 || b < 1 || !IsClientInGame(a) || !IsClientInGame(b))
        return false;

    const int kFirstPlayingTeam = 2;
    int team = GetClientTeam(a);
    return team >= kFirstPlayingTeam && team == GetClientTeam(b);
}

public void OnClientPostAdminCheck(int client)
{
    if (!BuildPlayerKey(client, g_PlayerKey[client], LC_MAX_KEY))
        return;

    if (g_Match)
        JoinMatch(client);
    else
        TryStartMatch();
}

public void OnClientDisconnect(int client)
{
    if (g_Match && g_PlayerInMatch[client])
        LeaveMatch(client);

    g_PlayerKey[client][0] = '\0';
    g_PlayerInMatch[client] = false;
}

// Tells the match about a player, or about their new name or team.
void JoinMatch(int client, int team = -1)
{
    if (!g_Match || !g_PlayerKey[client][0] || !IsClientInGame(client))
        return;

    char name[MAX_NAME_LENGTH], teamName[64];
    GetClientName(client, name, sizeof(name));
    GetReportedTeamName(team >= 0 ? team : GetClientTeam(client), teamName, sizeof(teamName));

    LC_MatchPlayerJoined(g_Match, g_PlayerKey[client], name, teamName, GameTimeMs());

    if (!g_PlayerInMatch[client])
    {
        g_PlayerInMatch[client]  = true;
        g_PlayerJoinedAt[client] = GetGameTime();

        // Back after leaving: a finisher again, not a leaver.
        g_LeftPlayers.Remove(g_PlayerKey[client]);
    }
}

void LeaveMatch(int client)
{
    AddTimePlayed(client);

    int left[2];
    left[0] = GetClientFrags(client);
    left[1] = GetClientTeam(client);
    g_LeftPlayers.SetArray(g_PlayerKey[client], left, sizeof(left));

    LC_MatchPlayerLeft(g_Match, g_PlayerKey[client], GameTimeMs());
    g_PlayerInMatch[client] = false;
}

// Adds the time since the player joined the match (or since this was last
// counted) to time_played_ms.
void AddTimePlayed(int client)
{
    if (!g_PlayerInMatch[client])
        return;

    float now = GetGameTime();
    float played = now - g_PlayerJoinedAt[client];

    if (played > 0.0)
        LC_MatchAddStatistic(g_Match, g_PlayerKey[client], "", "time_played_ms", played * 1000.0);

    g_PlayerJoinedAt[client] = now;
}

// Every authorized player in game joins a match that has just started.
void JoinEveryone()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_PlayerInMatch[client] = false;

        if (!IsClientInGame(client) || !IsClientAuthorized(client))
            continue;

        if (!g_PlayerKey[client][0] && !BuildPlayerKey(client, g_PlayerKey[client], LC_MAX_KEY))
            continue;

        JoinMatch(client);
    }
}

int CountHumans()
{
    int humans = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && !IsFakeClient(client))
            humans++;
    }

    return humans;
}
