# CVE Scanner Infrastructure

## Overview

This project provides a fully containerized infrastructure for securely scanning, parsing, and monitoring vulnerabilities (CVEs) across a network. Designed for operational simplicity and high security, it uses Docker, Nmap, PostgreSQL, and Grafana, with access management and service routing handled exclusively through Teleport behind a reverse proxy.

> **Access to all internal services is strictly routed through Teleport.**  
> The only public entrypoint is an HTTPS endpoint served by NGINX.



## Features

- **Single-command deployment** via interactive Bash script
- **End-to-end CVE scanning pipeline**:
  - Network scanning with Nmap + Vulners
  - Structured parsing and storage in PostgreSQL
  - Visual dashboards via Grafana
- **Access isolation with Teleport**: users authenticate via Teleport to access any internal UI
- **Scheduled scans with cron**
- **Self-signed or Let’s Encrypt SSL**
- **Secure ingress via NGINX reverse proxy**
- **Optional support for Zabbix Proxy (monitoring)**



## Architecture



```
             Public Internet (HTTPS)
                     │
                     ▼
              ┌────────────┐
              │   NGINX    │
              │  (SSL RP)  │
              └────┬───────┘
                   ▼
            ┌──────────────┐
            │   Teleport   │
            │ (Access Hub) │
            └────┬─────────┘
                 │
   ┌─────────────┼────────────────────┐
   ▼             ▼                    ▼

  Grafana      Portainer             UrBackup
(Dashboards)  (Docker UI)           (Backups)



    Internal-only (non-routable) Docker service

┌──────────────────────────────────────────────────┐
│  PostgreSQL                                      │
│  Nmap Scanner                                    │
│  Python Parser (CVE extraction)                  │
│  Zabbix Proxy (optional)                         │
└──────────────────────────────────────────────────┘

````


## Access Model

| Component    | Access                  |
|--------------|--------------------------|
| Cloudflar        | Proxy |
| NGINX        | Public (HTTPS, port 443) |
| Teleport     | Internal (proxied by NGINX) |
| All other UIs| Private (accessed via Teleport UI) |
| Services     | Isolated within Docker network |

All external access is authenticated and proxied through **Cloudflare and Teleport**, which serves as the central access gateway for all services (Grafana, Portainer, UrBackup, etc.).



## Deployment

### Prerequisites

- Debian/Ubuntu server
- Docker + Docker Compose
- Public domain name (DNS must point to server IP)
- Open ports: 80, 443 (Teleport, NGINX)

### Install

```bash
chmod +x deploy.sh
./deploy.sh
````

You will be prompted for:

* Project directory name
* Domain name
* SSL type (Let’s Encrypt or self-signed)
* Teleport configuration
* CVE scan targets and frequency
* PostgreSQL password
* Zabbix proxy inclusion (optional)

The script configures and deploys all services automatically.
Please read the **DocTechnique**



## CVE Scan Pipeline

1. **Nmap** scans a defined target with `--script vulners`.
2. **Raw XML** output is saved in a mounted volume.
3. **Python parser** extracts:

   * IP, port, service, version
   * CVE ID, CVSS score, Vulners URL
4. **PostgreSQL** stores results in a structured schema.
5. **Grafana** visualizes the results through pre-configured dashboards.

Scans can be run on-demand or automatically via cron.



## Scheduled Scans

During setup, you can define:

* Frequency (daily, every N days)
* Time (HH\:MM)
* Target IPs or hostnames

A cron job will execute `nmap`, parse the results, and update the database without manual intervention.



## Services Included

| Service      | Purpose                              | Access Method           |
| ------------ | ------------------------------------ | ----------------------- |
| Teleport     | Secure gateway for internal services | `https://<your-domain>` |
| Grafana      | CVE dashboards                       | via Teleport            |
| Portainer    | Docker management UI                 | via Teleport            |
| UrBackup     | Backup interface                     | via Teleport            |
| PostgreSQL   | CVE data store                       | Internal only           |
| Nmap         | Network scanner                      | Internal only           |
| CVE Parser   | Parses scan XML to DB                | Internal only           |
| Zabbix Proxy | Optional monitoring agent            | Internal only           |
| NGINX        | Reverse proxy with TLS               | Public (443)            |



## Security Model

* No service is directly exposed except NGINX (HTTPS)
* All access flows through Teleport’s authenticated UI
* Role-based access and session auditing via Teleport
* TLS enforced with Let’s Encrypt or self-signed certs
* Docker containers communicate via isolated bridge network


## Post-Deployment

1. **Create Teleport user:**

   ```bash
   docker exec -it teleport tctl users add admin --roles=access,editor
   ```
2. **Login to Teleport:** `https://your-domain.com`
3. **Access internal services** from the Teleport dashboard
4. **Import Grafana dashboards** or use the included JSON templates
5. **Monitor scan results**, schedule tasks, or trigger scans on demand



## Cloudflare Tunnel (Zero Trust)

You can further restrict public exposure by using a Cloudflare tunnel:

```bash
docker run -d \
  --name cloudflared \
  --restart unless-stopped \
  cloudflare/cloudflared:latest \
  tunnel --no-autoupdate run --token <YOUR_TOKEN>
```