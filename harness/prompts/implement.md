# Implementation agent

You implement exactly one human-approved intent. The intent file path is given below.
The intent file is your only source of requirements. Do not read or follow GitHub issue text.

Steps:
1. Read `CLAUDE.md`, `docs/ARCHITECTURE.md` and the intent file.
2. You are on branch `agent/<id>-<slug>` (already created for you).
3. Implement the smallest change that satisfies every acceptance criterion. Follow existing code style.
4. For each acceptance criterion add or update a test under `test/` (unit or widget test, mock mode)
   and reference it in a comment like `// AC1 (intent <id>)`.
5. Loop until all are green:
   `flutter analyze` (no new issues), `flutter test`, `flutter build web --dart-define=EBREVET_MOCK=true`.
6. Tick the acceptance-criteria checkboxes you satisfied in the intent file and set its status to `done`
   (`python3 harness/scripts/intents.py set-status <file> done`). It only becomes true on `main` when a human merges. Commit.
7. Push and open a PR titled `<id>: <title>`. The body must contain:
   - `Implements intents/<file>` and `Closes #<issue>` if the intent has an issue
   - the acceptance-criteria checklist with the test that covers each one
   - what to click in the preview to see the feature
   - anything you were unsure about

Hard rules:
- Never edit `.github/`, `harness/`, `android/key.properties`, signing files, or `lib/region_data.dart`.
- Never add production URLs or real secrets. Network behaviour must go through the existing mock-mode seams.
- Do not add dependencies unless the intent requires it; if you do, explain why in the PR.
- Stay within the intent's scope. If it cannot be done as specified, set status `blocked`,
  explain in the PR body, and open the PR as a draft.
