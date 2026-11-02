# models

Modelfiles only. Weights are Penstock release assets (penstock#218), never in git.

```
make models   # downloads the GGUFs named in each Modelfile from the release, checks SHA-256
              # against the release SBOM, runs `ollama create` for each
```

Each Modelfile: `FROM ./<name>-<ver>-q4_k_m.gguf`, the base model's own chat `TEMPLATE`, a
`SYSTEM` line (the task prompt from `docs/BUILD_PROMPT.md` § 7), `PARAMETER num_ctx 16384`.
Merged GGUFs, not adapters: Ollama's current docs no longer document `ADAPTER`.

Empty until the spike's step 6.
