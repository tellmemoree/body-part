# Auto-retry workflow for Claude Code

Generates several candidate implementations for a feature in parallel, reviews each against a fixed rubric, judges the best one, and merges it — looping (up to a cap) if nothing passes review yet.

## What's in here

```
agents/
  implementer.md   # produces one candidate, given a strategy + isolated worktree
  reviewer.md       # scores one candidate: correctness, safety, maintainability, tests
  judge.md          # compares reviewed candidates, picks a winner or asks for another round
commands/
  auto-retry.md     # the /auto-retry slash command — owns the loop
scripts/
  worktree-utils.sh # isolates each candidate in its own git worktree/branch
```

## Install

From your project root:

```bash
mkdir -p .claude/agents .claude/commands
cp agents/*.md .claude/agents/
cp commands/*.md .claude/commands/
cp scripts/worktree-utils.sh ./scripts/    # or wherever your repo keeps scripts
chmod +x scripts/worktree-utils.sh
```

Claude Code picks up new agent/command files within a few seconds if `.claude/agents/` and `.claude/commands/` already existed when the session started. If they're brand new directories, restart the session once.

## Use

```
/auto-retry implement retry-with-backoff for the flash write in the flyback controller driver
```

Optional flags: `--candidates N` (default 3), `--max-rounds M` (default 2). Hard caps are 5 candidates / 3 rounds — the orchestrator will ask before going higher, since cost scales with candidates × rounds.

## When this is worth it (and when it isn't)

Good fit: a discrete, comparable piece of work where multiple genuinely different implementations are plausible and reviewable independently — a new function, a bug fix with more than one valid approach, a bench-automation script, a small protocol handler.

Poor fit: work that's inherently sequential and depends on tight running context — a long debugging session where each step depends on the last, or a multi-file refactor where the pieces aren't independent. For that kind of task a single careful agent session usually beats parallel candidates; the parallelism here only pays off when the candidates can be judged side by side without needing to share evolving state.

## Notes

- All candidate work happens in isolated worktrees (`.auto-retry-worktrees/<task-slug>/<candidate-id>`) on throwaway branches (`auto-retry/<task-slug>/<candidate-id>`) — nothing touches your main branch until Step 5 of the orchestrator, and losing branches/worktrees get cleaned up automatically.
- Reviewers are read-only by tool access (`Read, Bash, Grep, Glob` — no `Write`/`Edit`) so they can't quietly "fix" what they're supposed to be scoring.
- The judge only ever sees summaries and verdicts, not raw diffs — keeps its context small and its decision auditable.
- Tune the rubric in `reviewer.md` for your domain — as-is it weighs safety/robustness heavily, which fits firmware-adjacent work, but you may want a different weighting for e.g. pure tooling/scripts.
- Local changes to `scripts/worktree-utils.sh` for this project: `cleanup` lists branches with
  `git for-each-ref` (the original `sed` pattern did not work on macOS, so losing branches were never
  deleted), and `create` puts a `.gdignore` in `.auto-retry-worktrees/` so the Godot editor does not
  import the candidate copies of the project.
