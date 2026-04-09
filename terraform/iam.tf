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

# AJUSTE: Permissão de Storage (Alterado para objectAdmin para permitir DELETE/Sobrescrita)
resource "google_project_iam_member" "sa_storage_permissions" {
  project = var.project_id
  role    = "roles/storage.objectAdmin" # Substitui Viewer/Creator para evitar erro 403 na linha 31
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Permissão para a Function ler segredos no Secret Manager
resource "google_secret_manager_secret_iam_member" "secret_reader" {
  secret_id = google_secret_manager_secret.weather_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.function_sa.email}"
}

# =============================================================================
# 2. PERMISSÕES PARA O WORKFLOW ( nexus-stream-sa )
# =============================================================================

# Permissão para o Workflow invocar a Cloud Function (Gen2 roda sobre Cloud Run)
resource "google_cloud_run_service_iam_member" "workflow_invokes_function" {
  location = var.region
  project  = var.project_id
  service  = google_cloudfunctions2_function.weather_processor.name
  role     = "roles/run.invoker"
  # O Workflow roda com a conta nexus-stream-sa
  member   = "serviceAccount:nexus-stream-sa@${var.project_id}.iam.gserviceaccount.com"
}

# Permissão para o Workflow ler segredos (necessário para pegar a API Key)
resource "google_project_iam_member" "workflow_secret_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:nexus-stream-sa@${var.project_id}.iam.gserviceaccount.com"
}

# =============================================================================
# 3. PERMISSÕES PARA IDENTIDADES AUTOMÁTICAS (Service Agents)
# =============================================================================

# Permissão para o Service Agent do DATAFORM
resource "google_project_iam_member" "dataform_service_agent_bq" {
  project = var.project_id
  role    = "roles/bigquery.admin" 
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-dataform.iam.gserviceaccount.com"

  depends_on = [time_sleep.wait_iam_propagation]
}

# Permissão para o Service Agent do Pub/Sub
resource "google_project_iam_member" "pubsub_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  
  depends_on = [time_sleep.wait_iam_propagation]
}

# Permissão para receber eventos (útil se você decidir usar Eventarc no futuro)
resource "google_project_iam_member" "eventarc_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [time_sleep.wait_iam_propagation]
}