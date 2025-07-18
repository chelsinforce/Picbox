#!/bin/bash
set -e # Arrêter l'exécution en cas d'erreur

# === Fonctions pour afficher des messages colorés ===
green()  { echo -e "\e[32m$1\e[0m"; } # Texte en vert
red()    { echo -e "\e[31m$1\e[0m"; } # Texte en rouge
yellow() { echo -e "\e[33m$1\e[0m"; } # Texte en jaune
blue()   { echo -e "\e[34m$1\e[0m"; } # Texte en bleu

# === Fonctions de vérification pour Docker ===
is_docker_installed() { command -v docker &> /dev/null; }
is_buildx_available() { docker buildx version &> /dev/null; }
is_compose_available() { docker compose version &> /dev/null || command -v docker-compose &> /dev/null; }

# === Installation de Docker si non présent ===
install_docker() {
  blue "🛠️ Installation de Docker et composants..."
  apt-get remove -y docker docker-engine docker.io containerd runc || true
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release openssl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor \
    -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# === Génération de certificat autosigné (si sélectionné) ===
generate_self_signed_cert() {
  local DOMAIN=$1
  local CERT_DIR=$2
  mkdir -p "$CERT_DIR"
  openssl req -x509 -nodes -days 365 \
	-newkey rsa:2048 \
  	-keyout "$CERT_DIR/$DOMAIN".key \
  	-out "$CERT_DIR/$DOMAIN".crt \
  	-config cert.conf
  green "✅ Certificat autosigné créé dans $CERT_DIR"
}

# === Collecte des paramètres de configuration via input utilisateur ===
# (Ex : nom de projet, domaine, type de certificat, base de données, etc.)

read -p "📁 Nom du projet (dossier) : " PROJECT_DIR
read -p "🌐 Domaine public (ex: teleport.example.com) : " DOMAIN

echo -e "\n🔐 Choix du certificat SSL :"
echo "1) Let's Encrypt"
echo "2) Certificat autosigné (self-signed)"
read -p "Choix (1 ou 2) : " CERT_TYPE

if [[ "$CERT_TYPE" == "1" ]]; then
  read -p "Email pour certbot : " CERTBOT_EMAIL
fi

echo -e "\n📦 Zabbix "
read -p "Hostname Zabbix (proxy) : " ZABBIX_HOSTNAME
read -p "IP Zabbix (proxy) : " ZABBIX_IP
read -p "Identité PSK (proxy) : " PSK_IDENTITY

echo -e "\n🖥️ Serveur NGINX"
read -p "IP de cloudflared (docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cloudflared): " CLOUDFLARE_IP


echo -e "\n📡 Lancer un scan initial maintenant ?"
echo "1) Oui"
echo "2) Non"
read -p "Choix initial scan (1 ou 2) : " INIT_SCAN

echo -e "\n⏱️ Planification des scans automatiques "
read -p "Intervalle en jours entre chaque scan (laisser vide pour désactiver) : " SCAN_INTERVAL_DAYS
read -p "Heure de lancement du scan (HH:MM, par ex. 03:00) : " SCAN_TIME
read -p "Cible à scanner (IP, plage ou domaine) : " SCAN_TARGET

echo -e "\n🗃️ Conserver l'historique des anciens scans ?"
echo "1) Oui"
echo "2) Non – supprimer les anciens"
read -p "Choix (1 ou 2) : " KEEP_HISTORY

read -p "🔐 Mot de passe PostgreSQL (laisser vide = 'dojo123') : " DB_PASS
DB_PASS=${DB_PASS:-dojo123}

export CLEAR_DB=$([[ "$KEEP_HISTORY" == "2" ]] && echo "true" || echo "false")

# Vérification / installation Docker
if ! is_docker_installed || ! is_buildx_available || ! is_compose_available; then
  install_docker
else
  green "✅ Docker, buildx et compose sont déjà installés."
fi

# === Installation et activation de cron ===
if ! command -v cron >/dev/null 2>&1; then
  blue "📦 Installation de cron..."
  apt-get update
  apt-get install -y cron
else
  green "✅ Cron est déjà installé."
fi

# === Activation du service cron ===
if ! pgrep -x "cron" > /dev/null; then
  blue "🔁 Démarrage du service cron..."
  service cron start
  systemctl enable cron 2>/dev/null || true
else
  green "✅ Le service cron est déjà en cours d'exécution."
fi

# === Suppression de l'ancienne installation si demandé ===
# (Ex : suppression de volumes, fichiers existants, etc.)

read -p "🧹 Supprimer ancienne installation '$PROJECT_DIR' ? (y/N) : " CLEANUP
CLEANUP=${CLEANUP:-n}
if [[ "$CLEANUP" =~ ^[Yy]$ ]]; then
  docker compose -f "$PROJECT_DIR/docker-compose.yaml" down --volumes --remove-orphans || true
  rm -rf "$PROJECT_DIR"
fi

# === Création de l'arborescence de fichiers et scripts nécessaires ===

# Création des dossiers
mkdir -p "$PROJECT_DIR"/{config,data,nginx/certs,nginx/conf.d,cve-scanner/scripts,cve-scanner/scans,psk}

# - Scripts Python de parsing

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

# - Script de scan Nmap avec CVE
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

# === Obtention du certificat SSL (Let's Encrypt ou autosigné) ===

if [[ "$CERT_TYPE" == "1" ]]; then
  blue "📥 Obtention du certificat Let's Encrypt..."
  if ! docker run --rm -v "$PROJECT_DIR/nginx/certs:/etc/letsencrypt" \
       -v "$PROJECT_DIR/nginx/conf.d:/var/www/certbot" \
       certbot/certbot certonly \
       --webroot -w /var/www/certbot \
       --email "$CERTBOT_EMAIL" --agree-tos --no-eff-email -d "$DOMAIN"; then
    red "❌ Échec de Certbot, vérifie la config du domaine et que port 80 est ouvert."
    exit 1 # - Si Let's Encrypt échoue, arrêt du script avec message d'erreur
  fi
  cp "$PROJECT_DIR/nginx/certs/live/$DOMAIN/fullchain.pem" "$PROJECT_DIR/nginx/certs/$DOMAIN.crt"
  cp "$PROJECT_DIR/nginx/certs/live/$DOMAIN/privkey.pem" "$PROJECT_DIR/nginx/certs/$DOMAIN.key"
else
  generate_self_signed_cert "$DOMAIN" "$PROJECT_DIR/nginx/certs"
fi

# === Génération du fichier.psk de zabbix ===

openssl rand -hex 32 > $PROJECT_DIR/psk/zabbix_proxy.psk

# === Génération du fichier docker-compose.yaml ===
# - Conteneurs : nginx, teleport, portainer, urbackup, postgres, grafana, zabbix, scanner CVE, parser
# - Configuration des volumes, réseaux, variables d'environnement

cat > "$PROJECT_DIR/docker-compose.yaml" <<EOF
version: "3.8"
services:
  nginx:
    image: nginx:alpine
    container_name: nginx
    ports:
      - "443:443"
      - "3080:3080"
    volumes:
      - ./nginx/certs:/etc/nginx/certs:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
    networks:
      - cloudflared
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

  zabbix_proxy:
    image: zabbix/zabbix-proxy-sqlite3:latest
    container_name: zabbix_proxy
    environment:
      - ZBX_HOSTNAME=${ZABBIX_HOSTNAME}
      - ZBX_SERVER_HOST=${ZABBIX_IP}
      - ZBX_PROXYMODE=0
      - ZBX_LOGLEVEL=3
      - ZBX_TLSCONNECT=psk
      - ZBX_TLSPSKFILE=/etc/zabbix/psk.key
      - ZBX_TLSPSKIDENTITY=${PSK_IDENTITY}
    volumes:
      - ./psk/zabbix_proxy.psk:/etc/zabbix/psk.key:ro
      - zabbix_proxy_data:/var/lib/zabbix
    restart: unless-stopped
EOF

cat >> "$PROJECT_DIR/docker-compose.yaml" <<EOF

networks:
  proxy:
  internal:
  cloudflared:

volumes:
  grafana_data:
  pg_data:
  portainer_data:
  urbackup_data:
  urbackup_db:
  zabbix_proxy_data:

EOF

# === Configuration du reverse proxy NGINX pour Teleport et redirections HTTPS ===

cat > "$PROJECT_DIR/nginx/conf.d/default.conf" <<EOF
server {
  listen 443 ssl;
  server_name $DOMAIN;

  allow $CLOUDFLARE_IP;
  deny all;

  ssl_certificate /etc/nginx/certs/$DOMAIN.crt;
  ssl_certificate_key /etc/nginx/certs/$DOMAIN.key;

  location / {
    proxy_pass https://teleport:3080;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$remote_addr;
  }
}

server {
  listen 3080;
  server_name $DOMAIN;

  location / {
    return 301 https://$host$request_uri;
  }
}
EOF

# === Configuration de Teleport via teleport.yaml ===
# - Ajout d'applications (portainer, urbackup, grafana)

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

# === Lancement des services via Docker Compose ===

cd $PROJECT_DIR
docker compose up -d

green "✅ Déploiement préparé dans $PROJECT_DIR"
yellow "⚠️ Pour créer un compte admin, exécutez : docker exec -it teleport tctl users add admin --roles=editor,access"
yellow "⚠️ Renseignez ces données dans Zabbix pour authentifier le proxy :"
yellow "- PSK Identity : $PSK_IDENTITY"
yellow "- PSK Key :"
yellow "  $(cat $PROJECT_DIR/psk/zabbix_proxy.psk)"

[[ "$CERT_TYPE" == "2" ]] && yellow "⚠️ Certificat autosigné : un avertissement apparaîtra dans le navigateur."

# === Planification d'un scan automatique avec cron si demandé ===

if [[ -n "$SCAN_INTERVAL_DAYS" ]]; then
  cron_line="${SCAN_TIME##*:} ${SCAN_TIME%%:*} */$SCAN_INTERVAL_DAYS * * cd $(pwd) && docker compose run --rm cve-scanner && docker compose run --rm parser"
  (crontab -l 2>/dev/null; echo "$cron_line") | crontab -

  blue "🔁 Tentative de démarrage du service cron..."

  cron_started=false
  if command -v service &>/dev/null && service cron start 2>/dev/null; then
    cron_started=true
  elif command -v cron &>/dev/null && cron 2>/dev/null & disown; then
    cron_started=true
  fi

  sleep 1
  if $cron_started && pgrep -x cron >/dev/null; then
    green "✅ Planification cron enregistrée et daemon démarré."
  else
    red "❌ Impossible de démarrer le daemon cron. Il est peut-être absent ou non compatible avec cet environnement."
  fi
fi

# === Lancement d'un scan initial manuel si sélectionné ===

if [[ "$INIT_SCAN" == "1" ]]; then
  green "🚀 Lancement du scan initial..."
  docker compose build parser
  docker compose run --rm cve-scanner
  docker compose run --rm parser
fi

exit 0
