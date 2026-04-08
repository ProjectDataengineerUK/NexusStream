# terraform/variables.tf

variable "project_id" {
  description = "O ID do seu projeto no GCP"
  type        = string
}

variable "region" {
  description = "A região onde os recursos serão criados"
  type        = string
  default     = "us-central1"
}

# ADICIONADO: Variável sensível para o token da API
variable "weather_api_token" {
  description = "Token da API OpenWeather que será armazenado no Secret Manager"
  type        = string
  sensitive   = true # Isso impede que o valor apareça nos logs do terminal
}