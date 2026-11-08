// Recording events, and the game events every Source game (or most) has.
// HookEventEx skips any a game does not define.

// Every event goes through here, the core's own and other plugins' alike.
// actor/subject are clients (0 = none); when 0, the given keys are used.
bool SendEvent(const char[] type, int actor, int subject, const char[] actorKeyIn, const char[] subjectKeyIn,
               LCPayload payload)
{
    if (!IsRecording())
        return false;

    char actorKey[LC_MAX_KEY], subjectKey[LC_MAX_KEY];

    if (actor > 0)
        GetKey(actor, actorKey, sizeof(actorKey));
    else
        strcopy(actorKey, sizeof(actorKey), actorKeyIn);

    if (subject > 0)
        GetKey(subject, subjectKey, sizeof(subjectKey));
    else
        strcopy(subjectKey, sizeof(subjectKey), subjectKeyIn);

    // Only bots involved, and bots are not recorded.
    if ((actor > 0 || subject > 0) && !actorKey[0] && !subjectKey[0])
        return false;

    // One round start per tick: games that fire their own (dod_round_start,
    // teamplay_round_start) may fire the shared round_start with it, and a
    // module and the core would each report one.
    if (StrEqual(type, "round_start"))
    {
        static int lastRoundStartTick = -1;
        int tick = GetGameTickCount();

        if (tick == lastRoundStartTick)
            return false;

        lastRoundStartTick = tick;
        g_Round++;
    }

    bool owned = payload == null;

    if (owned)
        payload = new LCPayload();

    if (g_Round > 0 && !payload.HasKey("round"))
        payload.SetInt("round", g_Round);

    if (g_Warmup)
        payload.SetBool("warmup", true);

    Action result = Plugin_Continue;

    Call_StartForward(g_fwdEvent);
    Call_PushString(type);
    Call_PushCell(actor);
    Call_PushCell(subject);
    Call_PushCell(payload);
    Call_Finish(result);

    // A plugin dropping the event (Plugin_Handled) means it did not happen
    // (TF2's Dead Ringer): false, and nothing counts for it. The server's filter
    // (lc_events_include / _exclude) only leaves it out of the record: true,
    // and its statistics still count -- which is also why the filter is
    // applied after LCStats_OnEvent, where modules add some of them.
    bool sent = false;

    if (result < Plugin_Handled)
    {
        if (IsEventFiltered(type))
            sent = true;
        else
            sent = LC_MatchEvent(g_Match, type, GameTimeMs(), GetGameTickCount(), actorKey, subjectKey,
                payload.Size > 0 ? payload : null);
    }

    if (owned)
        delete payload;

    return sent;
}

bool AddPlayerStat(int client, const char[] key, float delta)
{
    char playerKey[LC_MAX_KEY];

    if (!IsRecording() || !GetKey(client, playerKey, sizeof(playerKey)))
        return false;

    return LC_MatchAddStatistic(g_Match, playerKey, "", key, delta);
}

void AddPosition(LCPayload payload, const char[] prefix, int client)
{
    if (!g_cvRecordPositions.BoolValue || client < 1 || !IsClientInGame(client))
        return;

    float origin[3];
    GetClientAbsOrigin(client, origin);

    char key[64];
    FormatEx(key, sizeof(key), "%s_position", prefix);
    payload.SetVector(key, origin);
}

void AddTeam(LCPayload payload, const char[] key, int team)
{
    char name[64];
    GetReportedTeamName(team, name, sizeof(name));

    if (name[0])
        payload.SetString(key, name);
}

// The first of several fields with a value. Games name the same field
// differently (an assist: TF2 assister, PVKII assistid, FoF assist), and an
// absent field reads as 0.
int ReadFirstInt(Event event, const char[] a, const char[] b, const char[] c = "")
{
    int value = event.GetInt(a);

    if (!value)
        value = event.GetInt(b);

    if (!value && c[0])
        value = event.GetInt(c);

    return value;
}

// Damage totals, from player_hurt or a module's better source (LCStats_AddDamage).
void RecordDamage(int attacker, int victim, int damage)
{
    if (damage <= 0 || victim < 1)
        return;

    AddPlayerStat(victim, "damage_taken", float(damage));

    if (attacker > 0 && attacker != victim)
        AddPlayerStat(attacker, SameTeam(attacker, victim) ? "team_damage" : "damage_dealt", float(damage));
}

