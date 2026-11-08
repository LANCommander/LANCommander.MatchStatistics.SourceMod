#include "payload.h"

#include <charconv>
#include <cmath>
#include <cstdint>
#include <cstdio>

namespace lc
{

namespace
{

constexpr char32_t kReplacement = 0xFFFD;

// Decode one code point from text[i...], advancing i. Invalid or truncated
// sequences, overlong forms, surrogates and values past U+10FFFF decode as
// U+FFFD and consume a single byte, so decoding always makes progress.
char32_t DecodeUtf8(std::string_view text, size_t& i)
{
    const auto byte = [&](size_t at) { return static_cast<unsigned char>(text[at]); };

    const unsigned char lead = byte(i);

    if (lead < 0x80)
    {
        ++i;
        return lead;
    }

    size_t    length;
    char32_t  cp;
    char32_t  minimum;

    if ((lead & 0xE0) == 0xC0)      { length = 2; cp = lead & 0x1F; minimum = 0x80; }
    else if ((lead & 0xF0) == 0xE0) { length = 3; cp = lead & 0x0F; minimum = 0x800; }
    else if ((lead & 0xF8) == 0xF0) { length = 4; cp = lead & 0x07; minimum = 0x10000; }
    else
    {
        ++i;
        return kReplacement;
    }

    if (i + length > text.size())
    {
        ++i;
        return kReplacement;
    }

    for (size_t k = 1; k < length; ++k)
    {
        const unsigned char next = byte(i + k);

        if ((next & 0xC0) != 0x80)
        {
            ++i;
            return kReplacement;
        }

        cp = (cp << 6) | (next & 0x3F);
    }

    if (cp < minimum || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF))
    {
        ++i;
        return kReplacement;
    }

    i += length;
    return cp;
}

void AppendUtf8(std::string& out, char32_t cp)
{
    if (cp < 0x80)
        out += static_cast<char>(cp);
    else if (cp < 0x800)
    {
        out += static_cast<char>(0xC0 | (cp >> 6));
        out += static_cast<char>(0x80 | (cp & 0x3F));
    }
    else if (cp < 0x10000)
    {
        out += static_cast<char>(0xE0 | (cp >> 12));
        out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (cp & 0x3F));
    }
    else
    {
        out += static_cast<char>(0xF0 | (cp >> 18));
        out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
        out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (cp & 0x3F));
    }
}

} // namespace

std::string JsonString(std::string_view text)
{
    std::string out;
    out.reserve(text.size() + 2);
    out += '"';

    for (size_t i = 0; i < text.size();)
    {
        const char32_t cp = DecodeUtf8(text, i);

        switch (cp)
        {
        case '"':  out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\b': out += "\\b";  break;
        case '\f': out += "\\f";  break;
        case '\n': out += "\\n";  break;
        case '\r': out += "\\r";  break;
        case '\t': out += "\\t";  break;
        default:
            if (cp < 0x20)
            {
                char escaped[8];
                std::snprintf(escaped, sizeof(escaped), "\\u%04x", static_cast<unsigned>(cp));
                out += escaped;
            }
            else
                AppendUtf8(out, cp);
        }
    }

    out += '"';
    return out;
}

std::string JsonNumber(float value)
{
    if (!std::isfinite(value))
        return "null";

    char buffer[64];
    const auto result = std::to_chars(buffer, buffer + sizeof(buffer), value);

    return std::string(buffer, result.ptr);
}

std::string JsonNumber(int value)
{
    return std::to_string(value);
}

bool Payload::Set(std::string_view key, std::string rawJson)
{
    if (m_isArray)
        return false;

    for (auto& [existing, value] : m_fields)
    {
        if (existing == key)
        {
            value = std::move(rawJson);
            return true;
        }
    }

    m_fields.emplace_back(std::string(key), std::move(rawJson));
    return true;
}

bool Payload::Remove(std::string_view key)
{
    for (auto it = m_fields.begin(); it != m_fields.end(); ++it)
    {
        if (it->first == key)
        {
            m_fields.erase(it);
            return true;
        }
    }

    return false;
}

bool Payload::Has(std::string_view key) const
{
    for (const auto& field : m_fields)
        if (field.first == key)
            return true;

    return false;
}

bool Payload::Push(std::string rawJson)
{
    if (!m_isArray)
        return false;

    m_items.push_back(std::move(rawJson));
    return true;
}

void Payload::Clear()
{
    m_fields.clear();
    m_items.clear();
}

std::string Payload::ToJson() const
{
    std::string out;

    if (m_isArray)
    {
        out += '[';

        for (size_t i = 0; i < m_items.size(); ++i)
        {
            if (i)
                out += ',';
            out += m_items[i];
        }

        out += ']';
        return out;
    }

    out += '{';

    for (size_t i = 0; i < m_fields.size(); ++i)
    {
        if (i)
            out += ',';
        out += JsonString(m_fields[i].first);
        out += ':';
        out += m_fields[i].second;
    }

    out += '}';
    return out;
}

std::wstring Utf8ToWide(std::string_view text)
{
    std::wstring out;
    out.reserve(text.size());

    for (size_t i = 0; i < text.size();)
    {
        const char32_t cp = DecodeUtf8(text, i);

        if constexpr (sizeof(wchar_t) == 2)
        {
            if (cp >= 0x10000)
            {
                const char32_t v = cp - 0x10000;
                out += static_cast<wchar_t>(0xD800 + (v >> 10));
                out += static_cast<wchar_t>(0xDC00 + (v & 0x3FF));
                continue;
            }
        }

        out += static_cast<wchar_t>(cp);
    }

    return out;
}

std::string WideToUtf8(const wchar_t* text)
{
    std::string out;

    if (!text)
        return out;

    for (const wchar_t* p = text; *p; ++p)
    {
        char32_t cp = static_cast<char32_t>(*p);

        if constexpr (sizeof(wchar_t) == 2)
        {
            if (cp >= 0xD800 && cp <= 0xDBFF && p[1] >= 0xDC00 && p[1] <= 0xDFFF)
            {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (static_cast<char32_t>(p[1]) - 0xDC00);
                ++p;
            }
            else if (cp >= 0xD800 && cp <= 0xDFFF)
                cp = kReplacement;
        }
        else if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF))
            cp = kReplacement;

        AppendUtf8(out, cp);
    }

    return out;
}

} // namespace lc
