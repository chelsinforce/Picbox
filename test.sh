#!/bin/bash
set -e

# === Fonctions couleurs ===
green() { echo -e "\e[32m$1\e[0m"; }
red() { echo -e "\e[31m$1\e[0m"; }
yellow() { echo -e "\e[33m$1\e[0m"; }
blue() { echo -e "\e[34m$1\e[0m"; }

# === Vérifications Docker ===
is_docker_installed() { command -v docker &> /dev/null; }
is_buildx_available() { docker buildx version &> /dev/null; }
is_compose_available() { docker compose version &> /dev/null; }

install_docker() {
  blue "🛠️ Installation de Docker et composants..."
  apt-get remove -y docker docker-engine docker.io containerd runc || true
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release openssl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# === Génération certificat autosigné ===
generate_self_signed_cert() {
  local DOMAIN=$1
  local CERT_DIR=$2
  mkdir -p "$CERT_DIR"
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$CERT_DIR/$DOMAIN.key" \
    -out "$CERT_DIR/$DOMAIN.crt" \
    -subj "/CN=$DOMAIN"
  green "✅ Certificat autosigné créé dans $CERT_DIR"
}

# === Menu principal ===

read -p "📁 Nom du projet (dossier) : " PROJECT_DIR
read -p "🌐 Domaine public (ex: teleport.example.com) : " DOMAIN

echo -e "\n🔐 Choix certificat SSL :"
echo "1) Let's Encrypt (via certbot)"
echo "2) Certificat autosigné"
read -p "Choix (1 ou 2) : " CERT_TYPE

if [[ "$CERT_TYPE" == "1" ]]; then
  read -p "Email pour certbot : " CERTBOT_EMAIL
fi

echo -e "\n📦 Choix pour Zabbix:"
echo "1) Oui"
echo "2) Non"
read -p "Installer ZABBIX (1 ou 2)? :" SERVICES

if [[ "$SERVICES" == "1" ]]; then
   read -p "Mot de passe Zabbix (pour proxy) : " ZABBIX_PASS
fi 

echo -e "\n📡 Initialiser un scan à l'installation ?"
echo "1) Oui"
echo "2) Non"
read -p "Lancer un scan initial maintenant ? (1 ou 2) : " INIT_SCAN

echo -e "\n⏱️ Planifier des scans automatiques ?"
echo "1) Oui"
echo "2) Non"
read -p "Lancer un scan initial maintenant ? (1 ou 2) : " SCAN_AUT

if [[ "$SCAN_AUT" == "1" ]]; then
  echo -e "\n⏱️ Planifier des scans automatiques ?"
  read -p "Nombre de jours entre chaque scan (laisser vide pour ne pas planifier) : " SCAN_INTERVAL_DAYS
  if [[ -n "$SCAN_INTERVAL_DAYS" ]]; then
  read -p "🕒 À quelle heure lancer le scan ? (ex: 03:00) : " SCAN_TIME
  fi
  read -p "\n🎯 Adresse IP, plage ou domaine à scanner (ex: 192.168.1.0/24) : " SCAN_TARGET
fi

echo -e "\n🗃️ Voulez-vous conserver l'historique des anciens scans ?"
echo "1) Oui (garder les données précédentes)"
echo "2) Non (supprimer les anciennes données avant chaque scan)"
read -p "Choix (1 ou 2) : " KEEP_HISTORY

read -p "🔐 Mot de passe PostgreSQL (laisser vide pour 'dojo123') : " DB_PASS
DB_PASS=${DB_PASS:-dojo123}

if [[ "$KEEP_HISTORY" == "2" ]]; then
  export CLEAR_DB=true
else
  export CLEAR_DB=false
fi

if ! is_docker_installed || ! is_buildx_available || ! is_compose_available; then
  install_docker
else
  green "✅ Docker et composants déjà installés."
fi

read -p "🧹 Supprimer ancienne installation $PROJECT_DIR ? (y/N) : " CLEANUP
if [[ "$CLEANUP" =~ ^[Yy]$ ]]; then
  docker compose -f "$PROJECT_DIR/docker-compose.yaml" down --volumes --remove-orphans || true
  rm -rf "$PROJECT_DIR"
fi

mkdir -p "$PROJECT_DIR"/{config,data,nginx/certs,nginx/conf.d,cve-scanner/scripts,cve-scanner/scans}

cat > "$PROJECT_DIR/cve-scanner/scripts/parse_and_insert.py" <<EOF
import xml.etree.ElementTree as ET
import psycopg2
import os
import re

# Connexion à la base PostgreSQL
conn = psycopg2.connect(
    dbname=os.environ["DB_NAME"],
    user=os.environ["DB_USER"],
    password=os.environ["DB_PASS"],
    host=os.environ["DB_HOST"]
)
cur = conn.cursor()

# Création de la table si elle n'existe pas
cur.execute("""
CREATE TABLE IF NOT EXISTS vulns (
    ip TEXT,
    port INTEGER,
    service TEXT,
    product TEXT,
    version TEXT,
    cve TEXT,
    cvss FLOAT,
    url TEXT
)
""")
conn.commit()

if os.environ.get("CLEAR_DB", "false").lower() == "true":
    print("🧹 Suppression des anciennes données...")
    cur.execute("DELETE FROM vulns")
    conn.commit()

# Parsing du XML
tree = ET.parse('/data/scan.xml')
root = tree.getroot()

for host in root.findall('host'):
    addr_el = host.find('address')
    if addr_el is None:
        continue
    addr = addr_el.attrib.get('addr')

    for port in host.findall(".//port"):
        portid = int(port.attrib['portid'])
        service_el = port.find('service')
        if service_el is None:
            continue

        service = service_el.attrib.get('name')
        product = service_el.attrib.get('product', '')
        version = service_el.attrib.get('version', '')

        script = port.find('script[@id="vulners"]')
        if script is not None:
            output = script.attrib.get('output', '')
            for line in output.splitlines():
                # Recherche des CVE (format CVE-YYYY-XXXX)
                cve_matches = re.findall(r'CVE-\d{4}-\d{4,7}', line)
                for cve in cve_matches:
                    cvss_match = re.search(r'\b\d{1,2}\.\d\b', line)
                    cvss = float(cvss_match.group()) if cvss_match else 0.0

                    url_match = re.search(r'https?://\S+', line)
                    url = url_match.group() if url_match else ''

                    cur.execute("""
                        INSERT INTO vulns (ip, port, service, product, version, cve, cvss, url)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """, (addr, portid, service, product, version, cve, cvss, url))

conn.commit()
cur.close()
conn.close()
print("✅ Données CVE insérées dans la base.")
EOF

cat > "$PROJECT_DIR/cve-scanner/scripts/requirements.txt" <<EOF
psycopg2-binary
beautifulsoup4
lxml
EOF

# === Dockerfile parser ===
cat > "$PROJECT_DIR/cve-scanner/scripts/Dockerfile" <<EOF
FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY parse_and_insert.py .
CMD ["python", "parse_and_insert.py"]
EOF

# === Scan script ===
cat > "$PROJECT_DIR/cve-scanner/scripts/scan.sh" <<EOF
#!/bin/sh
echo "🔍 Scan en cours..."
SCAN_FILE="/scans/scan.xml"
# Créer fichier XML vide si n'existe pas pour éviter erreurs
mkdir -p /scans
echo '<?xml version="1.0" encoding="UTF-8"?><nmaprun></nmaprun>' > "\$SCAN_FILE"
nmap -sV --script vulners -oX "\$SCAN_FILE" "\${SCAN_TARGET:-192.168.100.0/24}"
sleep 2
echo "✅ Scan terminé. Parsing..."
EOF

chmod +x "$PROJECT_DIR/cve-scanner/scripts/scan.sh"

if [[ "$CERT_TYPE" == "1" ]]; then
  blue "📥 Obtention certificat Let's Encrypt..."
  docker run --rm -it \
    -v "$PROJECT_DIR/nginx/certs:/etc/letsencrypt" \
    -v "$PROJECT_DIR/nginx/conf.d:/var/www/certbot" \
    certbot/certbot certonly \
    --webroot -w /var/www/certbot \
    --email "$CERTBOT_EMAIL" --agree-tos --no-eff-email -d "$DOMAIN"

  cp "$PROJECT_DIR/nginx/certs/live/$DOMAIN/fullchain.pem" "$PROJECT_DIR/nginx/certs/$DOMAIN.crt"
  cp "$PROJECT_DIR/nginx/certs/live/$DOMAIN/privkey.pem" "$PROJECT_DIR/nginx/certs/$DOMAIN.key"
else
  generate_self_signed_cert "$DOMAIN" "$PROJECT_DIR/nginx/certs"
fi

# Docker Compose
cat > "$PROJECT_DIR/docker-compose.yaml" <<EOF
version: "3.8"
services:
  nginx:
    image: nginx:alpine
    container_name: nginx
    ports:
      - "443:443"
    volumes:
      - ./nginx/certs:/etc/nginx/certs:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
    networks:
      - proxy
    restart: unless-stopped

  teleport:
    image: public.ecr.aws/gravitational/teleport-distroless-debug:17.5.2
    container_name: teleport
    entrypoint: teleport
    command: start --config=/etc/teleport/teleport.yaml
    volumes:
      - ./config:/etc/teleport:ro
      - ./data:/var/lib/teleport
    ports:
      - "3022:3022"
      - "3023:3023"
      - "3025:3025"
    networks:
      - proxy
      - internal
    restart: unless-stopped

  portainer:
    image: portainer/portainer-ce:2.27.6
    container_name: portainer
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - internal
    restart: unless-stopped

  urbackup:
    image: uroni/urbackup-server:latest
    container_name: urbackup
    volumes:
      - urbackup_data:/var/urbackup
      - urbackup_db:/var/urbackup/db
    ports:
      - "55413:55413"
      - "35623:35623/udp"
    networks:
      - proxy
      - internal
    restart: unless-stopped

  cve-scanner:
    image: instrumentisto/nmap
    container_name: cve-scanner
    environment:
      - SCAN_TARGET=${SCAN_TARGET}
    volumes:
      - ./cve-scanner/scans:/scans
      - ./cve-scanner/scripts:/scripts
    entrypoint: ["/bin/sh", "-c", "/scripts/scan.sh"]
    network_mode: host
    restart: "no"

  postgres:
    image: postgres:13
    container_name: pg_vulns
    environment:
      POSTGRES_USER: dojo
      POSTGRES_PASSWORD: ${DB_PASS}
      POSTGRES_DB: vulnscan
    volumes:
      - pg_data:/var/lib/postgresql/data
    networks:
      - internal
    restart: unless-stopped

  grafana:
    image: grafana/grafana
    container_name: grafana-vulns
    depends_on:
      - postgres
    environment:
      - GF_SERVER_ROOT_URL=https://scanner.${DOMAIN}
      - GF_SERVER_SERVE_FROM_SUB_PATH=true
      - GF_SECURITY_ALLOW_EMBEDDING=true
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
    networks:
      - internal
    restart: unless-stopped

  parser:
    build: ./cve-scanner/scripts
    container_name: vuln_parser
    volumes:
      - ./cve-scanner/scans:/data
    environment:
      - DB_HOST=postgres
      - DB_USER=dojo
      - DB_PASS=${DB_PASS}
      - DB_NAME=vulnscan
      - CLEAR_DB=${CLEAR_DB}
    networks:
      - internal
    depends_on:
      - postgres
    restart: "no"

EOF

if [[ "$SERVICES" == "1" ]]; then
  cat >> "$PROJECT_DIR/docker-compose.yaml" <<EOF

  zabbix_proxy:
    image: zabbix/zabbix-proxy-sqlite3:latest
    container_name: zabbix_proxy
    environment:
      - ZBX_HOSTNAME=zabbix-proxy
      - ZBX_SERVER_HOST=127.0.0.1
      - ZBX_PROXYMODE=0
      - ZBX_LOGLEVEL=3
      - ZBX_PASS=${ZABBIX_PASS}
    volumes:
      - zabbix_proxy_data:/var/lib/sqlite
    networks:
      - internal
    restart: unless-stopped
EOF
fi

cat >> "$PROJECT_DIR/docker-compose.yaml" <<EOF

networks:
  proxy:
  internal:

volumes:
  grafana_data:
  pg_data:
  portainer_data:
  urbackup_data:
  urbackup_db:
  wazuh_data:
  zabbix_proxy_data:

EOF

cat > "$PROJECT_DIR/nginx/conf.d/default.conf" <<EOF
server {
  listen 443 ssl;
  server_name $DOMAIN;

  ssl_certificate /etc/nginx/certs/$DOMAIN.crt;
  ssl_certificate_key /etc/nginx/certs/$DOMAIN.key;

  location / {
    proxy_pass https://teleport:3080;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$remote_addr;
  }
}
EOF

mkdir -p "$PROJECT_DIR/config"
cat > "$PROJECT_DIR/config/teleport.yaml" <<EOF
teleport:
  data_dir: /var/lib/teleport
  log:
    output: stderr
    severity: INFO

auth_service:
  enabled: true
  cluster_name: teleport-cluster
  listen_addr: 0.0.0.0:3025

ssh_service:
  enabled: true
  listen_addr: 0.0.0.0:3022
  labels:
    type: "switch"
    access: "reseau-local"

proxy_service:
  enabled: true
  web_listen_addr: 0.0.0.0:3080
  public_addr: "$DOMAIN"
  ssh_public_addr: "$DOMAIN:3023"
  listen_addr: 0.0.0.0:3023

app_service:
  enabled: true
  apps:
    - name: portainer
      uri: http://portainer:9000
      public_addr: portainer.$DOMAIN
    - name: urbackup
      uri: http://urbackup:55414
      public_addr: urbackup.$DOMAIN
    - name: grafana
      uri: http://grafana-vulns:3000
      public_addr: grafana.$DOMAIN
      labels:
        type: "monitoring"
      rewrite:
        headers:
          - "Host: grafana.$DOMAIN"
          - "Origin: https://grafana.$DOMAIN"
EOF

# === Lancement ===
cd $PROJECT_DIR
docker compose up -d

green "✅ Déploiement préparé dans $PROJECT_DIR"
yellow "⚠️ Pour créer un compte admin, exécutez : docker exec -it teleport tctl users add admin --roles=editor,access"
[[ "$CERT_TYPE" == "2" ]] && yellow "⚠️ Certificat autosigné : un avertissement apparaîtra dans le navigateur."

#cron
if [[ -n "$SCAN_INTERVAL_DAYS" ]]; then
  /bin/sh -c "echo '${SCAN_TIME##*:} ${SCAN_TIME%%:*} */$SCAN_INTERVAL_DAYS * * docker compose run --rm cve-scanner && docker compose run --rm parser' | crontab - && crond -f"
fi

#Lancement scan
if [[ "$INIT_SCAN" == "1" ]]; then
  green "🚀 Lancement du scan initial..."
  docker compose -f "docker-compose.yaml" build parser
  docker compose -f "docker-compose.yaml" run --rm cve-scanner
  docker compose -f "docker-compose.yaml" run --rm parser
fi
exit 0