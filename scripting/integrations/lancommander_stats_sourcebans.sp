/**
 * LANCommander Match Statistics: SourceBans++ and SourceComms.
 *
 * Records mutes and gags (SourceComms) and player reports (SourceBans++) in
 * the match. Bans need nothing here: SourceBans++ bans through SourceMod's
 * ban system, which the core plugin already records as admin_ban.
 *
 * The forwards are implemented without the plugins' includes; their
 * signatures are from sourcebanspp.inc and sourcecomms.inc (sbpp/sourcebans-pp,
 * game/addons/sourcemod/scripting/include/).
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: SourceBans++",
    author      = "LANCommander",
    description = "Records SourceComms blocks and SourceBans++ reports in LANCommander matches",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

// sourcecomms.inc: TYPE_MUTE 1, TYPE_GAG 2, TYPE_SILENCE 3; their removals
// TYPE_UNMUTE 4, TYPE_UNGAG 5, TYPE_UNSILENCE 6, and for temporary blocks
// TYPE_TEMP_UNMUTE 14, TYPE_TEMP_UNGAG 15, TYPE_TEMP_UNSILENCE 16. Named by
// what is (un)blocked; the event type says which way.
void BlockTypeName(int type, char[] name, int maxlength)
{
    switch (type)
    {
        case 1, 4, 14: strcopy(name, maxlength, "mute");
        case 2, 5, 15: strcopy(name, maxlength, "gag");
        case 3, 6, 16: strcopy(name, maxlength, "silence");
        default:       FormatEx(name, maxlength, "type_%d", type);
    }
}

int ClientOrNone(int client)
{
    return client >= 1 && client <= MaxClients && IsClientInGame(client) ? client : 0;
}

// forward void SourceComms_OnBlockAdded(int client, int target, int time, int type, char[] reason);
public void SourceComms_OnBlockAdded(int client, int target, int time, int type, char[] reason)
{
    char typeName[16];
    BlockTypeName(type, typeName, sizeof(typeName));

    LCPayload payload = new LCPayload();
    payload.SetString("block", typeName);
    payload.SetInt("duration_minutes", time);

    if (reason[0])
        payload.SetString("reason", reason);

    LCStats_Event("admin_comm_block", ClientOrNone(client), ClientOrNone(target), payload);
    delete payload;
}

// forward void SourceComms_OnBlockRemoved(int client, int target, int type, char[] reason);
public void SourceComms_OnBlockRemoved(int client, int target, int type, char[] reason)
{
    char typeName[16];
    BlockTypeName(type, typeName, sizeof(typeName));

    LCPayload payload = new LCPayload();
    payload.SetString("block", typeName);

    if (reason[0])
        payload.SetString("reason", reason);

    LCStats_Event("admin_comm_unblock", ClientOrNone(client), ClientOrNone(target), payload);
    delete payload;
}

// forward void SBPP_OnReportPlayer(int iReporter, int iTarget, const char[] sReason);
public void SBPP_OnReportPlayer(int iReporter, int iTarget, const char[] sReason)
{
    LCPayload payload = new LCPayload();

    if (sReason[0])
        payload.SetString("reason", sReason);

    LCStats_Event("player_reported", ClientOrNone(iReporter), ClientOrNone(iTarget), payload);
    delete payload;
}
