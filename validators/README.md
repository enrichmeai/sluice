# validators

One script per check. Each takes the path to a generated work dir and prints its full output.
Exit codes are the contract, shared by the training filter, the evals and Penstock's tools
(penstock#216):

| Exit | Meaning |
|---|---|
| 0 | `pass` |
| 1 | `fail` (the output says why) |
| 2 | `not_run` (the tool is missing or the tier is not configured; never counts as pass) |

| Script | Check | Tier |
|---|---|---|
| `dbt_lint.sh` | `sqlfluff lint --dialect bigquery` on `models/` | offline |
| `dbt_parse.sh` | `dbt parse` with the dummy profile in `fixtures/profiles.yml` | offline |
| `dag_import.sh` | DagBag import test: `import_errors == {}`; then `ruff check --select AIR` | offline |
| `container.sh` | `docker build`, then `docker run -e CLOUD_RUN_TASK_INDEX=0 -e CLOUD_RUN_TASK_COUNT=1 <img> --version` | offline (needs Docker) |
| `dbt_sandbox.sh` | `dbt compile`, `bq query --dry_run`, `dbt build --empty`, unit tests, against the `sandbox` target | opt-in, needs a GCP project |

`test.sh` runs every script on `fixtures/<check>/red/` (must exit 1) and `fixtures/<check>/green/`
(must exit 0). A validator without both fixtures does not exist.

Nothing here is written yet: the scripts and fixtures are the first task of the spike
(`docs/BUILD_PROMPT.md` § 5, step 1).
