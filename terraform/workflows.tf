resource "google_workflows_workflow" "nexus_workflow" {
  name            = "nexus-main-workflow"
  region          = var.region
  project         = var.project_id
  service_account = "nexus-stream-sa@${var.project_id}.iam.gserviceaccount.com"

  # ADIÇÃO CRÍTICA: Permite que o Terraform exclua/recrie o recurso via CI/CD
  deletion_protection = false 

  depends_on = [time_sleep.wait_iam_propagation]

  source_contents = <<-EOF
    main:
      steps:
        - init:
            assign:
              - project_id: $${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
              - bucket_name: "${var.project_id}-nexus-raw-data"
              - city: "Sao Paulo"
              - current_time: $${string(int(sys.now()))}

        - get_secret:
            call: googleapis.secretmanager.v1.projects.secrets.versions.access
            args:
              name: $${"projects/" + project_id + "/secrets/openweathermap-api-key/versions/latest"}
            result: secret_response

        - decode_secret:
            assign:
              - api_key: $${text.decode(base64.decode(secret_response.payload.data))}

        - fetch_weather_data:
            call: http.get
            args:
              url: "https://api.openweathermap.org/data/2.5/weather"
              query:
                q: $${city}
                appid: $${api_key}
                units: "metric"
            result: weather_response

        - save_to_raw_storage:
            call: googleapis.storage.v1.objects.insert
            args:
              bucket: $${bucket_name}
              name: $${"ingestion/weather/" + current_time + ".json"}
              body: $${weather_response.body}

        - finish:
            return:
              message: "Ingestão realizada com sucesso"
              file_saved: $${"ingestion/weather/" + current_time + ".json"}
              # Ajustado conforme sua nota: .code é o padrão para respostas HTTP no Workflows
              http_code: $${weather_response.code}
  EOF
}