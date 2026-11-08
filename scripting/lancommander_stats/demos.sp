// SourceTV demos: a demo recorded with tv_record is uploaded to the match it
// covers once the recording stops (lc_attach_demos). A recording the engine
// stops itself at a map change, with no tv_stoprecord, is attached on the next
// map, when the file is complete.

char g_DemoPath[PLATFORM_MAX_PATH];   // the recording in progress, "" when none
int  g_DemoMatch;                     // the match it started in
int  g_DemoStartMs;                   // game time it started at, -1 if before the match

void RegisterDemoListeners()
{
    AddCommandListener(Listener_TvRecord, "tv_record");
    AddCommandListener(Listener_TvStopRecord, "tv_stoprecord");
}

public Action Listener_TvRecord(int client, const char[] command, int argc)
{
    if (!g_cvAttachDemos.BoolValue || argc < 1)
        return Plugin_Continue;

    // A recording still pending from before: it stops when this one starts.
    AttachPendingDemo();

    char name[PLATFORM_MAX_PATH];
    GetCmdArg(1, name, sizeof(name));

    if (StrContains(name, ".dem", false) == -1)
        StrCat(name, sizeof(name), ".dem");

    strcopy(g_DemoPath, sizeof(g_DemoPath), name);
    g_DemoMatch   = g_Match;
    g_DemoStartMs = g_Match ? GameTimeMs() : -1;

    return Plugin_Continue;
}

public Action Listener_TvStopRecord(int client, const char[] command, int argc)
{
    if (!g_DemoPath[0])
        return Plugin_Continue;

    // The engine closes the file once the command has run; give it a moment.
    // Not TIMER_FLAG_NO_MAPCHANGE: a match can take a file after it has ended.
    DataPack pack;
    CreateDataTimer(2.0, Timer_AttachDemo, pack);
    pack.WriteString(g_DemoPath);
    pack.WriteCell(g_DemoMatch);
    pack.WriteCell(g_DemoStartMs);
    pack.WriteCell(g_DemoMatch == g_Match ? GameTimeMs() : -1);

    g_DemoPath[0] = '\0';
    return Plugin_Continue;
}

public Action Timer_AttachDemo(Handle timer, DataPack pack)
{
    char path[PLATFORM_MAX_PATH];

    pack.Reset();
    pack.ReadString(path, sizeof(path));
    int match   = pack.ReadCell();
    int startMs = pack.ReadCell();
    int endMs   = pack.ReadCell();

    AttachDemo(path, match, startMs, endMs);
    return Plugin_Stop;
}

// A recording left running at the last map change is complete now.
void AttachPendingDemo()
{
    if (!g_DemoPath[0])
        return;

    AttachDemo(g_DemoPath, g_DemoMatch, g_DemoStartMs, -1);
    g_DemoPath[0] = '\0';
}

void AttachDemo(const char[] path, int match, int startMs, int endMs)
{
    if (!match)
        return;

    if (!FileExists(path))
    {
        LogMessage("SourceTV demo %s not found; not attached", path);
        return;
    }

    if (!LC_MatchAttachFile(match, path, LCAttachment_Demo, startMs, endMs))
        LogError("Could not attach SourceTV demo %s to match %d", path, match);
}
