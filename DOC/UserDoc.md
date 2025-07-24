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

#### 2. **Création du certificat cloudflare**

Afin de sécuriser le tout, il faut mêtre en place des certificats. 

- Cliquez sur le domaine :

  ![alt text](https://github.com/chelsinforce/Picbox/blob/d918af9b7db433d559d11458f0d3a8e2b069581e/DOC/Images/Cloudflare%20Start.png)

- Allez dans Edge Certificate

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a507e0991c743223765a8bf7d72e9ae284c96e6a/DOC/Images/Cloudflare%20Edge%20cert.png)

- Demander un nouveau certificat

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a507e0991c743223765a8bf7d72e9ae284c96e6a/DOC/Images/Cloudflare%20Order%20Advanced%20Cert.png)

- Cliquez sur les Hostnames

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a507e0991c743223765a8bf7d72e9ae284c96e6a/DOC/Images/Cloudflare%20Ajout%20Nom%20Domaine.png)

- Ajouter le domaine *.le nom du client et cliquez sur le domaine qui apparait en dessous et sauvegardez

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a507e0991c743223765a8bf7d72e9ae284c96e6a/DOC/Images/Cloudflare%20Validation%20Cert.png)

#### 3. **Création du tunnel cloudflare**

Une fois le certificat enregistré, il faut créer un tunnel : 

- Allez dans le portail 0 Trust

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Access.png)

- Cliquez sur Network

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Network.png)

- Cliquez sur Tunnels

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Tunnels.png)

- Et créer un Tunnel

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Create%20Tunnel.png)

- Nommez votre Tunnel

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Tunnel%20Name.png)

- Selectionner Cloudflared

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Cloudflared.png)

- Choisissez votre environnement (**DOCKER POUR LA PICBOX**) et copier la commade qui s'affiche.

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Choose%20Environment.png)

- Modifier la pour qu'elle ressemble a ceci :

  ```bash
  docker run -d \
    --name cloudflared \
    --restart unless-stopped \
    --network <domaine_utilisé_pour_projet_sans_point>_cloudflared \
    cloudflare/cloudflared:latest \
    tunnel --no-autoupdate run --token <votre_token_cloudflare>
  ```

  Pour le domaine, il ressemblera a : nomclientpicinformatiquecom

  Une fois la connection faites et validé, appuyé sur suivant :

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Tunnel%20Next.png)

- Assigner le nom de domaine et le services a contacter

  Pour le nom de domaine, il s'agit du domaine donnée auparavant

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Domaine.png)

  Concernant les services, dans le cadre de la PICBOX, ils faut renseigner HTTPS et teleport:3080

  **ATTENTION : Si vous avez un certificats autosigné installé, il vaut activer le NO TLS VERIFY**

  ![alt text](https://github.com/chelsinforce/Picbox/blob/346554bfa151f81a38d22e6df5294691a31e5112/DOC/Images/Cloudflare%200%20Trust%20NO%20TLS%20VERIFY.png)

  Et cliquez sur terminer.
  
#### 4. **Ajout du CNAME manquant


#### 5. **Accès a Teleport**

  - Accéder a votre domaine

    Vous tomberez alors sur cette page après avoir acepter les conditions d'utilisation: 

  - Retournez dans le terminal de la PICBOX et tapez (copier coller) cette commane :

    ```bash
    docker exec -it teleport tctl users add admin --roles=editor,access
    ```
  Une URL vous sera donné, (Ctrl + click gauche pour ouvrir dans le navigateur)

  Créer votre compte pour arriver sur le portail

 ![alt text]()

 #### 5.1. Ajout de serveur ssh

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

  * Modifier la règle Acces


