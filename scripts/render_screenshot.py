#!/usr/bin/env python3
"""Render a cctree SVG screenshot from a synthetic session tree.

Creates a throwaway Claude project under ~/.claude/projects/-tmp-cctree-demo,
drops fabricated JSONL files describing a fake branch tree, runs the real
cctree binary against that path, converts its ANSI output to SVG, and then
cleans up. No real session data is touched.
"""
import json
import os
import pty
import re
import select
import shutil
import signal
import sys
import time
import uuid
from html import escape

# Solarized-ish dark palette, close to what most terminals render
PALETTE = {
    "fg":     "#d0d0d0",
    "bg":     "#1e1e1e",
    "dim":    "#888888",
    "cyan":   "#5fd7d7",
    "green":  "#a6e22e",
    "yellow": "#e6db74",
    "bold":   "#ffffff",
}

ANSI_CSI = re.compile(r"\x1b\[([0-9;?]*)([a-zA-Z])")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CCTREE_BIN = os.path.join(REPO_ROOT, "cctree")


def _sid(prefix_hex):
    """Build a full UUID whose first 8 chars match the desired prefix."""
    rest = uuid.uuid4().hex
    return f"{prefix_hex}-{rest[:4]}-{rest[4:8]}-{rest[8:12]}-{rest[12:24]}"


# Shape: list of (sid_prefix, title, parent_prefix_or_None, minutes_ago)
# Titles are short, generic, and deliberately non-identifying.
TREE_SPEC = [
    ("a91f3c08", "feature/auth-rewrite",          None,       195),
    ("5e2c4d71", "postgres native roles",         "a91f3c08", 170),
    ("bc8a6e19", "add rls tests",                 "5e2c4d71", 140),
    ("7d43f2b0", "reconcile with middleware",     "a91f3c08", 100),
    ("3f6b1ea2", "bugfix/retry-jitter",           None,        85),
    ("d018497c", "cap backoff at 30s",            "3f6b1ea2",  60),
    ("9e5f2a34", "docs/onboarding-flow",          None,        25),
]

# Session rendered as "● active: X" in the cctree watch header and bold+reverse
# in the tree listing.
ACTIVE_PREFIX = "bc8a6e19"

FAKE_CWD = "/Users/sam/Code/my-app"


def _build_fake_project(proj_dir):
    """Write one JSONL per tree node under proj_dir. Set mtimes for ordering."""
    now = time.time()
    prefix_to_sid = {p: _sid(p) for p, *_ in TREE_SPEC}
    for prefix, title, parent_prefix, minutes_ago in TREE_SPEC:
        sid = prefix_to_sid[prefix]
        parent_sid = prefix_to_sid[parent_prefix] if parent_prefix else None
        ts = time.strftime(
            "%Y-%m-%dT%H:%M:%S.000Z",
            time.gmtime(now - minutes_ago * 60),
        )
        lines = [
            # Custom title — cctree's is_preamble() filters command tags, so
            # this plain string is what the tree will actually display.
            {
                "type": "custom-title",
                "sessionId": sid,
                "customTitle": title,
            },
            # Header user message carries cwd + forkedFrom.
            {
                "type": "user",
                "sessionId": sid,
                "cwd": FAKE_CWD,
                "timestamp": ts,
                "message": {"role": "user", "content": f"work on {title}"},
                **({"forkedFrom": {"sessionId": parent_sid, "messageUuid": uuid.uuid4().hex}}
                   if parent_sid else {}),
            },
        ]
        path = os.path.join(proj_dir, f"{sid}.jsonl")
        with open(path, "w") as fh:
            for d in lines:
                fh.write(json.dumps(d) + "\n")
        mtime = now - minutes_ago * 60
        os.utime(path, (mtime, mtime))
    return prefix_to_sid[ACTIVE_PREFIX]


def capture(cmd, env_overrides, timeout):
    env = os.environ.copy()
    env.update(env_overrides)
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe(cmd[0], cmd, env)
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                buf += os.read(fd, 8192)
            except OSError:
                break
    try:
        os.kill(pid, signal.SIGTERM)
    except Exception:
        pass
    try:
        os.waitpid(pid, 0)
    except Exception:
        pass
    return buf.decode("utf-8", errors="replace")


