# Helpers compartidos para la suite bats de pr-loop.
common_setup() {
  export REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export BATS_FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
}

# Carga scripts/state.sh con STATE_FILE aislado en un directorio temporal.
state_test_setup() {
  common_setup
  export STATE_DIR="${BATS_TMPDIR}/state-$$"
  mkdir -p "$STATE_DIR"
  export STATE_FILE="${STATE_DIR}/current.json"
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/scripts/state.sh"
}

# Mock gh en PATH (tests/fixtures/bin/gh lee MOCK_GH_*).
gh_mock_setup() {
  common_setup
  export PATH="${BATS_FIXTURES}/bin:${PATH}"
}

# Carga resolve_targets desde pr-loop.sh sin ejecutar main.
load_resolve_targets() {
  common_setup
  export SCRIPTS_DIR="${REPO_ROOT}/scripts"
  export PROGRESS_DIR="${BATS_TMPDIR}/progress"
  mkdir -p "$PROGRESS_DIR"
  export DRY_RUN=0
  export ISSUE=""
  export ISSUE_NUM=""
  export HEAD_REF=""
  export PR=""
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/pr-loop.sh"
}
