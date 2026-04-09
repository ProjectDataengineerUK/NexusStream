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
# Garante que o ID da auditoria seja válido
AUDIT_TABLE_ID = TABLE_ID.rsplit('.', 1)[0] + ".ingestion_audit_log"

@functions_framework.http
def process_weather_event(request):
    """
    Invocada via Cloud Workflows (HTTP POST).
    """
    request_json = request.get_json(silent=True)
    
    if not request_json:
        return "Nenhum payload recebido", 400

    # AJUSTE: O Workflow envia 'file', alinhando com o código anterior
    bucket_name = request_json.get('bucket')
    file_name = request_json.get('file') or request_json.get('name')

    if not bucket_name or not file_name:
        return f"Atributos ausentes. Recebido: {request_json}", 400

    # AJUSTE: Alinhado com o caminho definido no workflow.tf (ingestion/weather/)
    if not file_name.startswith("ingestion/weather/"):
        print(f"Ignorado: {file_name} não pertence à trilha de ingestão.")
        return f"Arquivo {file_name} ignorado", 200

    print(f"NexusStream Processando: gs://{bucket_name}/{file_name}")

    try:
        # 1. Download do dado bruto
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        content = blob.download_as_text()
        data_json = json.loads(content)

        # 2. Preparação (Bronze Layer)
        rows_to_insert = [{
            "city_name": data_json.get("name"),
            "temp": data_json.get("main", {}).get("temp"),
            "weather_data": json.dumps(data_json),
            "ingested_at": datetime.utcnow().isoformat()
        }]

        # 3. Inserção (Streaming Insert)
        errors = bq_client.insert_rows_json(TABLE_ID, rows_to_insert)

        if errors:
            raise Exception(f"Erro BigQuery Insert: {errors}")

        # 4. Auditoria
        _log_audit(file_name, "SUCCESS", len(rows_to_insert))
        
        return {"status": "success", "file": file_name}, 200

    except Exception as e:
        error_msg = str(e)
        print(f"FALHA CRÍTICA: {error_msg}")
        _log_audit(file_name, "FAILED", 0, error_msg)
        return {"status": "error", "message": error_msg}, 500

def _log_audit(file_name, status, rows, error=""):
    """Grava rastro para Governança."""
    audit_row = [{
        "file_name": file_name,
        "ingested_at": datetime.utcnow().isoformat(),
        "status": status,
        "rows_affected": rows,
        "error_message": error[:1000] # Trunca erros muito longos
    }]
    try:
        bq_client.insert_rows_json(AUDIT_TABLE_ID, audit_row)
    except Exception as ex:
        print(f"Erro de Auditoria (Verifique se a tabela existe): {ex}")