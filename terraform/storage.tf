# terraform/storage.tf

# Bucket de Ingestão
resource "google_storage_bucket" "raw_data_bucket" {
  name          = "${var.project_id}-nexus-raw-data"
  location      = var.region
  project       = var.project_id
  force_destroy = true
}

# EventArc Trigger
resource "google_eventarc_trigger" "storage_trigger" {
  name     = "nexus-storage-trigger"
  location = var.region
  project  = var.project_id

  # CRITÉRIOS OBRIGATÓRIOS
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    # Referência dinâmica: garante que o bucket exista antes do gatilho
    value     = google_storage_bucket.raw_data_bucket.name
  }

  destination {
    # AJUSTE CHAVE: Referência ao ID do recurso. 
    # Isso força o Terraform a esperar o Workflow ficar pronto.
    workflow = google_workflows_workflow.nexus_workflow.id
  }

  # Identidade do Gatilho
  service_account = "nexus-stream-sa@${var.project_id}.iam.gserviceaccount.com"

  # Dependência explícita para garantir que o Workflow e a SA já passaram 
  # pelo tempo de propagação do IAM definido no main.tf
  depends_on = [google_workflows_workflow.nexus_workflow]
}