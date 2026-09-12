#!/usr/bin/env python3
"""Subscribe to the relay stream and measure connect, first byte, rate, and RTT."""
from __future__ import annotations

import socket
import sys
import threading
import time


def main() -> None:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <host> <port> [seconds]", file=sys.stderr)
        sys.exit(2)

    host, port = sys.argv[1], int(sys.argv[2])
    dur = int(sys.argv[3]) if len(sys.argv) > 3 else 120

    t_connect = time.perf_counter()
    sock = socket.create_connection((host, port), timeout=10)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    connect_ms = (time.perf_counter() - t_connect) * 1000

    pending: dict[bytes, float] = {}
    rtts: list[float] = []
    msgs = byts = 0
    first_byte: float | None = None
    start = time.time()
    stop = False

    def pinger() -> None:
        nonlocal stop
        seq = 0
        while not stop and time.time() - start < dur:
            seq += 1
            key = str(seq).encode()
            pending[key] = time.perf_counter()
            try:
                sock.sendall(b"PING %d\n" % seq)
            except OSError:
                return
            time.sleep(1)

    threading.Thread(target=pinger, daemon=True).start()

    try:
        for line in sock.makefile("rb"):
            now = time.perf_counter()
            if first_byte is None:
                first_byte = (now - t_connect) * 1000
            byts += len(line)
            if line.startswith(b"PONG"):
                parts = line.split()
                if len(parts) > 1:
                    t0 = pending.pop(parts[1], None)
                    if t0 is not None:
                        rtts.append((now - t0) * 1000)
            else:
                msgs += 1
            if time.time() - start > dur:
                break
    finally:
        stop = True
        try:
            sock.close()
        except OSError:
            pass

    rtts.sort()

    def pct(q: float) -> float:
        if not rtts:
            return float("nan")
        return rtts[min(int(len(rtts) * q), len(rtts) - 1)]

    fb = first_byte if first_byte is not None else float("nan")
    print(
        f"target={host}:{port} "
        f"connect={connect_ms:.1f}ms first_byte={fb:.1f}ms "
        f"msgs={msgs} rate={byts / dur / 1024:.1f}KiB/s "
        f"rtt_p50={pct(0.50):.2f}ms rtt_p95={pct(0.95):.2f}ms "
        f"rtt_p99={pct(0.99):.2f}ms"
    )


if __name__ == "__main__":
    main()