// ── The hooks ────────────────────────────────────────────────────────────────

void HookGenericEvents()
{
    HookEventEx("player_death",      Event_PlayerDeath);
    HookEventEx("player_hurt",       Event_PlayerHurt);
    HookEventEx("player_spawn",      Event_PlayerSpawn);
    HookEventEx("player_team",       Event_PlayerTeam);
    HookEventEx("player_changename", Event_PlayerChangeName);
    HookEventEx("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
    HookEventEx("weapon_fire",       Event_WeaponFire);
    HookEventEx("round_start",       Event_RoundStart);
    HookEventEx("round_end",         Event_RoundEnd);
    HookEventEx("game_end",          Event_GameEnd);
}

// The shared game_end (winner in HL2:DM; none in FoF, PVKII and DAB; Empires
// has team and entity instead): the match is over, though the map runs on
// through the intermission. A module that already ended it makes this a no-op.
public void Event_GameEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_Match)
        return;

    LCPayload payload = new LCPayload();
    int winner = event.GetInt("winner");

    if (winner >= 2)
        AddTeam(payload, "winner", winner);

    SendEvent("game_end", 0, 0, "", "", payload);
    delete payload;

    if (EndMatch("game_over", false))
        g_MatchDoneThisMap = true;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsRecording())
        return;

    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int assister = GetClientOfUserId(ReadFirstInt(event, "assister", "assistid", "assist"));

    // An NPC's death, in games that report those as player_death.
    if (victim < 1)
        return;

    bool suicide  = attacker == victim || attacker < 1;
    bool teamkill = !suicide && SameTeam(attacker, victim);
    bool headshot = event.GetBool("headshot");

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    LCPayload payload = new LCPayload();

    if (weapon[0])
        payload.SetString("weapon", weapon);

    if (headshot)
        payload.SetBool("headshot", true);

    if (suicide)
        payload.SetBool("suicide", true);

    if (teamkill)
        payload.SetBool("teamkill", true);

    if (assister > 0)
    {
        char assisterKey[LC_MAX_KEY];

        if (GetKey(assister, assisterKey, sizeof(assisterKey)))
            payload.SetString("assister", assisterKey);
    }

    AddPosition(payload, "victim", victim);

    if (!suicide)
    {
        AddPosition(payload, "attacker", attacker);

        float from[3], to[3];
        GetClientAbsOrigin(attacker, from);
        GetClientAbsOrigin(victim, to);
        payload.SetFloat("distance", GetVectorDistance(from, to));
    }

    bool sent = SendEvent("kill", attacker > 0 ? attacker : 0, victim, "", "", payload);
    delete payload;

    // A kill a module dropped (TF2's Dead Ringer feigns death) counts for
    // nothing either.
    if (!sent)
        return;

    AddPlayerStat(victim, "deaths", 1.0);

    if (suicide)
        AddPlayerStat(victim, "suicides", 1.0);
    else if (teamkill)
        AddPlayerStat(attacker, "teamkills", 1.0);
    else
    {
        AddPlayerStat(attacker, "kills", 1.0);

        if (headshot)
            AddPlayerStat(attacker, "headshots", 1.0);
    }

    if (assister > 0)
        AddPlayerStat(assister, "assists", 1.0);
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsRecording())
        return;

    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (victim < 1)
        return;

    // CS:S dmg_health, TF2 damageamount, DoD:S and FoF damage. HL2:DM, PVKII,
    // DAB and Empires give no amount: a hit is still a hit, and their modules
    // report amounts from elsewhere with LCStats_AddDamage.
    int damage = ReadFirstInt(event, "dmg_health", "damageamount", "damage");

    RecordDamage(attacker, victim, damage);

    if (attacker > 0 && attacker != victim)
        AddPlayerStat(attacker, "hits", 1.0);

    if (!g_cvRecordDamage.BoolValue)
        return;

    LCPayload payload = new LCPayload();

    if (damage > 0)
        payload.SetInt("damage", damage);

    int health = event.GetInt("health");

    if (health > 0)
        payload.SetInt("health", health);

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    if (weapon[0])
        payload.SetString("weapon", weapon);

    int hitgroup = event.GetInt("hitgroup");

    if (hitgroup > 0)
        payload.SetInt("hitgroup", hitgroup);

    SendEvent("damage", attacker != victim ? attacker : 0, victim, "", "", payload);
    delete payload;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsRecording() || !g_cvRecordSpawns.BoolValue)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client < 1 || !IsClientInGame(client) || GetClientTeam(client) < 2)
        return;

    LCPayload payload = new LCPayload();
    AddTeam(payload, "team", GetClientTeam(client));
    AddPosition(payload, "spawn", client);

    SendEvent("spawn", client, 0, "", "", payload);
    delete payload;
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_Match || event.GetBool("disconnect"))
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client < 1 || !g_PlayerKey[client][0])
        return;

    int team    = event.GetInt("team");
    int oldTeam = event.GetInt("oldteam");

    // The participant's team, so LANCommander knows who played for whom.
    JoinMatch(client, team);

    LCPayload payload = new LCPayload();
    AddTeam(payload, "from", oldTeam);
    AddTeam(payload, "to", team);

    SendEvent("team_change", client, 0, "", "", payload);
    delete payload;
}

