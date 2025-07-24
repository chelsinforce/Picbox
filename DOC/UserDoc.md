## 🛠️ **Documentation Utilisateur : Déploiement de l’environnement Picbox**

### **Pré-requis**

* Serveur Debian (recommandé) / Ubuntu récent
* Mémoire RAM : 16 Go minimum
* Stockage : espace disque suffisant pour :
  - l’application
  - les sauvegardes
  - les journaux système et applicatifs
* Accès `root` ou `sudo`
* Docker pas nécessairement préinstallé (le script l’installe si absent)
* Un domaine public pointant vers le serveur (ex : `teleport.example.com`)
* Un token Cloudflare Tunnel Zero Trust

### **Étapes du déploiement**

#### 1. **Lancer le script de déploiement**

Créer un dossier pour la PICBOX (pas besoin si vous clonez le code, le fichier vient avec) à la racine.

```bash
cd /
mkdir PICBOX
cd PICBOX
```

Téléchargez ou copiez le script complet et exécutez-le :

- Pour le copier depuis le presse-papiers : 

```bash
nano deploy.sh

# Ctrl + Shift + V ou clic droit si connecté en SSH

# Ctrl + X puis Y, puis Entrée
```

- Pour le copier depuis un dépôt : 

```bash
apt update
apt install git

git clone (le lien du repo)
```
Donnez les droits nécessaires et exécutez le script :

```bash
chmod +x deploy.sh
./deploy.sh
```

Le script va :

* Installer Docker si besoin
* Vous demander les informations nécessaires
* Générer les certificats (Autosigné (testé et approuvé) ou Let’s Encrypt (à tester)) 
* Configurer Teleport, Portainer, Zabbix Proxy, Nginx, Grafana, PostgreSQL, etc.
* Lancer tous les conteneurs via `docker compose`

**Renseignez bien toutes les informations**

* Nom du dossier de projet
* Domaine public (`teleport.mondomaine.com`)
* Type de certificat (Let’s Encrypt ou autosigné)
* Email pour Certbot (si Let's Encrypt)
* Données Zabbix Proxy (hostname, IP du serveur Zabbix et un identifiant spk)
* Mot de passe PostgreSQL (par défaut : `dojo123` **À CHANGER**)
* Fréquence des scans CVE
* Suppression de l’ancienne installation (optionnel)

#### 2. **Création du certificat Cloudflare**

Afin de sécuriser l’ensemble, il faut mettre en place des certificats. 

- Cliquez sur le domaine :

  ![alt text](https://github.com/chelsinforce/Picbox/blob/d918af9b7db433d559d11458f0d3a8e2b069581e/DOC/Images/Cloudflare%20Start.png)

- Allez dans Edge Certificate

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a507e0991c743223765a8bf7d72e9ae284c96e6a/DOC/Images/Cloudflare%20Edge%20cert.png)

- Demandez un nouveau certificat

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a507e0991c743223765a8bf7d72e9ae284c96e6a/DOC/Images/Cloudflare%20Order%20Advanced%20Cert.png)

- Cliquez sur les Hostnames

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a507e0991c743223765a8bf7d72e9ae284c96e6a/DOC/Images/Cloudflare%20Ajout%20Nom%20Domaine.png)

- Ajoutez le domaine *.lenomduclient et cliquez sur le domaine qui apparaît en dessous puis sauvegardez

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a507e0991c743223765a8bf7d72e9ae284c96e6a/DOC/Images/Cloudflare%20Validation%20Cert.png)

#### 3. **Création du tunnel Cloudflare**

Une fois le certificat enregistré, il faut créer un tunnel : 

- Allez dans le portail Zero Trust

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Access.png)

- Cliquez sur Network

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Network.png)

- Cliquez sur Tunnels

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Tunnels.png)

- Et créez un Tunnel

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Create%20Tunnel.png)

- Nommez votre Tunnel

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Tunnel%20Name.png)

