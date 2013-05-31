#!/bin/sh

GIT_DIR_="$(git rev-parse --git-dir)"
BRANCH="$(git rev-parse --symbolic --abbrev-ref $(git symbolic-ref HEAD))"

PRE_PUSH="$GIT_DIR_/hooks/pre-push"
POST_PUSH="$GIT_DIR_/hooks/post-push"

git push origin dev"$@"

test $? -eq 0 && test -x "$POST_PUSH" &&
    exec "$POST_PUSH" "$BRANCH" "$@"
