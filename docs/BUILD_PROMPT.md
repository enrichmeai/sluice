# Build prompt: small, task-specific local LLMs for dbt on BigQuery, Composer DAGs and Cloud Run jobs, run inside Headworks (Penstock + Cistern)

> Hand this file to a Claude Code session in the product's own repo (working name `sluice`;
> the founder names it). Research done 2026-11-01. Every fact carries its source. **[unverified]**
> means the official page was blocked in the research environment and the fact came from a search
> summary or a mirror: check it before relying on it. The research environment could not reach
> huggingface.co, docs.unsloth.ai, ollama.com, docs.getdbt.com, docs.cloud.google.com, docs.spring.io
> or arxiv.org.

---

## 1. What you are building

**Three small, fine-tuned local models, one per task, running inside Headworks.** Headworks is
Penstock and Cistern together on one machine (enrichmeai.com/headworks): Penstock is the agent that
runs the model and its tools; Cistern is the data pod that holds what the agent may read, checks
the grant on every request and writes a receipt. No new service is built. The models are the
product; Headworks is the harness.

| Model | Task | Input | Output |
|---|---|---|---|
| `dbt-bq` | dbt for BigQuery | a request plus the BigQuery schema (tables, columns, types) | `models/*.sql`, `sources.yml`, `schema.yml` with tests and `unit_tests:` |
| `composer-dag` | Airflow DAG for Cloud Composer | a request plus the dbt model graph | one DAG file in Culvert's rendered style (`KubernetesPodOperator` or `CloudRunExecuteJobOperator`) |
| `cloudrun-job` | Cloud Run job container | a request plus the dbt command to run | `Dockerfile` and a Python entrypoint that honours `CLOUD_RUN_TASK_INDEX` / `CLOUD_RUN_TASK_COUNT` |

Each is a **LoRA fine-tune of a 3B–8B open-weight base, merged into one GGUF, loaded into Ollama**.
**Penstock** (Spring Boot, Ollama provider) calls them: one Penstock task per model, with the
validators as Penstock tools run through its `ShellTool`.

**Not a planner, not retrieval.** The models are the product. Penstock's job is thin: pick the
model for the task, call it, check the output with a deterministic validator, report.

**Two repos are touched.** This repo holds training, validators, evals and Modelfiles. Penstock
gets the small changes in §2.6, each as its own issue and PR in `enrichmeai/penstock`, built in a
Penstock session (one writer per repo).

**How Headworks is used**
- **Cistern holds the inputs**: the BigQuery schema exports (`INFORMATION_SCHEMA` or `bq show
  --schema` dumps), the existing dbt project and `system.yaml`. The user grants Penstock the
  schema folder and nothing else. Every read gets a receipt, so "the model saw schemas only" is
  provable from Cistern's receipts, not asserted.
- **Penstock runs the models** through its Ollama provider, one task → one model, and runs the
  validators through its tools. With memory on, past episodes (what was asked, what failed, what
  was fixed) go into the prompt first; the training loop can mine those episodes for new seeds.
- **Penstock's audit log** (database storage) records every model call and tool call, which is the
  eval's provenance.

**Hard rules**
- All training and inference run on the user's machine. Table **rows never enter a training set
  or a prompt**; schemas and metadata only. In Headworks this is a Cistern grant on a schema
  folder, with the receipts as evidence.
- The training data and the teacher model must be **licence-clean for a commercial product** (§4).
  No distilling from Claude, GPT or Gemini.
- Each model ships with an eval report. **No model ships below the baseline** (§6).
- Validators never run against production. The sandbox tier is opt-in. A check that could not run
  is reported as `not_run`, never as `pass`.

---

## 2. Verified facts

### 2.1 The target outputs (Culvert v0.6.1, `enrichmeai/culvert`, release tag v0.6.1)
- The cloud-neutral DAG model and renderers exist in Java only: `DagSpec`/`TaskSpec`,
  `SubstrateDagRenderer(ExecutionSubstrate)`, substrates `COMPOSER_2_GKE_PODS`, `COMPOSER_3`
  (`composer-3-airflow-2`, namespace `composer-user-workloads`, ≤1 sidecar) and `CLOUD_RUN_JOBS`
  (`data-pipeline-orchestration-java/README.md:23-56`, `ExecutionSubstrate.java:46-97`).