- Sélectionnez Cloudflared

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Cloudflared.png)

- Choisissez votre environnement (**DOCKER POUR LA PICBOX**) et copiez la commande qui s’affiche.

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Choose%20Environment.png)

- Modifiez-la pour qu’elle ressemble à ceci :

  ```bash
  docker run -d \
    --name cloudflared \
    --restart unless-stopped \
    --network <domaine_utilise_pour_projet_sans_point>_cloudflared \
    cloudflare/cloudflared:latest \
    tunnel --no-autoupdate run --token <votre_token_cloudflare>
  ```

  Pour le domaine, il ressemblera à : nomclientpicinformatiquecom

  Une fois la connexion faite et validée, appuyez sur Suivant :

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Tunnel%20Next.png)

- Assignez le nom de domaine et les services à contacter

  Pour le nom de domaine, il s’agit du domaine donné auparavant

  ![alt text](https://github.com/chelsinforce/Picbox/blob/a7dd8bcebef051b40e90cc7189c59291015a23b0/DOC/Images/Cloudflare%200%20Trust%20Domaine.png)

  Concernant les services, dans le cadre de la PICBOX, il faut renseigner HTTPS et teleport:3080

  **ATTENTION : Si vous avez un certificat autosigné installé, il faut activer le NO TLS VERIFY**

  ![alt text](https://github.com/chelsinforce/Picbox/blob/346554bfa151f81a38d22e6df5294691a31e5112/DOC/Images/Cloudflare%200%20Trust%20NO%20TLS%20VERIFY.png)

  Puis cliquez sur Terminer.

#### 4. **Ajout du CNAME manquant**

  Lors de la création du tunnel, vous allez avoir une alerte vous disant qu’un enregistrement ne sera pas fait. Vous devez le faire vous-même.

  - Cliquez sur le logo de Cloudflare

  - Sélectionnez le bon compte

  - Accédez à DNS

  ![alt text](https://github.com/chelsinforce/Picbox/blob/461b512a6c627a88e3fb59658bc1dcaeb1995c8e/DOC/Images/Cloudflare%20DNS%201.png)

  - Cliquez sur Ajouter un nouvel enregistrement

  ![alt text](https://github.com/chelsinforce/Picbox/blob/461b512a6c627a88e3fb59658bc1dcaeb1995c8e/DOC/Images/Cloudflare%20DNS%202.png)

  - Cliquez sur TYPE et choisissez CNAME

  ![alt text](https://github.com/chelsinforce/Picbox/blob/461b512a6c627a88e3fb59658bc1dcaeb1995c8e/DOC/Images/Cloudflare%20DNS%204.png)

  - Dans Nom, tapez *.nomclient (modifiez nomclient bien entendu)

  ![alt text](https://github.com/chelsinforce/Picbox/blob/461b512a6c627a88e3fb59658bc1dcaeb1995c8e/DOC/Images/Cloudflare%20DNS%205.png)

  - Dans Cible (Target), entrez l’ID du tunnel (vous le trouverez dans l’enregistrement CNAME de nomclient)

  ![alt text](https://github.com/chelsinforce/Picbox/blob/461b512a6c627a88e3fb59658bc1dcaeb1995c8e/DOC/Images/Cloudflare%20DNS%206.png)

  - Entrez une description et sauvegardez

  ![alt text](https://github.com/chelsinforce/Picbox/blob/461b512a6c627a88e3fb59658bc1dcaeb1995c8e/DOC/Images/Cloudflare%20DNS%207.png)

#### 5. **Accès à Teleport**

  - Accédez à votre domaine

    Vous arriverez alors sur cette page après avoir accepté les conditions d’utilisation :

    ![alt text](https://github.com/chelsinforce/Picbox/blob/458083d7dbf9d8e6237fc876ba62520aea62ebeb/DOC/Images/Teleport%20SETUP%201%20.png)

  - Retournez dans le terminal de la PICBOX et tapez (copier-coller) cette commande :

    ```bash
    docker exec -it teleport tctl users add admin --roles=editor,access
    ```
  Une URL vous sera donnée (Ctrl + clic gauche pour ouvrir dans le navigateur)

  Créez votre compte pour arriver sur le portail :

  ![alt text](https://github.com/chelsinforce/Picbox/blob/458083d7dbf9d8e6237fc876ba62520aea62ebeb/DOC/Images/Teleport%20SETUP%202.png)

 #### 5.1. **Ajout de serveur SSH**

 Afin d’enrôler un nouveau serveur, **ne cliquez pas sur « enrôler un serveur »**

**Sur la PICBOX**
  
  * Soyez root 
  - Obtenez le token d’authentification : 

    ```
    docker exec -it teleport tctl tokens add --type=node --ttl=1h
    ```

  Vous obtenez alors un token. Seul ce token compte.

**Sur le serveur à enrôler**

  - Installez teleport : 

    ```
    curl -fsSL https://goteleport.com/static/install.sh | bash -s 16.2.0
    ```

  - Initialisez la connexion :

    ```
    teleport start --roles=node --token=(token) --auth-server=(ipserver):3025 --nodename=(nom explicatif)
    ```

  - Modifiez la règle Access

    Pour ce faire, allez sur Zero Trust Access -> Roles

    ![alt text](https://github.com/chelsinforce/Picbox/blob/458083d7dbf9d8e6237fc876ba62520aea62ebeb/DOC/Images/Teleport%20SETUP%203.png)

    Une fois dans la fenêtre, cliquez sur Options puis sur Éditer le rôle access

    ![alt text](https://github.com/chelsinforce/Picbox/blob/458083d7dbf9d8e6237fc876ba62520aea62ebeb/DOC/Images/Teleport%20SETUP%204.png)

    Allez sur Resources et ajoutez l’utilisateur pic (**Cet utilisateur doit déjà être présent sur le serveur de destination**)

    ![alt text](https://github.com/chelsinforce/Picbox/blob/458083d7dbf9d8e6237fc876ba62520aea62ebeb/DOC/Images/Teleport%20SETUP%205.png)

    Sauvegardez et testez la connexion.

    ##### Si vous devez créer l’utilisateur

    Tapez ces commandes en étant root sur le serveur de destination :

    ```bash
    sudo adduser pic
    sudo usermod -aG sudo pic # Si sudo n’est pas installé sur la machine, il ne faut pas taper cette commande et retirez sudo des commandes

    # Si les commandes ci-dessus ne fonctionnent pas :

    sudo useradd -m -s /bin/bash nom_utilisateur
    sudo passwd nom_utilisateur
    ```

#### 6. Etablisement du ZERO TRUST Cloudflare 

Afin de sécuriser l'accès et l'autoriser qu'as PIC, un ZERO TRUST Cloudflare est nécéssaire. 

  - Allez dans la partie ZERO TRUST de cloudflare et allez dans Access

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%201.png)

- Cliquez en suite sur Application

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%202.png)

- Créer une nouvelle app

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%203.png)

- Sélectionner self hosted

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%204.png)

- Nommer votre app

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%205.png)

- Mettez le domaine (nomclient.picinformatique.com)

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%206.png)

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%207.png)

- Mettez la politique d'accès Mail et confirmer

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%208.png)

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%209.png)

- Tester la politique

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%2010.png)

- Cliquez sur Next, Next et Save

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%2011.png)

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%2012.png)

  ![alt text](https://github.com/chelsinforce/Picbox/blob/17653bd255846fe7f8e2aea70f178036202a459e/DOC/Images/Cloudflare%200%20Trust%20App%2013.png)

Déploiement de la PICBOX Terminé. Les outils a l'intérieurs de la PICBOX sont a conigurée a votre guise

Note : En ce qui concerne Portaner, vous allez devoir redémarer le conteneur ( Limite de temps dépasé)

```
docker compose restart portainer
```
