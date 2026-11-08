// The natives: InterposerMatch* one to one, plus LCPayload, the JSON builder
// their payloads are written with. Declared for plugins in
// scripting/include/lancommander.inc, which documents each of them.

#include "extension.h"
#include "payload.h"

#include <LANCommander.Interposer.h>

#include <string>

namespace
{

// ── Arguments ─────────────────────────────────────────────────────────────────

const char* Str(IPluginContext* ctx, cell_t param)
{
    char* text = nullptr;
    ctx->LocalToString(param, &text);
    return text ? text : "";
}

// An optional string: empty is "not given", which the Interposer takes as NULL.
const char* OptStr(IPluginContext* ctx, cell_t param)
{
    const char* text = Str(ctx, param);
    return *text ? text : nullptr;
}

// The payload behind a handle. A null handle is "no payload" (*out = nullptr)
// and fine; an invalid one is an error in the plugin, reported to it.
bool ReadPayload(IPluginContext* ctx, cell_t param, lc::Payload** out)
{
    *out = nullptr;

    const Handle_t handle = static_cast<Handle_t>(param);

    if (handle == BAD_HANDLE)
        return true;

    HandleSecurity security(ctx->GetIdentity(), myself->GetIdentity());
    const HandleError error = handlesys->ReadHandle(handle, g_PayloadType, &security, reinterpret_cast<void**>(out));

    if (error != HandleError_None)
    {
        ctx->ReportError("Invalid LCPayload handle %x (error %d)", handle, error);
        return false;
    }

    return true;
}

// The JSON of an optional payload argument that must be an object (events,
// results, settings): "" for none, false (with the error reported) when the
// handle is invalid, an array, or larger than LANCommander takes.
bool PayloadObjectJson(IPluginContext* ctx, cell_t param, std::string& json, const char* what)
{
    json.clear();

    lc::Payload* payload;

    if (!ReadPayload(ctx, param, &payload))
        return false;

    if (!payload)
        return true;

    if (payload->IsArray())
    {
        ctx->ReportError("The %s must be an LCPayload object, not an array", what);
        return false;
    }

    json = payload->ToJson();

    if (json.size() > lc::kMaxPayloadBytes)
    {
        smutils->LogError(myself, "The %s is %u bytes, over the %u LANCommander takes; it is left out",
            what, static_cast<unsigned>(json.size()), static_cast<unsigned>(lc::kMaxPayloadBytes));
        return false;
    }

    return true;
}

const char* JsonOrNull(const std::string& json)
{
    return json.empty() ? nullptr : json.c_str();
}

// ── Configuration ─────────────────────────────────────────────────────────────

// LC_Configure(bool enabled, const char[] serverUrl, const char[] token, const char[] gameId,
//              const char[] serverId, const char[] reporterName, int flushIntervalMs)
cell_t LC_Configure(IPluginContext* ctx, const cell_t* params)
{
    InterposerMatchConfig config{};
    config.structSize      = sizeof(config);
    config.enabled         = params[1] ? 1 : 0;
    config.serverUrl       = Str(ctx, params[2]);
    config.token           = Str(ctx, params[3]);
    config.gameId          = Str(ctx, params[4]);
    config.serverId        = Str(ctx, params[5]);
    config.reporterKind    = "Server";
    config.reporterName    = Str(ctx, params[6]);
    config.flushIntervalMs = params[7];

    return InterposerMatchConfigure(&config) ? 1 : 0;
}

// ── Matches ───────────────────────────────────────────────────────────────────

// LC_MatchStart(const char[] externalId, const char[] map, const char[] mode, const char[] gameVersion,
//               const char[] serverName, const char[] serverAddress, LCPayload settings,
//               LCPayload metadata, int startedOnUnix)
cell_t LC_MatchStart(IPluginContext* ctx, const cell_t* params)
{
    std::string settings, metadata;

    if (!PayloadObjectJson(ctx, params[7], settings, "match settings") ||
        !PayloadObjectJson(ctx, params[8], metadata, "match metadata"))
        return 0;

    InterposerMatchInfo info{};
    info.structSize    = sizeof(info);
    info.externalId    = OptStr(ctx, params[1]);
    info.map           = OptStr(ctx, params[2]);
    info.mode          = OptStr(ctx, params[3]);
    info.gameVersion   = OptStr(ctx, params[4]);
    info.serverName    = OptStr(ctx, params[5]);
    info.serverAddress = OptStr(ctx, params[6]);
    info.settingsJson  = JsonOrNull(settings);
    info.metadataJson  = JsonOrNull(metadata);
    info.startedOn     = params[9] > 0 ? static_cast<long long>(params[9]) * 1000 : 0;

    return static_cast<cell_t>(InterposerMatchStart(&info));
}

// LC_MatchPlayerJoined(int match, const char[] playerKey, const char[] displayName,
//                      const char[] team, int gameTimeMs)
cell_t LC_MatchPlayerJoined(IPluginContext* ctx, const cell_t* params)
{
    return InterposerMatchPlayerJoined(static_cast<DWORD>(params[1]), Str(ctx, params[2]),
        OptStr(ctx, params[3]), OptStr(ctx, params[4]), params[5]) ? 1 : 0;
}

// LC_MatchPlayerLeft(int match, const char[] playerKey, int gameTimeMs)
cell_t LC_MatchPlayerLeft(IPluginContext* ctx, const cell_t* params)
{
    return InterposerMatchPlayerLeft(static_cast<DWORD>(params[1]), Str(ctx, params[2]), params[3]) ? 1 : 0;
}

// LC_MatchEvent(int match, const char[] type, int gameTimeMs, int tick,
//               const char[] actorKey, const char[] subjectKey, LCPayload payload)
cell_t LC_MatchEvent(IPluginContext* ctx, const cell_t* params)
{
    std::string payload;

    if (!PayloadObjectJson(ctx, params[7], payload, "event payload"))
        return 0;

    return InterposerMatchEvent(static_cast<DWORD>(params[1]), Str(ctx, params[2]), params[3], params[4],
        OptStr(ctx, params[5]), OptStr(ctx, params[6]), JsonOrNull(payload)) ? 1 : 0;
}

// LC_MatchSetStatistic / LC_MatchAddStatistic(int match, const char[] playerKey, const char[] team,
//                                             const char[] key, float value)
cell_t LC_MatchSetStatistic(IPluginContext* ctx, const cell_t* params)
{
    return InterposerMatchSetStatistic(static_cast<DWORD>(params[1]), OptStr(ctx, params[2]),
        OptStr(ctx, params[3]), Str(ctx, params[4]), sp_ctof(params[5])) ? 1 : 0;
}

cell_t LC_MatchAddStatistic(IPluginContext* ctx, const cell_t* params)
{
    return InterposerMatchAddStatistic(static_cast<DWORD>(params[1]), OptStr(ctx, params[2]),
        OptStr(ctx, params[3]), Str(ctx, params[4]), sp_ctof(params[5])) ? 1 : 0;
}

// LC_MatchSetResult(int match, const char[] playerKey, const char[] team, int rank,
//                   LCResultStatus status, bool hasScore, float score, int timeMs, LCPayload payload)
cell_t LC_MatchSetResult(IPluginContext* ctx, const cell_t* params)
{
    std::string payload;

    if (!PayloadObjectJson(ctx, params[9], payload, "result payload"))
        return 0;

    InterposerMatchResult result{};
    result.structSize  = sizeof(result);
    result.playerKey   = OptStr(ctx, params[2]);
    result.team        = OptStr(ctx, params[3]);
    result.rank        = params[4];
    result.status      = params[5];
    result.hasScore    = params[6] ? 1 : 0;
    result.score       = sp_ctof(params[7]);
    result.timeMs      = params[8];
    result.payloadJson = JsonOrNull(payload);

    return InterposerMatchSetResult(static_cast<DWORD>(params[1]), &result) ? 1 : 0;
}

// LC_MatchEnd(int match, const char[] reason, bool abandoned)
cell_t LC_MatchEnd(IPluginContext* ctx, const cell_t* params)
{
    return InterposerMatchEnd(static_cast<DWORD>(params[1]), OptStr(ctx, params[2]), params[3] ? TRUE : FALSE) ? 1 : 0;
}

// LC_MatchAttachFile(int match, const char[] path, LCAttachmentKind kind, int startMs, int endMs)
cell_t LC_MatchAttachFile(IPluginContext* ctx, const cell_t* params)
{
    const char* path = Str(ctx, params[2]);

    if (!*path)
        return 0;

    // Relative paths are the game directory's, as everywhere in SourceMod
    // (a demo written by tv_record lands there).
    char full[PLATFORM_MAX_PATH];
    const bool absolute = path[0] == '/' || path[0] == '\\' || (path[0] && path[1] == ':');

    if (absolute)
        ke::SafeStrcpy(full, sizeof(full), path);
    else
        smutils->BuildPath(Path_Game, full, sizeof(full), "%s", path);

    const std::wstring wide = lc::Utf8ToWide(full);

    return InterposerMatchAttachFile(static_cast<DWORD>(params[1]), wide.c_str(), params[3], params[4], params[5]) ? 1 : 0;
}

// LC_MatchFlush(int match, int timeoutMs)
cell_t LC_MatchFlush(IPluginContext* /*ctx*/, const cell_t* params)
{
    const DWORD timeout = params[2] > 0 ? static_cast<DWORD>(params[2]) : 0;
    return InterposerMatchFlush(static_cast<DWORD>(params[1]), timeout) ? 1 : 0;
}

// LC_MatchGetStatus(int match, LCSink &sink, int &pendingEvents, int &rejectedEvents,
//                   int &pendingAttachments, bool &ended, bool &delivered,
//                   char[] matchId, int matchIdLength, char[] lastError, int lastErrorLength)
cell_t LC_MatchGetStatus(IPluginContext* ctx, const cell_t* params)
{
    InterposerMatchStatus status{};
    status.size = sizeof(status);

    if (!InterposerMatchGetStatus(static_cast<DWORD>(params[1]), &status))
        return 0;

    const auto put = [&](cell_t param, cell_t value)
    {
        cell_t* address;
        if (ctx->LocalToPhysAddr(param, &address) == SP_ERROR_NONE)
            *address = value;
    };

    put(params[2], status.sink);
    put(params[3], static_cast<cell_t>(status.pendingEvents));
    put(params[4], static_cast<cell_t>(status.rejectedEvents));
    put(params[5], static_cast<cell_t>(status.pendingAttachments));
    put(params[6], status.ended ? 1 : 0);
    put(params[7], status.delivered ? 1 : 0);

    ctx->StringToLocalUTF8(params[8], static_cast<size_t>(params[9]), status.matchId, nullptr);

    const std::string lastError = lc::WideToUtf8(status.lastError);
    ctx->StringToLocalUTF8(params[10], static_cast<size_t>(params[11]), lastError.c_str(), nullptr);

    return 1;
}

// ── LCPayload ─────────────────────────────────────────────────────────────────

// The payload a method was called on, or null with the error reported.
lc::Payload* This(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* payload;

    if (!ReadPayload(ctx, params[1], &payload))
        return nullptr;

    if (!payload)
        ctx->ReportError("LCPayload method called on a null handle");

    return payload;
}

lc::Payload* ThisObject(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* payload = This(ctx, params);

    if (payload && payload->IsArray())
    {
        ctx->ReportError("This LCPayload is an array: use the Push methods");
        return nullptr;
    }

    return payload;
}

lc::Payload* ThisArray(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* payload = This(ctx, params);

    if (payload && !payload->IsArray())
    {
        ctx->ReportError("This LCPayload is an object: use the Set methods");
        return nullptr;
    }

    return payload;
}

std::string VectorJson(IPluginContext* ctx, cell_t param)
{
    cell_t* vec;
    ctx->LocalToPhysAddr(param, &vec);

    return "[" + lc::JsonNumber(sp_ctof(vec[0])) + "," + lc::JsonNumber(sp_ctof(vec[1])) + "," +
        lc::JsonNumber(sp_ctof(vec[2])) + "]";
}

// The JSON of another payload, for nesting; empty with the error reported if
// the handle is not one.
bool ChildJson(IPluginContext* ctx, cell_t param, std::string& json)
{
    lc::Payload* child;

    if (!ReadPayload(ctx, param, &child))
        return false;

    json = child ? child->ToJson() : "null";
    return true;
}

// LCPayload(bool isArray = false)
cell_t LCPayload_Create(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* payload = new lc::Payload(params[1] != 0);

    HandleError error;
    const Handle_t handle = handlesys->CreateHandle(g_PayloadType, payload, ctx->GetIdentity(),
        myself->GetIdentity(), &error);

    if (handle == BAD_HANDLE)
    {
        delete payload;
        return ctx->ThrowNativeError("Could not create an LCPayload handle (error %d)", error);
    }

    return static_cast<cell_t>(handle);
}

cell_t LCPayload_SetInt(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisObject(ctx, params);
    return p && p->Set(Str(ctx, params[2]), lc::JsonNumber(static_cast<int>(params[3]))) ? 1 : 0;
}

cell_t LCPayload_SetFloat(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisObject(ctx, params);
    return p && p->Set(Str(ctx, params[2]), lc::JsonNumber(sp_ctof(params[3]))) ? 1 : 0;
}

cell_t LCPayload_SetBool(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisObject(ctx, params);
    return p && p->Set(Str(ctx, params[2]), params[3] ? "true" : "false") ? 1 : 0;
}

cell_t LCPayload_SetString(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisObject(ctx, params);
    return p && p->Set(Str(ctx, params[2]), lc::JsonString(Str(ctx, params[3]))) ? 1 : 0;
}

cell_t LCPayload_SetNull(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisObject(ctx, params);
    return p && p->Set(Str(ctx, params[2]), "null") ? 1 : 0;
}

cell_t LCPayload_SetVector(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisObject(ctx, params);
    return p && p->Set(Str(ctx, params[2]), VectorJson(ctx, params[3])) ? 1 : 0;
}

cell_t LCPayload_SetObject(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisObject(ctx, params);
    std::string json;
    return p && ChildJson(ctx, params[3], json) && p->Set(Str(ctx, params[2]), json) ? 1 : 0;
}

cell_t LCPayload_PushInt(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisArray(ctx, params);
    return p && p->Push(lc::JsonNumber(static_cast<int>(params[2]))) ? 1 : 0;
}

cell_t LCPayload_PushFloat(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisArray(ctx, params);
    return p && p->Push(lc::JsonNumber(sp_ctof(params[2]))) ? 1 : 0;
}

cell_t LCPayload_PushBool(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisArray(ctx, params);
    return p && p->Push(params[2] ? "true" : "false") ? 1 : 0;
}

cell_t LCPayload_PushString(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisArray(ctx, params);
    return p && p->Push(lc::JsonString(Str(ctx, params[2]))) ? 1 : 0;
}

cell_t LCPayload_PushVector(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisArray(ctx, params);
    return p && p->Push(VectorJson(ctx, params[2])) ? 1 : 0;
}

cell_t LCPayload_PushObject(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisArray(ctx, params);
    std::string json;
    return p && ChildJson(ctx, params[2], json) && p->Push(json) ? 1 : 0;
}

cell_t LCPayload_Remove(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisObject(ctx, params);
    return p && p->Remove(Str(ctx, params[2])) ? 1 : 0;
}

cell_t LCPayload_HasKey(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = ThisObject(ctx, params);
    return p && p->Has(Str(ctx, params[2])) ? 1 : 0;
}

cell_t LCPayload_Clear(IPluginContext* ctx, const cell_t* params)
{
    if (lc::Payload* p = This(ctx, params))
        p->Clear();
    return 0;
}

cell_t LCPayload_ToString(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = This(ctx, params);

    if (!p)
        return 0;

    const std::string json = p->ToJson();
    size_t written = 0;
    ctx->StringToLocalUTF8(params[2], static_cast<size_t>(params[3]), json.c_str(), &written);
    return static_cast<cell_t>(written);
}

cell_t LCPayload_SizeGet(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = This(ctx, params);
    return p ? static_cast<cell_t>(p->Size()) : 0;
}

cell_t LCPayload_IsArrayGet(IPluginContext* ctx, const cell_t* params)
{
    lc::Payload* p = This(ctx, params);
    return p && p->IsArray() ? 1 : 0;
}

} // namespace

