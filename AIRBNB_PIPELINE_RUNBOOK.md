# Airbnb Pipeline Runbook

This runbook covers deploying and operating the Airbnb snapshot/incremental pipeline in the GCP project. Replace the project ID below if using another environment.

## Pipeline Overview

1. Source CSVs are staged in `gs://PROJECT_ID-landing/raw/airbnb/`.
2. Dataproc Serverless runs `generate_snapshot_incremental.py`.
3. An 80% sample is written to `derived/airbnb/snapshot/`.
4. A 5% sample is written to `derived/airbnb/incremental/{table}/dt=YYYY-MM-DD/`.
5. The workflow runs `sql/airbnb/build_trusted.sql`, which creates six BigQuery external tables and three trusted tables in the `warehouse` dataset.

The `dt` value is encoded in the incremental directory path and is not a source-data column. Spark sampling is approximate, not an exact row percentage.

## Prerequisites

- `gcloud` is authenticated to the intended GCP project.
- Terraform-managed buckets, the `warehouse` dataset, service accounts, and APIs exist.
- The workflow `airbnb-snapshot-incremental` is deployed in `us-central1`.
- The Dataproc job and SQL files are present in the deploy bucket.
- The workflow service account has:
  - `roles/iam.serviceAccountUser` on `sa-dataproc-jobs`.
  - `roles/storage.objectViewer` on both the deploy and landing buckets.
  - `roles/bigquery.jobUser` on the project.
  - `roles/bigquery.dataEditor` on the `warehouse` dataset.
- The Dataproc service account can read/write the required GCS data and create/query BigQuery tables.

Set the project and confirm it:

```powershell
$PROJECT_ID = (gcloud config get-value project).Trim()
$PROJECT_ID
```

If Terraform IAM files were changed, inspect and apply them deliberately before running:

```powershell
terraform -chdir=terraform plan -var-file=terraform.tfvars
terraform -chdir=terraform apply -var-file=terraform.tfvars
```

Do not run an unreviewed full infrastructure apply from a source-push build. This Terraform configuration also manages paid and stateful resources.

## Publish Code to GCS

The Cloud Build trigger `publish-program-scripts-main-yaml` listens for pushes to `main` on `4dori/tf_gcp_mentor` and uses that repository's checked-in `cloudbuild.yaml`. A merged pull request produces that push event. The build config clones `4dori/gcp_de_programm` and copies its PySpark and SQL directories to the deploy bucket; it does not apply Terraform.

To publish an updated program:

1. Push/merge the updated PySpark or SQL files to `main` in `4dori/gcp_de_programm`.
2. Push/merge a commit to `main` in `4dori/tf_gcp_mentor` to invoke the trigger, if no source change already did so.
3. Check the Cloud Build run is successful.
4. Verify the deployed artifacts:

```powershell
gcloud storage ls "gs://$PROJECT_ID-deploy/jobs/airbnb/"
gcloud storage ls "gs://$PROJECT_ID-deploy/sql/airbnb/"
```

The artifact repository is cloned by the trigger; it is not itself linked as a Cloud Build repository.

## Upload Source CSVs

CSV files are not stored in Git. Upload all three to the expected landing prefix:

```powershell
gcloud storage cp listings.csv calendar.csv reviews.csv `
  "gs://$PROJECT_ID-landing/raw/airbnb/"
```

Check that all three objects exist before starting Dataproc:

```powershell
gcloud storage ls "gs://$PROJECT_ID-landing/raw/airbnb/"
```

## Initial Bootstrap

Run `both` once to write the snapshot and the first incremental date partition. The following PowerShell uses the Workflows Executions REST API because the local `gcloud workflows run --data` argument handling did not preserve JSON correctly.

```powershell
$RUN_DATE = Get-Date -Format "yyyy-MM-dd"
$ARGUMENT = @{
  project_id = $PROJECT_ID
  region = "us-central1"
  mode = "both"
  date = $RUN_DATE
} | ConvertTo-Json -Compress

$BODY = @{ argument = $ARGUMENT } | ConvertTo-Json -Compress
$TOKEN = (gcloud auth print-access-token).Trim()
$URI = "https://workflowexecutions.googleapis.com/v1/projects/$PROJECT_ID/locations/us-central1/workflows/airbnb-snapshot-incremental/executions"
$EXECUTION = Invoke-RestMethod -Method Post -Uri $URI `
  -Headers @{ Authorization = "Bearer $TOKEN" } `
  -ContentType "application/json" -Body $BODY