def parse_ansi(text):
    """Yield (char, fg_color_name, bold, reverse) tuples, skipping control seqs."""
    fg = "fg"
    bold = False
    reverse = False
    i = 0
    while i < len(text):
        m = ANSI_CSI.match(text, i)
        if m:
            params, final = m.group(1), m.group(2)
            if final == "m":
                codes = [int(x) for x in params.split(";") if x.isdigit()] or [0]
                for c in codes:
                    if c == 0:
                        fg, bold, reverse = "fg", False, False
                    elif c == 1:
                        bold = True
                    elif c == 2:
                        fg = "dim"
                    elif c == 7:
                        reverse = True
                    elif c == 22:
                        bold = False
                    elif c == 27:
                        reverse = False
                    elif c == 32:
                        fg = "green"
                    elif c == 33:
                        fg = "yellow"
                    elif c == 36:
                        fg = "cyan"
                    elif c == 39:
                        fg = "fg"
            i = m.end()
            continue
        ch = text[i]
        if ch == "\x0d":
            i += 1
            continue
        yield ch, fg, bold, reverse
        i += 1


def to_rows(events):
    rows = [[]]
    for ch, fg, bold, rev in events:
        if ch == "\n":
            rows.append([])
            continue
        rows[-1].append((ch, fg, bold, rev))
    return rows


def render_svg(rows, out_path, title="cctree"):
    cw = 8.4
    ch = 18
    pad_x = 16
    pad_y = 44
    max_cols = max((len(r) for r in rows), default=1)
    max_cols = max(max_cols, 54)
    width = int(pad_x * 2 + cw * max_cols)
    height = int(pad_y + ch * len(rows) + 16)

    out = []
    out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="13">')
    out.append(f'<rect x="0" y="0" width="{width}" height="{height}" rx="8" fill="{PALETTE["bg"]}"/>')
    out.append(f'<rect x="0" y="0" width="{width}" height="28" rx="8" fill="#2a2a2a"/>')
    out.append(f'<rect x="0" y="20" width="{width}" height="10" fill="#2a2a2a"/>')
    for i, col in enumerate(("#ff5f57", "#febc2e", "#28c840")):
        out.append(f'<circle cx="{16 + i*18}" cy="14" r="6" fill="{col}"/>')
    out.append(f'<text x="{width/2}" y="19" fill="#888" text-anchor="middle" font-size="11">{escape(title)}</text>')

    for ri, row in enumerate(rows):
        y = pad_y + ri * ch
        x = pad_x
        run_chars = []
        run_style = None

        def flush():
            nonlocal run_chars, x
            if not run_chars:
                return
            fg, bold, rev = run_style
            if rev:
                run_w = cw * len(run_chars)
                out.append(f'<rect x="{x:.1f}" y="{y - ch + 4:.1f}" width="{run_w:.1f}" height="{ch}" fill="{PALETTE["fg"]}"/>')
                text_fill = PALETTE["bg"]
            else:
                text_fill = PALETTE["bold"] if bold else PALETTE[fg]
            weight = ' font-weight="700"' if bold else ''
            text = "".join(run_chars)
            out.append(f'<text x="{x:.1f}" y="{y:.1f}" fill="{text_fill}"{weight}>{escape(text)}</text>')
            x += cw * len(run_chars)
            run_chars = []

        for ch_, fg, bold, rev in row:
            style = (fg, bold, rev)
            if style != run_style:
                flush()
                run_style = style
            run_chars.append(ch_)
        flush()

    out.append("</svg>")
    with open(out_path, "w") as f:
        f.write("\n".join(out))


def main():
    proj_dir = os.path.expanduser("~/.claude/projects/-tmp-cctree-demo")
    os.makedirs(proj_dir, exist_ok=True)
    # Start from a clean slate so prior runs don't leak sessions.
    for f in os.listdir(proj_dir):
        if f.endswith(".jsonl"):
            os.remove(os.path.join(proj_dir, f))

    try:
        active_sid = _build_fake_project(proj_dir)
        raw = capture(
            [
                CCTREE_BIN,
                "--path", FAKE_CWD,
                "--highlight", active_sid,
            ],
            env_overrides={"COLUMNS": "60", "LINES": "28", "TERM": "xterm-256color"},
            timeout=2.0,
        )
        rows = to_rows(parse_ansi(raw))
        while rows and not rows[0]:
            rows.pop(0)
        while rows and not rows[-1]:
            rows.pop()
        rows = rows[:24]

        out_path = os.path.join(REPO_ROOT, "assets", "screenshot.svg")
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        render_svg(rows, out_path)
        print(f"wrote {out_path}  ({len(rows)} rows)")
    finally:
        shutil.rmtree(proj_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
