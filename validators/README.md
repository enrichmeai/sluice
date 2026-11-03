# validators

One script per check. Each takes the path to a generated work dir, prints its full output, ends
with one line `SLUICE_RESULT=<status> <message>`, and exits with the status. The exit codes are
the contract, shared by the training filter, the evals and Penstock's tools (penstock#216):

| Exit | Status | Meaning |
|---|---|---|
| 0 | `pass` | the check ran and the work passed |
| 1 | `fail` | the check ran and the work failed; the output says why |
| 2 | `not_run` | the tool is missing or the tier is not configured; **never counts as pass** |

| Script | Check | Tool, pinned (proven 2026-11-03) | Tier |
|---|---|---|---|
| `dbt_lint.sh <project>` | `sqlfluff lint` on `models/`, BigQuery dialect, Jinja templater with dbt builtins (`config/.sqlfluff`) | sqlfluff 4.5.0 | offline |
| `dbt_parse.sh <project>` | `dbt parse --no-partial-parse` with a dummy BigQuery profile; no warehouse | dbt-core 1.12.6, dbt-bigquery 1.12.1 | offline |
| `dag_import.sh <dags dir>` | DagBag import test (`import_errors == {}`, at least one DAG), then ruff's hard AIR rules (AIR001, AIR002, AIR301, AIR302, AIR303) | apache-airflow 2.10.5 + providers cncf-kubernetes 10.1.0, google 12.0.0; ruff 0.16.9 | offline |
| `container.sh <dir>` | `docker build`, then `docker run -e CLOUD_RUN_TASK_INDEX=0 -e CLOUD_RUN_TASK_COUNT=1 <img> --version` | Docker (a running daemon) | offline |
| `dbt_sandbox.sh <project>` | `dbt compile`, `dbt build --empty`, `dbt test --select test_type:unit` against the `sandbox` target in `$SLUICE_SANDBOX_PROFILES_DIR` | dbt as above, a GCP project you own | opt-in |

Tools are found through `SLUICE_DBT_BIN`, `SLUICE_SQLFLUFF_BIN`, `SLUICE_AIRFLOW_PY`,
`SLUICE_RUFF_BIN`, `SLUICE_DOCKER_BIN` (defaults: on `PATH`), so each caller points at its own
venvs. `requirements.txt` has the pins and the two-venv setup.

## test.sh: red first

`validators/test.sh` runs every script on `fixtures/<check>/red/` (must exit 1) and
`fixtures/<check>/green/` (must exit 0). A check that exits 2 on both is printed `NOT RUN` and
the suite exits 2: not a pass. A validator without both fixtures does not exist.

The green fixtures are Culvert-shaped on purpose: `dag_import/green/` holds Culvert v0.6.1's
golden DAGs verbatim (`substrate-composer3.py`, `substrate-cloud-run.py`), and the dbt project
follows `deployments/bigquery-to-mapped-product/dbt` (staging view, incremental merge mart,
`unit_tests:`). The red fixtures each break one thing: unparsable SQL, a `ref()` to a missing
model, a DAG with an import error, a Dockerfile whose `COPY` has no source.

Run on 2026-11-03 in the cloud session (no Docker daemon, no sandbox):

```
dbt_lint     red    ok   (fails as it should)
dbt_lint     green  ok   (passes)
dbt_parse    red    ok   (fails as it should)
dbt_parse    green  ok   (passes)
dag_import   red    ok   (fails as it should)
dag_import   green  ok   (passes)
container    red    NOT RUN: docker daemon is not reachable (is Docker running?)
container    green  NOT RUN: docker daemon is not reachable (is Docker running?)
dbt_sandbox  red    NOT RUN: sandbox tier not configured (...)
dbt_sandbox  green  NOT RUN: sandbox tier not configured (...)
RESULT: NOT RUN for at least one check (not a pass)
```

`container.sh`'s red and green proofs are still owed from a machine with Docker (the M2 Max).
`dbt_sandbox.sh` is proven only when a sandbox project exists; until then its fixtures are the
`dbt_parse` ones.

## What the fixtures taught (rules the models must learn)
- dbt 1.12: a `unit_tests:` case on an incremental model must set
  `overrides: macros: is_incremental: <bool>`; without it `dbt parse` fails.
- sqlfluff RF02: a column inside a subquery that references two relations must be qualified
  (`max(t.updated_at)` with `from {{ this }} as t`).
- ruff AIR311 flags `from airflow import DAG` as an Airflow 3 suggestion. Culvert's Airflow 2
  DAGs use it on purpose, so only the hard rules are selected until culvert#286 lands.
