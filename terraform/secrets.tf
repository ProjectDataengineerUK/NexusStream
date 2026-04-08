# 1. Definição do Contêiner do Segredo
resource "google_secret_manager_secret" "weather_api_key" {
  secret_id = "openweathermap-api-key"
  project   = var.project_id

  replication {
    auto {}
  }
}

# 2. Versão do Segredo
resource "google_secret_manager_secret_version" "weather_api_key_version" {
  secret      = google_secret_manager_secret.weather_api_key.id
  # Recomendação: use var.weather_api_token vindo do seu variables.tf
  secret_data = "a62ca28cd75cfad42b2b76d500908b1d" 
}

# 3. Permissão de Acesso (Referência Dinâmica)
resource "google_secret_manager_secret_iam_member" "function_secret_access" {
  secret_id = google_secret_manager_secret.weather_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  
  # Usando a referência do recurso criado no seu main.tf
  member    = "serviceAccount:${google_service_account.function_sa.email}"
}