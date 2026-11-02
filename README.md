# Sluice

Three small, task-specific local models for data pipelines on Google Cloud, and the data, checks
and evals that make them. Each is a fine-tune of a permissively licensed open-weight base, merged
into one GGUF, shipped as a Penstock release asset, and run inside
[Headworks](https://enrichmeai.com/headworks) (Penstock + Cistern) on your own machine.

| Model | Writes | Checked by |
|---|---|---|
| `dbt-bq` | dbt models, `sources.yml`, `schema.yml` with tests and unit tests, for BigQuery | sqlfluff (bigquery), `dbt parse` |
| `composer-dag` | one Airflow DAG for Cloud Composer, in Culvert's rendered style | DagBag import test, `ruff --select AIR` |
| `cloudrun-job` | a Cloud Run job container (Dockerfile + entrypoint) that runs dbt | `docker build`, `docker run` with the task env vars |

A sluice is the gate that routes and meters what gets through. This one routes each task to its
own small model and lets only output that passes the checks go on.

## The decision: own the weights, not the runtime (2026-11-02)

```
owned, survives base-model changes          rented or off the shelf
  training data (execution-filtered)          base model (Qwen, Apache 2.0)
  frozen eval sets, graded scores             training framework (MLX-LM / Unsloth)
  the three models, Apache 2.0                teacher (open-weight, never a commercial API)
  the Headworks harness                       runtime (Ollama; an embedded JVM provider later)
```

A new best sub-10B base appears every 6–13 months. A LoRA only works on the base it was trained
on. So the models are build artefacts, regenerated from the data; the data and the checks are
what stays. The full reasoning, with sources, is in [`docs/RESEARCH_BRIEF.md`](docs/RESEARCH_BRIEF.md);
the one-page picture is [`docs/architecture.pdf`](docs/architecture.pdf).

## How it runs

```
Cistern pod ──grant + receipt──► Penstock ──task → model──► Ollama
(schemas, dbt project,            │ JSON-schema output        │
 never rows)                      │ validators as tools        ▼
                                  └─► pass / fail / not run ──► files, or a blocker report
```

- Cistern holds the BigQuery schema exports and the dbt project behind a grant. Every read gets a
  receipt, so "the model saw schemas only" is evidence, not a claim.
- Penstock picks the model per task, enforces the JSON output, runs the validators as tools,
  repairs at most three times, and logs every model and tool call.
- A check that could not run is reported as `not_run`, never as `pass`.

## Status

Nothing is trained yet. The plan is [`docs/BUILD_PROMPT.md`](docs/BUILD_PROMPT.md); the first
spike is § 7 of the brief: one task (`dbt-bq`), one base, a frozen 20-case eval set, measured
against the untuned base on an M2 Max (32 GB).

Work that lives in other repos:
- Penstock: [#214](https://github.com/enrichmeai/penstock/issues/214) model per request ·
  [#215](https://github.com/enrichmeai/penstock/issues/215) JSON-schema output ·
  [#216](https://github.com/enrichmeai/penstock/issues/216) validator tools ·
  [#217](https://github.com/enrichmeai/penstock/issues/217) MCP tools ·
  [#218](https://github.com/enrichmeai/penstock/issues/218) models as release assets
- Culvert: [#285](https://github.com/enrichmeai/culvert/issues/285) DagSpec JSON + render CLI ·
  [#286](https://github.com/enrichmeai/culvert/issues/286) Airflow 3 output ·
  [#287](https://github.com/enrichmeai/culvert/issues/287) run a Cloud Run job locally

## Layout

```
docs/        the build prompt, the research brief, the architecture diagram
validators/  the checks: one script each, exit 0 pass / 1 fail / 2 not run, full output on stdout
evals/       frozen eval cases and the generated report (never in the training set)
training/    data synthesis, filters, SFT configs (Python ≥ 3.12)
models/      Modelfiles only; weights are release assets, never in git
penstock/    the application.yml fragment for Headworks (task → model map, tool policy)
```

## Licence

Apache 2.0. Models trained here carry the same licence; their bases and training data are listed
with their licences in `docs/BUILD_PROMPT.md` § 2.4–2.5.
