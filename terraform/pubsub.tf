# terraform/pubsub.tf

# Tópico Principal
resource "google_pubsub_topic" "events_topic" {
  name    = "nexus-github-events"
  project = var.project_id # Adicionado para garantir o contexto
}

# Tópico de Erro (Dead Letter Queue)
resource "google_pubsub_topic" "dead_letter_topic" {
  name    = "nexus-events-dlq"
  project = var.project_id # Adicionado para garantir o contexto
}

# Assinatura de Push
resource "google_pubsub_subscription" "events_subscription" {
  name    = "nexus-events-sub"
  topic   = google_pubsub_topic.events_topic.name
  project = var.project_id # Adicionado para garantir o contexto

  ack_deadline_seconds = 60

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topic.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}