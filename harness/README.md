# AI-SDLC harness

```
issue (feature form) ──maintainer adds `request` label──▶ triage.yml
   triage agent writes intents/NNNN-slug.md and opens an intent PR
        │
   GATE 1: human edits the spec and merges (approve), or closes the PR (reject)
        │
   build-loop.yml (push to main that adds a new intent file)
   implement agent on agent/NNNN-slug: code + tests, then analyze/test/build web, then open a PR
        │
   ci.yml (analyze, test, mock-mode web build) ──▶ Cloudflare Pages preview pr-<n>, URL posted as a sticky comment
   pr-review.yml (advisory AI review against the acceptance criteria)
   fix-loop.yml  (CI red or maintainer "@claude ..." ──▶ agent fixes, max 3 attempts, then `needs-human`)
        │
   GATE 2: human merges the agent PR, and the intent counts as built
        │
   continue-slices.yml: if the intent has `final_slice: false`, re-run triage on the issue
   ──▶ the next slice's intent PR (back to GATE 1). The last slice's PR closes the issue.
```

## Multi-slice requests
Triage splits a large request into slices, in order. Each intent's "Out of scope" section lists the
slices still to come, and its `final_slice` field says whether more follow.
- Non-final slices' PRs say `Refs #N`, so the issue stays open.
- When one merges, `continue-slices.yml` dispatches triage again.
- Triage drafts the next slice against the code that actually merged.
- The final slice's PR says `Closes #N`.

You can also re-trigger triage by hand with a `/triage` comment on the issue, or with
`gh workflow run triage.yml -f issue=N`.

## One-time setup
1. **Secrets:**
   - `CLAUDE_CODE_OAUTH_TOKEN`: from `claude setup-token`. You can switch to `anthropic_api_key` in the workflows instead.
   - `CLOUDFLARE_API_TOKEN`: needs Pages:Edit.
   - `CLOUDFLARE_ACCOUNT_ID`
2. **Variables (optional):** `CF_PAGES_PROJECT`, `TRIAGE_MODEL`, `IMPLEMENT_MODEL`, `REVIEW_MODEL`.
3. **Claude GitHub App.** Install it on the repo, for example by running `/install-github-app` in Claude Code. PRs the agents open then trigger CI. PRs opened with the default `GITHUB_TOKEN` do not.
4. **Cloudflare Pages.** Create the project once: `npx wrangler pages project create ebrevet --production-branch main`.
5. **Labels:** `request`, `needs-human`.
6. **Branch protection on `main`:**
   - require a PR and 1 approval
   - require the `ci` check
   - require a review from Code Owners
   - disallow force-push

## Intent state
Intents have no status field. Their state comes from git and GitHub, so it cannot drift:

| State | Signal |
|---|---|
| proposed | open `intent/*` PR (gate 1 pending) |
| rejected | intent PR closed without merging; `intent-rejected.yml` comments on the issue |
| approved | the intent file is on `main`; adding it there starts the build loop |
| building / in review | running `build-loop` job, or an open `agent/*` PR |
| stuck | `needs-human` label on the agent PR |
| built | the `agent/<slug>` PR is merged |

- Editing an intent already on `main` never starts a build. To rebuild one, run
  `gh workflow run build-loop.yml -f intent=intents/NNNN-slug.md` (refused if already built).
- "Built" is read from git history: a merge commit from `agent/<slug>`, or a squash commit
  titled `<id>: … (#N)`. Do not rebase-merge agent PRs; that leaves no marker.
- To park an approved idea without building it, leave its intent PR open (or in draft).
- `python3 harness/scripts/intents.py index` prints a table; `for-issue N` lists an issue's slices.
