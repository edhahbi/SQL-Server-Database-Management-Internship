## Objectifs

> [!info] la préparation de l'environnement de développement nécessaire aux futures tâches du projet. L'objectif principal était d'installer et de configurer Microsoft SQL Server sur un environnement Linux, de vérifier son bon fonctionnement et de se familiariser avec les outils qui seront utilisés durant le stage.

## Installation de l'environnement

Dans un premier temps, j'ai étudié les prérequis nécessaires à l'exécution de SQL Server sous Linux. Après analyse des différentes solutions disponibles, l'installation a été réalisée à l'aide de Docker afin de faciliter le déploiement et la gestion du serveur de base de données.

Les principales étapes réalisées ont été :

### 1. Installation et configuration de Docker

```bash
sudo dnf update
sudo dnf install docker.io
sudo systemctl enable --now docker

sudo usermod -aG docker $USER   # optionnel
```

> [!tip] Astuce L'ajout de l'utilisateur au groupe `docker` permet d'exécuter les commandes Docker sans `sudo`. Une déconnexion/reconnexion (ou `newgrp docker`) est nécessaire pour que le changement prenne effet.

### 2. Téléchargement de l'image SQL Server

```bash
docker pull mcr.microsoft.com/mssql/server:2022-latest
```

### 3. Création et démarrage d'un conteneur SQL Server

```bash
# Hachage du mot de passe SA (à des fins de sécurité)
echo PASSWORD_TO_HASH | sha256sum

docker run -e "ACCEPT_EULA=Y" \
           -e "MSSQL_SA_PASSWORD=HASHED_PASSWORD" \
           -p 1433:1433 \
           -d mcr.microsoft.com/mssql/server:2022-latest
```

> [!warning] Attention Faire un hachage (SHA-256) du mot de passe puis l'utiliser comme valeur de `MSSQL_SA_PASSWORD` n'est pas la bonne pratique : SQL Server attend le mot de passe **en clair** pour l'authentification SA, pas son empreinte. Un hachage ne pourra pas être validé comme mot de passe. Il faudra revoir cette étape.

> [!danger] Sécurité Le mot de passe ne doit jamais apparaître en clair dans l'historique bash, un script versionné ou une commande partagée. Privilégier une variable d'environnement chargée depuis un fichier `.env` (non commité) ou un gestionnaire de secrets.

### 4. Vérification du fonctionnement du service

```bash
docker ps
```

![[Pasted image 20260621185014.png]]

> [!success] Résultat Cette approche permet d'isoler l'environnement de base de données tout en simplifiant sa maintenance et sa portabilité.

## Connexion et validation

Une fois le serveur opérationnel, plusieurs tests ont été effectués afin de valider son bon fonctionnement :

- Vérification de l'état du conteneur
- Connexion au serveur SQL

![[Pasted image 20260621193004.png]]

- Création d'une base de données de test
- Exécution de requêtes SQL simples

> [!success] Bilan Ces tests ont permis de confirmer que l'environnement était correctement configuré et prêt à être utilisé pour les développements futurs.

> [!note] À faire pour la prochaine séance
> 
> - Corriger la méthode de définition du mot de passe SA (utiliser le mot de passe en clair, sécurisé autrement)
> - Documenter la procédure de connexion (client utilisé, port, identifiants)
> - Explorer les outils complémentaires (Azure Data Studio, sqlcmd, etc.)