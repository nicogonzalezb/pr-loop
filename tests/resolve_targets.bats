#!/usr/bin/env bats

load test_helper

setup() {
  gh_mock_setup
  load_resolve_targets
}

@test "resolve_targets usa headRefName cuando es issue-N" {
  export PR=10
  export MOCK_GH_HEAD_REF="issue-8"
  unset MOCK_GH_BODY MOCK_GH_TITLE

  resolve_targets

  [ "$ISSUE" = "issue-8" ]
  [ "$ISSUE_NUM" = "8" ]
  [ "$WORKTREE" = "${REPO_ROOT}/.worktrees/issue-8" ]
}

@test "resolve_targets infiere issue-N desde Closes #N en el body del PR" {
  export PR=57
  export MOCK_GH_HEAD_REF="feature/foo"
  export MOCK_GH_BODY=$'Implementa bats\n\nCloses #8'
  export MOCK_GH_TITLE="feat: suite bats"

  resolve_targets

  [ "$ISSUE" = "issue-8" ]
  [ "$ISSUE_NUM" = "8" ]
  [ "$WORKTREE" = "${REPO_ROOT}/.worktrees/feature/foo" ]
}

@test "resolve_targets cae en pr-N si no hay pistas de issue" {
  export PR=12
  export MOCK_GH_HEAD_REF="random-branch"
  export MOCK_GH_BODY="Sin referencia a issues"
  export MOCK_GH_TITLE="chore: misc"

  resolve_targets

  [ "$ISSUE" = "pr-12" ]
  [ "$WORKTREE" = "${REPO_ROOT}/.worktrees/random-branch" ]
}
