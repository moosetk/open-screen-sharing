#!/usr/bin/env bash
# Merges upstream main into a new candidate branch cut from the fork's main.
# Only runs git; upstream code is never executed here.
#
# Env:
#   UPSTREAM_URL  default https://github.com/nekohasekai/open-screen-sharing.git
#   UPSTREAM_REF  default main
#   BASE_BRANCH   default main (the fork's known-good branch, never modified)
#   PUSH=1        push the candidate branch to origin (new branches only, never forced)
#
# Outputs (stdout and $GITHUB_OUTPUT when set):
#   status        up-to-date | created | exists | conflict
#   branch, upstream_sha, fork_sha, conflicts

set -euo pipefail

UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/nekohasekai/open-screen-sharing.git}
UPSTREAM_REF=${UPSTREAM_REF:-main}
BASE_BRANCH=${BASE_BRANCH:-main}

output() {
  echo "$1=$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1=$2" >> "$GITHUB_OUTPUT"
  fi
}

git fetch --quiet --no-tags origin "$BASE_BRANCH"
git fetch --quiet --no-tags "$UPSTREAM_URL" "$UPSTREAM_REF"
upstream_sha=$(git rev-parse FETCH_HEAD)
fork_sha=$(git rev-parse "origin/$BASE_BRANCH")
branch="fork-sync/upstream-${upstream_sha:0:12}"

output upstream_sha "$upstream_sha"
output fork_sha "$fork_sha"
output merge_base "$(git merge-base "$upstream_sha" "$fork_sha")"
output branch "$branch"

if git merge-base --is-ancestor "$upstream_sha" "$fork_sha"; then
  output status up-to-date
  exit 0
fi

if git ls-remote --exit-code --heads origin "$branch" > /dev/null; then
  output status exists
  exit 0
fi

git switch --quiet --detach "$fork_sha"
message="Merge upstream nekohasekai/open-screen-sharing@${upstream_sha:0:12}

Upstream: $UPSTREAM_URL $UPSTREAM_REF $upstream_sha
Fork base: $BASE_BRANCH $fork_sha"
if ! git merge --no-ff --no-edit -m "$message" "$upstream_sha"; then
  conflicts=$(git diff --name-only --diff-filter=U | paste -sd ' ' -)
  git merge --abort
  output conflicts "$conflicts"
  output status conflict
  exit 0
fi

if [ "${PUSH:-}" = 1 ]; then
  git push --quiet origin "HEAD:refs/heads/$branch"
fi
output status created
