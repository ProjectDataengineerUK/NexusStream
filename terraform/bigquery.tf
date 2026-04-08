# =============================================================================
# 1. DEFINIÇÃO DOS DATASETS (Bronze e Raw Layers)
# =============================================================================

resource "google_bigquery_dataset" "nexus_raw" {
  dataset_id                  = "nexus_raw_layer"
  friendly_name               = "Nexus Raw Data"
  description                 = "Camada Bronze: Dados brutos e Auditoria"
  project                     = var.project_id
  location                    = var.region
  delete_contents_on_destroy = false
}

resource "google_bigquery_dataset" "raw_github" {
  dataset_id                  = "raw_github_data"
  friendly_name               = "Github Raw Data"
  project                     = var.project_id
  location                    = var.region
  delete_contents_on_destroy = false
}

# =============================================================================
# 2. CAMADA DE STAGING (Tabela Externa / BigLake)
# =============================================================================

resource "google_bigquery_table" "weather_staging_external" {
  dataset_id = google_bigquery_dataset.nexus_raw.dataset_id
  table_id   = "stg_weather_external"
  project    = var.project_id
  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    # AJUSTE TÉCNICO: O formato correto para JSON no BigQuery Externo
    source_format = "NEWLINE_DELIMITED_JSON"
    
    # Lógica para ler os arquivos brutos do GCS sem precisar mover o dado
    source_uris   = ["gs://${google_storage_bucket.raw_data_bucket.name}/ingest_weather/*.json"]
  }
}

# =============================================================================
# 3. TABELAS DEFINITIVAS (Warehouse Layer)
# =============================================================================

# Tabela Weather (Clima) - Particionada para performance e custo
resource "google_bigquery_table" "weather_table" {
  dataset_id = google_bigquery_dataset.nexus_raw.dataset_id
  table_id   = "weather_history"
  project    = var.project_id
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "ingested_at" 
  }

  schema = <<EOF
[
  {"name": "city_name", "type": "STRING", "mode": "NULLABLE"},
  {"name": "temp", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "weather_data", "type": "JSON", "mode": "NULLABLE"},
  {"name": "ingested_at", "type": "TIMESTAMP", "mode": "REQUIRED"}
]
EOF
}

# Tabela de Auditoria (Essencial para o componente de Monitoring do seu diagrama)
resource "google_bigquery_table" "ingestion_audit_log" {
  dataset_id = google_bigquery_dataset.nexus_raw.dataset_id
  table_id   = "ingestion_audit_log"
  project    = var.project_id
  deletion_protection = false

  schema = <<EOF
[
  {"name": "file_name", "type": "STRING", "mode": "REQUIRED"},
  {"name": "ingested_at", "type": "TIMESTAMP", "mode": "REQUIRED"},
  {"name": "status", "type": "STRING", "mode": "REQUIRED"},
  {"name": "rows_affected", "type": "INTEGER", "mode": "NULLABLE"},
  {"name": "error_message", "type": "STRING", "mode": "NULLABLE"}
]
EOF
}

# Tabela GitHub (Stream de eventos brutos)
resource "google_bigquery_table" "events_table" {
  dataset_id = google_bigquery_dataset.raw_github.dataset_id
  table_id   = "github_events_stream"
  project    = var.project_id
  deletion_protection = false
}