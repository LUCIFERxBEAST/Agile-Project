---
name: checkpoint
description: Save current session state to disk before compacting or clearing context, so nothing is lost.
---

# /checkpoint

Run this before `/compact` or starting a new session on the same feature.

1. Look back over this session's work and produce a concise summary covering:
   - **Goal**: what the task was.
   - **Done**: what's been completed and verified working.
   - **In progress**: what's half-done, including the exact next step.
   - **Decisions**: any non-obvious choices made and why (so they aren't
     silently re-litigated later).
   - **Files touched**: list of paths, one line each.
   - **Open questions / TODOs**: anything still unresolved.

2. Write that summary to `.agents/memory/checkpoint-<feature-name>.md`,
   creating the `.agents/memory/` directory if it doesn't exist. Overwrite
   the same file if one already exists for this feature — don't pile up
   duplicates.

3. If the project uses Antigravity Knowledge Items, also save the
   "Decisions" and "In progress / next step" sections as a Knowledge Item so
   it's available automatically in future sessions without needing to
   re-read the checkpoint file.

4. Confirm to the user in one or two lines what was saved and where, then
   stop — don't continue the coding task in the same turn.
