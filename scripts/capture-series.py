#!/usr/bin/env python3
"""Capture per-second RTT + byte-rate samples for comparison charts.

Prints one JSON object to stdout:
  {target, connect_ms, first_byte_ms, seconds, samples:[{t,rtt_ms,rate_kib_s}],
   summary:{rtt_p50,rtt_p95,rtt_p99,rate_kib_s,msgs}}
"""
from __future__ import annotations

import json
import socket
import sys
import threading
import time


def pct(sorted_vals: list[float], q: float) -> float | None:
    if not sorted_vals:
        return None
    return sorted_vals[min(int(len(sorted_vals) * q), len(sorted_vals) - 1)]


def main() -> None:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <host> <port> [seconds]", file=sys.stderr)
        sys.exit(2)

    host, port = sys.argv[1], int(sys.argv[2])
    dur = int(sys.argv[3]) if len(sys.argv) > 3 else 60

    t_connect = time.perf_counter()
    sock = socket.create_connection((host, port), timeout=10)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    connect_ms = (time.perf_counter() - t_connect) * 1000

    pending: dict[bytes, float] = {}
    rtts: list[float] = []
    samples: list[dict] = []
    msgs = byts = 0
    first_byte: float | None = None
    start = time.time()
    stop = False
    window_byts = 0
    window_rtts: list[float] = []
    last_sample_t = 0.0

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
            elapsed = time.time() - start
            if first_byte is None:
                first_byte = (now - t_connect) * 1000
            byts += len(line)
            window_byts += len(line)
            if line.startswith(b"PONG"):
                parts = line.split()
                if len(parts) > 1:
                    t0 = pending.pop(parts[1], None)
                    if t0 is not None:
                        rtt = (now - t0) * 1000
                        rtts.append(rtt)
                        window_rtts.append(rtt)
            else:
                msgs += 1

            if elapsed - last_sample_t >= 1.0:
                bucket = elapsed
                rate = window_byts / max(elapsed - last_sample_t, 1e-6) / 1024
                rtt_s = sorted(window_rtts)
                samples.append(
                    {
                        "t": round(bucket, 1),
                        "rtt_ms": round(pct(rtt_s, 0.5) or float("nan"), 3)
                        if rtt_s
                        else None,
                        "rate_kib_s": round(rate, 2),
                    }
                )
                window_byts = 0
                window_rtts = []
                last_sample_t = elapsed

            if elapsed > dur:
                break
    finally:
        stop = True
        try:
            sock.close()
        except OSError:
            pass

    rtts_sorted = sorted(rtts)
    out = {
        "target": f"{host}:{port}",
        "connect_ms": round(connect_ms, 2),
        "first_byte_ms": round(first_byte, 2) if first_byte is not None else None,
        "seconds": dur,
        "samples": samples,
        "summary": {
            "msgs": msgs,
            "rate_kib_s": round(byts / dur / 1024, 2),
            "rtt_p50_ms": round(pct(rtts_sorted, 0.5) or float("nan"), 3)
            if rtts_sorted
            else None,
            "rtt_p95_ms": round(pct(rtts_sorted, 0.95) or float("nan"), 3)
            if rtts_sorted
            else None,
            "rtt_p99_ms": round(pct(rtts_sorted, 0.99) or float("nan"), 3)
            if rtts_sorted
            else None,
            "rtt_samples": len(rtts_sorted),
        },
    }
    print(json.dumps(out))


if __name__ == "__main__":
    main()
