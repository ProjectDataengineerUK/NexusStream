# 1. Gerar o ZIP do código-fonte
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../functions/ingest_weather"
  output_path = "${path.module}/ingest_weather.zip"
}

# 2. Upload para o Cloud Storage
resource "google_storage_bucket_object" "function_code" {
  name   = "code/ingest_weather-${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.raw_data_bucket.name 
  source = data.archive_file.function_zip.output_path

  depends_on = [google_storage_bucket.raw_data_bucket]
}

# 3. Definição da Cloud Function v2
resource "google_cloudfunctions2_function" "weather_processor" {
  name        = "nexus-weather-processor"
  location    = var.region
  description = "Processa JSON da OpenWeather invocado via Cloud Workflows"

  build_config {
    runtime     = "python310"
    entry_point = "process_weather_event" 
    
    docker_repository = google_artifact_registry_repository.nexus_repo.id

    source {
      storage_source {
        bucket = google_storage_bucket.raw_data_bucket.name
        object = google_storage_bucket_object.function_code.name
      }
    }
  }

  service_config {
    max_instance_count = 3
    available_memory   = "256Mi"
    timeout_seconds    = 60
    service_account_email = google_service_account.function_sa.email

    # CORREÇÃO: Utilizando valor aceito pelo provider para chamadas via Workflows/Internas
    ingress_settings = "ALLOW_INTERNAL_ONLY" 

    secret_environment_variables {
      key        = "OPENWEATHER_API_KEY"
      project_id = var.project_id
      secret     = google_secret_manager_secret.weather_api_key.secret_id
      version    = "latest"
    }

    environment_variables = {
      TABLE_ID = "${var.project_id}.${google_bigquery_dataset.nexus_raw.dataset_id}.${google_bigquery_table.weather_table.table_id}"
    }
  }

  depends_on = [
    time_sleep.wait_iam_propagation,
    google_artifact_registry_repository.nexus_repo,
    google_secret_manager_secret_version.weather_api_key_version,
    google_project_service.apis["run.googleapis.com"],
    google_project_service.apis["artifactregistry.googleapis.com"],
    google_project_service.apis["cloudfunctions.googleapis.com"],
    google_storage_bucket_object.function_code 
  ]
}

# 4. OUTPUT para conferência
output "function_uri" {
  value = google_cloudfunctions2_function.weather_processor.service_config[0].uri
}