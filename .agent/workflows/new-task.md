---
name: new-task
description: Start a fresh, scoped task — reload relevant checkpoint/knowledge instead of carrying over unrelated context.
---

# /new-task

Use this at the start of a new feature/bugfix, or right after `/checkpoint`
when you want to keep working on the same feature in a clean session.

1. Ask the user (if not already obvious) which feature/checkpoint this task
   continues, if any.
2. If a matching file exists at `.agents/memory/checkpoint-<feature-name>.md`,
   read it first and treat its "In progress" and "Decisions" sections as the
   current ground truth — don't ask the user to re-explain what's already
   written there.
3. Create/reset `task.md` for the new task: goal, files likely touched,
   checklist of steps.
4. Do not pull in context from unrelated earlier tasks in this workspace.
   If something from an old task seems relevant, ask the user to confirm
   before including it.
