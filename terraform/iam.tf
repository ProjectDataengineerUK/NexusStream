# 1. Permissão para o BigQuery (Escrita na Bronze/Silver e Auditoria)
resource "google_project_iam_member" "sa_bq_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "sa_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# 2. Permissão para o Storage (Leitura de arquivos brutos e escrita de logs)
resource "google_project_iam_member" "sa_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_storage_bucket_iam_member" "sa_storage_writer" {
  bucket = google_storage_bucket.raw_data_bucket.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# 3. Permissão para o Maestro (Workflow) invocar a Function
resource "google_cloud_run_service_iam_member" "invoker" {
  location = var.region
  project  = var.project_id
  service  = google_cloudfunctions2_function.weather_processor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.function_sa.email}"
}

# 4. Permissões específicas para o DATAFORM (O Filtro de Barro)
# Permite que a SA do pipeline dispare execuções no Dataform
resource "google_project_iam_member" "sa_dataform_editor" {
  project = var.project_id
  role    = "roles/dataform.editor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Permissão para o Service Agent do Dataform (O Google operando o SQL)
resource "google_project_iam_member" "dataform_service_agent_bq" {
  project = var.project_id
  role    = "roles/bigquery.admin" # Admin no BQ para criar/deletar tabelas Silver/Assertions
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

# 5. Infraestrutura de Eventos (Eventarc & Pub/Sub)
resource "google_project_iam_member" "pubsub_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "eventarc_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}