# 📘 **Documentation d'utilisation – Script de déploiement Docker + Scanner CVE**

## 🎯 Objectif

Ce script Bash automatise le déploiement d'une stack Docker composée des services suivants :

* **Teleport** pour la gestion d'accès sécurisé
* **Portainer** pour l'administration Docker
* **UrBackup** pour la sauvegarde
* **PostgreSQL** pour stocker les vulnérabilités détectées
* **Grafana** pour la visualisation des CVE
* **Nginx** comme reverse proxy avec SSL
* **Scanner CVE** basé sur Nmap + Vulners
* **Zabbix Proxy** *(optionnel)* pour la supervision

---

## 🧰 Prérequis

* Système Debian ou Ubuntu avec accès root
* Un nom de domaine pointant vers la machine (si Let's Encrypt est utilisé)
* Connexion Internet

---

## ▶️ **Lancer le script**

Rendez le script exécutable :

```bash
chmod +x deploy.sh
./deploy.sh
```

---

## 🔧 **Configuration interactive**

Lors de l'exécution, plusieurs informations vous seront demandées :

| Entrée demandée                     | Description                            |
| ----------------------------------- | -------------------------------------- |
| 📁 Nom du projet                    | Crée un dossier pour tous les fichiers |
| 🌐 Domaine public                   | Utilisé pour Nginx/Teleport/Certificat |
| 🔐 Type de certificat               | Let's Encrypt (1) ou autosigné (2)     |
| ✉️ Email Certbot                    | Requis pour Let's Encrypt              |
| 📦 Installer Zabbix ?               | Active ou non le proxy Zabbix          |
| 🔑 Mot de passe Zabbix proxy        | Si Zabbix est activé                   |
| 📡 Lancer un scan initial ?         | Effectue un scan dès l'installation    |
| ⏱️ Planifier des scans ?            | Active un cron job automatique         |
| ⌛ Intervalle entre scans            | En jours (ex : `7`)                    |
| 🕒 Heure du scan                    | Format `HH:MM`                         |
| 🎯 Cible à scanner                  | IP / plage / domaine                   |
| 🗃️ Conserver historique scans ?    | Oui ou suppression automatique         |
| 🔐 Mot de passe PostgreSQL          | Valeur par défaut : `dojo123`          |
| 🧹 Supprimer installation existante | Réinitialisation complète              |

---

## 🛠️ **Ce que fait le script**

1. **Vérifie ou installe Docker, Buildx, Compose**
2. **Installe `cron` et l’active**
3. **Crée l’arborescence du projet**
4. **Génère les fichiers nécessaires :**

   * `docker-compose.yaml`
   * Certificat SSL (Let's Encrypt ou autosigné)
   * Scripts de scan et parsing CVE
   * Configuration Nginx
   * Fichier `teleport.yaml`
5. **Lance tous les conteneurs Docker**
6. **Planifie les scans automatiques via `cron`** (si demandé)

---

## 🔍 **Scan et parsing CVE**

* Le service `cve-scanner` utilise **Nmap** et le script **vulners**.
* Résultat sauvegardé dans un fichier XML.
* Le script Python (`parse_and_insert.py`) :

  * Parse le XML
  * Extrait les CVE, versions, liens, CVSS
  * Insère les données dans PostgreSQL

---

## 📊 **Accès aux interfaces**

| Service   | URL (via Teleport)            |
| --------- | ----------------------------- |
| Teleport  | `https://<domaine>`           |


> ⚠️ Si vous avez utilisé un **certificat autosigné**, un avertissement apparaîtra dans le navigateur.

---

## 👤 **Créer un utilisateur admin dans Teleport**

Après déploiement :

```bash
docker exec -it teleport tctl users add admin --roles=editor,access
```

---

## 🔁 **Scan automatique via `cron`**

Si activé, un job `cron` sera créé pour :

* Lancer un scan Nmap régulier
* Parse et insérer les vulnérabilités dans PostgreSQL

---

## 📂 **Structure du projet généré**

```
<project_dir>/
├── config/
│   └── teleport.yaml
├── data/
├── nginx/
│   ├── certs/
│   └── conf.d/
├── cve-scanner/
│   ├── scans/
│   └── scripts/
│       ├── scan.sh
│       ├── parse_and_insert.py
│       └── Dockerfile
├── docker-compose.yaml
```

---

## 🧹 **Nettoyage**

Si vous répondez "Oui" à la suppression de l'ancienne installation :

* Arrête et supprime les anciens conteneurs
* Supprime les volumes et fichiers du dossier projet

---

## 📦 **Images utilisées**

* `nginx:alpine`
* `portainer/portainer-ce:2.27.6`
* `uroni/urbackup-server`
* `postgres:13`
* `grafana/grafana`
* `instrumentisto/nmap`
* `python:3.10-slim` *(pour le parser)*
* `zabbix/zabbix-proxy-sqlite3` *(si activé)*
* `public.ecr.aws/gravitational/teleport-distroless-debug:17.5.2`

---

## ✅ **Post-installation conseillée**

* Configurer les dashboards Grafana
* Sécuriser les accès Teleport
* Ajouter des scripts de mise à jour (optionnel)

