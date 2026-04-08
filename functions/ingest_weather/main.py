import json
import os
import functions_framework
from google.cloud import bigquery, storage
from datetime import datetime

# Inicialização global para performance (Warm Start)
bq_client = bigquery.Client()
storage_client = storage.Client()

# IDs de Tabelas vindos das variáveis de ambiente do Terraform
TABLE_ID = os.environ.get("TABLE_ID")
# O Terraform deve passar essa variável também para Auditoria
AUDIT_TABLE_ID = TABLE_ID.replace("weather_history", "ingestion_audit_log")

@functions_framework.http
def process_weather_event(request):
    """
    Invocada via Cloud Workflows (HTTP POST).
    O Workflow passa o payload do evento GCS no corpo da requisição.
    """
    request_json = request.get_json(silent=True)
    
    if not request_json:
        return "Nenhum payload recebido", 400

    # O Cloud Workflows entrega o objeto do evento GCS
    bucket_name = request_json.get('bucket')
    file_name = request_json.get('name')

    if not bucket_name or not file_name:
        return "Atributos de arquivo ausentes", 400

    # Filtro de segurança: processa apenas a pasta de ingestão
    if not file_name.startswith("ingest_weather/"):
        return f"Arquivo {file_name} ignorado (fora da pasta de ingestão)", 200

    print(f"Executando NexusStream Ingestion: gs://{bucket_name}/{file_name}")

    try:
        # 1. Download do dado bruto do GCS
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        content = blob.download_as_text()
        data_json = json.loads(content)

        # 2. Preparação do payload para a Bronze Layer
        rows_to_insert = [{
            "city_name": data_json.get("name"),
            "temp": data_json.get("main", {}).get("temp"),
            "weather_data": json.dumps(data_json),
            "ingested_at": datetime.utcnow().isoformat()
        }]

        # 3. Inserção na Bronze (Streaming Insert)
        errors = bq_client.insert_rows_json(TABLE_ID, rows_to_insert)

        if errors:
            raise Exception(f"Erro no BigQuery: {errors}")

        # 4. Log de Sucesso na Tabela de Auditoria
        _log_audit(file_name, "SUCCESS", len(rows_to_insert))
        
        return f"Sucesso: {file_name} processado.", 200

    except Exception as e:
        error_msg = str(e)
        print(f"FALHA: {error_msg}")
        # Log de Erro na Tabela de Auditoria para visibilidade no Looker
        _log_audit(file_name, "FAILED", 0, error_msg)
        return f"Erro ao processar {file_name}: {error_msg}", 500

def _log_audit(file_name, status, rows, error=""):
    """Grava o rastro de processamento para Governança."""
    audit_row = [{
        "file_name": file_name,
        "ingested_at": datetime.utcnow().isoformat(),
        "status": status,
        "rows_affected": rows,
        "error_message": error
    }]
    try:
        bq_client.insert_rows_json(AUDIT_TABLE_ID, audit_row)
    except Exception as ex:
        print(f"Erro ao gravar auditoria: {ex}")