"""Makes text from a proposal safe to show on a terminal, for review-deploy.

sanitize --color|--no-color [--diff]: stdin to stdout. Control characters (C0
but tab and newline, DEL, C1), invisible and bidi characters and bytes that are
not UTF-8 are written as visible placeholders (^[, <U+202E>, <FF>), so that
nothing from the input acts on the terminal or hides in it. The only escape
sequences in the output are then the colors added here, which is what makes it
safe to show with less -R.

--color highlights the placeholders and lines starting with "!!! ". --diff
colors the output of git log and git diff by line.
"""
import os
import re
import sys

UNSAFE = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f​-‏‪-‮⁦-⁩﻿\udc80-\udcff]")

RESET = "\x1b[0m"
BOLD = "\x1b[1m"
RED = "\x1b[31m"
GREEN = "\x1b[32m"
YELLOW = "\x1b[33m"
CYAN = "\x1b[36m"
WARNING = "\x1b[1;31m"
REVERSE, NO_REVERSE = "\x1b[7m", "\x1b[27m"

DIFF_HEADERS = (
    "index ", "--- ", "+++ ", "new file mode", "deleted file mode", "old mode",
    "new mode", "similarity index", "dissimilarity index", "rename from",
    "rename to", "copy from", "copy to", "Binary files",
)
STAT = re.compile(r"^( .* \| +\d+ )(\+*)(-*)$")


def placeholder(match):
    c = ord(match.group())
    if 0xdc80 <= c <= 0xdcff:
        return f"<{c - 0xdc00:02X}>"
    if c < 0x20 or c == 0x7f:
        return "^" + chr(c ^ 0x40)
    return f"<U+{c:04X}>"


class Diff:
    """Colors git log and diff output, line by line."""

    def __init__(self):
        self.in_hunk = False

    def style(self, line):
        if line.startswith("commit "):
            self.in_hunk = False
            return BOLD + YELLOW
        if line.startswith("diff --git "):
            self.in_hunk = False
            return BOLD
        if self.in_hunk and line[:1] in ("+", "-", " ", "\\"):
            return {"+": GREEN, "-": RED}.get(line[:1], "")
        self.in_hunk = False
        if line.startswith("@@"):
            self.in_hunk = True
            return CYAN
        if line.startswith(DIFF_HEADERS):
            return BOLD
        return ""


def main():
    color = sys.argv[1] == "--color"
    diff = Diff() if "--diff" in sys.argv[2:] else None
    out = sys.stdout.buffer
    try:
        for raw in sys.stdin.buffer:
            line = raw.decode("utf-8", "surrogateescape").rstrip("\n")
            if not color:
                out.write(UNSAFE.sub(placeholder, line).encode() + b"\n")
                continue
            style = diff.style(line) if diff else ""
            stat = STAT.match(line) if diff and not style and not diff.in_hunk else None
            text = UNSAFE.sub(lambda m: REVERSE + placeholder(m) + NO_REVERSE, line)
            if stat:
                text = UNSAFE.sub(lambda m: REVERSE + placeholder(m) + NO_REVERSE, stat.group(1)) \
                    + GREEN + stat.group(2) + RED + stat.group(3) + RESET
            elif line.startswith("!!! "):
                text = WARNING + text + RESET
            elif style:
                text = style + text + RESET
            out.write(text.encode() + b"\n")
        out.flush()
    except BrokenPipeError:
        # The pager was quit before the end
        os.dup2(os.open(os.devnull, os.O_WRONLY), out.fileno())


if __name__ == "__main__":
    main()
