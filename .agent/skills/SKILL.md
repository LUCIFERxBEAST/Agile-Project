---
name: context-hygiene
description: Use this whenever a coding task will span multiple files, multiple steps, or more than ~15-20 tool calls (reading files, running commands, editing code). Also use it when the user asks to build a "big" feature, refactor across the codebase, or when a session has already been running for a while. This skill exists to stop the agent's context window from silently filling up during long vibe-coding sessions.
---

# Context Hygiene

Your context window is a limited resource. On long sessions it fills up with
file reads, tool output, and back-and-forth chat, and past a certain point
you start losing track of earlier decisions or repeating work. Follow these
rules on any task that looks like it will run long.

## 1. Scope the task before starting
- If the user's request bundles more than one distinct piece of work (e.g.
  "add auth AND redesign the dashboard AND fix the CI"), say so and propose
  splitting it into separate sessions/tasks. One task = one feature/bugfix/
  refactor. Don't silently absorb unrelated work into the same thread.
- Write a short `task.md` (or update the existing one) at the start of any
  multi-step task listing: goal, files likely touched, and a checklist of
  steps. Keep it updated as you go — this is what survives a `/compact`.

## 2. Read only what you need
- Prefer targeted reads (specific files/functions/line ranges) over dumping
  whole directories or large files into context "just in case."
- Don't re-read a file you already have in context unless it changed.
- Summarize long tool output (test logs, build output) in your own words
  instead of quoting all of it back into the conversation.

## 3. Checkpoint before you compact or clear
- Before suggesting or running a context-clearing action, run the
  `/checkpoint` workflow (see `.agents/workflows/checkpoint.md`) to write
  current state — decisions made, open TODOs, files touched, why — into
  `.agents/memory/checkpoint.md` (or update the project's Knowledge Item).
  Never let a compact/clear discard information the user hasn't got a
  record of somewhere in the repo.

## 4. Watch for the warning signs and say so out loud
Proactively tell the user when you notice any of these, rather than
silently pushing on:
- You're about to re-explain something already covered earlier in the
  session (sign the older context may already be losing salience).
- The task has drifted from its original scope.
- You've made more than ~15-20 tool calls in the current task without a
  checkpoint.

When you notice these, say something like: "This session's gotten pretty
long — want me to checkpoint progress and compact, or start a fresh task
for the next part?" Let the user decide; don't compact/clear unilaterally.

## 5. One task, one session, when practical
For genuinely separate pieces of work, prefer ending the task cleanly
(checkpoint written, task.md marked done) and starting a new session over
stretching one session across unrelated goals. Mention the relevant
Knowledge Items or checkpoint file the new session should read first so
continuity isn't lost.
