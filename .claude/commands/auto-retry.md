---
description: Generate multiple candidate implementations for a feature, review each, judge the best, and implement it — looping until a winner is found or the round cap is hit.
argument-hint: "<feature description> [--candidates N] [--max-rounds M]"
---

You are orchestrating the auto-retry workflow for: $ARGUMENTS

Defaults if not specified: 3 candidates, 2 max rounds. Hard ceiling: never exceed 3 rounds or 5 candidates per round regardless of what's requested — ask the user to confirm explicitly if they want more (cost scales roughly linearly with candidates × rounds).

## Step 0 — setup
1. Confirm you're in a git repo with a clean working tree (no uncommitted changes) — if not, stop and tell the user to commit or stash first.
2. Pick a short `task-slug` from the feature description (kebab-case, e.g. `retry-flush-buffer`).
3. Use `scripts/worktree-utils.sh create <task-slug> <candidate-id>` to create one isolated worktree per candidate (candidate ids: `a`, `b`, `c`, ...).
4. Decide N distinct strategies for this specific task — don't reuse a generic template blindly. E.g. for a bug fix: "minimal patch" vs "fix the root cause even if it touches more files" vs "fix + add a regression test". Pick strategies that would plausibly lead to genuinely different code, not cosmetic variation.

## Step 1 — generate (parallel)
Invoke the `implementer` subagent once per candidate, in parallel, each with:
- The feature description
- Its assigned strategy
- Its worktree path
- If this is round 2+: the judge's `NEXT_ROUND_GUIDANCE` from the previous round

## Step 2 — review (parallel)
Once all implementers report back, invoke the `reviewer` subagent once per candidate, in parallel, each pointed at that candidate's worktree and SUMMARY.md.

## Step 3 — judge
Invoke the `judge` subagent once, giving it every candidate's summary + review verdict, the round number, and max rounds.

## Step 4 — branch on the judge's decision
- **WINNER**: go to Step 5.
- **ANOTHER_ROUND** (and rounds remaining < max): clean up this round's worktrees except keep notes on what was tried, increment round counter, go back to Step 1 with the judge's `NEXT_ROUND_GUIDANCE` fed to each implementer.
- **ANOTHER_ROUND** requested but max rounds already hit: this shouldn't happen per the judge's own rules, but if it does, treat it as a forced WINNER pick and flag this to the user.

## Step 5 — implement the winner
1. Show the user: which candidate won, the judge's reasoning, and any `REMAINING_FIXES` still open.
2. If there are remaining fixes, apply them directly in the winning worktree (small, targeted edits — don't re-run the whole pipeline for cleanup).
3. Merge the winning branch into the branch you started from. Use a real merge or cherry-pick/rebase, whichever keeps history cleanest for this repo's conventions — ask the user if unsure.
4. Run `scripts/worktree-utils.sh cleanup <task-slug>` to remove all worktrees and losing branches.
5. Report a final summary: strategy that won, why, what changed, and a link/reference to the merged commit(s).

## Guardrails throughout
- Never merge or push anything until Step 5 — all intermediate work stays in worktrees.
- Never silently exceed the candidate/round caps.
- If any implementer or reviewer subagent fails or times out, don't let that silently drop a candidate — tell the user and either retry that one subagent or proceed with the remaining candidates, whichever seems more sensible given how many are left.
- Keep the user informed with a brief status line after each step (round N, step X) rather than going silent for the whole loop.
