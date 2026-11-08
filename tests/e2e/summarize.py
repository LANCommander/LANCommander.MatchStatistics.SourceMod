"""Summarises what the fake LANCommander received (fake_lancommander.py's log).

    python -I tests/e2e/summarize.py out/e2e/requests.jsonl [--expect kill,bomb_planted,...]

Prints each match: its registration, participants, events by type, and the
end with its results and statistics. Exits 1 if any request had a problem,
or if an --expect'ed event type never arrived.
"""

import argparse
import collections
import json
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("log")
    parser.add_argument("--expect", default="", help="comma-separated event types that must appear")
    args = parser.parse_args()

    requests = [json.loads(line) for line in open(args.log, encoding="utf-8") if line.strip()]

    problems = [r for r in requests if r["problems"]]
    created = [r for r in requests if r["path"] == "/api/Matches" and r["method"] == "POST"]
    events = [e for r in requests if r["path"].endswith("/Events") for e in (r["body"] or {}).get("events", [])]
    participants = [p for r in requests if r["path"].endswith("/Participants") for p in (r["body"] or [])]
    ends = [r for r in requests if r["path"].endswith("/End")]
    attachments = [r for r in requests if "/Attachments" in r["path"]]

    print(f"{len(requests)} requests, {len(problems)} with problems")

    for r in created:
        b = r["body"]
        print(f"\nMATCH {b.get('externalId')}  map={b.get('map')} mode={b.get('mode')} "
              f"version={b.get('gameVersion')} reporter={b.get('reporterName')} ({b.get('reporterKind')})")
        print(f"  settings: {json.dumps(b.get('settings'))[:300]}")
        print(f"  metadata: {json.dumps(b.get('metadata'))[:300]}")

    keys = sorted({p.get("playerKey") for p in participants})
    print(f"\nPARTICIPANTS ({len(keys)}): {', '.join(keys[:20])}{' ...' if len(keys) > 20 else ''}")

    types = collections.Counter(e["type"] for e in events)
    print(f"\nEVENTS ({len(events)}):")
    for type_, count in sorted(types.items()):
        sample = next(e for e in events if e["type"] == type_)
        print(f"  {count:5}  {type_:24} e.g. actor={sample.get('actorKey')} subject={sample.get('subjectKey')} "
              f"payload={json.dumps(sample.get('payload'))[:160]}")

    sequences = sorted(e["sequence"] for e in events)
    duplicates = len(sequences) - len(set(sequences))
    print(f"\nsequence numbers: {sequences[:1]}..{sequences[-1:]} duplicates={duplicates}")

    for r in ends:
        b = r["body"]
        print(f"\nEND reason={b.get('reason')} abandoned={b.get('abandoned')}")
        for result in b.get("results", [])[:12]:
            print(f"  result {result}")
        stats = collections.Counter(s["key"] for s in b.get("statistics", []))
        print(f"  statistics: {dict(stats)}")

    if attachments:
        print(f"\nATTACHMENTS: {[(a['method'], a['path'].split('/Attachments')[1]) for a in attachments]}")

    for r in problems:
        print(f"\nPROBLEM {r['method']} {r['path']}: {r['problems']}")

    missing = [t for t in args.expect.split(",") if t and t not in types]
    if missing:
        print(f"\nMISSING expected event types: {missing}")

    sys.exit(1 if problems or missing else 0)


if __name__ == "__main__":
    main()
