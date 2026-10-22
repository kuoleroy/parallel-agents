# parallel-agents — rules for agents

Run several coding agents on one repository at the same time without merge conflicts, duplicated work, or false "done". Follow this whenever the task is project-scale, splits into file-disjoint modules, has **at least 3** parallelizable tasks, and requirements are settled enough to write a contract. If any of those fails, say so and work single-window.

Full methodology: `docs/methodology.md`. Installable form: `SKILL.md`.

## Order of operations

1. **Freeze the contract first.** Before any branch opens, write interfaces (endpoints, request/response schemas, error codes), data model (tables, fields, types, nullability) and shared types into `docs/contracts/`, commit to the base branch, record the sha. No contract, no branch.
2. **Plan waves.** Dependency test: does A's output appear in B's input (an interface shape, a field name, a type definition)? If no, same wave. "Related" is not a dependency. Waves run in sequence, tasks inside a wave run in parallel, cap 5 per wave, fill wave 1 completely.
3. **One task = one branch = one worktree = one exclusive file list**, registered in `docs/tasks/ownership.md` with its own port. Use `scripts/new-task.sh <id> <name> <exclusive-files...>`; it rejects overlapping boundaries and frozen files.
4. **The orchestrator pre-installs dependencies.** Executors never install, never start servers, never bind ports, never touch other worktrees.
5. **Each executor window gets only**: project knowledge doc + the contract + its own task book. Not other tasks' context.
6. **Gate before merging.** `scripts/gate.sh <branch>`: preflight, uncommitted changes, residue, file boundary, do-not-touch, build, live HTTP probe, tests. Red means it does not land. Resolve conflicts yourself, never send them back to the executor.
7. **After merging**, every remaining worktree runs `git merge <base>` to realign before the next wave opens.

## Hard rules

- Shared files are frozen: lockfiles, shared types, migrations, main docs, compose, `.env.example`, `docs/contracts/**`. Only the orchestrator changes them, then broadcasts.
- Acceptance criteria are a command plus expected output. Reject anything you cannot execute. `curl → 400 INVALID_QUERY` is a criterion; "works fine" is not.
- A `SKIP` is not a pass. Configure `BUILD_CMD` / `TEST_CMD` / `SERVE_CMD`, or say what went unverified.
- Completion produces a delivery contract: files changed, self-test commands with real output, contract conformance item by item, known gaps, what downstream tasks must know.
- Mark the ownership row `merged` when it lands.

## Rework

| Result | Action |
|---|---|
| All green | Merge, mark row merged, update docs |
| One task red | Reopen as a **new** task book and new branch. Never patch a branch that failed the gate. |
| Contract itself flawed | Back to step 1, fix, broadcast, re-wave everything |
| Several tasks red in the same place | The contract is incomplete. Fix the contract, do not blame executors. |

## Never

Run multiple tasks in one window · reuse an old window for a new task · skip the contract to start coding sooner · treat "related" as "dependent" · open every task at once · let executors install deps or start databases · hand-edit lockfiles · declare done without a runnable verification · have the orchestrator write business code · add roles for the sake of a complete process.

## Sizing the roster

Roles are a cost, not a capability. L1 (default): orchestrator + 2–3 executors. L2: add an architect for the contract phase only and a verifier for the merge phase only — each appears once and leaves. L3: add security review and tech writing, for public releases or anything touching money or permissions. Do not staff a 14-role SDLC org chart; every handoff loses context and the serial phases eat the parallel window.
