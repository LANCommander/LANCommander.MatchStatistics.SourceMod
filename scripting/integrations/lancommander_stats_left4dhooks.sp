/**
 * LANCommander Match Statistics: Left4DHooks (L4D and L4D2).
 *
 * Records when the survivors first leave the safe area, which is when a
 * campaign map's round really starts. Without Left4DHooks loaded this plugin
 * does nothing.
 *
 * The forward is implemented without Left4DHooks' include; its signature is
 * from left4dhooks.inc (SilvDev/Left4DHooks).
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Left4DHooks",
    author      = "LANCommander",
    description = "Records the survivors leaving the safe area in LANCommander matches",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

// forward void L4D_OnFirstSurvivorLeftSafeArea_Post(int client);
public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        client = 0;

    LCPayload payload = new LCPayload();
    LCStats_AddPosition(payload, "player", client);
    LCStats_Event("left_safe_area", client, 0, payload);
    delete payload;
}
