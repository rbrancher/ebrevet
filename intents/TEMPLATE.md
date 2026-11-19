---
id: "0000"
title: Short imperative title
status: draft            # draft | approved | in-progress | in-review | done | rejected | blocked
requested_by: github-handle
issue: null              # GitHub issue number, or null for hand-written intents
priority: medium         # low | medium | high
size: S                  # S | M | L  (L should usually be split)
risk: low                # low | medium | high  (high = touches check-in/codes/persistence)
touches:                 # files or areas expected to change
  - lib/event_card.dart
---

## Problem
What is wrong or missing today, from the rider's or organizer's point of view.

## User story
As a <rider | organizer | volunteer>, I want <capability> so that <outcome>.

## Acceptance criteria
Each item must be verifiable by an automated test (unit or widget) or by a
concrete check in the web preview (mock mode).

- [ ] AC1: ...
- [ ] AC2: ...

## Out of scope
- ...

## Test plan
Which tests will be added or changed, and what the reviewer should click in the preview.

## UI notes
Optional: wording, placement, screenshots/sketches.
