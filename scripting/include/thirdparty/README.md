# Vendored includes

These are other plugins' include files. The integrations compile against them; they are not
distributed with the plugins.

| File | Source | Version | Licence |
|---|---|---|---|
| `get5.inc` | [splewis/get5](https://github.com/splewis/get5), `scripting/include/get5.inc` | `development` @ `d937484` | GPLv3 |
| `json.inc`, `json/` | [clugg/sm-json](https://github.com/clugg/sm-json), needed by `get5.inc` | v5.0.2 | GPLv3 |

The other integrations only implement the plugins' forwards: PugSetup, SourceBans++/SourceComms,
Retakes and Left4DHooks. A forward needs no include, only a `public` function with the same
signature, so those signatures are copied into the integrations themselves, with a note of where
each came from.

To update one, replace the file and recompile every integration with warnings as errors.
