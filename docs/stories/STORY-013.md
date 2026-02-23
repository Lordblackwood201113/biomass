# STORY-013: Déployer l'API BIOMASS sur Coolify via VPS Hostinger

**Epic:** EPIC-004 (Déploiement)
**Priority:** Must Have
**Story Points:** 5
**Status:** Not Started
**Assigned To:** Unassigned
**Created:** 2026-02-23
**Sprint:** Post-Sprint (Déploiement)

---

## User Story

As a developer
I want to deploy the BIOMASS API on Coolify via my Hostinger VPS
So that the API is accessible en ligne par les applications clientes

---

## Description

### Background

L'API BIOMASS est complète et conteneurisée (Dockerfile fonctionnel). Il faut maintenant la déployer en production sur un VPS Hostinger en utilisant Coolify comme plateforme de déploiement.

Coolify est un PaaS self-hosted (alternative à Heroku/Railway) qui gère nativement les déploiements Docker. Il supporte :
- Build depuis un Dockerfile
- Build depuis un dépôt Git (GitHub, GitLab, etc.)
- Reverse proxy automatique (Traefik)
- SSL/HTTPS automatique (Let's Encrypt)
- Monitoring basique

### Scope

**In scope :**
- Installation de Coolify sur le VPS Hostinger
- Configuration du projet dans Coolify (Dockerfile-based)
- Déploiement de l'API BIOMASS
- Configuration du domaine/sous-domaine (optionnel)
- HTTPS automatique via Let's Encrypt

**Out of scope :**
- CI/CD automatique depuis Git (phase future)
- Monitoring avancé (Prometheus, Grafana)
- Scaling multi-instances
- Backup automatisé

---

## Prérequis VPS Hostinger

### Configuration minimale recommandée

| Ressource | Minimum | Recommandé |
|-----------|---------|------------|
| RAM | 2 GB | 4 GB |
| CPU | 2 vCPU | 4 vCPU |
| Stockage | 40 GB | 60 GB |
| OS | Ubuntu 22.04/24.04 | Ubuntu 24.04 LTS |

**Important :** L'image Docker `rocker/geospatial` fait ~2-3 GB. Prévoir suffisamment d'espace disque (40 GB minimum). La RAM de 4 GB est recommandée car le build de l'image Docker + le runtime R consomment ~1.5-2 GB.

---

## Guide de déploiement pas-à-pas

### Étape 1 : Préparer le VPS Hostinger

1. **Se connecter au VPS en SSH :**
   ```bash
   ssh root@<IP_DU_VPS>
   ```

2. **Mettre à jour le système :**
   ```bash
   apt update && apt upgrade -y
   ```

3. **S'assurer que curl est installé :**
   ```bash
   apt install -y curl
   ```

### Étape 2 : Installer Coolify

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

L'installation prend 2-5 minutes. Elle installe :
- Docker Engine
- Docker Compose
- Coolify (conteneurs)
- Traefik (reverse proxy)

Une fois terminé, Coolify est accessible sur `http://<IP_DU_VPS>:8000`.

**Premier accès :**
1. Ouvrir `http://<IP_DU_VPS>:8000` dans le navigateur
2. Créer le compte administrateur
3. Configurer le serveur (Coolify détecte automatiquement le serveur local)

### Étape 3 : Pousser le code sur un dépôt Git

Coolify déploie depuis un dépôt Git. Créer un dépôt GitHub (ou GitLab) :

```bash
cd /chemin/vers/BIOMASS
git init
git add api.R run_api.R Dockerfile .dockerignore
git commit -m "Initial commit: BIOMASS API with Dockerfile"
git remote add origin https://github.com/<USERNAME>/biomass-api.git
git push -u origin main
```

**Alternative sans Git :** Coolify supporte aussi le déploiement par upload direct de Dockerfile, mais Git est recommandé.

### Étape 4 : Créer le projet dans Coolify

1. **Dans l'interface Coolify :**
   - Cliquer **"+ Add New Resource"**
   - Sélectionner **"Application"**
   - Choisir le **Server** (localhost)

2. **Configurer la source :**
   - Source : **"GitHub"** (ou GitLab)
   - Connecter son compte GitHub (OAuth)
   - Sélectionner le repository **biomass-api**
   - Branche : **main**

3. **Configurer le build :**
   - Build Pack : **"Dockerfile"** (Coolify détecte automatiquement le Dockerfile)
   - Laisser les autres paramètres par défaut

4. **Configurer le réseau :**
   - Port exposé : **8000**
   - Domaine : `biomass-api.<votre-domaine>.com` (ou utiliser le domaine généré par Coolify)

5. **Variables d'environnement (optionnel) :**
   - `API_PORT=8000` (par défaut)

6. **Cliquer "Deploy"**

### Étape 5 : Vérifier le déploiement

Le build prend **5-15 minutes** (téléchargement de rocker/geospatial + installation des packages R).

```bash
# Tester l'API
curl -X POST https://biomass-api.<votre-domaine>.com/compute-biomass \
  -H "Content-Type: application/json" \
  -d '{
    "trees": [{
      "longitude": -52.68,
      "latitude": 4.08,
      "diameter": 46.2,
      "height": 25.5,
      "speciesName": "Symphonia globulifera"
    }]
  }'
```

---

## Configuration Coolify recommandée

### Ressources du conteneur

Dans Coolify > Application > Resources :

```
Memory Limit: 2048 MB (2 GB)
CPU Limit: 2
```

### Health Check (optionnel)

Si vous ajoutez un endpoint `/health` dans le futur :
```
Health Check Path: /health
Health Check Port: 8000
Health Check Interval: 30s
```

### Restart Policy

```
Restart Policy: unless-stopped
```

---

## Optimisation du Dockerfile pour Coolify

Le Dockerfile actuel est compatible. Une optimisation possible pour accélérer les re-builds :

```dockerfile
FROM rocker/geospatial:latest

# Install R packages (cached layer - ne change pas souvent)
RUN R -e "install.packages(c('plumber', 'jsonlite', 'BIOMASS'), repos='https://cran.r-project.org/')"

# Copy API files (change souvent → en dernier pour le cache Docker)
WORKDIR /app
COPY api.R .
COPY run_api.R .

EXPOSE 8000
CMD ["Rscript", "run_api.R"]
```

Le Dockerfile actuel suit déjà cette structure optimale.

---

## Troubleshooting

### Problème : Build timeout sur Coolify

L'image rocker/geospatial est volumineuse (~2-3 GB). Le premier build peut prendre 10-15 min.

**Solution :** Dans Coolify > Application > Advanced, augmenter le timeout de build à 30 minutes.

### Problème : Out of Memory pendant le build

Le build Docker + installation des packages R consomme beaucoup de RAM.

**Solution :**
- Vérifier que le VPS a au moins 4 GB de RAM
- Ou ajouter du swap :
  ```bash
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  ```

### Problème : Port 8000 en conflit avec Coolify

Coolify utilise par défaut le port 8000 pour son interface.

**Solution :** L'API n'a pas besoin d'exposer le port directement. Coolify utilise Traefik comme reverse proxy et route le trafic via le domaine configuré. Le port 8000 est interne au conteneur.

### Problème : computeE() échoue (téléchargement rasters)

Au premier appel, BIOMASS télécharge des rasters bioclimatiques.

**Solution :** S'assurer que le conteneur a accès à Internet. Dans Coolify, c'est le cas par défaut.

---

## Acceptance Criteria

- [ ] Coolify est installé et accessible sur le VPS Hostinger
- [ ] Le code est poussé sur un dépôt Git (GitHub/GitLab)
- [ ] L'application est configurée dans Coolify (Dockerfile build)
- [ ] Le build Docker se termine sans erreur
- [ ] L'API est accessible via HTTPS sur le domaine configuré
- [ ] Le endpoint POST /compute-biomass retourne des résultats corrects
- [ ] L'API survit à un redémarrage du conteneur (restart policy)

---

## Definition of Done

- [ ] API déployée et accessible en HTTPS
- [ ] Test curl réussi depuis une machine externe
- [ ] Logs visibles dans Coolify
- [ ] Restart policy configurée

---

## Coût estimé

| Ressource | Coût (Hostinger) |
|-----------|------------------|
| VPS KVM 2 (4 GB RAM, 2 vCPU, 50 GB) | ~$8-12/mois |
| Domaine (optionnel) | ~$10/an |
| SSL (Let's Encrypt via Coolify) | Gratuit |
| Coolify | Gratuit (self-hosted) |

---

## Progress Tracking

**Status History:**
- 2026-02-23: Story créée

**Actual Effort:** TBD

---

**This story was created using BMAD Method v6 - Phase 4 (Implementation Planning)**
