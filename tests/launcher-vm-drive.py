# SPDX-License-Identifier: MIT
"""Drive a QEMU serial console over a unix socket.

usage: launcher-vm-drive.py SOCKET TRANSCRIPT TIMEOUT EXPECT SEND [EXPECT SEND ...]

Connects to QEMU's serial chardev socket, then for each (EXPECT, SEND)
pair waits until EXPECT appears in the stream and writes SEND (with
\\r for Enter). Everything read is appended to TRANSCRIPT, ANSI escape
sequences stripped. Exits 1 if any EXPECT does not show up within
TIMEOUT seconds; exits 0 once the last SEND is written and the peer
closes (or the timeout passes while draining).
"""

import re
import socket
import sys
import time

ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")


def main() -> int:
    sock_path, transcript, timeout = sys.argv[1], sys.argv[2], float(sys.argv[3])
    steps = list(zip(sys.argv[4::2], sys.argv[5::2]))
    deadline = time.monotonic() + timeout

    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    while True:
        try:
            conn.connect(sock_path)
            break
        except OSError:
            if time.monotonic() > deadline:
                print(f"timed out connecting to {sock_path}", file=sys.stderr)
                return 1
            time.sleep(0.5)
    conn.settimeout(1.0)

    buf = b""
    with open(transcript, "ab") as log:

        def read_some() -> bool:
            nonlocal buf
            try:
                chunk = conn.recv(4096)
            except TimeoutError:
                return True
            if not chunk:
                return False
            buf += chunk
            log.write(ANSI.sub(b"", chunk).replace(b"\r", b""))
            log.flush()
            return True

        for expect, send in steps:
            needle = expect.encode()
            while needle not in buf:
                if time.monotonic() > deadline:
                    print(f"timed out waiting for {expect!r}", file=sys.stderr)
                    return 1
                if not read_some():
                    print(f"peer closed while waiting for {expect!r}", file=sys.stderr)
                    return 1
            buf = buf[buf.index(needle) + len(needle) :]
            conn.sendall(send.encode().replace(b"\\r", b"\r"))
            # Give the guest a moment to echo before the next expectation.
            time.sleep(0.5)

        while time.monotonic() < deadline:
            if not read_some():
                break
    return 0


if __name__ == "__main__":
    sys.exit(main())
