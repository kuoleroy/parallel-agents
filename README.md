# parallel-agents

**Multiple AI agents writing one project at the same time — without stepping on each other.**

> 中文：[README.zh.md](README.zh.md) · 简体中文说明

<p align="center">
  <a href="https://github.com/kuoleroy/parallel-agents/actions/workflows/ci.yml"><img src="https://github.com/kuoleroy/parallel-agents/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/kuoleroy/parallel-agents/tags"><img src="https://img.shields.io/github/v/tag/kuoleroy/parallel-agents?label=release&color=blue" alt="latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
  <a href="https://agentskills.io"><img src="https://img.shields.io/badge/Agent_Skills-compatible-lightgrey" alt="Agent Skills standard"></a>
</p>

<p>
  <a href="docs/evidence.md"><strong>Verified: 10 violations injected, 10 blocked · compliant branch OK 12 / SKIP 0 / FAIL 0</strong></a>
</p>

An agent-agnostic playbook for running several AI coding agents on one project at once: freeze the contract first, schedule by dependency waves, isolate each agent in its own git worktree with a machine-checked file boundary, and merge only through a gate. Follows the [Agent Skills](https://agentskills.io) open standard — no platform feature, no MCP server, no slash command required.

---

## What you expect vs what happens

You have 3 AI windows and one project. Here is the actual outcome:

| You expect | You get |
|---|---|
| 3× the speed | The orchestrator resolves conflicts all day and becomes a human serialiser |
| Everyone writes their own files | Two agents edit the same file, one silently overwrites the other |
| Frontend and backend in parallel | Frontend writes `userId`, backend writes `user_id`, discovered at integration |
| Everyone installs deps | Port contention, dependency drift, lockfiles clobbering each other |
| Everyone says "done" | Nobody can produce a single command that proves it |

**Parallel development is not "open more windows". It is boundary and contract engineering.**

## The mechanism, verified

[`tests/run-test.sh`](tests/run-test.sh) builds a throwaway repo, creates real tasks in real worktrees, then injects the exact mistakes this method claims to prevent. No AI, no network, no token spend — a few seconds on your machine.

```
10 violations injected → 10 blocked; 11 positive assertions passed.
```

The most useful one is not a merge conflict. The contract says invalid pagination must return `400`; the agent wrote code that silently falls back to page 1. Boundaries are clean, the build is clean, git reports nothing:

```
-- boundary check (nothing changed outside the exclusive list)
  OK    no out-of-bounds · no intrusion · no frozen files touched
-- build
  OK    build passed
-- live HTTP probe
  OK    server started (pid 1557, port 21234)
  OK    health http://127.0.0.1:21234/api/health
  FAIL  boundary case expected 4xx, got 200
```

The gate's own words for that last line are `FAIL 边界用例期望 4xx，实际 200` — verdict strings are currently Chinese-only, see [Limits](#limits-stated-plainly).

And the probe refuses to borrow a server it did not start. If something is already listening on the task's port, the gate cannot know that process runs *this* branch, so it stops rather than issue a verdict:

```
-- live HTTP probe
  FAIL  port 21234 already has a service; the gate cannot confirm it runs this branch
```

That guard is not theoretical. It replaced a bug where the gate silently probed a leftover server and handed "passed" to the wrong build — and the fix itself needed a second round, because `kill $SERVE_PID` on Linux only reached the wrapper shell, not the grandchild still holding the port.

Three defects shipped that way, all caught by CI on a Linux runner after the same test had passed for weeks on the author's Windows machine: missing git exec bits (`Permission denied` for every macOS/Linux user), the borrowed server, and an unquoted expansion that silently disabled the frozen-file check. [`docs/evidence.md`](docs/evidence.md) documents all three. Running your checks on one machine is how you ship a green test and a broken tool.

And when a task edits inside another live task's boundary, it names the owner:

```
      src/api/search.js (belongs to 02 search @ feature/search)
  FAIL  intruded on a live task's boundary; the two would overwrite each other
```

Read the full transcript and its limits in [docs/evidence.md](docs/evidence.md).

## The four mechanisms

**1. Contract first.** Before any branch opens, freeze three artifacts into `docs/contracts/` and commit the sha: interfaces (endpoints, schemas, error codes), data model (tables, fields, types, nullability), shared types (frontend types and backend DTOs in one file). After that, branches may not touch them — only the orchestrator can, and every change is broadcast and followed by `git merge <base>` in every live worktree. Most rework in parallel development is two agents disagreeing about one field name; freezing moves that discovery from merge time to before start.

**2. Dependency waves.** Run each wave in parallel, the waves in sequence:

```
Wave 1 (no deps, full parallel)   data model / route skeleton / design tokens / deploy
Wave 2 (needs wave 1 contract)    backend API / frontend pages / data import
Wave 3 (needs wave 2)             integration / end-to-end verification
```

One test decides dependency: **does A's output appear in B's input** — an interface shape, a field name, a type definition. If no, they belong in the same wave. "Related" is not a dependency, and treating it as one is how people throw away their parallel windows.

**3. Machine-checked file boundary.** One task = one branch = one worktree = one exclusive file list, registered in `docs/tasks/ownership.md`. `new-task.sh` refuses to create a task whose list overlaps a live task or names a frozen file, and allocates one port per task so executors cannot collide. `gate.sh` then checks every changed file against that row.

**4. The merge gate.** `gate.sh <branch>` runs pre-merge and stops at the first red: preflight → uncommitted/ residue → boundary → do-not-touch → build → live HTTP probe → tests. Acceptance criteria must be a command and an expected output:

```
✅  curl -s "localhost:3102/api/items?page=abc" → 400 {"code":"INVALID_QUERY"}
❌  works fine
```

## Why not just staff 14 agents

A popular setup runs a full SDLC org chart: PM / PO / researcher / analyst / architect / designer / frontend / backend / DevOps / writer / tester / critic / security / merge, all online the whole time.

It is complete, and it is slower. Every role boundary is a handoff, and every handoff loses context; the serial phases carve the parallel window into confetti; and the orchestrator's scheduling cost grows with the roster.

`parallel-agents` sizes the roster to the project instead:

| Tier | Staffing | Use when |
|---|---|---|
| **L1** default | orchestrator + 2–3 executors | feature modules, pages, data layer |
| **L2** | + architect (contract phase only) + verifier (merge phase only) | new project from zero, cross-platform |
| **L3** | + security reviewer + tech writer | public release, money or permissions involved |

The architect and the verifier appear once and leave. **Adding roles is a cost, not a capability.**

## Quick start

```bash
git clone https://github.com/kuoleroy/parallel-agents.git
# 国内镜像: git clone https://gitee.com/kuoleroy/parallel-agents.git

# 1. freeze the contract in your project
mkdir -p docs/contracts        # copy templates/contract.md, fill it, commit to your base branch

# 2. create tasks (worktree + branch + task book + ownership row + allocated port)
./parallel-agents/scripts/new-task.sh 01 data src/db migrations
./parallel-agents/scripts/new-task.sh 02 search src/api/search.ts

# 3. pre-install deps as the orchestrator, then hand each task book to its own agent window

# 4. gate every branch before it lands
./parallel-agents/scripts/gate.sh feature/search
```

Configure the gate for your stack with env vars — `BUILD_CMD`, `TEST_CMD`, `SERVE_CMD`, `BASE_BRANCH`, `BASE_PORT`, `REQUIRE_FULL`. Unset steps report `SKIP`, never a pass.

## Install as a skill

The repo root **is** the skill folder, so it installs anywhere the Agent Skills format is read. `SKILL.md` name matches the folder name, as the spec requires. Copy only the skill payload — leave `.git/` and `.github/` behind; they are repo plumbing, not skill content. `tests/` ships with the skill because `SKILL.md` cites it as the mechanism self-test:

```bash
mkdir -p ~/.claude/skills/parallel-agents
cp -r parallel-agents/{SKILL.md,AGENTS.md,LICENSE,scripts,templates,docs,tests} ~/.claude/skills/parallel-agents/
```

| Agent | Path |
|---|---|
| Claude Code | `~/.claude/skills/parallel-agents` (project: `.claude/skills/`) |
| Cursor | `.cursor/skills/parallel-agents` or `.agents/skills/parallel-agents` |
| Codex / Gemini CLI / Copilot / others | copy the same seven entries into that agent's skills directory |
| Rule-file-only agents | copy [`AGENTS.md`](AGENTS.md) into your project |
| Nothing to install | hand [`docs/methodology.md`](docs/methodology.md) to an agent and it can follow it |

Deliberately: **no platform feature, no MCP server, no slash command.** Claude Code / Codex plugin manifests are not included yet because the author has not verified them on a real install; a tested PR is welcome.

## When this is the wrong tool

- Small changes — one bug, one function: stay single-window.
- Fewer than 3 tasks: coordination costs more than it returns.
- Tasks that share many files: redraw the boundaries first.
- Requirements still moving: write the contract first, or don't parallelise yet.

Two questions decide it: **can the file lists be disjoint, and are there at least 3 tasks?**

## Limits, stated plainly

- The test suite verifies the **mechanism**, not the outcome of a real multi-agent project. There is no measured "rework dropped from X to Y" figure here, and this README does not claim one.
- Boundary-overlap detection is heuristic: exact paths, bare directories, `dir/**`, `dir/*` and single-level `*.ts` are understood; negation and brace expansion are not. Keep lists narrow.
- Scripts are bash (Git Bash on Windows). No PowerShell port exists.
- Verdict strings printed by `new-task.sh` / `gate.sh` and the generated task books are Chinese-only. Docs are bilingual; localising the tool output means touching the task-book parser in `gate.sh` and every template at once, so it is deliberately not half-done.
- The gate probes HTTP endpoints, so a stack without an HTTP layer configures `BUILD_CMD` / `TEST_CMD` and reads the probe `SKIP` honestly.

## Security note

Install only from `kuoleroy/parallel-agents` on GitHub or `kuoleroy/parallel-agents` on Gitee. This repo ships markdown and shell scripts only — never a binary. The scripts do not call the network, and `tests/` binds ports only under your own machine's temp directory.

## License

MIT.

> AI生成
