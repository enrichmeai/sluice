# evals

The frozen eval set and the report that gates every model.

- `cases/<task>/<id>.yaml`: one case = `request`, `input` (a schema export or dbt project path,
  schemas only), `assertions` (files that must exist, task ids and edges a DAG must have, the
  substrate). At least 20 per task before any training data is generated; frozen from then on,
  and checked against the training set for leakage.
- `report.md`: regenerated on every run. Per model and tier: first-try pass rate, pass rate after
  ≤3 repairs, mean repairs, tokens out, wall time, peak RAM at q4_k_m.

Release gate (`docs/BUILD_PROMPT.md` § 6): a fine-tune ships only if it beats the untuned base on
first-try offline pass rate here and loses no more than 5 points on the generic code set.

Empty until the spike's step 2.
