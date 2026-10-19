---
name: parallel-agents
description: Orchestrate multiple AI coding agents on a single project in parallel using git worktrees, frozen API/data contracts, dependency-wave scheduling, and a merge gate. This skill should be used when a project can be split into file-disjoint, independently verifiable modules to be built concurrently by separate agent windows, or when coordinating parallel development to prevent merge conflicts and rework.
agent_created: true
---

# Parallel Agents

Run several coding agents on one repository at the same time without merge conflicts, without duplicated work, and without losing track of what is actually done.

## When to activate

Activate this skill when all of the following hold:

- The work is project-scale, not a single bug or function.
- The work splits into modules with **disjoint file lists**.
- There are **at least 3** parallelizable tasks.
- Requirements are settled enough to write an interface contract.

Do not activate for small changes, for fewer than 3 tasks, or when requirements are still moving. State the reason and proceed single-window instead.

## Preconditions — verify before opening any branch

Stop and fix if any item fails. Opening branches early is the main cause of rework.

- [ ] Project knowledge doc exists: direction, architecture, known traps.
- [ ] `docs/contracts/` holds frozen interfaces, data model, and shared types, committed to `main`.
- [ ] Every task has a disjoint exclusive-file list.
- [ ] Tasks are assigned to waves by real dependency.
- [ ] Each worktree has dependencies pre-installed.
- [ ] `scripts/gate.sh` runs successfully on `main`.

## Workflow

### Step 0 — Freeze the contract

Freeze three artifacts into `docs/contracts/`, then commit to `main`:

1. **Interfaces** — endpoints, methods, request/response schemas, error codes.
2. **Data model** — tables, field names, types, nullability, indexes.
3. **Shared types** — frontend TS types, backend DTOs, in a shared file.

Record the commit sha. Every task book cites it.

After freezing, no branch may modify these files. Only the orchestrator changes them, and any change must be broadcast and followed by `git merge main` in every live worktree.

Use `templates/contract.md` as the starting shape.

### Step 1 — Scale the roles

Pick the smallest tier that works. Adding roles adds handoffs, and handoffs lose context.

| Tier | Staffing | Use when |
|---|---|---|
| L1 (default) | orchestrator + 2–3 executors | architecture already clear |
| L2 | + architect (contract phase only) + verifier (merge phase only) | new project, cross-platform |
| L3 | + security reviewer + tech writer | public release, money or permissions involved |

The architect and verifier each appear once and then leave. They do not stay online.

### Step 2 — Plan waves

Group tasks by dependency, then run each wave in parallel and the waves in sequence.

```
Wave 1 (no deps, full parallel)   data model / route skeleton / design tokens / deploy
Wave 2 (needs wave 1 contract)    backend API / frontend pages / data import
Wave 3 (needs wave 2)             integration / end-to-end verification
```

Apply exactly one test for dependency: **does A's output appear in B's input** — an interface shape, a field name, a type definition. If the answer is no, they belong in the same wave. "Related" is not a dependency.

Fill wave 1 completely. It is the only window with no upstream waiting. Cap each wave at 5 tasks.

### Step 3 — Write task books

One task book per task, generated with:

```bash
scripts/new-task.sh <id> <name> <exclusive-files...>
```

Each task book must contain: branch, worktree path, wave number, prerequisites, upstream contract sha, goal, exclusive files, do-not-touch list, steps, machine-verifiable acceptance criteria.

Write acceptance criteria as command plus expected output. Reject any criterion that cannot be executed.

See `templates/task-book.example.md` for a filled example.

### Step 4 — Prepare worktrees

Create one worktree and branch per task, and pre-install dependencies in each:

```bash
git worktree add ../wk-<name> -b feature/<name> main
cd ../wk-<name> && <install command>
```

Executors must never run install commands, start servers, or bind ports. Concurrent installs cause port contention and dependency drift.

### Step 5 — Dispatch execution

Give each executor window only: the project knowledge doc, the contract, and its own task book. Do not hand over other tasks' context.

Require a delivery contract on completion:

- Files changed (must fall entirely inside the exclusive list)
- Self-test commands and actual output
- Contract conformance, item by item
- Known gaps and compromises
- What downstream tasks must know

### Step 6 — Run the merge gate

For each finished branch, in order, stopping at the first failure:

1. **Inspect** — commits within authorization, clean tree, no out-of-bounds changes, no leftover verification files.
2. **Merge** — `git merge --no-ff <branch>`. Resolve conflicts personally; never send them back to the executor.
3. **Build** — compose config, frontend build, backend start.
4. **Probe** — `curl` real endpoints, including boundary cases: invalid params, upstream down, 404.
5. **Regress** — confirm existing behavior is unchanged.
6. **Security** — hardcoded secrets, unvalidated input, authorization gaps, string-concatenated SQL, PII in logs.
7. **Clean** — remove verification leftovers before it lands on `main`.

Run `scripts/gate.sh <branch>` to automate steps 1, 3, 4, and 5.

After merging, have every remaining worktree run `git merge main` to realign before opening the next wave.

### Step 7 — Rework loop

| Result | Action |
|---|---|
| All green | Update docs and the ownership table |
| One task red | Reopen that task as a **new** task book and new branch. Do not patch the old branch. |
| Contract itself flawed | Return to step 0, fix, broadcast, re-wave everything |
| Several tasks fail in the same place | The contract is incomplete — return to step 0, do not blame executors |

## Hard rules

1. One task = one branch = one worktree = one exclusive file list.
2. No contract, no branch.
3. Shared files are frozen: lockfiles, shared types, migrations, main docs, compose, `.env.example`.
4. The orchestrator pre-installs all dependencies.
5. No task book, no work.
6. Documentation is the single source of truth; agents align through documents, not conversation.
7. Waves run in sequence; tasks within a wave run in parallel.
8. A merge is complete only when the gate is green.

## Never do

- Run multiple tasks in one window.
- Reuse an old window for a new task — old assumptions leak in.
- Skip the contract to start coding sooner.
- Treat "related" as "dependent".
- Open every task at once.
- Let executors install dependencies, start databases, or bind ports.
- Hand-edit lockfiles or shared types.
- Declare done without a runnable verification command.
- Have the orchestrator write business code.
- Patch a branch that failed the gate — open a new one.
- Add roles for the sake of a complete process.

## Reference files

- `docs/methodology.md` — full methodology, rationale, and anti-pattern catalog.
- `templates/contract.md` — contract template.
- `templates/task-book.example.md` — a completed task book.
- `scripts/new-task.sh` — worktree plus task book generator.
- `scripts/gate.sh` — merge gate automation.
