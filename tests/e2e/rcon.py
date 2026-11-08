"""A minimal Source RCON client for the end-to-end tests.

    python -I tests/e2e/rcon.py --host 127.0.0.1 --port 27115 --password secret "sm_lc_status" ["cmd2" ...]
"""

import argparse
import socket
import struct

SERVERDATA_AUTH = 3
SERVERDATA_EXECCOMMAND = 2


def send(sock, request_id, kind, body):
    data = struct.pack("<ii", request_id, kind) + body.encode() + b"\x00\x00"
    sock.sendall(struct.pack("<i", len(data)) + data)


def receive(sock):
    def exactly(count):
        data = b""
        while len(data) < count:
            chunk = sock.recv(count - len(data))
            if not chunk:
                raise ConnectionError("connection closed")
            data += chunk
        return data

    (size,) = struct.unpack("<i", exactly(4))
    request_id, kind = struct.unpack("<ii", exactly(8))
    body = exactly(size - 8)[:-2]
    return request_id, kind, body.decode(errors="replace")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=27015)
    parser.add_argument("--password", required=True)
    parser.add_argument("commands", nargs="+")
    args = parser.parse_args()

    with socket.create_connection((args.host, args.port), timeout=10) as sock:
        send(sock, 1, SERVERDATA_AUTH, args.password)

        # An empty RESPONSE_VALUE, then the AUTH_RESPONSE (id -1 on failure).
        while True:
            request_id, kind, _ = receive(sock)
            if kind == 2:
                if request_id == -1:
                    raise SystemExit("rcon: wrong password")
                break

        for index, command in enumerate(args.commands, start=10):
            send(sock, index, SERVERDATA_EXECCOMMAND, command)
            # A marker after the command: its (empty) reply ends the output.
            send(sock, index + 1000, SERVERDATA_EXECCOMMAND, "")

            output = ""
            while True:
                request_id, _, body = receive(sock)
                if request_id == index + 1000:
                    break
                output += body

            print(f"> {command}\n{output}", end="" if output.endswith("\n") else "\n")


if __name__ == "__main__":
    main()
