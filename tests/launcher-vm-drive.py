# SPDX-License-Identifier: MIT
"""Drive a QEMU guest: read the serial output from a file, send keys over QMP.

usage: launcher-vm-drive.py OUTFILE QMPSOCK TRANSCRIPT TIMEOUT EXPECT SEND [EXPECT SEND ...]

QEMU writes the guest's serial console to OUTFILE (-serial file:OUTFILE)
and exposes a QMP socket at QMPSOCK. For each (EXPECT, SEND) pair this
waits until EXPECT appears in OUTFILE, then injects SEND as keystrokes
via QMP `send-key`. A separate output file avoids the flush/buffering
problems a bidirectional unix-socket chardev has with OVMF: the guest's
bytes hit the file as they are written, and input goes the other way
entirely.

SEND is a small language: `\\r` is Enter, any other single character is
that key. Only the characters the tests need are mapped (letters,
digits, space, `-`, Enter). OUTFILE keeps ANSI escapes; TRANSCRIPT is a
copy with them stripped. Exits 1 if any single EXPECT does not appear
within TIMEOUT seconds of the previous step (TCG boots are slow, so the
budget is per step, not shared); exits 0 once the last SEND is injected.
"""

import json
import re
import socket
import sys
import time

ANSI = re.compile(rb"\x1b\[[0-9;?=]*[A-Za-z]")

# QMP key names for the characters the tests send.
QCODE = {
    " ": "spc",
    "-": "minus",
    "\r": "ret",
    "\n": "ret",
}
for _c in "abcdefghijklmnopqrstuvwxyz":
    QCODE[_c] = _c
for _c in "0123456789":
    QCODE[_c] = _c


class Qmp:
    def __init__(self, path: str, deadline: float) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        while True:
            try:
                self.sock.connect(path)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.5)
        self.f = self.sock.makefile("rwb")
        self._readline()  # greeting
        self._cmd({"execute": "qmp_capabilities"})

    def _readline(self) -> dict:
        return json.loads(self.f.readline())

    def _cmd(self, obj: dict) -> None:
        self.f.write((json.dumps(obj) + "\r\n").encode())
        self.f.flush()
        while True:
            reply = self._readline()
            if "event" in reply:
                continue
            return

    def send(self, text: str) -> None:
        for ch in text.replace("\\r", "\r"):
            code = QCODE.get(ch)
            if code is None:
                continue
            self._cmd(
                {
                    "execute": "send-key",
                    "arguments": {"keys": [{"type": "qcode", "data": code}]},
                }
            )
            time.sleep(0.05)


def main() -> int:
    outfile, qmpsock, transcript = sys.argv[1], sys.argv[2], sys.argv[3]
    timeout = float(sys.argv[4])
    steps = list(zip(sys.argv[5::2], sys.argv[6::2]))

    deadline = time.monotonic() + timeout
    qmp = Qmp(qmpsock, deadline)

    def read_all() -> bytes:
        try:
            with open(outfile, "rb") as fh:
                return fh.read()
        except FileNotFoundError:
            return b""

    for expect, send in steps:
        needle = expect.encode()
        step_deadline = time.monotonic() + timeout
        while needle not in read_all():
            if time.monotonic() > step_deadline:
                with open(transcript, "wb") as t:
                    t.write(ANSI.sub(b"", read_all()).replace(b"\r", b""))
                print(f"timed out waiting for {expect!r}", file=sys.stderr)
                return 1
            time.sleep(1.0)
        qmp.send(send)

    # Let the last keystroke take effect, then snapshot the transcript.
    time.sleep(2.0)
    with open(transcript, "wb") as t:
        t.write(ANSI.sub(b"", read_all()).replace(b"\r", b""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
