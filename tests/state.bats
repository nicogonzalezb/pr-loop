#!/usr/bin/env bats

load test_helper

setup() {
  state_test_setup
}

@test "state_init crea sub-objeto pr_loop" {
  state_init "issue-8" "null" "20260101T000000"
  [ "$(state_get issue)" = "issue-8" ]
  [ "$(state_get fase)" = "init" ]
  [ "$(state_get session_id)" = "20260101T000000" ]
  [ -z "$(state_get pr)" ]
  [ "$(state_get intentos_fix)" = "0" ]
}

@test "state_set_fase actualiza la fase" {
  state_init "issue-8" "57" "sess"
  state_set_fase "review-claude"
  [ "$(state_get_fase)" = "review-claude" ]
}

@test "state_inc_fix incrementa y devuelve el contador" {
  state_init "issue-8" "null" "sess"
  run state_inc_fix
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  [ "$(state_get intentos_fix)" = "1" ]
  run state_inc_fix
  [ "$output" = "2" ]
}

@test "state_init respeta PR_LOOP_DRY_RUN sin escribir" {
  export PR_LOOP_DRY_RUN=1
  state_init "issue-dry" "99" "dry-sess"
  [ ! -s "$STATE_FILE" ]
}
