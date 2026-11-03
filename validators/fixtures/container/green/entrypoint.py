"""Cloud Run job entrypoint: run one dbt command, honouring the task env Cloud Run sets."""
import os
import subprocess
import sys

index = int(os.environ.get("CLOUD_RUN_TASK_INDEX", "0"))
count = int(os.environ.get("CLOUD_RUN_TASK_COUNT", "1"))
args = sys.argv[1:] or ["run"]
print(f"sluice job task {index + 1}/{count}: dbt {' '.join(args)}", flush=True)
sys.exit(subprocess.call(["dbt", *args]))
