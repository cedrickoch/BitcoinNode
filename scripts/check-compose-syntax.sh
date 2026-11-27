#!/bin/sh
# Check the YAML flow-sequence syntax of compose files without needing a daemon.
#
# Exists because `docker compose config` is the only other thing that catches
# this, and it needs Docker: a stray unescaped double quote inside a quoted
# flow-scalar (e.g. a healthcheck with an embedded " in it) slips past review and
# fails at `up` time with "must be a string".
#
# Exit codes: 0 clean, 1 syntax problem, 2 usage problem.
#
# Usage: scripts/check-compose-syntax.sh [file ...]   (default: docker-compose*.yml)

set -eu

cd "$(dirname "$0")/.."

if [ "$#" -eq 0 ]; then
    set -- $(ls docker-compose*.yml 2>/dev/null)
fi
[ "$#" -gt 0 ] || { echo "no compose files found" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 2; }

exec python3 - "$@" <<'PY'
import re
import sys

QUOTES = "\"'"
SQ = "'"


def check_file(path: str) -> int:
    bad = 0
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            m = re.match(r"^(\s*)test:\s*(\[.*)$", line.rstrip("\n"))
            if not m:
                continue
            text = m.group(2)
            quote = None
            depth = 0
            items: list[str] = []
            cur = ""
            closed = False
            i = 0
            while i < len(text):
                ch = text[i]
                if quote:
                    if ch == "\\":
                        cur += ch + (text[i + 1] if i + 1 < len(text) else "")
                        i += 2
                        continue
                    if ch == quote:
                        quote = None
                        closed = True
                        cur += ch
                        nxt = text[i + 1] if i + 1 < len(text) else ""
                        # After a closing quote only a separator may follow.
                        if nxt and nxt not in " \t,]":
                            print(f"{path}:{lineno}  element ends at {nxt!r}, so it is not a string")
                            bad = 1
                        i += 1
                        continue
                    cur += ch
                    i += 1
                    continue
                if ch in QUOTES:
                    quote = ch
                    closed = False
                    cur += ch
                    i += 1
                    continue
                if ch == "[":
                    depth += 1
                    i += 1
                    continue
                if ch == "]":
                    depth -= 1
                    i += 1
                    continue
                if ch == "," and depth == 1:
                    items.append(cur.strip())
                    cur = ""
                    i += 1
                    continue
                cur += ch
                i += 1

            if quote:
                print(f"{path}:{lineno}  unterminated quote")
                bad = 1
            if closed:
                items.append(cur.strip())

            for item in items:
                if not item:
                    continue
                body = item[1:-1] if len(item) > 1 else item
                is_dq = item[0] == '"' and item[-1] == '"' and '"' not in body.replace('\\"', "")
                is_sq = item[0] == SQ and item[-1] == SQ and SQ not in body
                is_plain = re.fullmatch(r"[A-Za-z0-9_./:-]+", item) is not None
                if not (is_dq or is_sq or is_plain):
                    print(f"{path}:{lineno}  element is not a scalar: {item!r}")
                    bad = 1
    return bad


fail = 0
for name in sys.argv[1:]:
    try:
        fail |= check_file(name)
    except FileNotFoundError:
        print(f"missing {name}")
        fail = 1

print("OK: flow-sequence syntax" if not fail else "FAIL: fix the lines above")
sys.exit(1 if fail else 0)
PY