public void Event_PlayerChangeName(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_Match)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client < 1 || !g_PlayerKey[client][0])
        return;

    char oldName[MAX_NAME_LENGTH], newName[MAX_NAME_LENGTH];
    event.GetString("oldname", oldName, sizeof(oldName));
    event.GetString("newname", newName, sizeof(newName));

    LCPayload payload = new LCPayload();
    payload.SetString("from", oldName);
    payload.SetString("to", newName);

    SendEvent("name_change", client, 0, "", "", payload);
    delete payload;

    // The participant's display name. The game applies the new name after
    // this event, so it is passed on a frame later.
    RequestFrame(Frame_RefreshParticipant, GetClientUserId(client));
}

public void Frame_RefreshParticipant(int userid)
{
    int client = GetClientOfUserId(userid);

    if (client > 0 && g_PlayerInMatch[client])
        JoinMatch(client);
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client < 1 || !g_PlayerKey[client][0] || !IsRecording())
        return Plugin_Continue;

    char reason[128];
    event.GetString("reason", reason, sizeof(reason));

    LCPayload payload = new LCPayload();
    payload.SetString("reason", reason);

    SendEvent("disconnect", client, 0, "", "", payload);
    delete payload;

    return Plugin_Continue;
}

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsRecording())
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client < 1)
        return;

    AddPlayerStat(client, "shots", 1.0);

    if (!g_cvRecordWeaponFire.BoolValue)
        return;

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    LCPayload payload = new LCPayload();

    if (weapon[0])
        payload.SetString("weapon", weapon);

    SendEvent("weapon_fire", client, 0, "", "", payload);
    delete payload;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_ModuleOwnsRounds)
        SendEvent("round_start", 0, 0, "", "", null);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsRecording() || g_ModuleOwnsRounds)
        return;

    LCPayload payload = new LCPayload();

    int winner = event.GetInt("winner");

    if (winner >= 2)
        AddTeam(payload, "winner", winner);

    payload.SetInt("reason", event.GetInt("reason"));

    char message[128];
    event.GetString("message", message, sizeof(message));

    if (message[0])
        payload.SetString("message", message);

    SendEvent("round_end", 0, 0, "", "", payload);
    delete payload;
}

// ── Chat and admin actions ───────────────────────────────────────────────────

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
    if (!g_cvRecordChat.BoolValue || client < 1 || !IsRecording())
        return;

    LCPayload payload = new LCPayload();
    payload.SetString("message", sArgs);

    if (StrEqual(command, "say_team"))
        payload.SetBool("team_only", true);

    SendEvent("chat", client, 0, "", "", payload);
    delete payload;
}

public Action OnBanClient(int client, int time, int flags, const char[] reason, const char[] kick_message,
                          const char[] command, any source)
{
    if (!IsRecording())
        return Plugin_Continue;

    int admin = source;

    LCPayload payload = new LCPayload();
    payload.SetInt("duration_minutes", time);

    if (reason[0])
        payload.SetString("reason", reason);

    SendEvent("admin_ban", admin > 0 && admin <= MaxClients ? admin : 0, client, "", "", payload);
    delete payload;

    return Plugin_Continue;
}
