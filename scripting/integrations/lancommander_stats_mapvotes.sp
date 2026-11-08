/**
 * LANCommander Match Statistics: map votes.
 *
 * Records the next map whenever it is decided -- by MapChooser, MapChooser
 * Extended, RockTheVote, NativeVotes or an admin's sm_setnextmap. All of them
 * set the sm_nextmap cvar, which is what this follows. MapChooser Extended
 * also reports a finished vote, recorded with it.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Map votes",
    author      = "LANCommander",
    description = "Records the next map and map votes in LANCommander matches",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

bool g_VoteJustEnded;

public void OnPluginStart()
{
    ConVar nextMap = FindConVar("sm_nextmap");

    if (nextMap != null)
        nextMap.AddChangeHook(OnNextMapChanged);
}

public void OnNextMapChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (!newValue[0] || StrEqual(oldValue, newValue))
        return;

    LCPayload payload = new LCPayload();
    payload.SetString("map", newValue);

    if (g_VoteJustEnded)
        payload.SetBool("by_vote", true);

    LCStats_Event("next_map_set", 0, 0, payload);
    delete payload;

    g_VoteJustEnded = false;
}

// MapChooser Extended: forward OnMapVoteEnd(const String:map[]);
public void OnMapVoteEnd(const char[] map)
{
    g_VoteJustEnded = true;

    LCPayload payload = new LCPayload();
    payload.SetString("winner", map);
    LCStats_Event("map_vote_end", 0, 0, payload);
    delete payload;
}
