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

# Permissão de Storage (Admin para permitir que a function limpe/mova arquivos se necessário)
resource "google_project_iam_member" "sa_storage_permissions" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
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
  member   = "serviceAccount:nexus-stream-sa@${var.project_id}.iam.gserviceaccount.com"
}

# AJUSTE CRÍTICO: Permite que o Workflow gere o Token OIDC necessário para a chamada
resource "google_service_account_iam_member" "workflow_sa_user" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/nexus-stream-sa@${var.project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:nexus-stream-sa@${var.project_id}.iam.gserviceaccount.com"
}

# Permissão para o Workflow ler segredos (necessário para a API Key)
resource "google_project_iam_member" "workflow_secret_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:nexus-stream-sa@${var.project_id}.iam.gserviceaccount.com"
}

# Permissão para o Workflow inserir objetos no Storage (onde ele salva o JSON bruto)
resource "google_project_iam_member" "workflow_storage_insert" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:nexus-stream-sa@${var.project_id}.iam.gserviceaccount.com"
}

# =============================================================================
# 3. PERMISSÕES PARA IDENTIDADES AUTOMÁTICAS (Service Agents)
# =============================================================================

resource "google_project_iam_member" "dataform_service_agent_bq" {
  project = var.project_id
  role    = "roles/bigquery.admin" 
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-dataform.iam.gserviceaccount.com"
  depends_on = [time_sleep.wait_iam_propagation]
}

resource "google_project_iam_member" "pubsub_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  depends_on = [time_sleep.wait_iam_propagation]
}