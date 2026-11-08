#ifndef LANCOMMANDER_EXTENSION_H
#define LANCOMMANDER_EXTENSION_H

#include "smsdk_ext.h"

// The extension: SourceMod's side of the LANCommander Interposer.
//
// It embeds the Interposer (LANCommander.Interposer.Static) and attaches it in
// API-only mode, so nothing in srcds is hooked; the Interposer only batches,
// spools and delivers match reports. Its working directory, .interposer/, sits
// beside the extension binary: logs in .interposer/Logs/, unsent matches in
// .interposer/Matches/, and an optional Config.yml for logging settings.
//
// Natives (natives.cpp) bridge SourcePawn to the InterposerMatch* API one to
// one; the payload handle type (LCPayload) builds the JSON the API takes.
class LANCommanderExtension : public SDKExtension, public IHandleTypeDispatch
{
public:
    bool SDK_OnLoad(char* error, size_t maxlength, bool late) override;
    void SDK_OnUnload() override;

    // IHandleTypeDispatch
    void OnHandleDestroy(HandleType_t type, void* object) override;
    bool GetHandleApproxSize(HandleType_t type, void* object, unsigned int* size) override;
};

extern LANCommanderExtension g_Extension;

// LCPayload handles.
extern HandleType_t g_PayloadType;

// LC_OnMatchReport(const char[] kind, int match, const char[] json)
extern IForward* g_MatchReportForward;

extern const sp_nativeinfo_t g_Natives[];

#endif // LANCOMMANDER_EXTENSION_H
