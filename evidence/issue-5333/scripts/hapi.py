#!/usr/bin/env python3
"""Minimal herdr raw socket API client for #5333 sandbox repros.

Speaks the documented newline-delimited JSON protocol over the unix socket
(docs: Socket API). One request per line; responses carry the same `id`.
"""
from __future__ import annotations

import json
import socket
import sys
import time


class HerdrApi:
    def __init__(self, sock_path: str, timeout: float = 10.0):
        self.sock_path = sock_path
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout)
        self.sock.connect(sock_path)
        self._buf = b""
        self._req_id = 0

    def request(self, method: str, params: dict | None = None, timeout: float | None = None):
        self._req_id += 1
        rid = f"py_{self._req_id}"
        req = {"id": rid, "method": method, "params": params or {}}
        if timeout is not None:
            self.sock.settimeout(timeout)
        self.sock.sendall((json.dumps(req) + "\n").encode())
        while True:
            while b"\n" not in self._buf:
                chunk = self.sock.recv(65536)
                if not chunk:
                    raise ConnectionError("socket closed")
                self._buf += chunk
            line, self._buf = self._buf.split(b"\n", 1)
            msg = json.loads(line)
            if msg.get("id") == rid:
                return msg

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def burst(sock_path: str, method: str, params_list: list[dict]) -> tuple[int, float]:
    """Send many pipelined requests over ONE connection, drain all responses.

    Returns (count, elapsed_seconds). Used to overflow the 512-event hub ring
    faster than a waiting agent.wait connection can poll.
    """
    import time as _time

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(30.0)
    sock.connect(sock_path)
    n = len(params_list)
    payload = "".join(
        json.dumps({"id": f"burst_{i}", "method": method, "params": p}) + "\n"
        for i, p in enumerate(params_list)
    )
    t0 = _time.monotonic()
    sock.sendall(payload.encode())
    got = b""
    while got.count(b"\n") < n:
        chunk = sock.recv(65536)
        if not chunk:
            break
        got += chunk
    elapsed = _time.monotonic() - t0
    sock.close()
    return got.count(b"\n"), elapsed


def parallel(sock_path: str, method: str, params_list: list[dict], threads: int) -> tuple[int, float]:
    """Fire requests over many concurrent short-lived connections.

    The raw API serves one request per connection; this opens `threads`
    connections in parallel, each issuing a slice of params_list sequentially.
    """
    import threading
    import time as _time

    chunks = [params_list[i::threads] for i in range(threads)]
    done = [0] * threads

    def worker(idx: int, chunk: list[dict]) -> None:
        for p in chunk:
            try:
                api = HerdrApi(sock_path, timeout=10.0)
                resp = api.request(method, p)
                if "result" in resp:
                    done[idx] += 1
                api.close()
            except OSError:
                return

    t0 = _time.monotonic()
    workers = [threading.Thread(target=worker, args=(i, c)) for i, c in enumerate(chunks)]
    for w in workers:
        w.start()
    for w in workers:
        w.join()
    return sum(done), _time.monotonic() - t0


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: hapi.py SOCK_PATH METHOD [PARAMS_JSON]", file=sys.stderr)
        print("       hapi.py SOCK_PATH burst METHOD N  (alternating workspace renames)", file=sys.stderr)
        return 2
    sock_path, method = sys.argv[1], sys.argv[2]
    if method == "burst":
        api_method, count = sys.argv[3], int(sys.argv[4])
        params_list = [
            {"workspace_id": "w1", "label": f"burst-{'a' if i % 2 else 'b'}-{i}"}
            for i in range(count)
        ]
        done, elapsed = burst(sock_path, api_method, params_list)
        print(json.dumps({"responses": done, "elapsed_s": round(elapsed, 3)}))
        return 0 if done == count else 1
    if method == "parallel":
        api_method, count, nthreads = sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
        params_list = [
            {"workspace_id": "w1", "label": f"race-{'a' if i % 2 else 'b'}-{i}"}
            for i in range(count)
        ]
        done, elapsed = parallel(sock_path, api_method, params_list, nthreads)
        print(json.dumps({"responses": done, "elapsed_s": round(elapsed, 3)}))
        return 0 if done == count else 1
    params = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
    api = HerdrApi(sock_path)
    try:
        resp = api.request(method, params)
    finally:
        api.close()
    print(json.dumps(resp))
    return 0 if "result" in resp else 1


if __name__ == "__main__":
    sys.exit(main())
