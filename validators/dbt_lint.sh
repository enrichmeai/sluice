#!/usr/bin/env bash
# dbt_lint.sh <dbt project dir>
# sqlfluff on models/ with the BigQuery dialect and the Jinja templater, with dbt's ref(),
# source(), config() and is_incremental() stubbed in validators/config/.sqlfluff so no profile
# or warehouse is needed. Tier: offline.
# Source: sqlfluff 4.5.0, `sqlfluff dialects` lists bigquery; `sqlfluff lint --help` for flags.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

proj="${1:-}"
[ -n "$proj" ] || result fail "usage: dbt_lint.sh <dbt project dir>"
need_dir "$proj" "dbt project"
need_dir "$proj/models" "dbt project models/"

SQLFLUFF="${SLUICE_SQLFLUFF_BIN:-sqlfluff}"
need_cmd "$SQLFLUFF" "sqlfluff (offline SQL lint)"

if run_logged "$SQLFLUFF" lint --config "$VALIDATORS_DIR/config/.sqlfluff" --dialect bigquery "$proj/models"; then
  result pass "sqlfluff: no violations in $proj/models"
else
  result fail "sqlfluff: violations or unparsable SQL in $proj/models (see above)"
fi
