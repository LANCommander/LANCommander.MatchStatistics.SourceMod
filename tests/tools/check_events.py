"""Checks the plugins' game events against the games' own event definitions.

    python -I tests/tools/check_events.py [--gameinfo out/gameinfo]

For every game module, every event it hooks and every field its handlers
read (event.GetInt("field") and the like) must exist in that game's event
files: resource/modevents.res, gameevents.res and serverevents.res, as
extract_gameinfo.py copies them out of a server install into
out/gameinfo/<game>/. As in the engine, an event's definition in modevents
replaces the shared one whole, fields included.

An event hooked with HookEventEx may be missing from some of a module's games
(the L4D module's L4D2-only events) but not from all of them.

It also prints which of the generic events the core plugin records, and their
fields, each game has. Exit code 1 when a module reads something that does
not exist.
"""

import argparse
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Module -> the games (out/gameinfo folders) it runs on.
MODULES = {
    "cstrike": ["css"],
    "dods": ["dods"],
    "l4d": ["l4d", "l4d2"],
    "pvkii": ["pvkii"],
    "fof": ["fof"],
    "dab": ["dab"],
    "empires": ["empires"],
    "hl2dm": ["hl2dm"],
    "darkmessiah": ["darkmessiah"],
    "lambdawars": ["lambdawars"],
    "tf2": ["tf2"],
    "mcv": ["mcv"],
    "insurgency": ["insurgency"],
}

# Events and fields a module reads for a game whose definitions are not in
# out/gameinfo, with the reason. Reported as notes, not problems.
ELSEWHERE = {
    "cstrike": {
        "CS:GO only": [
            "player_blind.attacker", "player_death.attackerblind", "player_death.noscope",
            "player_death.penetrated", "player_death.thrusmoke", "molotov_detonate", "decoy_detonate",
            "round_mvp",
        ],
    },
}

# What the core reads from the generic events (events.sp).
GENERIC = {
    "player_death": ["userid", "attacker", "weapon", "headshot", "assister|assistid|assist"],
    "player_hurt": ["userid", "attacker", "dmg_health|damageamount|damage", "health", "weapon", "hitgroup"],
    "player_spawn": ["userid"],
    "player_team": ["userid", "team", "oldteam", "disconnect"],
    "player_changename": ["userid", "oldname", "newname"],
    "player_disconnect": ["userid", "reason"],
    "weapon_fire": ["userid", "weapon"],
    "round_start": [],
    "round_end": ["winner", "reason", "message"],
    "game_end": ["winner"],
}


# ── Valve KeyValues, enough for the event files ──────────────────────────────

def tokens(text):
    for match in re.finditer(r'"([^"]*)"|([{}])|//[^\n]*|([^\s{}"]+)', text):
        quoted, brace, bare = match.group(1), match.group(2), match.group(3)
        if brace:
            yield brace
        elif quoted is not None:
            yield ("s", quoted)
        elif bare is not None:
            yield ("s", bare)


def parse(text):
    stack = [{}]
    key = None
    for token in tokens(text):
        if token == "{":
            child = {}
            if key is not None:
                stack[-1][key] = child
            stack.append(child)
            key = None
        elif token == "}":
            if len(stack) > 1:
                stack.pop()
            key = None
        else:
            if key is None:
                key = token[1]
            else:
                stack[-1][key] = token[1]
                key = None
    return stack[0]


def load_game(folder):
    """event name -> set of fields, with modevents replacing the shared files."""
    found = {"server": [], "game": [], "mod": []}

    for dirpath, _, filenames in os.walk(folder):
        for name in filenames:
            lower = name.lower()
            kind = {"serverevents.res": "server", "gameevents.res": "game", "modevents.res": "mod"}.get(lower)
            if kind:
                found[kind].append(os.path.join(dirpath, name))

    events = {}
    for kind in ("server", "game", "mod"):
        defined = {}
        for path in found[kind]:
            with open(path, encoding="utf-8", errors="replace") as f:
                root = parse(f.read())
            for section in root.values():
                if isinstance(section, dict):
                    for event, fields in section.items():
                        if isinstance(fields, dict):
                            # Several files of one kind (an update VPK over the
                            # base one): their union.
                            defined.setdefault(event.lower(), set()).update(k.lower() for k in fields)
        events.update(defined)

    return events


# ── The plugins ──────────────────────────────────────────────────────────────

# LCStats_HookEvent (an event the module expects; logged if missing) and the
# plain HookEvent count as expected; HookEventEx as optional.
HOOK = re.compile(r'(?<![\w])(?:LCStats_)?HookEvent(Ex)?\(\s*("([^"]+)"|(\w+)\[\s*\w+\s*\](?:\[\s*\d+\s*\])?)\s*,\s*(\w+)')
GET = re.compile(r'\bevent\.Get(?:Int|Bool|Float|String)\(\s*"([^"]+)"')


