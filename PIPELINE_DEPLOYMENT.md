# Airbnb Snapshot and Incremental Pipeline

## Data layout

The Dataproc job reads the three Airbnb CSVs from `gs://PROJECT_ID-landing/raw/airbnb/` and writes Parquet under `gs://PROJECT_ID-landing/derived/airbnb/`:

- `snapshot/{listings,calendar,reviews}/` contains a deterministic 80% sample per source table.
- `incremental/{listings,calendar,reviews}/dt=YYYY-MM-DD/` contains a deterministic 5% sample per table and run date. The date is a Hive partition in the path, not a source-data column.

The job's `both` mode is for the initial run. Use `incremental` on later daily runs. Re-running a date overwrites only that date's partition.

BigQuery external tables and trusted-table SQL live in `sql/airbnb/build_trusted.sql`. The query creates six external tables in `warehouse`, then materializes `airbnb_trusted_listings`, `airbnb_trusted_calendar`, and `airbnb_trusted_reviews`, preferring incremental rows when keys overlap.

## GitHub and Cloud Build setup

1. Sign in to GitHub and create an empty public repository named `gcp_de_programm` under `4dori`.
2. In Google Cloud Console, connect that repository under Cloud Build > Repositories (2nd gen) and install/authorize the Cloud Build GitHub App for it.
3. Push this repository's `main` branch to `https://github.com/4dori/gcp_de_programm.git`.
4. From `terraform/`, run `terraform init` and inspect `terraform plan`. Apply only after reviewing the plan; this Terraform configuration also manages existing Cloud SQL and NAT resources, so do not use an automatic apply on each push.
5. The Terraform Cloud Build trigger watches `main`. A push publishes `pyspark-jobs/` and `sql/` to the existing `${PROJECT_ID}-deploy` bucket and deploys both workflow definitions. It does not apply Terraform.

The deploy bucket is the existing Terraform-managed bucket; no separate scripts bucket is needed. The workflow service account has read access to the SQL artifact and permission to create tables and submit BigQuery jobs.

## Run the workflow

Bootstrap the snapshot and the first incremental partition:

```powershell
$PROJECT_ID = (gcloud config get-value project).Trim()
$RUN_DATA = @{ project_id = $PROJECT_ID; region = "us-central1"; mode = "both"; date = (Get-Date -Format "yyyy-MM-dd") } | ConvertTo-Json -Compress
gcloud workflows run airbnb-snapshot-incremental `
  --location=us-central1 `
  --data="$RUN_DATA"
```

For subsequent daily runs, use `"mode":"incremental"` and the run date. `snapshot` refreshes only the snapshot; use it after a successful bootstrap. The workflow waits for Dataproc, fetches the deployed SQL file, substitutes the project ID, and waits for the BigQuery script to finish.

The job uses Spark's fractional sampling, so 80% and 5% are expected sample fractions rather than guaranteed exact row counts. Incremental samples are deterministic for a given date; they represent sampled changed rows only if the input files have been updated to contain that day's changes.