extern const sp_nativeinfo_t g_Natives[] =
{
    { "LC_Configure",          LC_Configure },
    { "LC_MatchStart",         LC_MatchStart },
    { "LC_MatchPlayerJoined",  LC_MatchPlayerJoined },
    { "LC_MatchPlayerLeft",    LC_MatchPlayerLeft },
    { "LC_MatchEvent",         LC_MatchEvent },
    { "LC_MatchSetStatistic",  LC_MatchSetStatistic },
    { "LC_MatchAddStatistic",  LC_MatchAddStatistic },
    { "LC_MatchSetResult",     LC_MatchSetResult },
    { "LC_MatchEnd",           LC_MatchEnd },
    { "LC_MatchAttachFile",    LC_MatchAttachFile },
    { "LC_MatchFlush",         LC_MatchFlush },
    { "LC_MatchGetStatus",     LC_MatchGetStatus },

    { "LCPayload.LCPayload",   LCPayload_Create },
    { "LCPayload.SetInt",      LCPayload_SetInt },
    { "LCPayload.SetFloat",    LCPayload_SetFloat },
    { "LCPayload.SetBool",     LCPayload_SetBool },
    { "LCPayload.SetString",   LCPayload_SetString },
    { "LCPayload.SetNull",     LCPayload_SetNull },
    { "LCPayload.SetVector",   LCPayload_SetVector },
    { "LCPayload.SetObject",   LCPayload_SetObject },
    { "LCPayload.PushInt",     LCPayload_PushInt },
    { "LCPayload.PushFloat",   LCPayload_PushFloat },
    { "LCPayload.PushBool",    LCPayload_PushBool },
    { "LCPayload.PushString",  LCPayload_PushString },
    { "LCPayload.PushVector",  LCPayload_PushVector },
    { "LCPayload.PushObject",  LCPayload_PushObject },
    { "LCPayload.Remove",      LCPayload_Remove },
    { "LCPayload.HasKey",      LCPayload_HasKey },
    { "LCPayload.Clear",       LCPayload_Clear },
    { "LCPayload.ToString",    LCPayload_ToString },
    { "LCPayload.Size.get",    LCPayload_SizeGet },
    { "LCPayload.IsArray.get", LCPayload_IsArrayGet },
    { nullptr,                 nullptr },
};
