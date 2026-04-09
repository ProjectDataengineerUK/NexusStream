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

resource "google_project_service" "apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "run.googleapis.com",      # ESSENCIAL: Resolve o erro 403 da Function
    "dataform.googleapis.com", # ESSENCIAL: Para o Service Agent do Dataform
    "artifactregistry.googleapis.com",
    "cloudfunctions.googleapis.com",
    "workflows.googleapis.com"
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# Pausa crítica para as APIs propagarem e o Google criar as SAs automáticas
resource "time_sleep" "wait_api_activation" {
  depends_on = [google_project_service.apis]
  create_duration = "60s" # Aumentado para 60s para maior segurança com Dataform
}

data "google_project" "project" {
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

resource "google_project_iam_member" "iam_roles" {
  for_each = toset([
    "roles/eventarc.eventReceiver",
    "roles/workflows.invoker",
    "roles/secretmanager.secretAccessor",
    "roles/iam.serviceAccountUser",
    "roles/run.invoker",
    "roles/dataform.editor"
  ])
  project    = var.project_id
  role       = each.key
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

# Pausa para propagação de IAM antes de deploy de Functions/Workflows
resource "time_sleep" "wait_iam_propagation" {
  depends_on = [
    google_service_account.function_sa,
    google_project_iam_member.iam_roles
  ]
  create_duration = "50s"
}