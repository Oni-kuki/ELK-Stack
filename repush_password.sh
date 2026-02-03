source .env

# Check Elasticsearch
curl -k -u elastic:${ELASTIC_PASSWORD} https://localhost:9200

# RePush kibana_system password on elasticsearch
docker exec elasticsearch \
  curl -k -u elastic:${ELASTIC_PASSWORD} \
  -X POST https://localhost:9200/_security/user/kibana_system/_password \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${KIBANA_PASSWORD}\"}"

# Restard Kibana
docker compose restart kibana
