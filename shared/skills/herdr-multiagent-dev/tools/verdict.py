"""Read a role session's verdict from its log.

The contract is an independent line: the last line of the report carries the
verdict and nothing else. Scan from the bottom so the prompt's own echo -- which
contains the verdict words as part of its instructions -- is never mistaken for
the answer. `grep <word> | tail -1` is exactly the mistake this exists to avoid.

usage: verdict.py <log>
prints the verdict and exits 0, or prints 判定不明 and exits 1.
"""

import re
import sys

# Plain 合格/不合格 (herdr-multiagent-dev) and the classified form
# (code-perfection-multiagent). A bare 不合格 means the classification is
# missing -- the caller treats that as 不合格:内部構造.
VERDICT = re.compile(
    r"^[•\-*\s]*(合格|不合格[:：](?:内部構造|API境界|要求前提)|不合格)[。．\s]*$"
)
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verdict.py <log>", file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    for line in reversed(lines):
        m = VERDICT.match(ANSI.sub("", line))
        if m:
            print(m.group(1))
            return 0
    print("判定不明")
    return 1


if __name__ == "__main__":
    sys.exit(main())
