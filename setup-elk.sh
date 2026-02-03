#!/bin/bash
set -e

echo "Configuration HTTPS ELK (Elastic 9 – clean & safe)"

# =======================
# ENV
# =======================
if [ ! -f .env ]; then
  echo "Password generation..."
  ELASTIC_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
  KIBANA_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

  cat > .env <<EOF
ELK_VERSION=9.0.0
ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
KIBANA_PASSWORD=${KIBANA_PASSWORD}
EOF

  chmod 600 .env
fi

source .env

docker compose down -v || true

# =======================
# CERTS GENERATION
# =======================
IMAGE="docker.elastic.co/elasticsearch/elasticsearch:${ELK_VERSION}"
OUT_DIR="$(pwd)/certs"
TMP_DIR="/tmp/output"

echo "📦 Génération certificats via conteneur temporaire..."

CID=$(docker create "$IMAGE" bash -c "
  set -e
  mkdir -p ${TMP_DIR}

  elasticsearch-certutil ca --silent --pem -out /tmp/ca.zip
  unzip -q /tmp/ca.zip -d ${TMP_DIR}

  elasticsearch-certutil cert --silent --pem \
    --ca-cert ${TMP_DIR}/ca/ca.crt \
    --ca-key  ${TMP_DIR}/ca/ca.key \
    --dns elasticsearch \
    --dns localhost \
    --ip 127.0.0.1 \
    -out /tmp/certs.zip

  unzip -q /tmp/certs.zip -d ${TMP_DIR}
")

docker start -a "$CID"

rm -rf certs
mkdir certs
docker cp "$CID:${TMP_DIR}/." certs
docker rm "$CID"

echo "Certificats Generated"

# =======================
# LOGSTASH CONF
# =======================
mkdir -p logstash/pipeline

cat > logstash/pipeline/logstash.conf <<'EOF'
input {
  beats { port => 5044 }
  tcp {
    port => 5000
    codec => json_lines
  }
}

output {
  elasticsearch {
    hosts => ["https://elasticsearch:9200"]
    user => "elastic"
    password => "${ELASTIC_PASSWORD}"
    ssl_enabled => true
    ssl_certificate_authorities => "/usr/share/logstash/config/certs/ca/ca.crt"
    ssl_verification_mode => "none"
  }
  stdout { codec => rubydebug }
}
EOF

# =======================
# BUILD
# =======================
docker compose build

# =======================
# START
# =======================
docker compose up -d

echo "Elasticsearch initialisation..."
for i in {1..60}; do
  if curl -k -s -u elastic:${ELASTIC_PASSWORD} https://localhost:9200 >/dev/null; then
    break
  fi
  echo "   Try $i/60..."
  sleep 3
done

docker exec elasticsearch \
  curl -k -u elastic:${ELASTIC_PASSWORD} \
  -X POST https://localhost:9200/_security/user/kibana_system/_password \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${KIBANA_PASSWORD}\"}"

docker compose restart kibana

sleep 10

echo ""
echo "To access (HTTPS):"
echo "   - Elasticsearch: https://localhost:9200"
echo "   - Kibana: https://localhost:5601"
echo "   - Logstash TCP: localhost:5000"
echo "   - Logstash Beats: localhost:5044"
echo ""
echo "Elasticsearch Creds:"
echo "   - User: elastic"
echo "   - Password: ${ELASTIC_PASSWORD}"
echo ""
echo "Kibana logging Creds:"
echo "   - User: kibana_system"
echo "   - Password: ${KIBANA_PASSWORD}"
echo ""
echo "Elasticsearch Testing:"
echo "   curl -k -u elastic:${ELASTIC_PASSWORD} https://localhost:9200"
echo ""
echo "You can retrieve generated Certs in ./Certs folder"
echo "and passwords of Elasticsearch and Kibana in the .env file wich are created with this script"
echo "Save the .env file securely and correctly"
echo ""
echo "ELK OK"
