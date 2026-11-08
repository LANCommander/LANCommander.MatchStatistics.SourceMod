// LCPayload: a JSON object (or array) built up from SourcePawn, one value at a
// time, then handed to the Interposer as text.
//
// Plain C++ with no SourceMod dependency, so the unit tests can exercise it on
// its own (tests/payload_tests.cpp).

#pragma once

#include <cstddef>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace lc
{

// The largest payload LANCommander accepts for one event (MatchEventSubmission).
constexpr size_t kMaxPayloadBytes = 16 * 1024;

// JSON text for a string: quoted, escaped, and with any invalid UTF-8
// replaced by U+FFFD. The Interposer refuses a payload that is not strictly
// valid JSON, and SourcePawn strings are bytes: a player name cut in the middle
// of a multi-byte character must not cost the whole event.
std::string JsonString(std::string_view text);

// JSON text for a number. Finite values use the shortest text that reads back
// as the same float; NaN and infinities, which JSON cannot express, are null.
std::string JsonNumber(float value);
std::string JsonNumber(int value);

class Payload
{
public:
    explicit Payload(bool isArray = false) : m_isArray(isArray) {}

    bool IsArray() const { return m_isArray; }
    size_t Size() const { return m_isArray ? m_items.size() : m_fields.size(); }

    // Objects: set a key to a JSON value, replacing it in place if present.
    // Arrays: refused (false).
    bool Set(std::string_view key, std::string rawJson);
    bool Remove(std::string_view key);
    bool Has(std::string_view key) const;

    // Arrays: append a JSON value. Objects: refused (false).
    bool Push(std::string rawJson);

    void Clear();

    // The whole payload as JSON text.
    std::string ToJson() const;

private:
    bool m_isArray;
    std::vector<std::pair<std::string, std::string>> m_fields; // key, raw JSON value
    std::vector<std::string>                         m_items;  // raw JSON values
};

// UTF-8 <-> wchar_t (UTF-16 on Windows, UTF-32 elsewhere), for the Interposer's
// wide-character file paths and callback text.
std::wstring Utf8ToWide(std::string_view text);
std::string  WideToUtf8(const wchar_t* text);

} // namespace lc
