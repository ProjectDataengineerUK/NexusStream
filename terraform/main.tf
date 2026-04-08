terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0" 
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# 0. ATIVAÇÃO DE APIS ESSENCIAIS
# =============================================================================

# Esta é a API que causou o seu erro 403
resource "google_project_service" "cloudresourcemanager" {
  project            = var.project_id
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

# Recomendado ativar também a de IAM para evitar problemas similares
resource "google_project_service" "iam" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

# Obtém dados do projeto (agora depende da ativação da API acima)
data "google_project" "project" {
  depends_on = [google_project_service.cloudresourcemanager]
}

# =============================================================================
# 1. IDENTIDADE CENTRAL (Service Account)
# =============================================================================
resource "google_service_account" "function_sa" {
  account_id   = "nexus-stream-sa"
  display_name = "Service Account para NexusStream Pipeline"
  project      = var.project_id

  # Garante que a SA só seja criada após as APIs estarem ativas
  depends_on = [google_project_service.iam]
}

# =============================================================================
# 2. PERMISSÕES DE IAM
# =============================================================================

# Adicionei o 'depends_on' para garantir que a API Resource Manager esteja pronta
resource "google_project_iam_member" "eventarc_receiver" {
  project    = var.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [google_project_service.cloudresourcemanager]
}

resource "google_project_iam_member" "workflow_invoker" {
  project    = var.project_id
  role       = "roles/workflows.invoker"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [google_project_service.cloudresourcemanager]
}

resource "google_project_iam_member" "secret_accessor" {
  project    = var.project_id
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [google_project_service.cloudresourcemanager]
}

resource "google_project_iam_member" "act_as" {
  project    = var.project_id
  role       = "roles/iam.serviceAccountUser"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [google_project_service.cloudresourcemanager]
}

resource "google_project_iam_member" "workflow_invoker_run" {
  project    = var.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [google_project_service.cloudresourcemanager]
}

resource "google_project_iam_member" "workflow_dataform_editor" {
  project    = var.project_id
  role       = "roles/dataform.editor"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [google_project_service.cloudresourcemanager]
}

# ... (restante das permissões de Service Agents permanecem iguais)