$EXECUTION.name
```

The workflow submits and polls Dataproc, then runs the trusted SQL after the batch succeeds. Save the execution name printed above for monitoring.

## Daily Incremental Run

Upload or refresh the CSV inputs with the data intended for that run, then use a unique date and `incremental` mode:

```powershell
$RUN_DATE = Get-Date -Format "yyyy-MM-dd"
$ARGUMENT = @{
  project_id = $PROJECT_ID
  region = "us-central1"
  mode = "incremental"
  date = $RUN_DATE
} | ConvertTo-Json -Compress

$BODY = @{ argument = $ARGUMENT } | ConvertTo-Json -Compress
$TOKEN = (gcloud auth print-access-token).Trim()
$URI = "https://workflowexecutions.googleapis.com/v1/projects/$PROJECT_ID/locations/us-central1/workflows/airbnb-snapshot-incremental/executions"
$EXECUTION = Invoke-RestMethod -Method Post -Uri $URI `
  -Headers @{ Authorization = "Bearer $TOKEN" } `
  -ContentType "application/json" -Body $BODY
$EXECUTION.name
```

Re-running the same date overwrites that date's incremental output. Use `snapshot` mode only when intentionally refreshing the snapshot; `both` rewrites both the snapshot and that date's incremental partition.

## Monitor and Verify

List recent workflow executions:

```powershell
gcloud workflows executions list airbnb-snapshot-incremental `
  --project=$PROJECT_ID --location=us-central1 --limit=5
```

Describe an execution using its final ID from the resource name:

```powershell
gcloud workflows executions describe EXECUTION_ID `
  --project=$PROJECT_ID --location=us-central1 `
  --workflow=airbnb-snapshot-incremental
```

A successful execution returns `SUCCEEDED` and a result similar to `Airbnb both pipeline completed for YYYY-MM-DD`.

Verify the GCS outputs:

```powershell
gcloud storage ls --recursive "gs://$PROJECT_ID-landing/derived/airbnb/snapshot/"
gcloud storage ls --recursive "gs://$PROJECT_ID-landing/derived/airbnb/incremental/"
```

The incremental paths should contain a `dt=YYYY-MM-DD` directory for each table.

Verify the BigQuery tables:

```powershell
bq ls --project_id=$PROJECT_ID warehouse
```

The dataset should contain six external tables (`airbnb_snapshot_*` and `airbnb_incremental_*`) and three trusted tables (`airbnb_trusted_*`). Run `sql/airbnb/count_warehouse_rows.sql` to count rows in all nine tables:

```powershell
$QUERY = (Get-Content sql/airbnb/count_warehouse_rows.sql -Raw).Replace("{{PROJECT_ID}}", $PROJECT_ID)
$BODY = @{ query = $QUERY; useLegacySql = $false } | ConvertTo-Json -Compress
$TOKEN = (gcloud auth print-access-token).Trim()
$URI = "https://bigquery.googleapis.com/bigquery/v2/projects/$PROJECT_ID/queries"
$RESULT = Invoke-RestMethod -Method Post -Uri $URI `
  -Headers @{ Authorization = "Bearer $TOKEN" } `
  -ContentType "application/json" -Body $BODY
$RESULT.rows | ForEach-Object {
  [pscustomobject]@{
    table_name = $_.f[0].v
    row_count = $_.f[1].v
  }
} | Format-Table -AutoSize
```

## Retry SQL Without Re-running Dataproc

Only use this when the Dataproc batch for the same date is already `SUCCEEDED` and its GCS outputs are present. Set `skip_dataproc = $true` in the workflow argument and start a new execution using the same REST request pattern above. This skips compute and reruns the external/trusted table SQL only.

Do not use this option if the previous Dataproc batch failed or output files are incomplete.

## Important Incremental Semantics

The current job samples 5% of the CSV contents using a deterministic seed for the date. It does **not** detect modified rows or perform CDC. To represent actual daily changes, provide CSV inputs containing the intended changed records or implement source-side change detection before scheduling unattended daily runs. The trusted SQL resolves key overlap by preferring incremental rows over snapshot rows.

## Troubleshooting

- **Dataproc cannot act as the runtime service account:** grant the Workflows service account `roles/iam.serviceAccountUser` on `sa-dataproc-jobs`.
- **Workflow cannot read the SQL file:** grant it `roles/storage.objectViewer` on the deploy bucket.
- **BigQuery cannot list external Parquet files:** grant it `roles/storage.objectViewer` on the landing bucket.
- **BigQuery permission denied:** grant `roles/bigquery.jobUser` on the project and `roles/bigquery.dataEditor` on `warehouse` to the workflow service account.
- **Missing input object:** confirm `listings.csv`, `calendar.csv`, and `reviews.csv` are under `raw/airbnb/` and match the expected columns in the PySpark job.
- **Inspect Dataproc status:** `gcloud dataproc batches list --project=$PROJECT_ID --region=us-central1`.
