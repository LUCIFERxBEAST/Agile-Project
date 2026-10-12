# Antigravity Context Kit

One Skill + two Workflows for keeping vibe-coding sessions in Antigravity
from filling up their context window.

## Install

Copy the folders to the right place, either globally (all projects) or
per-project:

**Global** (available everywhere):
```
skills/context-hygiene/   -> ~/.gemini/config/skills/context-hygiene/
workflows/checkpoint.md   -> ~/.gemini/config/workflows/checkpoint.md
workflows/new-task.md     -> ~/.gemini/config/workflows/new-task.md
```

**Per-project** (only this repo):
```
skills/context-hygiene/   -> .agents/skills/context-hygiene/
workflows/checkpoint.md   -> .agents/workflows/checkpoint.md
workflows/new-task.md     -> .agents/workflows/new-task.md
```

(Older Antigravity builds used `~/.gemini/antigravity/skills/` for global
skills instead of `~/.gemini/config/skills/` — if the first path doesn't
exist on your machine, check Settings for the exact folder, or just try
both.)

## Do you have to invoke these every message?

No, and yes — differently for each:

- **`context-hygiene` is a Skill.** Skills load themselves automatically.
  Antigravity reads the `description` in the frontmatter and pulls the
  skill into context on its own when your request matches — e.g. a
  multi-file refactor. You never type its name in chat.

- **`/checkpoint` and `/new-task` are Workflows.** Workflows are on-demand
  templates — normally you trigger them with the slash command
  (`/checkpoint`) when you want them to run right now, once, in that turn.
  You do need to type `/checkpoint` (or `/new-task`) each time you want one
  to run — Antigravity doesn't guess when to compact/clear on its own.
  That said, once the `context-hygiene` skill is loaded it's instructed to
  *tell you* when it's a good moment to run `/checkpoint`, so you don't
  have to remember the timing yourself, just approve it. And plenty of
  people just describe it in plain English ("save where we're at before we
  compact") — Antigravity is generally able to dispatch the matching
  workflow from that.

## Typical loop
1. Work on a feature normally.
2. When `context-hygiene` flags the session is getting long, run
   `/checkpoint`.
3. Run Antigravity's own `/compact` (or start a new chat) once the
   checkpoint file is saved.
4. Run `/new-task` to resume — it reads the checkpoint back in so you don't
   have to re-explain anything.

## Good free skill resources worth grabbing
- **Google's own codelab** — the official walkthrough for setting up
  Skills/Workflows/Knowledge Items from scratch:
  https://codelabs.developers.google.com/getting-started-google-antigravity
- **AG Kit** (vudovn/ag-kit, MIT license, free) — a large, actively updated
  pack of 45+ ready-made skills, 20 specialist "agent" personas, and 13
  orchestration workflows (React, Next.js, FastAPI, Prisma, Docker, testing,
  security review, etc.) with built-in persistent memory and context
  compression — built specifically for Antigravity's `.agents/` layout, so
  it sits right alongside this kit:
  https://github.com/vudovn/ag-kit
  To use it, run this inside your project folder:
  ```
  npx @vudovn/ag-kit init
  ```
  That drops a `.agents/` folder into the project with everything wired up
  (or install globally once with `npm install -g @vudovn/ag-kit` and reuse
  it across projects via symlinks — see the repo's README for that).
