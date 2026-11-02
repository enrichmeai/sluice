# Research brief: making a small, task-specific LLM is cheap now. What to invest in.

Written 2026-11-01 for EnrichMeAI. Every number carries its source. **(search summary)** means the
page itself could not be fetched from the research environment (arxiv.org, huggingface.co,
unsloth.ai, openai.com, epoch.ai and several vendor sites did not resolve); treat those numbers as
unverified until someone opens the page. Vendor blogs are vendor blogs.

## 1. The cost of one training run is already small

| What | 2024 | 2025–26 | Source |
|---|---|---|---|
| LoRA/QLoRA fine-tune of a 7–8B model, GPU time | ≈$3 for 2 h on one A100 (search summary) | $1.56–$10 per run | arXiv 2406.02611; thundercompute.com; deploybase.ai; stratagem-systems.com |
| Full fine-tune of an 8B model | — | ≈$2,400 (40 H100-hours) | compute-market.com |
| H100 rental, per hour | ≈$8 at the late-2024 peak | $2.85–3.50 (Dec 2025); $1.25 spot to $12 on Azure (2026) | introl.com; emma.ms |
| 24 GB GPU (RTX 4090) rental | — | $0.34/h community, $0.69/h secure | tech-insider.org (RunPod) |
| QLoRA memory need | — | 7B ≈ 5 GB, 14B ≈ 8.5 GB; gpt-oss-20b 14 GB (search summary) | Unsloth docs |

One 2026 benchmark puts the GPU share of an end-to-end fine-tuning programme at $200–6,000 out of
$30k–180k (yusmpgroup.com, search summary). **The money goes into data, evaluation and people, not
compute.** A used 24 GB card or a Mac covers the training runs in this plan.

## 2. The tooling is commodity, and the hosted options are shrinking

- Open, Apache-2.0 frameworks have converged on one feature list (SFT, LoRA/QLoRA, DPO, GRPO,
  GGUF export): **Unsloth** (Studio no-code UI in beta since March 2026, UI under AGPL-3.0),
  **Axolotl** (YAML-driven, active), **LLaMA-Factory** (web UI). Pick one; do not write one.
- **NVIDIA NeMo Data Designer** (Apache-2.0) generates synthetic data with Python/SQL/LLM-judge
  validators built in. Worth a look for the generator.
- Hosted options are a bad dependency: **OpenAI fine-tuning closed to new users 7 May 2026** and
  ends 6 Jan 2027 (modelbrew.ai; official page is a search summary); **Predibase** was absorbed by
  Rubrik (June 2025) and its public pricing is gone; **Hugging Face AutoTrain is unmaintained**;
  **Google's distillation service** produces a Gemini student you cannot export.

## 3. Synthetic data with execution checks is the lever

- **SynSQL-2.5M / OmniSQL**: 2.5M samples over 16,583 synthetic databases, generated with open
  models only, Apache-2.0. OmniSQL-7B beats GPT-4o on several text-to-SQL sets (github.com/RUCKBReasoning/OmniSQL).
- **SLM-SQL** (July 2025): SFT + RL on that data takes a **1.5B** model to 67.08% BIRD dev, above
  OmniSQL-7B's 66.10% (arXiv 2507.22478, search summary).
- **Nemotron-4**: over 98% of its alignment data was synthetic, from about 20k human seeds (arXiv
  2406.11704, search summary). **Magpie**: 300k self-generated instructions beat the official
  Llama-3-8B-Instruct (arXiv 2406.08464, search summary).
- **s1 and LIMO**: about 1,000 and 817 well-chosen examples were enough for large reasoning
  gains on a 32B model (arXiv 2501.19393, 2502.03387, search summaries). Quality beats volume.
- **Caution on RL**: outcome-only GRPO on Qwen2.5-Coder-1.5B gave about no gain over SFT
  (huggingface.co/Anurich/slmsql-grpo-v2, search summary); Think2SQL finds partial, execution-based
  rewards essential (arXiv 2504.15077, search summary). So the validators must give graded
  signals (parses / compiles / tests pass / matches gold), not just pass-fail.

## 4. Small models are getting better fast

LiveCodeBench, as reported per model card (versions of the benchmark differ, so compare loosely):

