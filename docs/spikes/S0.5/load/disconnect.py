"""S0.5: clients that leave in the middle of a verify.

Each of N threads loops for D seconds: open a connection, POST /login, then either leave
before the answer (after a random 0..LEAVE_MS, half with a FIN and half with an RST), or read
the answer and send a /ui/ping on the same connection (so a kept-alive connection serves the
next request after a deferred one). Prints the status counts as JSON.

    python3 disconnect.py HOST PORT THREADS SECONDS [LEAVE_MS] [LEAVE_SHARE]
"""
import json, random, socket, struct, sys, threading, time
from collections import Counter

host, port = sys.argv[1], int(sys.argv[2])
threads, seconds = int(sys.argv[3]), float(sys.argv[4])
leave_ms = float(sys.argv[5]) if len(sys.argv) > 5 else 300
leave_share = float(sys.argv[6]) if len(sys.argv) > 6 else 0.7

BODY = b"user=alice&pass=correct%20horse%20battery%20staple"
LOGIN = (b"POST /login HTTP/1.1\r\nHost: s05\r\nContent-Type: application/x-www-form-urlencoded\r\n"
         b"Content-Length: " + str(len(BODY)).encode() + b"\r\n\r\n" + BODY)
PING = b"GET /ui/ping HTTP/1.1\r\nHost: s05\r\n\r\n"

counts = Counter()
lock = threading.Lock()


def read_response(s):
    """Reads one response (Content-Length bodies only); returns the status code."""
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            raise ConnectionError("closed before the headers")
        buf += chunk
    head, rest = buf.split(b"\r\n\r\n", 1)
    status = int(head.split(b" ", 2)[1])
    length = 0
    for line in head.split(b"\r\n")[1:]:
        k, _, v = line.partition(b":")
        if k.strip().lower() == b"content-length":
            length = int(v.strip())
    while len(rest) < length:
        chunk = s.recv(4096)
        if not chunk:
            raise ConnectionError("closed in the body")
        rest += chunk
    return status


def client(seed):
    rnd = random.Random(seed)
    local = Counter()
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            s = socket.create_connection((host, port), timeout=10)
            s.sendall(LOGIN)
            if rnd.random() < leave_share:
                time.sleep(rnd.random() * leave_ms / 1000)
                if rnd.random() < 0.5:
                    # RST instead of FIN: SO_LINGER on, timeout 0.
                    s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
                    local["left_rst"] += 1
                else:
                    local["left_fin"] += 1
                s.close()
                continue
            local["login_%d" % read_response(s)] += 1
            s.sendall(PING)
            local["ping_%d" % read_response(s)] += 1
            s.close()
        except Exception as e:  # noqa: BLE001 - a refused or reset connection is a result too
            local["error_" + type(e).__name__] += 1
    with lock:
        counts.update(local)


ts = [threading.Thread(target=client, args=(i,)) for i in range(threads)]
for t in ts:
    t.start()
for t in ts:
    t.join()
print(json.dumps(dict(sorted(counts.items()))))
