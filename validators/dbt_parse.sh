#!/usr/bin/env bash
# dbt_parse.sh <dbt project dir>
# `dbt parse --no-partial-parse` with a dummy BigQuery profile. dbt parse "parses and validates
# the contents of your dbt project", fails on Jinja/YAML errors and on a ref() to a missing
# node, and "doesn't connect to your warehouse" (docs.getdbt.com reference/commands/parse,
# fetched 2026-11-03 from the docs repo). Tier: offline.
# Profile fields: method=oauth, project, dataset (dbt-bigquery 1.12.1 BigQueryCredentials).
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

proj="${1:-}"
[ -n "$proj" ] || result fail "usage: dbt_parse.sh <dbt project dir>"
need_dir "$proj" "dbt project"
[ -f "$proj/dbt_project.yml" ] || result fail "dbt project: no dbt_project.yml in $proj"

DBT="${SLUICE_DBT_BIN:-dbt}"
need_cmd "$DBT" "dbt (offline project parse)"

profile_name="$(sed -n "s/^profile:[[:space:]]*['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}[[:space:]]*$/\1/p" "$proj/dbt_project.yml" | head -1)"
[ -n "$profile_name" ] || result fail "dbt project: dbt_project.yml has no 'profile:' line"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/profiles.yml" <<EOF
$profile_name:
  target: parse
  outputs:
    parse:
      type: bigquery
      method: oauth
      project: sluice-parse-only
      dataset: sluice_parse_only
      threads: 1
EOF

# Partial parse would reuse a stale target/; packages are not installed (no network): a project
# that needs dbt deps fails here on purpose, because the model must not depend on packages the
# container does not install.
if run_logged "$DBT" parse --no-partial-parse --no-use-colors --project-dir "$proj" --profiles-dir "$tmp" --target-path "$tmp/target" --log-path "$tmp/logs"; then
  result pass "dbt parse: $proj parses"
else
  result fail "dbt parse: $proj does not parse (see above)"
fi
