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
# 0. ATIVAÇÃO DE APIS ESSENCIAIS E PAUSA
# =============================================================================

resource "google_project_service" "cloudresourcemanager" {
  project            = var.project_id
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

# NOVO: Pausa crítica para a API propagar antes de qualquer leitura ou escrita de IAM
resource "time_sleep" "wait_api_activation" {
  depends_on = [
    google_project_service.cloudresourcemanager,
    google_project_service.iam
  ]
  create_duration = "45s"
}

data "google_project" "project" {
  # Agora depende do sleep, não direto da API
  depends_on = [time_sleep.wait_api_activation]
}

# =============================================================================
# 1. IDENTIDADE CENTRAL (Service Account)
# =============================================================================

resource "google_service_account" "function_sa" {
  account_id   = "nexus-stream-sa"
  display_name = "Service Account para NexusStream Pipeline"
  project      = var.project_id
  depends_on   = [time_sleep.wait_api_activation]
}

# =============================================================================
# 2. PERMISSÕES DE IAM
# =============================================================================

# Todos os IAM members agora aguardam a API estar 100% pronta (via wait_api_activation)
resource "google_project_iam_member" "eventarc_receiver" {
  project    = var.project_id
  role       = "roles/eventarc.eventReceiver"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [time_sleep.wait_api_activation]
}

resource "google_project_iam_member" "workflow_invoker" {
  project    = var.project_id
  role       = "roles/workflows.invoker"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [time_sleep.wait_api_activation]
}

resource "google_project_iam_member" "secret_accessor" {
  project    = var.project_id
  role       = "roles/secretmanager.secretAccessor"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [time_sleep.wait_api_activation]
}

resource "google_project_iam_member" "act_as" {
  project    = var.project_id
  role       = "roles/iam.serviceAccountUser"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [time_sleep.wait_api_activation]
}

resource "google_project_iam_member" "workflow_invoker_run" {
  project    = var.project_id
  role       = "roles/run.invoker"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [time_sleep.wait_api_activation]
}

resource "google_project_iam_member" "workflow_dataform_editor" {
  project    = var.project_id
  role       = "roles/dataform.editor"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
  depends_on = [time_sleep.wait_api_activation]
}

# =============================================================================
# 3. RECURSOS DE INFRA (Artifacts & Wait)
# =============================================================================

resource "google_artifact_registry_repository" "nexus_repo" {
  location      = var.region
  repository_id = "nexus-functions-repo"
  description   = "Repositorio para imagens e artefatos do NexusStream"
  format        = "DOCKER"
  depends_on    = [time_sleep.wait_api_activation]
}

# Esta segunda pausa continua sendo necessária para garantir que as permissões IAM
# aplicadas acima sejam propagadas antes dos arquivos 'functions.tf' e 'workflows.tf' rodarem.
resource "time_sleep" "wait_iam_propagation" {
  depends_on = [
    google_service_account.function_sa,
    google_project_iam_member.eventarc_receiver,
    google_project_iam_member.workflow_invoker,
    google_project_iam_member.secret_accessor,
    google_project_iam_member.act_as,
    google_project_iam_member.workflow_invoker_run,
    google_project_iam_member.workflow_dataform_editor
  ]
  create_duration = "50s"
}