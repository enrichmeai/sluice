#!/usr/bin/env bash
# dag_import.sh <dags dir>
# 1. DagBag import test, the one Airflow's best-practices page gives (Airflow 2.10 docs,
#    "Unit tests", fetched 2026-11-03): `from airflow.models import DagBag`,
#    `assert dagbag.import_errors == {}`, plus at least one DAG found.
# 2. ruff 0.16.9's hard AIR rules: AIR001 (task_id mismatch), AIR002 (no schedule), AIR301
#    (removed in Airflow 3), AIR302 (moved to a provider), AIR303 (incompatible signature).
#    AIR311/AIR312 are *suggestions* for Airflow 3 (they flag `from airflow import DAG`, which
#    Culvert's Airflow 2 golden DAGs use on purpose), so they are not selected until the
#    Airflow 3 target exists (culvert#286). `ruff rule --all` lists the set.
# Tier: offline. Needs a Python with apache-airflow (and the providers the DAG imports).
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

dags="${1:-}"
[ -n "$dags" ] || result fail "usage: dag_import.sh <dags dir>"
need_dir "$dags" "dags dir"

PY="${SLUICE_AIRFLOW_PY:-python3}"
RUFF="${SLUICE_RUFF_BIN:-ruff}"
need_cmd "$PY" "python for the DagBag test"
need_cmd "$RUFF" "ruff (AIR rules)"
"$PY" -c 'import airflow' >/dev/null 2>&1 || result not_run "apache-airflow is not importable by '$PY' (set SLUICE_AIRFLOW_PY to a venv that has it)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export AIRFLOW_HOME="$tmp/airflow_home"
export AIRFLOW__CORE__LOAD_EXAMPLES=False
export AIRFLOW__CORE__UNIT_TEST_MODE=True
export AIRFLOW__LOGGING__LOGGING_LEVEL=ERROR

printf '+ DagBag(%s)\n' "$dags"
if ! "$PY" - "$dags" <<'PYEOF'
import sys
from airflow.models import DagBag

folder = sys.argv[1]
bag = DagBag(dag_folder=folder, include_examples=False)
if bag.import_errors:
    for path, err in bag.import_errors.items():
        print(f"import error in {path}:\n{err}")
    sys.exit(1)
if not bag.dags:
    print(f"no DAG found under {folder}")
    sys.exit(1)
for dag_id, dag in bag.dags.items():
    print(f"dag {dag_id}: {len(dag.tasks)} task(s), schedule={dag.schedule_interval!r}")
PYEOF
then
  result fail "DagBag: import errors or no DAG in $dags (see above)"
fi

if run_logged "$RUFF" check --no-cache --select AIR001,AIR002,AIR301,AIR302,AIR303 --isolated "$dags"; then
  result pass "DagBag imports and ruff AIR is clean for $dags"
else
  result fail "ruff AIR: findings in $dags (see above)"
fi
