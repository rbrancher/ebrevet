#!/usr/bin/env python3
"""Intent file tooling for the eBrevet AI-SDLC harness.

Usage:
  intents.py validate [FILES...]        validate frontmatter + required sections (default: all intents)
  intents.py approved-changed BASE HEAD print intent paths whose status became 'approved' between two commits
  intents.py set-status FILE STATUS     rewrite the status field in place
  intents.py next-id                    print the next free 4-digit id
  intents.py index                      print a markdown table of all intents

No third-party dependencies: the frontmatter subset used by intents is parsed by hand.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INTENTS = ROOT / "intents"

STATUSES = {"draft", "approved", "in-progress", "in-review", "done", "rejected", "blocked"}
ENUMS = {
    "status": STATUSES,
    "priority": {"low", "medium", "high"},
    "size": {"S", "M", "L"},
    "risk": {"low", "medium", "high"},
}
REQUIRED_FIELDS = ["id", "title", "status", "requested_by", "issue", "priority", "size", "risk", "touches"]
REQUIRED_SECTIONS = ["Problem", "User story", "Acceptance criteria", "Out of scope", "Test plan"]
NAME_RE = re.compile(r"^(\d{4})-[a-z0-9]+(-[a-z0-9]+)*\.md$")


def split_frontmatter(text):
    if not text.startswith("---\n"):
        raise ValueError("missing frontmatter")
    end = text.find("\n---", 4)
    if end < 0:
        raise ValueError("unterminated frontmatter")
    return text[4:end], text[end + 4:]


def parse_frontmatter(fm):
    data, key = {}, None
    for raw in fm.splitlines():
        line = raw.split(" #", 1)[0].rstrip()
        if not line.strip():
            continue
        m = re.match(r"^([a-z_]+):\s*(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            data[key] = [] if val == "" else val.strip('"\'')
        elif line.lstrip().startswith("- ") and key and isinstance(data.get(key), list):
            data[key].append(line.lstrip()[2:].strip().strip('"\''))
        else:
            raise ValueError(f"unparseable frontmatter line: {raw!r}")
    return data


def load(path):
    text = Path(path).read_text()
    fm, body = split_frontmatter(text)
    return parse_frontmatter(fm), body


def validate(path):
    path = Path(path)
    errs = []
    m = NAME_RE.match(path.name)
    if not m:
        return [f"{path}: filename must look like NNNN-kebab-slug.md"]
    try:
        data, body = load(path)
    except ValueError as e:
        return [f"{path}: {e}"]
    for f in REQUIRED_FIELDS:
        if f not in data:
            errs.append(f"{path}: missing field '{f}'")
    for f, allowed in ENUMS.items():
        if f in data and data[f] not in allowed:
            errs.append(f"{path}: {f}={data[f]!r} not in {sorted(allowed)}")
    if data.get("id") and data["id"] != m.group(1):
        errs.append(f"{path}: id {data['id']!r} does not match filename prefix {m.group(1)!r}")
    if "touches" in data and not isinstance(data["touches"], list):
        errs.append(f"{path}: touches must be a list")
    for s in REQUIRED_SECTIONS:
        if not re.search(rf"^##\s+{re.escape(s)}\s*$", body, re.M):
            errs.append(f"{path}: missing section '## {s}'")
    ac = re.search(r"^##\s+Acceptance criteria\s*$(.*?)(?=^##\s|\Z)", body, re.M | re.S)
    if ac and not re.search(r"^- \[[ x]\] ", ac.group(1), re.M):
        errs.append(f"{path}: acceptance criteria need at least one '- [ ]' item")
    return errs


def all_intents():
    return sorted(p for p in INTENTS.glob("*.md") if NAME_RE.match(p.name))


def status_at(rev, relpath):
    try:
        text = subprocess.run(["git", "show", f"{rev}:{relpath}"], cwd=ROOT,
                              capture_output=True, text=True, check=True).stdout
        return parse_frontmatter(split_frontmatter(text)[0]).get("status")
    except (subprocess.CalledProcessError, ValueError):
        return None


def approved_changed(base, head):
    out = subprocess.run(["git", "diff", "--name-only", base, head, "--", "intents/"],
                         cwd=ROOT, capture_output=True, text=True, check=True).stdout
    for rel in out.split():
        if NAME_RE.match(Path(rel).name) and status_at(head, rel) == "approved" \
                and status_at(base, rel) != "approved":
            print(rel)


def set_status(path, status):
    if status not in STATUSES:
        sys.exit(f"bad status {status!r}")
    p = Path(path)
    text = p.read_text()
    new, n = re.subn(r"^status:\s*\S+", f"status: {status}", text, count=1, flags=re.M)
    if n != 1:
        sys.exit(f"{path}: no status field")
    p.write_text(new)


def main(argv):
    if not argv:
        sys.exit(__doc__)
    cmd, args = argv[0], argv[1:]
    if cmd == "validate":
        files = args or [str(p) for p in all_intents()]
        errs = [e for f in files for e in validate(f)]
        print("\n".join(errs) if errs else f"ok: {len(files)} intent(s)")
        sys.exit(1 if errs else 0)
    elif cmd == "approved-changed":
        approved_changed(*args)
    elif cmd == "set-status":
        set_status(*args)
    elif cmd == "next-id":
        ids = [int(NAME_RE.match(p.name).group(1)) for p in all_intents()]
        print(f"{(max(ids) if ids else 0) + 1:04d}")
    elif cmd == "index":
        print("| id | title | status | size | risk | issue |\n|---|---|---|---|---|---|")
        for p in all_intents():
            d, _ = load(p)
            print(f"| [{d.get('id')}]({p.name}) | {d.get('title')} | {d.get('status')} "
                  f"| {d.get('size')} | {d.get('risk')} | {d.get('issue')} |")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
