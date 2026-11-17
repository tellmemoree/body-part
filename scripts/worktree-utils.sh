#!/usr/bin/env bash
# worktree-utils.sh
# Helper functions for the auto-retry workflow: give each implementer
# candidate an isolated git worktree so parallel candidates can never
# collide on the same files.
#
# Usage (sourced by the orchestrator, or run directly):
#   ./worktree-utils.sh create <task-slug> <candidate-id>
#   ./worktree-utils.sh cleanup <task-slug>
#   ./worktree-utils.sh list <task-slug>

set -euo pipefail

WORKTREE_ROOT=".auto-retry-worktrees"

require_git_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: not inside a git repository" >&2
    exit 1
  fi
}

create_worktree() {
  local task_slug="$1"
  local candidate_id="$2"
  local base_branch
  base_branch="$(git rev-parse --abbrev-ref HEAD)"

  local branch="auto-retry/${task_slug}/${candidate_id}"
  local path="${WORKTREE_ROOT}/${task_slug}/${candidate_id}"

  mkdir -p "${WORKTREE_ROOT}/${task_slug}"
  # Each candidate is a full copy of the Godot project; keep the editor from importing them.
  touch "${WORKTREE_ROOT}/.gdignore"

  if git show-ref --quiet "refs/heads/${branch}"; then
    echo "error: branch ${branch} already exists — pick a different candidate id or clean up first" >&2
    exit 1
  fi

  git worktree add -b "${branch}" "${path}" "${base_branch}" >/dev/null
  echo "${path}"
}

cleanup_worktrees() {
  local task_slug="$1"
  local dir="${WORKTREE_ROOT}/${task_slug}"

  if [[ ! -d "${dir}" ]]; then
    echo "nothing to clean up for ${task_slug}"
    return 0
  fi

  for candidate_path in "${dir}"/*/; do
    [[ -d "${candidate_path}" ]] || continue
    git worktree remove --force "${candidate_path}" 2>/dev/null || true
  done

  # Remove the now-orphaned local branches too.
  # for-each-ref prints bare names (git branch adds "* " / "+ " markers, and BSD sed can't strip them).
  git worktree prune
  git for-each-ref --format='%(refname:short)' "refs/heads/auto-retry/${task_slug}/" | while read -r b; do
    [[ -n "${b}" ]] || continue
    git branch -D "${b}" >/dev/null 2>&1 || echo "warning: could not delete branch ${b}" >&2
  done

  rmdir "${dir}" 2>/dev/null || true
  echo "cleaned up worktrees for ${task_slug}"
}

list_worktrees() {
  local task_slug="$1"
  git worktree list | grep "auto-retry/${task_slug}/" || echo "no active worktrees for ${task_slug}"
}

main() {
  require_git_repo
  local cmd="${1:-}"
  case "${cmd}" in
    create)
      create_worktree "${2:?task slug required}" "${3:?candidate id required}"
      ;;
    cleanup)
      cleanup_worktrees "${2:?task slug required}"
      ;;
    list)
      list_worktrees "${2:?task slug required}"
      ;;
    *)
      echo "usage: $0 {create|cleanup|list} <task-slug> [candidate-id]" >&2
      exit 1
      ;;
  esac
}

main "$@"
