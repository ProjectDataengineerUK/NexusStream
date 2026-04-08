# 1. Criação do Data Lake (Dataplex)
resource "google_dataplex_lake" "nexus_lake" {
  name         = "nexus-stream-lake"
  project      = var.project_id
  location     = var.region
  display_name = "NexusStream Data Lake"
  description  = "Governança centralizada para dados de Clima e GitHub"
}

# 2. Zona de Dados (Mapeando os Datasets do BigQuery)
resource "google_dataplex_zone" "raw_zone" {
  name         = "bronze-raw-zone"
  lake         = google_dataplex_lake.nexus_lake.name
  project      = var.project_id
  location     = var.region
  display_name = "Camada Bronze (Raw)"
  type         = "RAW"

  resource_spec {
    location_type = "SINGLE_REGION"
  }

  # AJUSTE: Adicionado bloco obrigatório para descoberta de metadados
  discovery_spec {
    enabled = true
  }
}

# 3. Asset (Vincula o Dataset nexus_raw ao Dataplex)
resource "google_dataplex_asset" "weather_asset" {
  name          = "weather-raw-data"
  lake          = google_dataplex_lake.nexus_lake.name
  dataplex_zone = google_dataplex_zone.raw_zone.name
  project       = var.project_id
  location      = var.region

  resource_spec {
    name = "projects/${var.project_id}/datasets/${google_bigquery_dataset.nexus_raw.dataset_id}"
    type = "BIGQUERY_DATASET"
  }

  discovery_spec {
    enabled = true 
  }
}