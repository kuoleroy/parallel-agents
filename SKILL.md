---
name: parallel-agents
description: Orchestrate multiple AI coding agents on a single project in parallel using git worktrees, frozen API/data contracts, dependency-wave scheduling, and a merge gate. This skill should be used when a project can be split into file-disjoint, independently verifiable modules to be built concurrently by separate agent windows, or when coordinating parallel development to prevent merge conflicts and rework. Also triggers on Chinese cues like 并行开发 / 多智能体 / 多窗口并行 / git worktree / 合并冲突 / 防返工.
name_cn: 并行智能体编排
description_cn: 在单个项目上编排多个 AI 编码智能体并行开发：git worktree 隔离、冻结契约、依赖波次排期、合并前闸门。当项目可拆成文件不重叠、可独立验收的模块需多窗口并行推进，或要防止并行开发的合并冲突与返工时使用。
license: MIT
metadata:
  agent_created: true
  version: 0.2.1
---

# Parallel Agents

Run several coding agents on one repository at the same time without merge conflicts, without duplicated work, and without losing track of what is actually done.

## Requirements

bash, git, curl, awk, mktemp — on Windows that means Git Bash; if `bash` resolves to a WSL shim (no distro installed), invoke Git Bash by full path (`C:\Program Files\Git\bin\bash.exe`). The self-test additionally needs node and git ≥ 2.28 (`git init -b`).

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
- [ ] `docs/contracts/` holds frozen interfaces, data model, and shared types, committed to the base branch.
- [ ] `docs/tasks/frozen.patterns` lists the files no branch may touch. `new-task.sh` creates it with defaults on first run; edit it to fit the project.
- [ ] Every task has a disjoint exclusive-file list, registered in `docs/tasks/ownership.md`.
- [ ] Tasks are assigned to waves by real dependency.
- [ ] Each worktree has dependencies pre-installed by the orchestrator.
- [ ] `scripts/gate.sh` runs green against the base branch.

The base branch is auto-detected (`main`, else `master`); override with `BASE_BRANCH`.

## Workflow

### Step 0 — Freeze the contract

Freeze three artifacts into `docs/contracts/`, then commit to the base branch:

1. **Interfaces** — endpoints, methods, request/response schemas, error codes.
2. **Data model** — tables, field names, types, nullability, indexes.
3. **Shared types** — frontend TS types, backend DTOs, in a shared file.

Record the commit sha. Every task book cites it.

After freezing, no branch may modify these files. Only the orchestrator changes them, and any change must be broadcast and followed by `git merge <base>` in every live worktree.

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

### Step 3 — Create tasks

One call per task creates the worktree, the branch, the task book and the ownership row:

```bash
scripts/new-task.sh <id> <name> <exclusive-files...>
# scripts/new-task.sh 02 search src/api/search.ts src/api/__tests__/search.test.ts
```

It refuses to proceed when the exclusive list overlaps a live task, names a frozen file, or when the branch/worktree/task book already exists. It also allocates one port per task from `BASE_PORT` (default 3100) so parallel executors cannot collide on a port.

Each task book must contain: branch, worktree path, wave number, prerequisites, upstream contract sha, allocated port, goal, exclusive files, do-not-touch list, steps, machine-verifiable acceptance criteria.

Write acceptance criteria as command plus expected output. Reject any criterion that cannot be executed.

See `templates/task-book.example.md` for a filled example.

### Step 4 — Pre-install dependencies

Worktrees exist by now. In each one, install dependencies as the orchestrator:

```bash
( cd ../wk-<name> && <install command> )
```

Executors must never run install commands, start servers, or bind ports. Concurrent installs cause port contention and dependency drift. When two projects share a parent directory, separate their worktrees with `WK_PARENT`.

### Step 5 — Dispatch execution

Give each executor window only: the project knowledge doc, the contract, and its own task book. Do not hand over other tasks' context.

Require a delivery contract on completion:

- Files changed (must fall entirely inside the exclusive list)
- Self-test commands and actual output
- Contract conformance, item by item
- Known gaps and compromises
- What downstream tasks must know

### Step 6 — Run the merge gate, before merging

`scripts/gate.sh <branch>` runs **pre-merge** against the branch's own worktree, stopping at the first failure. Red means the branch does not land.

Automated:

1. **Preflight** — branch exists, base resolved, branch registered in the ownership table.
2. **Inspect** — worktree has no uncommitted changes, no leftover verification files.
3. **Boundary** — every changed file falls inside its exclusive list, outside the frozen list, and outside every other live task's boundary.
4. **Protection** — nothing touched from the task book's do-not-touch section.
5. **Build** — `BUILD_CMD` in the worktree.
6. **Probe** — starts `SERVE_CMD` on the task's allocated port, then `curl`s the health endpoint and a boundary case that must return 4xx, then stops the server and waits for the port to free. A port already occupied by something the gate did not start is a `FAIL`, not a shortcut: the gate cannot prove that process runs this branch. Point `HEALTH_URL` at an external service if you want to test one deliberately.
7. **Regress** — `TEST_CMD`, plus a report of which changed files already existed on the base.

Manual, never answered by the gate:

- **Merge** — `git merge --no-ff <branch>`; resolve conflicts personally, never send them back to the executor.
- **Security** — hardcoded secrets, unvalidated input, authorization gaps, string-concatenated SQL, PII in logs.
- **Clean** — remove verification leftovers before it lands on the base branch.

Steps skipped for lack of configuration are reported as `SKIP`, not as passes; set `REQUIRE_FULL=1` to make any `SKIP` a failure in CI.

After merging, have every remaining worktree run `git merge <base>` to realign before opening the next wave.

### Step 7 — Rework loop

| Result | Action |
|---|---|
| All green | Merge, mark the ownership row `merged`, update docs |
| One task red | Reopen that task as a **new** task book and new branch. Do not patch the old branch. |
| Contract itself flawed | Return to step 0, fix, broadcast, re-wave everything |
| Several tasks fail in the same place | The contract is incomplete — return to step 0, do not blame executors |

## Hard rules

1. One task = one branch = one worktree = one exclusive file list.
2. No contract, no branch.
3. Shared files are frozen in `docs/tasks/frozen.patterns`: lockfiles, shared types, migrations, main docs, compose, `.env.example`.
4. The orchestrator pre-installs all dependencies.
5. No task book, no work. No ownership row, no merge.
6. Documentation is the single source of truth; agents align through documents, not conversation.
7. Waves run in sequence; tasks within a wave run in parallel.
8. A merge is complete only when the gate is green — and green means verified, not skipped.

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
- Read a `SKIP` as a pass.

## Verified behavior

`docs/evidence.md` records the mechanism test: 10 injected violations, 10 blocked, and a compliant branch passing `OK 12 · SKIP 0 · FAIL 0` with a real HTTP probe. Reproduce with `bash tests/run-test.sh` — no AI, no network, no token spend. It verifies the gate's mechanism, not the outcome of a real multi-agent project.

## Reference files

- `docs/methodology.md` — full methodology, rationale, and anti-pattern catalog.
- `docs/evidence.md` — mechanism verification transcript and its limits.
- `templates/contract.md` — contract template.
- `templates/task-book.example.md` — a completed task book.
- `scripts/new-task.sh` — worktree, branch, task book and ownership row.
- `scripts/gate.sh` — the pre-merge gate.
- `scripts/parallel-lib.sh` — shared boundary/ownership lookup used by both.
- `tests/run-test.sh` — end-to-end mechanism test.
