resource "google_bigquery_dataset" "warehouse" {
  dataset_id                 = "warehouse"
  location                   = var.region
  description                = "Fact/dim tables for both the Airbnb and AdventureWorks lanes"
  project                    = var.project_id
  delete_contents_on_destroy = true

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_dataset_iam_member" "workflows_warehouse_editor" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.warehouse.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.workflows.email}"
}

# Tables (airbnb_fact_listings, sales_fact, sales_dim) are created at runtime
# by PySpark jobs writing via the Spark BigQuery connector — NOT managed by Terraform.