def string_array(source, name):
    """The event names in a static string array: the first string of each row, or all of a flat one."""
    match = re.search(name + r"\s*\[\][^=]*=\s*\{(.*?)\};", source, re.S)
    if not match:
        return []
    body = match.group(1)
    rows = re.findall(r"\{([^{}]*)\}", body)
    if rows:
        return [re.findall(r'"([^"]+)"', row)[0] for row in rows if re.findall(r'"([^"]+)"', row)]
    return re.findall(r'"([^"]+)"', body)


def handler_body(source, handler):
    match = re.search(r"public\s+\w+\s+" + handler + r"\s*\([^)]*\)\s*\{", source)
    if not match:
        return ""
    depth, i = 1, match.end()
    while i < len(source) and depth:
        depth += {"{": 1, "}": -1}.get(source[i], 0)
        i += 1
    return source[match.end():i]


def module_hooks(path):
    with open(path, encoding="utf-8") as f:
        source = f.read()

    hooks = []
    for match in HOOK.finditer(source):
        optional, literal, array, handler = bool(match.group(1)), match.group(3), match.group(4), match.group(5)
        names = [literal] if literal else string_array(source, array)
        body = handler_body(source, handler)
        fields = sorted(set(GET.findall(body)))
        for name in names:
            hooks.append((name, optional, handler, fields))
    return hooks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--gameinfo", default=os.path.join(ROOT, "out", "gameinfo"))
    args = parser.parse_args()

    games = {}
    for name in sorted(os.listdir(args.gameinfo)):
        folder = os.path.join(args.gameinfo, name)
        if os.path.isdir(folder):
            events = load_game(folder)
            if events:
                games[name] = events

    problems = 0
    print(f"Event definitions found for: {', '.join(games)}\n")

    for module, module_games in MODULES.items():
        path = os.path.join(ROOT, "scripting", "modules", f"lancommander_stats_{module}.sp")
        if not os.path.exists(path):
            continue

        available = [g for g in module_games if g in games]
        if not available:
            print(f"-- {module}: not checked, no event definitions for {', '.join(module_games)}")
            continue

        elsewhere = {item: reason for reason, items in ELSEWHERE.get(module, {}).items() for item in items}

        def report(item, message):
            nonlocal problems
            if item in elsewhere:
                print(f"   note   {message} ({elsewhere[item]})")
            else:
                print(f"   ERROR  {message}")
                problems += 1

        print(f"-- {module} against {', '.join(available)}")
        hooks = module_hooks(path)

        # A handler may serve several events and read a field only for the ones
        # that have it (if (StrEqual(name, ...))): a field is fine when any of
        # the handler's events has it, in each game that has any of them.
        by_handler = {}
        for event, optional, handler, fields in hooks:
            by_handler.setdefault(handler, (set(), fields))[0].add(event.lower())

        for event, optional, handler, fields in hooks:
            present = [g for g in available if event.lower() in games[g]]
            if not present:
                report(event, f"{event} ({handler}): no such event")
                continue
            if len(present) < len(available):
                missing = [g for g in available if g not in present]
                if optional:
                    print(f"   note   {event}: not in {', '.join(missing)} (HookEventEx)")
                else:
                    report(event, f"{event}: not in {', '.join(missing)}; use HookEventEx for an event only some of its games have")

        for handler, (events, fields) in by_handler.items():
            for field in fields:
                lacking = []
                for game in available:
                    served = [e for e in events if e in games[game]]
                    if served and not any(field.lower() in games[game][e] for e in served):
                        lacking.append(game)
                if not lacking:
                    continue
                item = next((f"{e}.{field}" for e in sorted(events) if f"{e}.{field}" in elsewhere), f"?.{field}")
                where = "/".join(sorted(events))
                if len(lacking) < len([g for g in available if any(e in games[g] for e in events)]):
                    print(f"   note   {where}.{field} ({handler}): not in {', '.join(lacking)}")
                else:
                    report(item, f"{where}.{field} ({handler}): not in {', '.join(lacking)}")

    print("\nGeneric events the core records (- missing event; field alternatives with |; ! = no alternative present):")
    width = max(len(g) for g in games)
    for event, fields in GENERIC.items():
        print(f"\n  {event}")
        for game, events in games.items():
            if event not in events:
                print(f"    {game:<{width}}  -")
                continue
            parts = []
            for field in fields:
                options = field.split("|")
                hit = [o for o in options if o in events[event]]
                parts.append(hit[0] if hit else "!" + options[0])
            print(f"    {game:<{width}}  {' '.join(parts)}")

    print(f"\n{problems} problem(s)")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
