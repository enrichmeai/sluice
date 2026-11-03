# Shape of deployments/bigquery-to-mapped-product/Dockerfile in enrichmeai/culvert v0.6.1,
# cut down to what a Cloud Run job needs: python:3.11-slim, dbt-bigquery, an entrypoint that
# honours CLOUD_RUN_TASK_INDEX / CLOUD_RUN_TASK_COUNT.
FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir dbt-bigquery==1.12.1
COPY entrypoint.py /app/entrypoint.py
ENTRYPOINT ["python", "/app/entrypoint.py"]
CMD ["run"]
