// Admin commands.
//
//   sm_lc_status            the open match and how its delivery is going
//   sm_lc_flush             send what is waiting now (blocks up to 5 s)
//   sm_lc_startmatch [mode] open a match now, ignoring lc_min_players
//   sm_lc_endmatch [reason] end the open match ("admin" by default)
//   sm_lc_abandonmatch      end it as abandoned: its results do not count

void RegisterCommands()
{
    RegAdminCmd("sm_lc_status", Command_Status, ADMFLAG_GENERIC, "Shows the LANCommander match being recorded");
    RegAdminCmd("sm_lc_flush", Command_Flush, ADMFLAG_RCON, "Sends waiting match reports to LANCommander now");
    RegAdminCmd("sm_lc_startmatch", Command_StartMatch, ADMFLAG_CHANGEMAP, "sm_lc_startmatch [mode] - starts recording a match now");
    RegAdminCmd("sm_lc_endmatch", Command_EndMatch, ADMFLAG_CHANGEMAP, "sm_lc_endmatch [reason] - ends the match being recorded");
    RegAdminCmd("sm_lc_abandonmatch", Command_AbandonMatch, ADMFLAG_CHANGEMAP, "Ends the match being recorded as abandoned (its results do not count)");
}

public Action Command_Status(int client, int args)
{
    if (!g_Match)
    {
        ReplyToCommand(client, "[LANCommander] No match is being recorded.%s",
            g_MatchHeld ? " Another plugin is holding the start." : "");
        return Plugin_Handled;
    }

    LCSink sink;
    int pending, rejected, attachments;
    bool ended, delivered;
    char matchId[40], lastError[256];

    LC_MatchGetStatus(g_Match, sink, pending, rejected, attachments, ended, delivered,
        matchId, sizeof(matchId), lastError, sizeof(lastError));

    static const char sinkNames[][] = { "not sent (only logged)", "LANCommander server", "LANCommander launcher" };

    ReplyToCommand(client, "[LANCommander] Match %s (%d), round %d, %d s in%s",
        g_MatchExternalId, g_Match, g_Round, GameTimeMs() / 1000, g_Warmup ? ", warmup" : "");
    ReplyToCommand(client, "[LANCommander] Sent to: %s. LANCommander id: %s",
        sinkNames[view_as<int>(sink)], matchId[0] ? matchId : "(not registered yet)");
    ReplyToCommand(client, "[LANCommander] Waiting: %d events, %d attachments. Refused: %d events.",
        pending, attachments, rejected);

    if (lastError[0])
        ReplyToCommand(client, "[LANCommander] Last problem: %s", lastError);

    return Plugin_Handled;
}

public Action Command_Flush(int client, int args)
{
    if (!g_Match)
    {
        ReplyToCommand(client, "[LANCommander] No match is being recorded.");
        return Plugin_Handled;
    }

    bool done = LC_MatchFlush(g_Match, 5000);
    ReplyToCommand(client, "[LANCommander] %s", done ? "Everything has been sent." : "Some reports are still waiting; see sm_lc_status.");
    return Plugin_Handled;
}

public Action Command_StartMatch(int client, int args)
{
    if (g_Match)
    {
        ReplyToCommand(client, "[LANCommander] A match is already being recorded; end it first with sm_lc_endmatch.");
        return Plugin_Handled;
    }

    char mode[64];

    if (args >= 1)
        GetCmdArg(1, mode, sizeof(mode));

    // A fresh external id: an admin starting again on the same map wants a
    // new match, not the one just ended.
    char externalId[192];
    DefaultExternalId(externalId, sizeof(externalId));
    Format(externalId, sizeof(externalId), "%s-%d", externalId, GetTime());

    g_MatchDoneThisMap = false;

    if (StartMatch(externalId, mode, null, false))
        ReplyToCommand(client, "[LANCommander] Recording match %s.", g_MatchExternalId);
    else
        ReplyToCommand(client, "[LANCommander] Could not start a match: is lc_enabled 1?");

    return Plugin_Handled;
}

public Action Command_EndMatch(int client, int args)
{
    char reason[64] = "admin";

    if (args >= 1)
        GetCmdArg(1, reason, sizeof(reason));

    EndFromCommand(client, reason, false);
    return Plugin_Handled;
}

public Action Command_AbandonMatch(int client, int args)
{
    EndFromCommand(client, "admin_abandoned", true);
    return Plugin_Handled;
}

void EndFromCommand(int client, const char[] reason, bool abandoned)
{
    if (!EndMatch(reason, abandoned))
    {
        ReplyToCommand(client, "[LANCommander] No match is being recorded.");
        return;
    }

    // Not again on this map unless an admin starts one.
    g_MatchDoneThisMap = true;
    ReplyToCommand(client, "[LANCommander] Match ended (%s).", reason);
}
