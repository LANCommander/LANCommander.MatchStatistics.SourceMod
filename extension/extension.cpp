#include "extension.h"
#include "payload.h"

#include <LANCommander.Interposer.h>
#include <LANCommander.Interposer.Embedded.h>

#include <string>
#include <thread>

LANCommanderExtension g_Extension;
SMEXT_LINK(&g_Extension);

HandleType_t g_PayloadType        = 0;
IForward*    g_MatchReportForward = nullptr;

namespace
{

std::thread::id g_gameThread;
bool            g_attached = false;

// The Interposer fires this from its exports, on the thread that called them:
// the game thread, for every native here. A forward may only run on the game
// thread, so a step reported from anywhere else (another extension calling the
// Interposer from a thread of its own) is not passed on. Queueing it with
// AddFrameAction instead could run it after this extension unloads.
void INTERPOSER_CALL OnMatchCallback(const wchar_t* kind, DWORD match, const wchar_t* json)
{
    if (!g_MatchReportForward || !g_MatchReportForward->GetFunctionCount())
        return;

    if (std::this_thread::get_id() != g_gameThread)
        return;

    const std::string kindText = lc::WideToUtf8(kind);
    const std::string jsonText = lc::WideToUtf8(json);

    g_MatchReportForward->PushString(kindText.c_str());
    g_MatchReportForward->PushCell(static_cast<cell_t>(match));
    g_MatchReportForward->PushString(jsonText.c_str());
    g_MatchReportForward->Execute(nullptr);
}

#ifdef _WIN32
HMODULE SelfModule()
{
    HMODULE module = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&SelfModule), &module);
    return module;
}
#endif

bool AttachInterposer()
{
#ifdef _WIN32
    // API-only: no detour is placed in srcds, so the extension can be unloaded
    // (sm exts unload, a server shutdown) without leaving hooks behind.
    const BOOL primary = InterposerEmbeddedAttachApiOnly(SelfModule());
#else
    const BOOL primary = InterposerEmbeddedAttach();
#endif

    // FALSE is not a failure: another Interposer already owns this process (one
    // LANCommander deployed beside srcds) and every call forwards to it.
    if (!primary)
        smutils->LogMessage(myself, "Another LANCommander Interposer is loaded in this process; reporting through it");

    return true;
}

} // namespace

bool LANCommanderExtension::SDK_OnLoad(char* error, size_t maxlength, bool /*late*/)
{
    g_gameThread = std::this_thread::get_id();

    HandleError handleError;
    g_PayloadType = handlesys->CreateType("LCPayload", this, 0, nullptr, nullptr, myself->GetIdentity(), &handleError);

    if (!g_PayloadType)
    {
        ke::SafeSprintf(error, maxlength, "Could not create the LCPayload handle type (error %d)", handleError);
        return false;
    }

    g_MatchReportForward = forwards->CreateForward("LC_OnMatchReport", ET_Ignore, 3, nullptr,
        Param_String, Param_Cell, Param_String);

    g_attached = AttachInterposer();
    InterposerRegisterMatchCallback(OnMatchCallback);

    sharesys->AddNatives(myself, g_Natives);
    sharesys->RegisterLibrary(myself, "lancommander");
    return true;
}

void LANCommanderExtension::SDK_OnUnload()
{
    InterposerRegisterMatchCallback(nullptr);

    // Stops the delivery thread (bounded); whatever is still unsent is already
    // in .interposer/Matches/ and goes out on the next load.
    if (g_attached)
        InterposerEmbeddedDetach(FALSE);

    g_attached = false;

    if (g_MatchReportForward)
        forwards->ReleaseForward(g_MatchReportForward);

    g_MatchReportForward = nullptr;

    if (g_PayloadType)
        handlesys->RemoveType(g_PayloadType, myself->GetIdentity());

    g_PayloadType = 0;
}

void LANCommanderExtension::OnHandleDestroy(HandleType_t type, void* object)
{
    if (type == g_PayloadType)
        delete static_cast<lc::Payload*>(object);
}

bool LANCommanderExtension::GetHandleApproxSize(HandleType_t type, void* object, unsigned int* size)
{
    if (type != g_PayloadType)
        return false;

    *size = static_cast<unsigned int>(sizeof(lc::Payload) + static_cast<lc::Payload*>(object)->ToJson().size());
    return true;
}
