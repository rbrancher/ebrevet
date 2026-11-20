#!/usr/bin/env python3
"""Intent file tooling for the eBrevet AI-SDLC harness.

Intents have no status field. Their state comes from git and GitHub:
  open intent/* PR         proposed (gate 1 pending); closed unmerged = rejected
  intent file on main      approved; merging the intent PR is the approval
  agent/<slug> merged      built (done)

Usage:
  intents.py validate [FILES...]   validate frontmatter + required sections (default: all intents)
  intents.py added BASE HEAD       print intent paths added between two commits (new approvals)
  intents.py built FILE [REV]      exit 0 if the intent's agent PR is merged into REV (default HEAD)
  intents.py next-id               print the next free 4-digit id
  intents.py for-issue N           print intents linked to issue N: path, built|pending, final_slice
  intents.py field FILE KEY        print one frontmatter field
  intents.py index                 print a markdown table of all intents

"Built" is read from git history, so callers in CI need a full clone (fetch-depth: 0).
It recognises a merge commit ("Merge pull request #N from <owner>/agent/<slug>") or a
squash commit (subject "<id>: <title> (#N)", the agent PR title). Rebase merges leave
no marker, so do not rebase-merge agent PRs.

No third-party dependencies: the frontmatter subset used by intents is parsed by hand.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INTENTS = ROOT / "intents"

ENUMS = {
    "priority": {"low", "medium", "high"},
    "size": {"S", "M", "L"},
    "risk": {"low", "medium", "high"},
    "final_slice": {"true", "false"},
}
REQUIRED_FIELDS = ["id", "title", "requested_by", "issue", "final_slice",
                   "priority", "size", "risk", "touches"]
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
    if "status" in data:
        errs.append(f"{path}: remove the 'status' field; merging the intent PR approves it "
                    "and the merged agent PR marks it built")
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


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True,
                          check=True).stdout


def added(base, head):
    for rel in git("diff", "--name-only", "--diff-filter=A", base, head, "--", "intents/").split():
        if NAME_RE.match(Path(rel).name):
            print(rel)


def is_built(path, rev="HEAD"):
    name = Path(path).name
    slug, iid = name[:-3], NAME_RE.match(name).group(1)
    pattern = (rf"^Merge pull request #[0-9]+ from [^ /]+/agent/{re.escape(slug)}$"
               rf"|^{iid}: .* \(#[0-9]+\)$")
    return bool(git("log", rev, "-E", "--format=%H", f"--grep={pattern}").strip())


def main(argv):
    if not argv:
        sys.exit(__doc__)
    cmd, args = argv[0], argv[1:]
    if cmd == "validate":
        files = args or [str(p) for p in all_intents()]
        errs = [e for f in files for e in validate(f)]
        print("\n".join(errs) if errs else f"ok: {len(files)} intent(s)")
        sys.exit(1 if errs else 0)
    elif cmd == "added":
        added(*args)
    elif cmd == "built":
        sys.exit(0 if is_built(*args) else 1)
    elif cmd == "next-id":
        ids = [int(NAME_RE.match(p.name).group(1)) for p in all_intents()]
        print(f"{(max(ids) if ids else 0) + 1:04d}")
    elif cmd == "for-issue":
        for p in all_intents():
            d, _ = load(p)
            if str(d.get("issue")) == args[0]:
                state = "built" if is_built(p) else "pending"
                print(f"intents/{p.name}\t{state}\t{d.get('final_slice')}")
    elif cmd == "field":
        print(load(args[0])[0].get(args[1], ""))
    elif cmd == "index":
        print("| id | title | built | size | risk | issue | final |\n|---|---|---|---|---|---|---|")
        for p in all_intents():
            d, _ = load(p)
            built = "yes" if is_built(p) else "no"
            print(f"| [{d.get('id')}]({p.name}) | {d.get('title')} | {built} "
                  f"| {d.get('size')} | {d.get('risk')} | {d.get('issue')} | {d.get('final_slice')} |")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