| Model | Size | Date | Score | Source |
|---|---|---|---|---|
| Qwen2.5-Coder-7B-Instruct | 7B | Sep 2024 | 37.6 | arXiv 2409.12186 (search summary) |
| Qwen3.5-4B / 9B | 4B / 9B | Mar 2026 | 55.8 / 65.6 | model card (search summary) |
| Gemma 4 E4B / 26B-A4B | 4B / 26B MoE | Apr 2026 | 52.0 / 77.1 | ai.google.dev model card (search summary) |

A 4B model in 2026 beats the 7B coder of 2024. Qwen3/3.5 and Gemma 4 are Apache-2.0; Llama 4 has
no small dense model and a community licence.

## 5. What stays hard, and so is where value accrues

1. **The verifier.** No published benchmark exists for dbt-on-BigQuery or Airflow DAG generation.
   The nearest is defog's sql-eval (executes generated against gold SQL; supports BigQuery). An
   execution harness for these tasks is both the eval and the training reward, and nobody sells one.
2. **Base-model churn.** A LoRA lives in one base's weight space: Qwen3 (Apr 2025) → Qwen3.5
   (Mar 2026) → Qwen3.6 (Apr 2026); Gemma 3 → Gemma 4 in about 13 months. Expect a new best
   sub-10B base every 6–13 months. **Adapters are disposable; data and harness are not.** (Ramp's
   PorTAL claims adapters can be ported at ~98% of the lift, self-reported, July 2026.)
3. **Provenance.** The standards exist and are cheap: OpenSSF model signing v1.0 (Apr 2025, Sigstore
   bundles), CycloneDX 1.7 (Oct 2025) with a `machine-learning-model` component type, SPDX 3.0 AI
   and Dataset profiles. Penstock already ships an SBOM; models fit the same release.
4. **Inference cost is not the argument for local.** Per-token prices fall roughly 3–13× a year
   (Epoch AI, a16z, arXiv 2511.23455, search summaries). Local serving is justified by privacy,
   grants and receipts (Cistern), and control, which is Headworks' claim anyway.

## 6. What this means for EnrichMeAI

- **Own three things**: the execution-filtered training data, the frozen eval sets, and the
  Headworks harness (Cistern grants, Penstock tools, validators). Rent everything else.
- **Treat each fine-tune as a build artefact**, regenerated from the data whenever the base
  changes, signed and listed in the Penstock release SBOM.
- **Start on one task with one machine.** Budget: tens of dollars of GPU time, or none on your
  own card.
- **Do not depend on any hosted fine-tuning API.**

## 7. First spike (two weeks, one person, one machine)

Goal: prove the loop works end to end on `dbt-bq`, and measure whether a fine-tune beats the base.

1. **Eval set first.** 20 hand-checked cases: request + BigQuery schema (from Culvert's example
   projects and jaffle_shop) + assertions. Frozen before any data is generated.
2. **Validators**: `sqlfluff` (bigquery), `dbt parse`, and if a sandbox project exists `bq query
   --dry_run` on the compiled SQL. Each returns a graded score, not pass/fail.
3. **Baseline**: Qwen3.5-4B-Instruct (or Qwen2.5-Coder-7B if 3.5 lacks Unsloth support; check)
   untuned, run through the validators on the eval set. Record first-try scores.
4. **Generate**: Qwen3-Coder-30B-A3B via Ollama as teacher; 500–2,000 kept samples after
   validation; log the keep rate (this number tells you how much of the task the teacher already
   gets right).
5. **Train**: Unsloth QLoRA, r 16, 2 epochs, on the 24 GB card or the Mac. Merge, `q8_0` GGUF,
   `ollama create`.
6. **Measure**: rerun step 3. Ship only if it beats the base and loses ≤5 points on a generic code
   set. Write the numbers down, including a failed result.
7. **Decide**: if the keep rate in step 4 is above ~80%, the teacher alone may be good enough and
   the fine-tune's value is size and speed, not accuracy. That is still a result, and it changes
   which model to train next.

## Sources not opened (verify before quoting externally)
arXiv 2406.02611, 2406.11704, 2406.08464, 2409.12186, 2501.19393, 2502.03387, 2504.15077,
2507.22478, 2511.23455; Unsloth docs; Qwen3.5 and Gemma 4 model cards; Epoch AI and a16z posts;
OpenAI fine-tuning page; Google distillation page; yusmpgroup.com benchmark.
