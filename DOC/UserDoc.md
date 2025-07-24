## 🛠️ **Documentation Utilisateur : Déploiement de l’environnement Picbox**


### **Pré-requis**

* Serveur Debian (recommendé) /Ubuntu récent
* Mémoire RAM : 16 Go minimum
* Stockage : Espace disque suffisant pour :
  - L'application
  - Les sauvegardes
  - Les journaux système et applicatifs
* Accès `root` ou `sudo`
* Docker non nécessairement préinstallé (le script l’installe si absent)
* Un domaine public pointant vers le serveur (ex: `teleport.example.com`)
* Un token Cloudflare Tunnel Zero Trust

### **Étapes du déploiement**

#### 1. **Lancer le script de déploiement**

Créer un fichier pour la PICBOX (pas besoin si vous clonnez le code, le fichier viens avec) a la racine.

```bash
cd /
mkdir PICBOX
cd PICBOX
```

Téléchargez ou copiez le script complet et exécutez-le :

- Pour le copier depuis le presse papier : 

```bash
nano deploy.sh

#Ctrl + shift + v ou click droit si connecté en ssh

# Ctrl + x et y puis Entrée
```

- Pour le copier depuis un repo : 

```bash
apt update
apt install git

git clone (le liens du repo)
```
Donner les droits nécéssaire et exécuté le script

```bash
chmod +x deploy.sh
./deploy.sh
```

Le script va :

* Installer Docker si besoin
* Vous demander les informations nécessaires
* Générer les certificats (Autosigné (testé et approuver) ou Let’s Encrypt(a tester)) 
* Configurer Teleport, Portainer, Zabbix Proxy, Nginx, Grafana, PostgreSQL, etc.
* Lancer tous les conteneurs via `docker compose`

**Renseigné bien toutes les informations**

* Nom du dossier de projet
* Domaine public (`teleport.mondomaine.com`)
* Type de certificat (Let’s Encrypt ou autosigné)
* Email pour Certbot (si Let's Encrypt)
* Données Zabbix Proxy (hostname, IP du serveur Zabbix et un identifiant spk)
* Mot de passe PostgreSQL (par défaut : `dojo123` **A CHANGER**)
* Fréquence des scans CVE
* Suppression de l’ancienne installation (optionnel)

#### 2. **Création du tunel cloudflare**

Dans le tableau de bord Cloudflare Zero Trust :

1. Créez un **tunnel** dans l’interface Cloudflare.
2. Récupérez le **token de connexion** fourni.

Référez vous a la doc Cloudflare

Ensuite, exécutez les commandes suivantes **sur le serveur** :

```bash
docker network create <domaine_utilisé_pour_projet>_cloudflared

docker run -d \
  --name cloudflared \
  --restart unless-stopped \
  --network <domaine_utilisé_pour_projet>_cloudflared \
  cloudflare/cloudflared:latest \
  tunnel --no-autoupdate run --token <votre_token_cloudflare>
```
> Remplacez `<votre_token_cloudflare>` par votre token réel.
> Remplacez `<domaine_utilisé_pour_projet>` par votre domaine réel. (ex:teleportpicinformatiquecom)

#### 2. 🔍 **Récupérer l’IP du conteneur Cloudflared**

Exécutez :

```bash
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cloudflared
```

Notez l’IP affichée (ex: `172.20.0.3`) — elle sera utilisée pour configurer NGINX.


#### 3. 🚀 **Lancer le script de déploiement**

Téléchargez ou copiez le script complet et exécutez-le :

```bash
chmod +x deploy.sh
./deploy.sh
```

Le script va :

* Installer Docker si besoin
* Vous demander les informations nécessaires
* Générer les certificats (Let’s Encrypt ou autosigné)
* Configurer Teleport, Portainer, Zabbix Proxy, Nginx, Grafana, PostgreSQL, etc.
* Lancer tous les conteneurs via `docker compose`


#### 4. 📥 **Répondez aux questions posées par le script**

Vous devrez fournir des informations comme :

* Nom du dossier de projet
* Domaine public (`teleport.mondomaine.com`)
* Type de certificat (Let’s Encrypt ou autosigné)
* Email pour Certbot (si Let's Encrypt)
* IP de Cloudflared (cf. étape 2)
* Données Zabbix Proxy (hostname, IP du serveur Zabbix et un identifiant spk)
* Mot de passe PostgreSQL (par défaut : `dojo123`)
* Fréquence des scans CVE (si souhaité)
* Suppression de l’ancienne installation (optionnel)


#### 5. 🧑‍💼 **Créer un compte administrateur Teleport**

Une fois les services déployés, créez un utilisateur administrateur Teleport :

```bash
docker exec -it teleport tctl users add admin --roles=editor,access
```

Vous recevrez un **lien de connexion** avec un **code d’inscription** à saisir dans le navigateur.

> ⚠️ Accédez à Teleport sans le port `3080` dans l’URL (utilisez simplement `https://teleport.mondomaine.com`).


#### 6. 📂 **Accès à Portainer (attention au délai !)**

* Portainer est **exposé via Teleport** sous `https://portainer.mondomaine.com`
* **Connectez-vous rapidement**, sinon le conteneur peut se couper automatiquement au bout de 5 minutes (selon config)


#### 7. 🖼️ **Picbox & autres services**

* **UrBackup** : [https://urbackup.mondomaine.com](https://urbackup.mondomaine.com)
* **Grafana** (visualisation des vulnérabilités) : [https://grafana.mondomaine.com](https://grafana.mondomaine.com)
* **Portainer** : gestion de conteneurs Docker


### 🕐 **Planification automatique des scans CVE**

Si vous avez choisi de planifier des scans :

* Le script configure un **cron job** automatiquement.
* Il exécutera régulièrement :

  * Le scan Nmap avec détection CVE
  * Le parsing et insertion des données dans PostgreSQL
  * Visualisation via Grafana


### 🧹 **Nettoyage**

Si vous avez répondu "Oui" à la suppression de l’ancienne installation, le script :

* Supprime les volumes et données existantes
* Supprime le dossier du projet

### 📰 **ZABBIX — Configuration du Proxy**

1. **Accédez à l'interface du serveur Zabbix**.

2. Naviguez vers :
   **`Administration` → `Proxies`**

3. **Créez un nouveau proxy** avec :

   * **Le même nom** que celui utilisé dans le script (`Hostname`)
   * **Le type d’authentification** configuré (ex. : PSK)
   * **Les informations suivantes** :

     * 🔐 **PSK Identity** : `Ce que vous avez renseigné`
     * 🔑 **PSK Key** : `Donnée par le script`

### ➕ Enrollement d'un serveur SSH linux

Afin d'enroller un nouveau serveur, **ne cliquez pas sur enroller un serveur**

**Sur la PICBOX**
  
  * Soyez root 
  * Obtenez le tocken d'authentification : 

    ```
    docker exec -it teleport tctl tokens add --type=node --ttl=1h
    ```

  Vous obtennez alors un token. Seul ce token compte

**Sur le serveur a enroller**

  * Installer teleport 

    ```
    curl -fsSL https://goteleport.com/static/install.sh | bash -s 16.2.0
    ```

  * Initialiser la connection

    ```
    teleport start --roles=node --token=(token) --auth-server=(ipserver):3025 --nodename=(nom explicatif)
    ```

### ✅ **Recommandation :**

* Configurez **l'adresse IP du proxy en statique**
* Renseignez **cette IP** dans la configuration du proxy sur Zabbix pour éviter tout problème de résolution ou détection

