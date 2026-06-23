#!/usr/bin/env bats

load test_helper

setup() {
  common_setup
  export PROMPTS_DIR="${BATS_FIXTURES}/prompts"
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/scripts/render_prompt.sh"
}

@test "render_prompt sustituye todos los placeholders" {
  run render_prompt "test-template.md" "42" "99" "sess-1" "/tmp/reviews.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Issue #42"* ]]
  [[ "$output" == *"PR 99"* ]]
  [[ "$output" == *"sesión sess-1"* ]]
  [[ "$output" == *"reviews /tmp/reviews.json"* ]]
  [[ "$output" != *"{{ISSUE}}"* ]]
}

@test "render_prompt falla si el archivo no existe" {
  run render_prompt "no-existe.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Prompt no encontrado"* ]]
}
