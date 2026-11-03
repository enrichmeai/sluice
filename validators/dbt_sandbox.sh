#!/usr/bin/env bash
# dbt_sandbox.sh <dbt project dir>
# The opt-in tier: the SQL is valid against the real schemas. Runs only when the user has
# named a sandbox: SLUICE_SANDBOX_PROFILES_DIR must hold a profiles.yml whose target is
# `sandbox` (a dataset the user owns; never production). Otherwise: not_run.
#   dbt compile      (connects; resolves sources and macros against the warehouse)
#   dbt build --empty --target sandbox   (schema-only dry run: runs each model with LIMIT 0,
#                                         dbt-core >= 1.8)
#   dbt test --select "test_type:unit"   (the unit_tests: cases; dbt-core >= 1.8)
# The dbt command pages (compile, build, test) are the source; `--empty` since 1.8.0 per the
# dbt-core 1.8 CHANGELOG (fetched 2026-11-01). Tier: sandbox.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

proj="${1:-}"
[ -n "$proj" ] || result fail "usage: dbt_sandbox.sh <dbt project dir>"
need_dir "$proj" "dbt project"

[ -n "${SLUICE_SANDBOX_PROFILES_DIR:-}" ] || result not_run "sandbox tier not configured (set SLUICE_SANDBOX_PROFILES_DIR to a dir with a profiles.yml whose target is 'sandbox')"
[ -f "$SLUICE_SANDBOX_PROFILES_DIR/profiles.yml" ] || result not_run "no profiles.yml in SLUICE_SANDBOX_PROFILES_DIR=$SLUICE_SANDBOX_PROFILES_DIR"
grep -q 'sandbox' "$SLUICE_SANDBOX_PROFILES_DIR/profiles.yml" || result not_run "profiles.yml has no 'sandbox' target; this check never runs against anything else"

DBT="${SLUICE_DBT_BIN:-dbt}"
need_cmd "$DBT" "dbt"

common=(--no-use-colors --project-dir "$proj" --profiles-dir "$SLUICE_SANDBOX_PROFILES_DIR" --target sandbox)
run_logged "$DBT" compile "${common[@]}"            || result fail "dbt compile failed against the sandbox (see above)"
run_logged "$DBT" build --empty "${common[@]}"      || result fail "dbt build --empty failed against the sandbox (see above)"
run_logged "$DBT" test --select "test_type:unit" "${common[@]}" || result fail "dbt unit tests failed against the sandbox (see above)"
result pass "compile, build --empty and unit tests pass against the sandbox: $proj"
