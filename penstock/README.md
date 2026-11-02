# penstock

The `application.yml` fragment that wires the three models into Headworks once penstock#214
(model per request), #215 (JSON-schema output) and #216 (validator tools) ship:

```yaml
agent:
  llm:
    provider: ollama
    ollama:
      num-ctx: 16384
      models:
        dbt-bq: enrichmeai/dbt-bq:0.1
        composer-dag: enrichmeai/composer-dag:0.1
        cloudrun-job: enrichmeai/cloudrun-job:0.1
  tools:
    enabled: [read_file, write_file, validate_dbt, validate_dag, validate_container, pod]
    policy:
      validate_container: ask
```

Until #214 ships, `run-headworks.sh` (to be written) starts one Penstock per model, each with its
own `OLLAMA_MODEL`, beside a Cistern pod with the schema folder granted.
