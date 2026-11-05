# Pipeline Follow-Up Plan

## Current State

- [x] Created public GitHub repository `4dori/gcp_de_programm`.
- [x] Pushed commit `570d6e3` to branch `main`; the original `origin` remote remains unchanged.
- [x] Added the snapshot/incremental Dataproc job, BigQuery external/trusted SQL, workflow, and Cloud Build publishing configuration.
- [x] Terraform format and validation checks pass.
- [x] Deployed `airbnb-snapshot-incremental` in `us-central1`; Workflows accepted the source.
- [x] Connected source repository `4dori/tf_gcp_mentor` to the existing Cloud Build GitHub connection. The artifact repository `4dori/gcp_de_programm` remains unlinked.
- [x] Created trigger `publish-program-scripts-main-yaml` for pushes to `main` on `tf_gcp_mentor`, using its checked-in `cloudbuild.yaml`. It clones the public artifact repo and publishes only PySpark and SQL files to the deploy bucket.
- [x] Manually ran the YAML-based trigger successfully; the expected PySpark and SQL objects are present in GCS.
- [x] Uploaded the three Airbnb CSV inputs and ran the bootstrap workflow for `2026-11-04`.
- [x] Dataproc wrote all snapshot and incremental Parquet outputs; BigQuery created all six external tables and three trusted tables.
- [x] Added the workflow service-account permissions needed to submit Dataproc, read SQL and source objects, and create/query BigQuery tables.

## Remaining Steps

### 1. Run Daily Incrementals

For subsequent daily runs, change `mode` to `incremental` and supply the date for the new partition:

```powershell
$PROJECT_ID = (gcloud config get-value project).Trim()
gcloud storage ls "gs://$PROJECT_ID-landing/raw/airbnb/"
$RUN_DATA = @{ project_id = $PROJECT_ID; region = "us-central1"; mode = "incremental"; date = (Get-Date -Format "yyyy-MM-dd") } | ConvertTo-Json -Compress
gcloud workflows run airbnb-snapshot-incremental --location=us-central1 --data="$RUN_DATA"
```

Add Cloud Scheduler only after a manual incremental run succeeds and the input files represent that day's changes.

## Data Semantics to Confirm

- Spark's `sample` uses fractional sampling; the output is an expected 80% or 5% sample, not a guaranteed exact row count.
- The current incremental job samples 5% from each current CSV with a date-based seed. It does not detect changed records by itself. To model real modifications, provide source files containing the day's changed records or add a source-side change-detection rule before production scheduling.
- Re-running the same date overwrites only that date's incremental output partition.
