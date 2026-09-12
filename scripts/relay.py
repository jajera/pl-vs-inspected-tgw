#!/usr/bin/env python3
"""Ingest a public SSE firehose (or replay a capture) and fan out to TCP subscribers.

Stream lines to clients:
  <relay_send_ns> <json>

Control on the same connection:
  client → PING <seq>
  relay  → PONG <seq> <relay_ns>
"""
from __future__ import annotations

import argparse
import socket
import socketserver
import threading
import time
import urllib.request

DEFAULT_UPSTREAM = "https://stream.wikimedia.org/v2/stream/recentchange"
DEFAULT_PORT = 9000
USER_AGENT = "pl-vs-inspected-tgw/1.0 (lab; contact via repo)"


class Sub:
    def __init__(self, sock: socket.socket) -> None:
        self.sock = sock
        self.lock = threading.Lock()

    def send(self, data: bytes) -> None:
        with self.lock:
            self.sock.sendall(data)


subs: set[Sub] = set()
subs_lock = threading.Lock()


def broadcast(payload: bytes) -> None:
    line = b"%d %s\n" % (time.time_ns(), payload)
    with subs_lock:
        targets = list(subs)
    dead: list[Sub] = []
    for sub in targets:
        try:
            sub.send(line)
        except OSError:
            dead.append(sub)
    if dead:
        with subs_lock:
            for sub in dead:
                subs.discard(sub)


def ingest_live(url: str) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    while True:
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                for raw in resp:
                    if raw.startswith(b"data: "):
                        broadcast(raw[6:].rstrip())
        except Exception:
            time.sleep(2)


def ingest_replay(path: str, pace_s: float) -> None:
    while True:
        with open(path, "rb") as fh:
            for raw in fh:
                if raw.startswith(b"data: "):
                    broadcast(raw[6:].rstrip())
                    if pace_s > 0:
                        time.sleep(pace_s)
                elif raw.strip():
                    # tolerate plain JSONL captures
                    broadcast(raw.rstrip())
                    if pace_s > 0:
                        time.sleep(pace_s)
        time.sleep(0.5)


class Handler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        self.request.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sub = Sub(self.request)
        with subs_lock:
            subs.add(sub)
        try:
            for line in self.request.makefile("rb"):
                if line.startswith(b"PING"):
                    parts = line.split()
                    seq = parts[1] if len(parts) > 1 else b"0"
                    sub.send(b"PONG %s %d\n" % (seq, time.time_ns()))
        except OSError:
            pass
        finally:
            with subs_lock:
                subs.discard(sub)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    p.add_argument("--upstream", default=DEFAULT_UPSTREAM)
    p.add_argument("--replay", metavar="FILE", help="Replay a captured .sse / JSONL file")
    p.add_argument(
        "--pace",
        type=float,
        default=0.05,
        help="Seconds between replay lines (default 0.05)",
    )
    args = p.parse_args()

    if args.replay:
        t = threading.Thread(
            target=ingest_replay, args=(args.replay, args.pace), daemon=True
        )
    else:
        t = threading.Thread(target=ingest_live, args=(args.upstream,), daemon=True)
    t.start()

    print(f"listening on 0.0.0.0:{args.port}", flush=True)
    Server(("0.0.0.0", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
