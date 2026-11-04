resource "google_cloudbuild_trigger" "publish_data_pipeline" {
  name            = "publish-data-pipeline"
  description     = "Publish PySpark and SQL artifacts and deploy workflows on main pushes."
  filename        = "cloudbuild.yaml"
  service_account = google_service_account.cloudbuild.id
  project         = var.project_id

  github {
    owner = var.github_owner
    name  = var.github_repo

    push {
      branch = "^main$"
    }
  }

  depends_on = [google_project_service.apis]
}
