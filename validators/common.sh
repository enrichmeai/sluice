#!/usr/bin/env bash
# Shared by every validator. Source it; do not run it.
#
# The contract (validators/README.md):
#   exit 0  pass
#   exit 1  fail      (stdout says why)
#   exit 2  not_run   (a tool is missing or a tier is not configured; never counts as pass)
#
# Tools are found through env vars so the training filter, the evals and Penstock's tools can
# point at their own venvs:
#   SLUICE_DBT_BIN      (default: dbt on PATH)
#   SLUICE_SQLFLUFF_BIN (default: sqlfluff on PATH)
#   SLUICE_AIRFLOW_PY   (default: python3 on PATH; must have apache-airflow importable)
#   SLUICE_RUFF_BIN     (default: ruff on PATH)
#   SLUICE_DOCKER_BIN   (default: docker on PATH)

set -u

PASS=0
FAIL=1
NOT_RUN=2

VALIDATORS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# result <pass|fail|not_run> <message>
# Prints one machine-readable line, then exits with the matching code.
result() {
  local status="$1"; shift
  printf 'SLUICE_RESULT=%s %s\n' "$status" "$*"
  case "$status" in
    pass) exit $PASS ;;
    fail) exit $FAIL ;;
    not_run) exit $NOT_RUN ;;
    *) printf 'SLUICE_RESULT=not_run bad status %s\n' "$status"; exit $NOT_RUN ;;
  esac
}

# need_cmd <binary> <what it is for>
# Exits not_run when the binary is missing. Nothing else is inferred from its absence.
need_cmd() {
  local bin="$1" why="$2"
  if ! command -v "$bin" >/dev/null 2>&1; then
    result not_run "$why: '$bin' is not installed or not on PATH"
  fi
}

# need_dir <path> <what it is>
need_dir() {
  local d="$1" what="$2"
  [ -d "$d" ] || result fail "$what: '$d' is not a directory"
}

# run_logged <cmd...>
# Runs a command, streams its output to stdout, returns its exit code.
run_logged() {
  printf '+ %s\n' "$*"
  "$@" 2>&1
  return "${PIPESTATUS[0]:-$?}"
}