- Task params: `image` (required), `namespace` (Composer 3 rejects it), `sidecars`,
  `cloud_run_job` + `region` (Cloud Run), `project_id` defaulting to `{{ var.value.gcp_project }}`
  (`SubstrateDagRenderer.java:33-39`).
- **Golden output files**: `golden/substrate-composer3.py` (`KubernetesPodOperator`,
  `config_file="/home/airflow/composer_kube_config"`) and `golden/substrate-cloud-run.py`
  (`CloudRunExecuteJobOperator`). **These define the `composer-dag` model's output style.**
- dbt: `culvert[transform]` (`dbt-bigquery>=1.5.0`) ships the macros `audit_columns`,
  `data_quality_check`, `enrichment`, `pii_masking`. Example projects:
  `deployments/bigquery-to-mapped-product/dbt`, `deployments/fdp-to-consumable-product/dbt`,
  `deployments/spanner-to-bigquery-load/dbt`, `data-pipeline-transform/tests/unit/dbt_test_project`.
  A scaffolder: `deployments/bigquery-to-mapped-product/generate_dbt_models.py`.
- dbt container: `python:3.11-slim` → `pip install dbt-bigquery` → `dbt deps` → `ENTRYPOINT ["dbt"]`
  (`deployments/bigquery-to-mapped-product/Dockerfile`). **This defines the `cloudrun-job` style.**
- Local stack: `scripts/airflow-local/docker-compose.yml` (Airflow 2.10.0, BigQuery/GCS/Pub-Sub
  emulators; `up.sh`, `seed-all.sh`, `run-dag.sh`, `down.sh`).
- Gaps: Composer proof harness not yet run on real GCP (`CHANGELOG.md:249-260`); Composer 3 pinned
  to Airflow 2 (`terraform/variables.tf:49-51`); no local Cloud Run instructions.

### 2.2 dbt, Composer, Cloud Run
- dbt-core 1.12.6, dbt-bigquery 1.12.1 (Python ≥3.10) on PyPI. dbt-core `main` is **dbt v2, a Rust
  rewrite** (v2.0.8); v1 lives on `1.latest`. Pin one.
- `dbt parse` validates the project **without a warehouse connection**; `dbt compile` connects
  (dbt-labs/docs.getdbt.com `reference/commands/parse.md`, `compile.md`). Unit tests and `--empty`
  since dbt-core 1.8.0.
