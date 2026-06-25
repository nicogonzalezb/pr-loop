#!/usr/bin/env bats

load test_helper

setup() {
  common_setup
  export ORDER_FILE="${BATS_FIXTURES}/orden-de-trabajo.md"
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/scripts/check_order.sh"
}

@test "check_order acepta issue listado en el plan (#8)" {
  run check_order 8
  [ "$status" -eq 0 ]
  [[ "$output" == *"está en el plan de trabajo"* ]]
}

@test "check_order avisa si issue bloqueado (#3)" {
  run check_order 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEADO"* ]]
}

@test "check_order avisa si issue no está en el plan" {
  run check_order 9999
  [ "$status" -eq 1 ]
  [[ "$output" == *"no aparece"* ]]
}
