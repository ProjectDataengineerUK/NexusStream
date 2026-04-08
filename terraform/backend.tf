terraform {
  backend "gcs" {
    bucket  = "nexus-stream-terraform-state"
    prefix  = "terraform/state"
  }
}