# AI-SDLC harness

```
issue (feature form) ──maintainer adds `request` label──▶ triage.yml
   triage agent writes intents/NNNN-slug.md (status: draft) and opens an intent PR
        │
   GATE 1: human edits the spec, sets `status: approved`, merges
        │
   build-loop.yml (push to main touching intents/**)
   implement agent on agent/NNNN-slug: code + tests, then analyze/test/build web, then open a PR
        │
   ci.yml (analyze, test, mock-mode web build) ──▶ Cloudflare Pages preview pr-<n>, URL posted as a sticky comment
   pr-review.yml (advisory AI review against the acceptance criteria)
   fix-loop.yml  (CI red or maintainer "@claude ..." ──▶ agent fixes, max 3 attempts, then `needs-human`)
        │
   GATE 2: human merges, and the intent ends up `status: done` on main
```

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

## Intent status
`draft` (triage) → `approved` (gate 1, merged to main) → `done` (set in the agent PR, true once merged).
`blocked` means the agent could not finish. `rejected` means a human declined it.
In-flight work is visible as open `agent/*` PRs. Run `python3 harness/scripts/intents.py index` for a table.
