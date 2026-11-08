// The event map: configs/lancommander_events.cfg records any game event as a
// match event without code, for games without a module of their own. See the
// file for its format.

enum struct EventMapping
{
    char type[64];          // the match event recorded
    char actorField[32];    // the game event field naming who did it
    bool actorIsClient;     // ... as a client index rather than a userid
    char subjectField[32];
    bool subjectIsClient;
    char actorStat[64];     // statistic added to the actor (+1)
    char subjectStat[64];   // and to the subject
    ArrayList fieldNames;   // copied into the payload
    ArrayList fieldKinds;   // int, float, bool, string, userid, client
}

ArrayList g_EventMappings;   // of EventMapping
StringMap g_EventMappingIndex;  // game event name -> index in g_EventMappings
bool      g_EventMapLoaded;

void LoadEventMap()
{
    // Game events do not change while the server runs: read the file once.
    if (g_EventMapLoaded)
        return;

    g_EventMapLoaded    = true;
    g_EventMappings     = new ArrayList(sizeof(EventMapping));
    g_EventMappingIndex = new StringMap();

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/lancommander_events.cfg");

    if (!FileExists(path))
        return;

    KeyValues kv = new KeyValues("LANCommanderEvents");

    if (!kv.ImportFromFile(path))
    {
        LogError("Could not read %s", path);
        delete kv;
        return;
    }

    char game[64];
    GetGameFolderName(game, sizeof(game));

    // "*" applies to every game; the game's own section comes after it, so a
    // game event it maps again replaces the generic one.
    LoadEventMapSection(kv, "*");
    LoadEventMapSection(kv, game);

    delete kv;

    if (g_EventMappings.Length)
        LogMessage("Recording %d game events from configs/lancommander_events.cfg", g_EventMappings.Length);
}

void LoadEventMapSection(KeyValues kv, const char[] section)
{
    kv.Rewind();

    if (!kv.JumpToKey(section) || !kv.GotoFirstSubKey())
        return;

    char eventName[64], kind[16];

    do
    {
        kv.GetSectionName(eventName, sizeof(eventName));

        EventMapping mapping;
        kv.GetString("type", mapping.type, sizeof(mapping.type), eventName);
        kv.GetString("actor", mapping.actorField, sizeof(mapping.actorField));
        kv.GetString("subject", mapping.subjectField, sizeof(mapping.subjectField));
        kv.GetString("actor_stat", mapping.actorStat, sizeof(mapping.actorStat));
        kv.GetString("subject_stat", mapping.subjectStat, sizeof(mapping.subjectStat));

        kv.GetString("actor_kind", kind, sizeof(kind), "userid");
        mapping.actorIsClient = StrEqual(kind, "client", false);

        kv.GetString("subject_kind", kind, sizeof(kind), "userid");
        mapping.subjectIsClient = StrEqual(kind, "client", false);

        mapping.fieldNames = new ArrayList(ByteCountToCells(64));
        mapping.fieldKinds = new ArrayList(ByteCountToCells(16));

        if (kv.JumpToKey("fields"))
        {
            if (kv.GotoFirstSubKey(false))
            {
                char field[64];

                do
                {
                    kv.GetSectionName(field, sizeof(field));
                    kv.GetString(NULL_STRING, kind, sizeof(kind), "string");

                    mapping.fieldNames.PushString(field);
                    mapping.fieldKinds.PushString(kind);
                }
                while (kv.GotoNextKey(false));

                kv.GoBack();   // from the first field up to "fields"
            }

            kv.GoBack();       // from "fields" up to the event
        }

        int index;

        if (g_EventMappingIndex.GetValue(eventName, index))
        {
            EventMapping old;
            g_EventMappings.GetArray(index, old);
            delete old.fieldNames;
            delete old.fieldKinds;
            g_EventMappings.SetArray(index, mapping);
        }
        else if (HookEventEx(eventName, Event_Mapped))
        {
            index = g_EventMappings.PushArray(mapping);
            g_EventMappingIndex.SetValue(eventName, index);
        }
        else
        {
            LogMessage("configs/lancommander_events.cfg: this game has no \"%s\" event; skipped", eventName);
            delete mapping.fieldNames;
            delete mapping.fieldKinds;
        }
    }
    while (kv.GotoNextKey());
}

int MappedClient(Event event, const char[] field, bool isClient)
{
    if (!field[0])
        return 0;

    int value = event.GetInt(field);
    int client = isClient ? value : GetClientOfUserId(value);

    return client >= 1 && client <= MaxClients && IsClientInGame(client) ? client : 0;
}

public void Event_Mapped(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsRecording())
        return;

    int index;

    if (!g_EventMappingIndex.GetValue(name, index))
        return;

    EventMapping mapping;
    g_EventMappings.GetArray(index, mapping);

    int actor   = MappedClient(event, mapping.actorField, mapping.actorIsClient);
    int subject = MappedClient(event, mapping.subjectField, mapping.subjectIsClient);

    LCPayload payload = new LCPayload();
    char field[64], kind[16], text[256];

    for (int i = 0; i < mapping.fieldNames.Length; i++)
    {
        mapping.fieldNames.GetString(i, field, sizeof(field));
        mapping.fieldKinds.GetString(i, kind, sizeof(kind));

        if (StrEqual(kind, "int", false))
            payload.SetInt(field, event.GetInt(field));
        else if (StrEqual(kind, "float", false))
            payload.SetFloat(field, event.GetFloat(field));
        else if (StrEqual(kind, "bool", false))
            payload.SetBool(field, event.GetBool(field));
        else if (StrEqual(kind, "userid", false) || StrEqual(kind, "client", false))
        {
            int client = MappedClient(event, field, StrEqual(kind, "client", false));
            char key[LC_MAX_KEY];

            if (client > 0 && GetKey(client, key, sizeof(key)))
                payload.SetString(field, key);
        }
        else
        {
            event.GetString(field, text, sizeof(text));
            payload.SetString(field, text);
        }
    }

    AddPosition(payload, "actor", actor);

    SendEvent(mapping.type, actor, subject, "", "", payload);
    delete payload;

    if (actor > 0 && mapping.actorStat[0])
        AddPlayerStat(actor, mapping.actorStat, 1.0);

    if (subject > 0 && mapping.subjectStat[0])
        AddPlayerStat(subject, mapping.subjectStat, 1.0);
}
