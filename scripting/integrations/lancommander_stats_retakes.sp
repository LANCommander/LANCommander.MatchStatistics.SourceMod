/**
 * LANCommander Match Statistics: Retakes (splewis/csgo-retakes).
 *
 * Reports the mode as "retakes" and records each retake: the bombsite and
 * which side won it, with a statistic per player for retakes won. Without
 * Retakes loaded this plugin does nothing.
 *
 * The forwards are implemented without Retakes' include; their signatures are
 * from retakes.inc (scripting/include/retakes.inc in csgo-retakes), where
 * enum Bombsite { BombsiteA = 0, BombsiteB = 1 }.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Retakes",
    author      = "LANCommander",
    description = "Records Retakes rounds in LANCommander matches",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

int g_Site = -1;

public Action LCStats_OnMatchStarting(char[] externalId, int externalIdLength, char[] mode, int modeLength, LCPayload metadata)
{
    if (!LibraryExists("retakes"))
        return Plugin_Continue;

    strcopy(mode, modeLength, "retakes");
    return Plugin_Changed;
}

// forward void Retakes_OnSitePicked(Bombsite& site);
public void Retakes_OnSitePicked(any &site)
{
    g_Site = site;
}

// forward void Retakes_OnRoundWon(int winner, ArrayList tPlayers, ArrayList ctPlayers);
public void Retakes_OnRoundWon(int winner, ArrayList tPlayers, ArrayList ctPlayers)
{
    LCPayload payload = new LCPayload();

    if (g_Site == 0 || g_Site == 1)
        payload.SetString("site", g_Site == 0 ? "A" : "B");

    LCStats_AddTeam(payload, "winner", winner);
    payload.SetInt("terrorists", tPlayers.Length);
    payload.SetInt("counter_terrorists", ctPlayers.Length);

    LCStats_Event("retake_round_won", 0, 0, payload);
    delete payload;

    ArrayList winners = winner == CS_TEAM_CT ? ctPlayers : tPlayers;

    for (int i = 0; i < winners.Length; i++)
    {
        int client = winners.Get(i);

        if (client >= 1 && client <= MaxClients && IsClientInGame(client))
            LCStats_AddStat(client, winner == CS_TEAM_CT ? "retakes_won" : "retake_holds_won");
    }
}
