/**
 * LANCommander Match Statistics: Counter-Strike: Source and CS:GO.
 *
 * Bomb plants, defusals and explosions, hostage rescues, the VIP, purchases,
 * flashes and grenades, MVPs, the reason each round ended, warmup (CS:GO), and
 * the match's end at the final scoreboard. Loads only on Counter-Strike.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <lancommander_stats>

public Plugin myinfo =
{
    name        = "LANCommander Match Statistics: Counter-Strike",
    author      = "LANCommander",
    description = "Counter-Strike objectives, economy and round results for LANCommander",
    version     = "1.0.0",
    url         = "https://github.com/LANCommander"
};

bool g_IsCSGO;

// round_end's reason, as CS_OnTerminateRound named it.
CSRoundEndReason g_RoundEndReason;
bool             g_HaveRoundEndReason;

// player_death fields the core does not know, for the "kill" event that follows.
// dominated/revenge are CS:S and CS:GO; the rest CS:GO only (read as 0 on CS:S).
bool g_KillPenetrated, g_KillNoScope, g_KillThroughSmoke, g_KillAttackerBlind;
bool g_KillDominated, g_KillRevenge;

// CS:S's player_blind names only the victim. The flash is put down to whoever's
// flashbang detonated in the same tick; which event comes first in that tick is
// not certain, so blinds wait a frame for it.
int       g_FlashThrower;
int       g_FlashTick = -1;
ArrayList g_PendingBlinds;   // [victim userid, duration (float), tick]

// Money before a buy command, to see what it cost.
int g_MoneyBefore[MAXPLAYERS + 1];

static const char g_ReasonNames[][] =
{
    "target_bombed", "vip_escaped", "vip_killed", "terrorists_escaped", "ct_stopped_escape",
    "terrorists_stopped", "bomb_defused", "ct_win", "terrorist_win", "draw", "hostages_rescued",
    "target_saved", "hostages_not_rescued", "terrorists_not_escaped", "vip_not_escaped", "game_start",
    "terrorists_surrender", "ct_surrender", "terrorists_planted", "cts_reached_hostage"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    EngineVersion engine = GetEngineVersion();

    if (engine != Engine_CSS && engine != Engine_CSGO)
        return APLRes_SilentFailure;

    g_IsCSGO = engine == Engine_CSGO;
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_PendingBlinds = new ArrayList(3);

    LCStats_HookEvent("bomb_beginplant", Event_Bomb);
    LCStats_HookEvent("bomb_abortplant", Event_Bomb);
    LCStats_HookEvent("player_falldamage", Event_FallDamage);
    LCStats_HookEvent("bomb_planted", Event_Bomb);
    LCStats_HookEvent("bomb_defused", Event_Bomb);
    LCStats_HookEvent("bomb_exploded", Event_Bomb);
    LCStats_HookEvent("bomb_begindefuse", Event_Bomb);
    LCStats_HookEvent("bomb_abortdefuse", Event_Bomb);
    LCStats_HookEvent("bomb_dropped", Event_Bomb);
    LCStats_HookEvent("bomb_pickup", Event_Bomb);

    LCStats_HookEvent("hostage_follows", Event_Hostage);
    LCStats_HookEvent("hostage_killed", Event_Hostage);
    LCStats_HookEvent("hostage_rescued", Event_Hostage);
    LCStats_HookEvent("hostage_rescued_all", Event_HostagesRescuedAll, EventHookMode_PostNoCopy);

    HookEventEx("vip_escaped", Event_VipEscaped);
    HookEventEx("vip_killed", Event_VipKilled);

    LCStats_HookEvent("player_blind", Event_PlayerBlind);
    LCStats_HookEvent("hegrenade_detonate", Event_Grenade);
    LCStats_HookEvent("flashbang_detonate", Event_Grenade);
    LCStats_HookEvent("smokegrenade_detonate", Event_Grenade);
    HookEventEx("molotov_detonate", Event_Grenade);
    HookEventEx("decoy_detonate", Event_Grenade);

    LCStats_HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
    HookEventEx("round_mvp", Event_RoundMvp);

    LCStats_HookEvent("cs_win_panel_match", Event_GameOver, EventHookMode_PostNoCopy);

    // CS:GO's team names (mp_teamname_1 is the CTs', _2 the Terrorists'), set
    // by Get5, PUG plugins and admins and swapped with the sides at halftime.
    ConVar ctName = FindConVar("mp_teamname_1");
    ConVar tName  = FindConVar("mp_teamname_2");

    if (ctName != null && tName != null)
    {
        ctName.AddChangeHook(OnTeamNameChanged);
        tName.AddChangeHook(OnTeamNameChanged);
    }
}

public void OnTeamNameChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    UpdateTeamNames();
}

// Reports the teams under their mp_teamname names, or the game's own when unset.
void UpdateTeamNames()
{
    ConVar ctName = FindConVar("mp_teamname_1");
    ConVar tName  = FindConVar("mp_teamname_2");

    if (ctName == null || tName == null)
        return;

    char name[64];

    ctName.GetString(name, sizeof(name));
    LCStats_SetTeamName(CS_TEAM_CT, name);

    tName.GetString(name, sizeof(name));
    LCStats_SetTeamName(CS_TEAM_T, name);
}

public void OnMapStart()
{
    g_HaveRoundEndReason = false;
}

// The core forgets team names at every map start; this runs after that.
public void OnConfigsExecuted()
{
    UpdateTeamNames();
}

// ── The match ────────────────────────────────────────────────────────────────

public Action LCStats_OnMatchStarting(char[] externalId, int externalIdLength, char[] mode, int modeLength, LCPayload metadata)
{
    // Before the match registers its players, so they join under these names.
    UpdateTeamNames();

    if (mode[0])
        return Plugin_Continue;

    GetMode(mode, modeLength);
    return Plugin_Changed;
}

public void LCStats_OnMatchStarted(int match, const char[] externalId)
{
    if (g_IsCSGO)
        LCStats_SetWarmup(InWarmup());
}

// The mode: CS:GO's game_type/game_mode, or what the map is played for.
void GetMode(char[] mode, int maxlength)
{
    if (g_IsCSGO)
    {
        ConVar type = FindConVar("game_type");
        ConVar gameMode = FindConVar("game_mode");

        if (type != null && gameMode != null)
        {
            int t = type.IntValue, m = gameMode.IntValue;

            if (t == 0 && m == 0)      strcopy(mode, maxlength, "casual");
            else if (t == 0 && m == 1) strcopy(mode, maxlength, "competitive");
            else if (t == 0 && m == 2) strcopy(mode, maxlength, "wingman");
            else if (t == 1 && m == 0) strcopy(mode, maxlength, "arms_race");
            else if (t == 1 && m == 1) strcopy(mode, maxlength, "demolition");
            else if (t == 1 && m == 2) strcopy(mode, maxlength, "deathmatch");
            else if (t == 6)           strcopy(mode, maxlength, "danger_zone");
            else                       FormatEx(mode, maxlength, "game_type_%d_mode_%d", t, m);
            return;
        }
    }

    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));

    // Workshop paths: the file name decides.
    int slash = FindCharInString(map, '/', true);
    int start = slash >= 0 ? slash + 1 : 0;

    if (StrContains(map[start], "de_", false) == 0)      strcopy(mode, maxlength, "defusal");
    else if (StrContains(map[start], "cs_", false) == 0) strcopy(mode, maxlength, "hostage");
    else if (StrContains(map[start], "as_", false) == 0) strcopy(mode, maxlength, "assassination");
    else if (StrContains(map[start], "es_", false) == 0) strcopy(mode, maxlength, "escape");
    else if (StrContains(map[start], "ar_", false) == 0) strcopy(mode, maxlength, "arms_race");
    else if (StrContains(map[start], "dm_", false) == 0) strcopy(mode, maxlength, "deathmatch");
    else                                                 strcopy(mode, maxlength, "classic");
}

bool InWarmup()
{
    return g_IsCSGO && GameRules_GetProp("m_bWarmupPeriod") != 0;
}

// The final scoreboard: the match is over, though the map runs on until the
// next one loads.
public void Event_GameOver(Event event, const char[] name, bool dontBroadcast)
{
    LCStats_EndMatch("game_over");
}

public void LCStats_OnMatchEnding(int match, const char[] reason, bool abandoned)
{
    if (abandoned)
        return;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || GetClientTeam(client) < CS_TEAM_T)
            continue;

        if (g_IsCSGO)
            LCStats_SetStat(client, "contribution_score", float(CS_GetClientContributionScore(client)));

        LCStats_SetStat(client, "mvps", float(CS_GetMVPCount(client)));
    }
}

// ── Rounds ───────────────────────────────────────────────────────────────────

public Action CS_OnTerminateRound(float &delay, CSRoundEndReason &reason)
{
    g_RoundEndReason     = reason;
    g_HaveRoundEndReason = true;
    return Plugin_Continue;
}

public void OnGameFrame()
{
    // CS:GO's warmup ends without an event of its own; it is checked every
    // frame rather than on a timer so the first live round is never recorded
    // as warmup.
    if (!g_IsCSGO || LCStats_GetMatch() == 0)
        return;

    bool warmup = InWarmup();

    if (warmup != LCStats_IsWarmup())
        LCStats_SetWarmup(warmup);
}

public Action LCStats_OnEvent(const char[] type, int actor, int subject, LCPayload payload)
{
    if (StrEqual(type, "round_end"))
    {
        // "Game Commencing": the game restarts once both teams have players.
        // What came before was not a round; the next one is round 1.
        if (g_HaveRoundEndReason && g_RoundEndReason == CSRoundEnd_GameStart)
        {
            g_HaveRoundEndReason = false;
            LCStats_SetRound(0);
            return Plugin_Handled;
        }

        if (g_HaveRoundEndReason)
        {
            int reason = view_as<int>(g_RoundEndReason);

            if (reason >= 0 && reason < sizeof(g_ReasonNames))
                payload.SetString("reason_name", g_ReasonNames[reason]);

            g_HaveRoundEndReason = false;
        }

        payload.SetInt("score_t", CS_GetTeamScore(CS_TEAM_T));
        payload.SetInt("score_ct", CS_GetTeamScore(CS_TEAM_CT));
        return Plugin_Changed;
    }

    if (StrEqual(type, "kill"))
    {
        if (g_KillPenetrated)    payload.SetBool("penetrated", true);
        if (g_KillNoScope)       payload.SetBool("noscope", true);
        if (g_KillThroughSmoke)  payload.SetBool("through_smoke", true);
        if (g_KillAttackerBlind) payload.SetBool("attacker_blind", true);
        if (g_KillDominated)     payload.SetBool("domination", true);
        if (g_KillRevenge)       payload.SetBool("revenge", true);

        if (actor > 0)
        {
            if (g_KillDominated) LCStats_AddStat(actor, "dominations");
            if (g_KillRevenge)   LCStats_AddStat(actor, "revenges");
        }

        g_KillPenetrated = g_KillNoScope = g_KillThroughSmoke = g_KillAttackerBlind = false;
        g_KillDominated = g_KillRevenge = false;
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

// Before the core's own player_death hook: what CS:GO adds to a kill.
public Action Event_PlayerDeathPre(Event event, const char[] name, bool dontBroadcast)
{
    g_KillPenetrated    = event.GetInt("penetrated") > 0;
    g_KillNoScope       = event.GetBool("noscope");
    g_KillThroughSmoke  = event.GetBool("thrusmoke");
    g_KillAttackerBlind = event.GetBool("attackerblind");
    g_KillDominated     = event.GetInt("dominated") != 0;
    g_KillRevenge       = event.GetInt("revenge") != 0;
    return Plugin_Continue;
}

// player_falldamage: userid, damage (float).
public void Event_FallDamage(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    float damage = event.GetFloat("damage");

    if (client > 0 && damage > 0.0)
        LCStats_AddStat(client, "fall_damage", damage);
}

public void Event_RoundMvp(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client < 1)
        return;

    LCPayload payload = new LCPayload();
    payload.SetInt("reason", event.GetInt("reason"));
    LCStats_Event("round_mvp", client, 0, payload);
    delete payload;
}

// ── The bomb ─────────────────────────────────────────────────────────────────

public void Event_Bomb(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();

    if (StrEqual(name, "bomb_beginplant") || StrEqual(name, "bomb_planted") ||
        StrEqual(name, "bomb_defused") || StrEqual(name, "bomb_exploded"))
    {
        char site[8];
        GetBombsiteName(event.GetInt("site"), site, sizeof(site));

        if (site[0])
            payload.SetString("site", site);
    }

    if (StrEqual(name, "bomb_begindefuse"))
        payload.SetBool("has_kit", event.GetBool("haskit"));

    LCStats_AddPosition(payload, "player", client);

    // bomb_exploded names the planter; the explosion is the actor-less event.
    LCStats_Event(name, StrEqual(name, "bomb_exploded") ? 0 : client, 0, payload);
    delete payload;

    if (client < 1)
        return;

    if (StrEqual(name, "bomb_planted"))
    {
        LCStats_AddStat(client, "bomb_plants");
        LCStats_AddTeamStat(CS_TEAM_T, "bomb_plants");
    }
    else if (StrEqual(name, "bomb_defused"))
    {
        LCStats_AddStat(client, "bomb_defuses");
        LCStats_AddTeamStat(CS_TEAM_CT, "bomb_defuses");
    }
    else if (StrEqual(name, "bomb_exploded"))
    {
        LCStats_AddStat(client, "bomb_explosions");
        LCStats_AddTeamStat(CS_TEAM_T, "bomb_explosions");
    }
}

// "A" or "B", from the bombsite's position relative to the map's two
// bomb target areas; the site index in the event is an entity, not a letter.
void GetBombsiteName(int site, char[] name, int maxlength)
{
    name[0] = '\0';

    if (site <= 0 || !IsValidEntity(site))
        return;

    // CS:GO's player resource knows the sites' centres.
    int resource = g_IsCSGO ? FindEntityByClassname(-1, "cs_player_manager") : -1;

    if (resource != -1 && HasEntProp(resource, Prop_Send, "m_bombsiteCenterA") &&
        HasEntProp(site, Prop_Send, "m_vecMins") && HasEntProp(site, Prop_Send, "m_vecOrigin"))
    {
        float a[3], b[3], origin[3], mins[3], maxs[3], center[3];
        GetEntPropVector(resource, Prop_Send, "m_bombsiteCenterA", a);
        GetEntPropVector(resource, Prop_Send, "m_bombsiteCenterB", b);
        GetEntPropVector(site, Prop_Send, "m_vecOrigin", origin);
        GetEntPropVector(site, Prop_Send, "m_vecMins", mins);
        GetEntPropVector(site, Prop_Send, "m_vecMaxs", maxs);

        for (int i = 0; i < 3; i++)
            center[i] = origin[i] + (mins[i] + maxs[i]) / 2.0;

        strcopy(name, maxlength, GetVectorDistance(center, a) <= GetVectorDistance(center, b) ? "A" : "B");
        return;
    }

    // CS:S: the order the map declares its func_bomb_target entities in.
    int first = FindEntityByClassname(-1, "func_bomb_target");

    if (first == -1)
        return;

    strcopy(name, maxlength, site == first ? "A" : "B");
}

// ── Hostages and the VIP ─────────────────────────────────────────────────────

public void Event_Hostage(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    LCPayload payload = new LCPayload();
    payload.SetInt("hostage", event.GetInt("hostage"));
    LCStats_AddPosition(payload, "player", client);

    LCStats_Event(name, client, 0, payload);
    delete payload;

    if (client < 1)
        return;

    if (StrEqual(name, "hostage_rescued"))
    {
        LCStats_AddStat(client, "hostages_rescued");
        LCStats_AddTeamStat(CS_TEAM_CT, "hostages_rescued");
    }
    else if (StrEqual(name, "hostage_killed"))
        LCStats_AddStat(client, "hostages_killed");
}

public void Event_HostagesRescuedAll(Event event, const char[] name, bool dontBroadcast)
{
    LCStats_Event("hostages_rescued_all");
}

public void Event_VipEscaped(Event event, const char[] name, bool dontBroadcast)
{
    int vip = GetClientOfUserId(event.GetInt("userid"));
    LCStats_Event("vip_escaped", vip);

    if (vip > 0)
        LCStats_AddStat(vip, "vip_escapes");
}

public void Event_VipKilled(Event event, const char[] name, bool dontBroadcast)
{
    int vip      = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    LCStats_Event("vip_killed", attacker, vip);

    if (attacker > 0)
        LCStats_AddStat(attacker, "vip_kills");
}

// ── Equipment ────────────────────────────────────────────────────────────────

public Action CS_OnBuyCommand(int client, const char[] weapon)
{
    if (!LCStats_IsRecording())
        return Plugin_Continue;

    g_MoneyBefore[client] = GetEntProp(client, Prop_Send, "m_iAccount");

    // The purchase happens after this; what it cost shows a frame later.
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(weapon);
    RequestFrame(Frame_CheckPurchase, pack);

    return Plugin_Continue;
}

public void Frame_CheckPurchase(DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());

    char weapon[64];
    pack.ReadString(weapon, sizeof(weapon));
    delete pack;

    if (client < 1 || !IsClientInGame(client))
        return;

    int spent = g_MoneyBefore[client] - GetEntProp(client, Prop_Send, "m_iAccount");

    // Refused (not enough money, out of the buy zone): nothing was bought.
    if (spent <= 0)
        return;

    LCPayload payload = new LCPayload();
    payload.SetString("item", weapon);
    payload.SetInt("cost", spent);
    LCStats_Event("purchase", client, 0, payload);
    delete payload;

    LCStats_AddStat(client, "money_spent", float(spent));
}

// player_blind: userid; CS:GO adds attacker. CS:S's flashes are attributed a
// frame later, to the flashbang that detonated in the same tick.
public void Event_PlayerBlind(Event event, const char[] name, bool dontBroadcast)
{
    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (victim < 1 || !IsClientInGame(victim))
        return;

    float duration = GetEntPropFloat(victim, Prop_Send, "m_flFlashDuration");

    // A flash that barely touched the player is not worth an event.
    if (duration < 0.5)
        return;

    if (attacker > 0 || g_IsCSGO)
    {
        RecordFlash(attacker, victim, duration);
        return;
    }

    any blind[3];
    blind[0] = event.GetInt("userid");
    blind[1] = duration;
    blind[2] = GetGameTickCount();
    g_PendingBlinds.PushArray(blind);

    if (g_PendingBlinds.Length == 1)
        RequestFrame(Frame_ResolveBlinds);
}

public void Frame_ResolveBlinds(any unused)
{
    for (int i = 0; i < g_PendingBlinds.Length; i++)
    {
        any blind[3];
        g_PendingBlinds.GetArray(i, blind);

        int victim = GetClientOfUserId(blind[0]);
        int thrower = blind[2] == g_FlashTick ? GetClientOfUserId(g_FlashThrower) : 0;

        if (victim > 0 && IsClientInGame(victim))
            RecordFlash(thrower, victim, blind[1]);
    }

    g_PendingBlinds.Clear();
}

void RecordFlash(int attacker, int victim, float duration)
{
    LCPayload payload = new LCPayload();
    payload.SetFloat("duration", duration);

    if (attacker > 0 && attacker != victim && GetClientTeam(attacker) == GetClientTeam(victim))
        payload.SetBool("teammate", true);

    LCStats_Event("flashed", attacker, victim, payload);
    delete payload;

    if (attacker > 0 && attacker != victim && GetClientTeam(attacker) != GetClientTeam(victim))
        LCStats_AddStat(attacker, "enemies_flashed");
}

public void Event_Grenade(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (StrEqual(name, "flashbang_detonate"))
    {
        g_FlashThrower = event.GetInt("userid");
        g_FlashTick    = GetGameTickCount();
    }

    char grenade[32];
    strcopy(grenade, sizeof(grenade), name);
    ReplaceString(grenade, sizeof(grenade), "_detonate", "");

    LCPayload payload = new LCPayload();
    payload.SetString("grenade", grenade);

    float position[3];
    position[0] = event.GetFloat("x");
    position[1] = event.GetFloat("y");
    position[2] = event.GetFloat("z");
    payload.SetVector("position", position);

    LCStats_Event("grenade_detonate", client, 0, payload);
    delete payload;

    if (client > 0)
        LCStats_AddStat(client, "grenades_thrown");
}
