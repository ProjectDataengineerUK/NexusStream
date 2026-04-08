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
  depends_on   = [google_project_service.iam]
}

# =============================================================================
# 2. PERMISSÕES DE IAM
# =============================================================================

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

# =============================================================================
# 3. RECURSOS DE INFRA (Artifacts & Wait)
# =============================================================================

# Declarando o repositório que o functions.tf não estava achando
resource "google_artifact_registry_repository" "nexus_repo" {
  location      = var.region
  repository_id = "nexus-functions-repo"
  description   = "Repositorio para imagens e artefatos do NexusStream"
  format        = "DOCKER"
  depends_on    = [google_project_service.cloudresourcemanager]
}

# Declarando a pausa que o functions.tf e workflows.tf não estavam achando
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