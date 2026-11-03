from datetime import datetime
from airflow import DAG
from airflow.providers.google.cloud.operators.cloud_run import CloudRunExecuteJobOperatorr  # typo

with DAG(dag_id="broken", schedule=None, start_date=datetime(2024, 1, 1), catchup=False) as dag:
    CloudRunExecuteJobOperatorr(task_id="t", project_id="p", region="europe-west2", job_name="j")
