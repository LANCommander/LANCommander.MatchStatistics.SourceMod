// Unit tests for the LCPayload JSON builder (extension/payload.cpp). Exit code
// 0 = all passed; one PASS/FAIL line per assertion.

#include "payload.h"

#include <cmath>
#include <cstdio>
#include <limits>
#include <string>

static int g_failures = 0;

static void Check(bool ok, const char* what)
{
    std::printf("%s  %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++g_failures;
}

static void CheckEq(const std::string& actual, const std::string& expected, const char* what)
{
    if (actual != expected)
        std::printf("      expected: %s\n      actual:   %s\n", expected.c_str(), actual.c_str());
    Check(actual == expected, what);
}

int main()
{
    using lc::JsonNumber;
    using lc::JsonString;
    using lc::Payload;

    // Strings
    CheckEq(JsonString("plain"), "\"plain\"", "P-01: a plain string is quoted");
    CheckEq(JsonString("say \"hi\" \\ bye"), "\"say \\\"hi\\\" \\\\ bye\"", "P-02: quotes and backslashes are escaped");
    CheckEq(JsonString("a\nb\tc\r\b\f"), "\"a\\nb\\tc\\r\\b\\f\"", "P-03: the short control escapes are used");
    CheckEq(JsonString(std::string("x\x01y", 3)), "\"x\\u0001y\"", "P-04: other control characters are \\u-escaped");
    CheckEq(JsonString("J\xC3\xA4ger \xE2\x98\x85 \xF0\x9F\x8E\xAE"), "\"J\xC3\xA4ger \xE2\x98\x85 \xF0\x9F\x8E\xAE\"",
        "P-05: valid UTF-8 passes through unchanged");
    CheckEq(JsonString("cut\xE2\x98"), "\"cut\xEF\xBF\xBD\xEF\xBF\xBD\"",
        "P-06: a truncated sequence becomes U+FFFD per byte");
    CheckEq(JsonString("\xC0\xAF"), "\"\xEF\xBF\xBD\xEF\xBF\xBD\"", "P-07: an overlong encoding is refused");
    CheckEq(JsonString("\xED\xA0\x80"), "\"\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD\"", "P-08: an encoded surrogate is refused");
    CheckEq(JsonString(std::string("nul\0in", 6)), "\"nul\\u0000in\"", "P-09: an embedded NUL is escaped");

    // Numbers
    CheckEq(JsonNumber(42), "42", "P-10: ints");
    CheckEq(JsonNumber(-7), "-7", "P-11: negative ints");
    CheckEq(JsonNumber(0.1f), "0.1", "P-12: floats use the shortest text that reads back the same");
    CheckEq(JsonNumber(1500.25f), "1500.25", "P-13: floats with a fraction");
    CheckEq(JsonNumber(std::numeric_limits<float>::quiet_NaN()), "null", "P-14: NaN is null");
    CheckEq(JsonNumber(std::numeric_limits<float>::infinity()), "null", "P-15: infinity is null");

    // Objects
    {
        Payload p;
        Check(p.Set("weapon", JsonString("ak47")), "P-16: Set on an object succeeds");
        p.Set("headshot", "true");
        p.Set("damage", JsonNumber(100));
        CheckEq(p.ToJson(), "{\"weapon\":\"ak47\",\"headshot\":true,\"damage\":100}", "P-17: keys keep their order");

        p.Set("weapon", JsonString("m4a1"));
        CheckEq(p.ToJson(), "{\"weapon\":\"m4a1\",\"headshot\":true,\"damage\":100}", "P-18: setting a key again replaces it in place");

        Check(p.Has("damage") && !p.Has("missing"), "P-19: Has");
        Check(p.Remove("headshot") && !p.Remove("headshot"), "P-20: Remove, once");
        CheckEq(p.ToJson(), "{\"weapon\":\"m4a1\",\"damage\":100}", "P-21: a removed key is gone");
        Check(p.Size() == 2, "P-22: Size counts keys");
        Check(!p.Push("1"), "P-23: Push on an object is refused");

        p.Set("we\"ird", "null");
        CheckEq(p.ToJson(), "{\"weapon\":\"m4a1\",\"damage\":100,\"we\\\"ird\":null}", "P-24: keys are escaped");

        p.Clear();
        CheckEq(p.ToJson(), "{}", "P-25: an empty object");
    }

    // Arrays and nesting
    {
        Payload list(true);
        Check(!list.Set("k", "1"), "P-26: Set on an array is refused");
        list.Push(JsonNumber(1));
        list.Push(JsonString("two"));
        CheckEq(list.ToJson(), "[1,\"two\"]", "P-27: arrays");

        Payload outer;
        outer.Set("assisters", list.ToJson());
        Payload inner;
        inner.Set("x", JsonNumber(1.5f));
        outer.Set("position", inner.ToJson());
        CheckEq(outer.ToJson(), "{\"assisters\":[1,\"two\"],\"position\":{\"x\":1.5}}", "P-28: nested values");
    }

    // Wide strings
    {
        const std::string  utf8 = "D\xC3\xA9mo \xF0\x9F\x8E\xAE.dem";
        const std::wstring wide = lc::Utf8ToWide(utf8);
        Check(lc::WideToUtf8(wide.c_str()) == utf8, "P-29: UTF-8 survives the round trip through wchar_t");
        Check(wide.size() == (sizeof(wchar_t) == 2 ? 11u : 10u), "P-30: astral characters are surrogate pairs only in UTF-16");
        Check(lc::WideToUtf8(nullptr).empty(), "P-31: a null wide string is empty");
    }

    std::printf("=== %d failed ===\n", g_failures);
    return g_failures ? 1 : 0;
}
