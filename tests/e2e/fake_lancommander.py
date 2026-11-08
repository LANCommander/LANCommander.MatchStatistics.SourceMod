"""A stand-in for LANCommander's /api/Matches, for end-to-end tests.

Answers the requests the Interposer makes the way LANCommander does
(LANCommander.Server/Endpoints/MatchEndpoints.cs, MatchSubmissions.cs) and
appends each one to a JSON-lines log for the test to inspect:

    python -I tests/e2e/fake_lancommander.py --port 8099 --log out/e2e/requests.jsonl

It checks what the real server would refuse -- a missing bearer token, more
than 500 events in a batch, an event without id/sequence/type, a payload
that is not an object or is over 16 KB -- and records each problem as
"problems" in the log line, answering 400 as the server would.
"""

import argparse
import json
import re
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_EVENTS_PER_BATCH = 500
MAX_PAYLOAD_BYTES = 16 * 1024

lock = threading.Lock()
matches = {}  # externalId -> {"matchId", "reporterId", "lastSequence"}


def check_events(body):
    problems = []
    events = body.get("events") if isinstance(body, dict) else None

    if not isinstance(events, list):
        return ["events is not a list"]

    if len(events) > MAX_EVENTS_PER_BATCH:
        problems.append(f"{len(events)} events in one batch")

    for event in events:
        for key in ("id", "sequence", "type"):
            if not event.get(key):
                problems.append(f"event without {key}: {event}")

        payload = event.get("payload")

        if payload is not None:
            if not isinstance(payload, dict):
                problems.append(f"payload is not an object: {payload}")
            elif len(json.dumps(payload)) > MAX_PAYLOAD_BYTES:
                problems.append(f"payload over 16 KB in {event.get('type')}")

    return problems


class Handler(BaseHTTPRequestHandler):
    log_path = None

    def log_message(self, format, *args):
        pass

    def answer(self, status, body=None):
        data = json.dumps(body).encode() if body is not None else b""
        self.send_response(status)
        if data:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def record(self, body, problems, status):
        line = {
            "method": self.command,
            "path": self.path,
            "authorization": self.headers.get("Authorization", ""),
            "status": status,
            "body": body,
            "problems": problems,
        }
        with lock, open(self.log_path, "a", encoding="utf-8") as log:
            log.write(json.dumps(line) + "\n")

    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        content_type = self.headers.get("Content-Type", "")

        body = None
        problems = []

        if raw and content_type.startswith("application/json"):
            try:
                body = json.loads(raw)
            except ValueError as error:
                problems.append(f"invalid JSON: {error}")
        elif raw:
            body = {"bytes": len(raw)}

        if not self.headers.get("Authorization", "").startswith("Bearer "):
            problems.append("no bearer token")

        status, reply = self.route(body, problems)
        if problems:
            status, reply = 400, {"errors": problems}

        self.record(body, problems, status)
        self.answer(status, reply)

    def route(self, body, problems):
        path = self.path.split("?")[0]
        post = self.command == "POST"

        if post and path == "/api/Matches":
            external_id = (body or {}).get("externalId", "")
            for key in ("gameId", "externalId", "reporterKind"):
                if not (body or {}).get(key):
                    problems.append(f"match without {key}")
            with lock:
                created = external_id not in matches
                match = matches.setdefault(external_id, {
                    "matchId": str(uuid.uuid4()),
                    "reporterId": str(uuid.uuid4()),
                    "lastSequence": 0,
                })
            return (201 if created else 200), {
                "matchId": match["matchId"], "reporterId": match["reporterId"],
                "created": created, "lastSequence": match["lastSequence"], "status": "Open",
            }

        if post and re.fullmatch(r"/api/Matches/[^/]+/Participants", path):
            return 204, None

        if post and re.fullmatch(r"/api/Matches/[^/]+/Events", path):
            problems.extend(check_events(body))
            events = (body or {}).get("events", [])
            with lock:
                for match in matches.values():
                    if match["reporterId"] == (body or {}).get("reporterId"):
                        match["lastSequence"] = max([match["lastSequence"]] + [e.get("sequence", 0) for e in events])
            return 202, {"queued": len(events), "rejected": []}

        if post and re.fullmatch(r"/api/Matches/[^/]+/End", path):
            return 204, None

        if post and re.fullmatch(r"/api/Matches/[^/]+/Attachments", path):
            return 201, {"id": str(uuid.uuid4())}

        if self.command == "PUT" and re.fullmatch(r"/api/Matches/[^/]+/Attachments/[^/]+/Content", path):
            return 204, None

        if post and re.fullmatch(r"/api/Matches/[^/]+/Attachments/[^/]+/Complete", path):
            return 200, {"id": path.split("/")[-2], "status": "Uploaded"}

        return 404, {"error": "not found"}

    do_POST = handle_any
    do_PUT = handle_any
    do_GET = handle_any


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8099)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    Handler.log_path = args.log
    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(f"Fake LANCommander on :{args.port}, logging to {args.log}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
