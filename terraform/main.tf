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

# Obtém dados do projeto para referenciar o Project Number
data "google_project" "project" {}

# =============================================================================
# 1. IDENTIDADE CENTRAL (Service Account)
# =============================================================================
resource "google_service_account" "function_sa" {
  account_id   = "nexus-stream-sa"
  display_name = "Service Account para NexusStream Pipeline"
  project      = var.project_id
}

# =============================================================================
# 2. PERMISSÕES DE IAM (O que a Service Account pode fazer)
# =============================================================================

resource "google_project_iam_member" "eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "workflow_invoker" {
  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "act_as" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# NOVO: Permite que o Workflow chame a Cloud Function (Cloud Run subjacente)
resource "google_project_iam_member" "workflow_invoker_run" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# NOVO: Permite que o Workflow dispare o Dataform
resource "google_project_iam_member" "workflow_dataform_editor" {
  project = var.project_id
  role    = "roles/dataform.editor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Permissões de Service Agents (Sistemas do GCP)
resource "google_project_iam_member" "gcs_pubsub_publishing" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "pubsub_dead_letter_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild_service_agent" {
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# =============================================================================
# 3. REPOSITÓRIO E PAUSA ESTRATÉGICA
# =============================================================================
resource "google_artifact_registry_repository" "nexus_repo" {
  location      = var.region
  repository_id = "nexus-functions-repo"
  description   = "Repositorio para imagens e artefatos do NexusStream"
  format        = "DOCKER" 
}

resource "time_sleep" "wait_iam_propagation" {
  depends_on = [
    google_service_account.function_sa,
    google_project_iam_member.eventarc_receiver,
    google_project_iam_member.workflow_invoker,
    google_project_iam_member.secret_accessor,
    google_project_iam_member.act_as,
    google_project_iam_member.workflow_invoker_run,
    google_project_iam_member.workflow_dataform_editor,
    google_project_iam_member.pubsub_dead_letter_publisher,
    google_project_iam_member.cloudbuild_service_agent,
    google_artifact_registry_repository.nexus_repo
  ]
  create_duration = "50s"
}

# =============================================================================
# 4. ORQUESTRAÇÃO (O Maestro e o Gatilho)
# =============================================================================

# O Maestro: Cloud Workflows
resource "google_workflows_workflow" "nexus_orchestrator" {
  name            = "nexus-main-orchestrator"
  region          = var.region
  description     = "Orquestra Ingestão (Function) -> Qualidade (Dataform)"
  service_account = google_service_account.function_sa.id

  source_contents = <<-EOF
    main:
      params: [event]
      steps:
        - init:
            assign:
              - project_id: $${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
              - repository: "projects/" + project_id + "/locations/${var.region}/repositories/nexus-data-quality-repo"
        
        - call_ingestion_function:
            call: http.post
            args:
              url: ${google_cloudfunctions2_function.weather_processor.service_config[0].uri}
              auth:
                type: OIDC
              body: $${event}
            result: ingestion_result

        - run_dataform_pipeline:
            call: http.post
            args:
              url: $${"https://dataform.googleapis.com/v1beta1/" + repository + "/workflowInvocations"}
              auth:
                type: OAuth2
              body:
                compilationResult: $${repository + "/compilationResults/main"}
            result: dataform_result

        - finish:
            return: $${dataform_result.body}
  EOF

  depends_on = [
    time_sleep.wait_iam_propagation,
    google_cloudfunctions2_function.weather_processor
  ]
}

# O Gatilho: Eventarc (Agora aponta para o Maestro)
resource "google_eventarc_trigger" "gcs_trigger" {
  name     = "nexus-gcs-trigger"
  location = var.region

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.raw_data_bucket.name
  }

  destination {
    workflow = google_workflows_workflow.nexus_orchestrator.id
  }

  service_account = google_service_account.function_sa.email

  depends_on = [ time_sleep.wait_iam_propagation ]
}