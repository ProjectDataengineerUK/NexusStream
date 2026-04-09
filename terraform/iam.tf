# =============================================================================
# 1. PERMISSÕES PARA A SERVICE ACCOUNT DA FUNCTION (NexusStream SA)
# =============================================================================

# Permissões de BigQuery (Leitura/Escrita na Bronze e execução de Jobs)
resource "google_project_iam_member" "sa_bq_permissions" {
  for_each = toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser"
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Permissões de Storage (Leitura de arquivos brutos e escrita de logs/artefatos)
resource "google_project_iam_member" "sa_storage_permissions" {
  for_each = toset([
    "roles/storage.objectViewer",
    "roles/storage.objectCreator"
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Permissão para invocar a Cloud Function (necessário para o Workflows/Eventarc)
resource "google_cloud_run_service_iam_member" "invoker" {
  location = var.region
  project  = var.project_id
  service  = google_cloudfunctions2_function.weather_processor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.function_sa.email}"
}

# =============================================================================
# 2. PERMISSÕES PARA IDENTIDADES AUTOMÁTICAS (Service Agents)
# =============================================================================

# AJUSTE CRÍTICO: Permissão para o Service Agent do DATAFORM
# Essa conta é criada pelo Google com o padrão: service-PROJECT_NUMBER@gcp-sa-dataform.iam.gserviceaccount.com
resource "google_project_iam_member" "dataform_service_agent_bq" {
  project = var.project_id
  role    = "roles/bigquery.admin" 
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-dataform.iam.gserviceaccount.com"

  # Espera a ativação das APIs e a pausa de propagação do main.tf
  depends_on = [
    time_sleep.wait_iam_propagation 
  ]
}

# Permissão para o Service Agent do Pub/Sub (necessário para Eventarc/Push)
resource "google_project_iam_member" "pubsub_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  
  depends_on = [time_sleep.wait_iam_propagation]
}

# Permissão para a Service Account da Function receber eventos do Eventarc
resource "google_project_iam_member" "eventarc_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [time_sleep.wait_iam_propagation]
}