- **goccy/bigquery-emulator does not run dbt reliably** (no `DestinationTable`, issue #197; adapter
  PR #1017 not merged). Do not use it as a dbt validator.
- Composer 3 offers Airflow 3 (GA 2026-04-22) **[unverified]**; Culvert targets Airflow 2.
  `composer-dev` (GoogleCloudPlatform/composer-local-dev) runs Composer images locally, test only.
- apache-airflow-providers-google 22.8.0: `CloudRunExecuteJobOperator(overrides=…, deferrable=…)`.
- DAG validation without a cluster: DagBag import test (`assert dagbag.import_errors == {}`,
  apache/airflow `best-practices.rst`); `airflow dags test` on SQLite; ruff `AIR` rules.
- Cloud Run jobs set `CLOUD_RUN_TASK_INDEX` (0…n−1) and `CLOUD_RUN_TASK_COUNT` **[unverified]**;
  Google's sample defaults the index to 0 when unset. Local run (inferred):
  `docker run -e CLOUD_RUN_TASK_INDEX=0 -e CLOUD_RUN_TASK_COUNT=1 <image> <args>`.

### 2.3 Fine-tuning
- **Unsloth 2026.10.11** (PyPI): LoRA/QLoRA/full FT, GGUF export via
  `save_pretrained_gguf(..., quantization_method=…)` with `q4_k_m`, `q5_k_m`, `q8_0`, `f16`
  (`unsloth/save.py`). Notebooks for Qwen2.5-Coder 1.5B/14B, Qwen3 0.6B–32B, Llama 3.1 8B,
  Llama 3.2 1B/3B, Gemma 3, gpt-oss 20B; **none for Qwen3-Coder or Devstral**. Chat templates
  `qwen-3`, `qwen-2.5-coder`, `llama-3.1`, `gemma-3`, plus `train_on_responses_only`
  (`unsloth/chat_templates.py`). QLoRA VRAM: 7B ≈ 5 GB, 8B ≈ 6 GB, 14B ≈ 8.5 GB; 16-bit LoRA 7B
  ≈ 19 GB **[unverified]**. Hyperparameter defaults: LR 2e-4, 1–3 epochs, r 16, alpha = r or 2r
  **[unverified]**.
- **TRL 1.17.1 / PEFT 0.21.2**: `SFTTrainer(model, train_dataset, peft_config=LoraConfig())`;
  `assistant_only_loss=True` masks loss to assistant turns; ~1e-4 LR for adapters
  (huggingface/trl `docs/source/sft_trainer.md`).
- **LLaMA-Factory 0.9.5**: QLoRA 4-bit, 7B ≈ 6 GB, 14B ≈ 12 GB; merge with `llamafactory-cli export`.
- **MLX-LM 0.32.2** (Apple Silicon): `mlx_lm.lora --model <m> --train --data <d> --iters 600`;
  `mlx_lm.fuse --export-gguf` only for Mistral/Mixtral/Llama-style fp16 (`mlx_lm/LORA.md`).
- **llama.cpp**: `convert_hf_to_gguf.py --outtype f16|bf16|q8_0`, then `llama-quantize`;
  `convert_lora_to_gguf.py --base <dir>` for adapter-only GGUF.
- **Ollama v0.40.13**: `FROM /path/to/file.gguf` + `ollama create`; it does not quantize on import
  (`docs/import.mdx`). **`ADAPTER` is no longer in the current docs**, though `parser/parser.go`
  still accepts it; safetensors-base-plus-LoRA is an open PR (#17377). **Ship merged GGUFs.**
  Default context is 4096 tokens; set `num_ctx`.
- Chat-template mismatch is the usual cause of garbage output from a converted model **[unverified,
  Unsloth docs]**.

### 2.4 Base models (licence · Unsloth notebook)
| Base | Sizes | Licence | Unsloth |
|---|---|---|---|
| Qwen2.5-Coder | 0.5/1.5/3/7/14/32B | Apache 2.0, **except 3B = qwen-research** **[unverified]** | 1.5B, 14B |
| Qwen3 | 0.6B–32B dense, 30B-A3B | Apache 2.0 (QwenLM/Qwen3 README) | 0.6B–32B |
| Qwen3-Coder | 30B-A3B, 480B-A35B, Next 80B-A3B | README states no licence; Apache 2.0 per aggregators **[unverified]** | none |
| Llama 3.1 / 3.2 | 1B/3B/8B | Llama licence: derivative names must start with "Llama", "Built with Llama" notice | yes |
| Gemma 3 | 270M–27B | Gemma Terms, not Apache; Gemma 4 is Apache 2.0 **[unverified]** | yes |
| gpt-oss-20b | 21B / 3.6B active | Apache 2.0, runs in 16 GB (openai/gpt-oss README) | yes |

**Recommendation:** student = **Qwen2.5-Coder-7B** (or Qwen3-8B) for all three tasks; teacher for
synthetic data = **Qwen3-Coder-30B-A3B** or **gpt-oss-20b** (both open-weight). Both sides are
Apache 2.0 **once the Qwen3-Coder licence is confirmed on huggingface.co**. Avoid the Qwen2.5-Coder
3B (research licence), Llama (naming clause) and Gemma 3 (terms).

### 2.5 Training data and licences
- **SQL**: SynSQL-2.5M (2.5M samples, 16,583 synthetic DBs, Apache 2.0, RUCKBReasoning/OmniSQL);
  gretel `synthetic_text_to_sql` (100k+, Apache 2.0 **[unverified]**); sql-create-context
  (CC BY 4.0 **[unverified]**). Spider and BIRD are CC BY-SA 4.0 (one paper says BIRD is CC BY-NC
  **[unverified]**: check before use). All are SQLite dialect, so useful only as pre-training for
  SQL shape, not for BigQuery.
- **Spider 2.0-DBT**: 68 repository-level dbt tasks (DuckDB); Spider2-Lite has 214 BigQuery examples
  (xlang-ai/Spider2 README). The nearest published eval.
- **No public dbt or Airflow corpus exists.** Seeds available: Culvert's example projects and golden
  DAGs, dbt-labs `jaffle_shop` (and its successors), astronomer-cosmos `dev/dags` (Apache 2.0).
  GitHub repos with `dbt_project.yml` or `DAG(` would have to be mined and licence-filtered.
- **Synthesis**: Self-Instruct (175 seeds → 52k; yizhongw/self-instruct), Magpie **[unverified]**.
  Evol-Instruct/WizardCoder data is CC BY-NC: **do not use**.
- **Teacher ToS**: Anthropic consumer terms §3 and commercial terms D.4(a) forbid using the service
  to train competing models (anthropic.com/legal); OpenAI's terms bar using output to develop
  competing models **[unverified]**. An open-weight teacher avoids the question.
- Dataset size: LIMA, 1,000 curated examples **[unverified]**; practitioner guidance 1k–10k for a
  domain, 5k–50k for code **[unverified]**. "LoRA Learns Less and Forgets Less": LoRA lags full
  fine-tuning most on code but forgets less **[unverified]**.

### 2.6 Penstock v0.6.0 (`enrichmeai/penstock`, tag v0.6.0, read 2026-11-01)
- **One provider and one model per process.** The provider bean is chosen by
  `agent.llm.provider` (`OllamaProvider.java:38`); the Ollama model is a single property, default
  `llama3.2:3b`, `num_ctx` 16384 (`AgentProperties.java:261-282`), sent as
  `body.put("model", cfg.getModel())` (`OllamaProvider.java:98`). `ChatRequest` has only
  `sessionId` and `message` (`ChatRequest.java:5-8`). **So Penstock cannot yet route a request to
  `dbt-bq` and the next to `composer-dag`.**
- Tools are Java `Tool` implementations (`name`, `description`, `inputSchema`, `execute`),
  discovered by `ToolRegistry` and filtered by `agent.tools.enabled` (`ToolRegistry.java:23-38`),
  each with an allow/ask/deny policy (`application.yml:222-225`) and pre-tool hooks (`:215-219`).
- `ShellTool` runs `bash -lc <command>` behind an optional allow-list of first tokens, blocked
  patterns and a 600 s timeout (`ShellTool.java:95-106`, `application.yml:226-234`). **So `dbt
  parse`, `docker build` and the DagBag test can run today, fenced by `allowed-commands`.**
- `OllamaProvider` calls `/api/chat` with `tools` (`OllamaProvider.java:115,156`) and falls back
  to parsing tool calls written as text (`:216`, `TextToolCallParser.java`). **It does not use
  Ollama's `format` (JSON schema) field.**
- MCP: server only (`--mcp` exposes `recall`, `draft_episode`; `McpStdioRunner.java:24-34`). No
  MCP client.
- Penstock's own tool-call check: `llama3.2:3b` 4/4, `llama3.1:8b` 4/4, `qwen3-coder:30b` 1/4,
  `qwen2.5-coder:3b` 0/4 (`.claude/skills/model-toolcall-check/SKILL.md:14-17`).

**Penstock changes needed (file each as an issue in `enrichmeai/penstock`, smallest first):**
1. **Model per request or per task.** A `model` field on `ChatRequest` (or a named task → model
   map in `agent.llm.ollama.models`) that `OllamaProvider` sends instead of the single property.
   Workaround until it ships: one Penstock instance per model, each with its own `OLLAMA_MODEL`.
2. **Structured output.** Pass a JSON schema as Ollama's `format` so the model returns
   `{"files": {path: content}}` rather than free text (Ollama docs `capabilities/structured-outputs.mdx`).
3. **Three MCP tools** on the existing server: `generate_dbt`, `generate_dag`,
   `generate_cloudrun_job`, each calling its model and the validators, so Claude Code can use them.
4. **Validator tools**: either `ShellTool` with `allowed-commands: [dbt, python, ruff, docker,
   sqlfluff]`, or one `Tool` per validator wrapping the scripts in this repo's `validators/`.
5. **Model assets on the release** (`RELEASE.md`): the three GGUFs and Modelfiles attached to the
   Penstock release, with checksums in the SBOM. Later, not now: an embedded inference provider.

### 2.7 Considered on 2026-11-02 (all facts from search summaries; verify before use)
- **Colibri** (github.com/JustVugg/colibri): a pure-C, dependency-free inference engine that
  streams Mixture-of-Experts experts from disk, so very large MoE models run on ordinary
  hardware; Apache 2.0, v1.8.0 (2026-08-24) **[unverified]**. It is a runtime, so it does not
  change the decision ("own the weights, not the runtime"). **Optional spike experiment:** use
  it only as the *teacher* runtime, to run a larger open-weight MoE teacher on the M2 Max than
  Ollama can hold, for overnight data generation. Check first: Apple Silicon / Metal support,
  model formats it loads, tokens per second. Never for serving.
- **nanochat** (github.com/karpathy/nanochat, Oct 2025): a minimal full-stack pipeline that
  pretrains, fine-tunes and serves a small model from scratch on a rented 8×H100 node; the $100
  tier (~4 h) yields a model well below any 4B open-weight base, and $300–1,000 tiers approach
  GPT-2 **[unverified]**. **Not chosen**: a fine-tune of an Apache 2.0 base starts from far more
  pretraining than this budget buys. Keep it as (1) reading for the team on what SFT, eval and a
  chat loop are, and (2) a round-two idea: its March 2026 follow-on, autoresearch, has agents
  search training configs against an eval, which fits this project once the eval harness exists.
- **Names:** "Colibri"/"Collibri" is taken several times over and is one letter from Collibra;
  not usable. Working name under consideration: **Sluice** (check PyPI, GitHub, Maven Central).

---

## 3. Architecture

```
training/  (Python, this repo)                        Headworks = Penstock + Cistern
seeds ─► synth (open teacher) ─► exec filter ─► SFT ─► merge ─► GGUF ─► ollama create
                                   ▲                                         │
                                   └──── same validators/ scripts ───────────┤
                                                                             ▼
 Cistern pod ──grant+receipt──► Penstock task (task → Ollama model) ─► JSON-schema call ─► validator tools ─► report
 (schemas, dbt project)                                                              │ fail (≤3) ─► re-call with the error
                                                                                      └─► episode → memory → next seeds
```

- **Repo layout:** `training/` (Python ≥3.12: data synthesis, filters, SFT configs, eval),
  `validators/` (shell scripts, called by the training filter, the evals and Penstock's tools),
  `evals/` (held-out sets and reports), `models/` (Modelfiles, never weights),
  `penstock/` (the `application.yml` fragment: task → model map, tool policies, allowed commands).
- **Execution-filtered data is the whole trick.** Every synthetic example passes the same
  validators the service runs before it enters the training set. The teacher writes candidates;
  `dbt parse`, the DagBag import, ruff `AIR` and `docker build` decide which survive.
- **Output contract per model** is a JSON object `{ "files": { "<path>": "<content>" } }`, enforced
  through Ollama's `format` once Penstock change 2 ships; until then, trained into the model and
  parsed leniently. Penstock writes the files to a work dir and runs the validator tools.
- **Repair** is one more call to the same model with the validator's output appended, at most 3
  times, then a blocker report.

### 3.1 Validators (shared by training filter, Penstock tools and eval)
| Tier | Check | Tool |
|---|---|---|
| Offline | SQL lint, BigQuery dialect | `sqlfluff` (`dialect = bigquery`, `templater = dbt`) **[check current sqlfluff docs]** |
| Offline | dbt project valid | `dbt parse` with a dummy `profiles.yml` |
| Offline | DAG imports; style | DagBag import test; `ruff check --select AIR`; diff against Culvert golden structure |
| Offline | image builds and starts | `docker build`; `docker run -e CLOUD_RUN_TASK_INDEX=0 -e CLOUD_RUN_TASK_COUNT=1 <img> --version` |
| Local Airflow | DAG executes | Culvert `scripts/airflow-local` or `composer-dev`, `airflow dags test` with remote operators stubbed |
| Sandbox (opt-in) | SQL valid on real schema | `dbt compile`, `bq query --dry_run`, `dbt build --empty --target sandbox`, `dbt test --select test_type:unit` |

---

## 4. Decisions for the founder (ask once, lead with the recommendation)
1. **Student base.** Recommended Qwen2.5-Coder-7B (Apache 2.0, Unsloth support, QLoRA fits 8 GB).
   Alternative Qwen3-8B. A 1.5B variant for laptops is a stretch goal.
2. **Teacher.** Recommended Qwen3-Coder-30B-A3B via Ollama, after confirming its licence on
   huggingface.co. Alternative gpt-oss-20b. **Never a commercial API.**
3. **Training machine (decided 2026-11-02): the founder's M2 Max, 32 GB.** Train with MLX-LM
   (`mlx_lm.lora`, QLoRA on a 4-bit base; tune `--batch-size`, `--num-layers`,
   `--grad-checkpoint` to fit). Run the teacher (Qwen3-Coder-30B-A3B at Q4 ≈ 19 GB) and the
   training in sequence, never together. Export: `mlx_lm.fuse` to merge, then llama.cpp
   `convert_hf_to_gguf.py` + `llama-quantize` (MLX's own `--export-gguf` covers only
   Llama/Mistral-style fp16). Fallback for anything MLX cannot train: rent an RTX 4090
   ($0.34–0.69/h) and use Unsloth; buy NVIDIA hardware only after the spike proves the fine-tune
   beats the base.
4. **Airflow line and dbt engine.** Recommended Airflow 2 on `composer-3-airflow-2` and
   dbt-core 1.12.x, matching Culvert. Airflow 3 and dbt v2 as later targets.
5. **Where it lives.** New repo `enrichmeai/sluice` for training, validators, evals and
   Modelfiles. Penstock changes are issues and PRs in `enrichmeai/penstock`. Culvert gaps (JSON
   DagSpec input, render CLI, Airflow 3 renderer, local Cloud Run docs) are issues in
   `enrichmeai/culvert`, not fixes here.
6. **Distribution (decided 2026-11-01: own the weights, not the runtime).** The merged GGUFs
   and their Modelfiles are **Penstock release assets**, next to the jar, SBOM and image, under
   Apache 2.0 and named `enrichmeai/dbt-bq`, `enrichmeai/composer-dag`, `enrichmeai/cloudrun-job`
   with the Penstock version they were tested against. Ollama is the runtime for now: `make
   models` downloads the assets from the release and runs `ollama create`. Weights are never in
   git. A fifth Penstock issue, **"embedded inference provider"** (run a GGUF inside the JVM so
   Headworks needs no Ollama install), is filed as later work and not built in this round.

---

## 5. Build order (each step green before the next)
1. **Validators** in `validators/` as scripts returning `pass|fail|not_run` + output. Prove each one
   red on a broken fixture first.
2. **Seeds and held-out eval set**: ≥60 hand-checked cases (20 per task) from Culvert's projects,
   jaffle_shop and Cosmos example DAGs, each with request, schema input and assertions. **Freeze it
   before any training data is generated**, and keep it out of the training set.
3. **Baseline**: run the untuned student (Qwen2.5-Coder-7B-Instruct) through the validators on the
   eval set. Record first-try pass rate per tier. This is the bar.
4. **Synthetic data per task**: teacher generates (request, input, files) triples from schema
   templates and Self-Instruct-style prompt variation; keep only validator-passing samples; dedupe;
   target 2k–5k per task. Log the keep rate.
5. **SFT**: Unsloth (or TRL) QLoRA, r 16, alpha 32, LR 2e-4, 2 epochs, `train_on_responses_only`,
   the base model's own chat template, `num_ctx` ≥ 16k for the dbt task. One run per task, config
   in `training/configs/<task>.yaml`.
6. **Merge and export**: merge LoRA, `save_pretrained_gguf` (`q8_0` for eval, `q4_k_m` for
   distribution), Modelfile with the matching template and a `SYSTEM` line, `ollama create`.
7. **Eval**: rerun step 3 on each fine-tune; also a generic held-out code prompt set to check
   forgetting. Write `evals/report.md`.
8. **Headworks wiring**: file the four issues in §2.6 in `enrichmeai/penstock` at step 1, so they
   are built in parallel in a Penstock session. Here, ship `penstock/application.yml` (task →
   model map, `agent.tools.enabled`, `allowed-commands`) and an end-to-end script that starts
   Ollama with the three models, starts Penstock with that config, and runs the eval set through
   it. Until Penstock change 1 ships, the script starts one Penstock per model. Cistern needs no
   change: the schema folder is an ordinary grant (Cistern quickstart + INTEGRATION.md step 1).
9. **Iterate**: failure modes from the eval report become new seed categories; retrain.

---

## 6. Eval and release gate
- Metrics per model per tier: first-try pass rate, pass rate after ≤3 repairs, mean repairs, tokens
  out, wall time, peak RAM at q4_k_m.
- **Release gate:** fine-tune beats the untuned base on first-try offline pass rate on the frozen
  eval set, and loses no more than 5 points on the generic code set.
- Report Spider2-Lite BigQuery results for `dbt-bq` where the 214 examples can be run (opt-in, needs GCP).

---

## 7. Training-prompt templates (the system prompt baked into each Modelfile)

**dbt-bq**
> You write dbt projects for BigQuery Standard SQL (dbt-core 1.12). Use `{{ source() }}` and
> `{{ ref() }}`; never hard-code project or dataset names. Incremental models use
> `materialized='incremental'`, `incremental_strategy='merge'`, a `unique_key` and an
> `is_incremental()` filter. Every model has a `schema.yml` entry with a description, `not_null`
> and `unique` tests on its key, and one `unit_tests:` case with `given`/`expect` rows. Use only
> columns present in the SCHEMA. Reply with JSON `{"files": {path: content}}` only.

**composer-dag**
> You write one Airflow 2 DAG file for Cloud Composer in the style of the provided example. Tasks
> run a container: on `composer_3` use `KubernetesPodOperator` with
> `config_file="/home/airflow/composer_kube_config"`, namespace `composer-user-workloads`, no
> extra namespace, at most one sidecar; on `cloud_run_jobs` use `CloudRunExecuteJobOperator` with
> `project_id`, `region`, `job_name`. Task ids are snake_case; dependencies follow the model graph.
> Reply with JSON `{"files": {path: content}}` only.

**cloudrun-job**
> You write a Cloud Run job: a `Dockerfile` from `python:3.11-slim` that installs
> `dbt-bigquery==<pinned>`, copies the dbt project, runs `dbt deps`, and a Python entrypoint that
> reads `CLOUD_RUN_TASK_INDEX` and `CLOUD_RUN_TASK_COUNT` (defaulting to 0 and 1), runs the given
> dbt command, and exits non-zero on failure. Reply with JSON `{"files": {path: content}}` only.

---

## 8. Done means
- `validators/` green on fixtures; `evals/report.md` shows each model above the gate in §6.
- Three Modelfiles and a `make models` that downloads the GGUFs from the Penstock release and
  runs `ollama create`; the checksums match the release's SBOM.
- The end-to-end script starts Headworks (Cistern pod with the schema folder granted, Penstock with
  the three models), runs the eval set through it, and reproduces the report's numbers. Cistern's
  receipts for the run show reads of the schema folder only.
- The four Penstock issues are filed and linked; the README says which have shipped and which
  still need the one-instance-per-model workaround.
- README states the pinned versions (base model and revision, Unsloth/TRL, dbt, Airflow,
  providers-google, Penstock, Ollama), the training data sources and licences, the
  teacher model and its licence, hardware used and training time, and **everything still marked
  [unverified] above** that was not confirmed.
- Issues filed in `enrichmeai/culvert` for the gaps in §4.5 and linked from the README.
