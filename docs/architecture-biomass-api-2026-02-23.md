# System Architecture: BIOMASS API

**Date:** 2026-02-23
**Architect:** User
**Version:** 1.0
**Project Type:** API REST / Backend analytique
**Project Level:** 2 (Projet moyen)
**Status:** Draft

---

## Document Overview

This document defines the system architecture for BIOMASS API. It provides the technical blueprint for implementation, addressing all functional and non-functional requirements from the PRD.

**Related Documents:**
- Product Requirements Document: `docs/prd-biomass-api-2026-02-23.md`
- Product Brief: `docs/product-brief-biomass-api-2026-02-23.md`

---

## Executive Summary

Architecture d'une API REST stateless en R (plumber) conteneurisée dans Docker, exposant un unique endpoint POST `/compute-biomass`. L'API encapsule le workflow complet du package BIOMASS (parsing espèces → wood density → paramètre E → AGB). Aucune base de données, aucun frontend, aucune authentification. Architecture volontairement simple et focalisée sur la fiabilité scientifique.

---

## Architectural Drivers

Les NFRs qui influencent le plus les décisions architecturales :

1. **NFR-005: Précision scientifique** → L'API doit produire des résultats identiques au package BIOMASS en R. Cela impose d'utiliser R comme runtime et le package BIOMASS directement, sans réimplémentation.
2. **NFR-003: Portabilité Docker** → L'image Docker doit être auto-suffisante avec toutes les dépendances géospatiales (GDAL, PROJ, GEOS). Cela impose le choix de l'image de base `rocker/geospatial`.
3. **NFR-001: Performance < 5s pour 1000 arbres** → Le workflow BIOMASS doit être optimisé (calcul unique de E par coordonnées uniques, vectorisation R native).
4. **NFR-002: Fiabilité** → L'API ne doit jamais crasher. Impose un try/catch global et une gestion exhaustive des NA.

---

## System Overview

### High-Level Architecture

L'architecture est un **monolithe simple** composé de 3 couches dans un seul conteneur Docker :

1. **Couche HTTP** : Serveur plumber qui reçoit les requêtes POST et retourne du JSON
2. **Couche Logique** : Fonctions R orchestrant le workflow BIOMASS (parsing, WD, E, AGB)
3. **Couche Scientifique** : Package BIOMASS (getWoodDensity, computeE, computeAGB)

### Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│                  Docker Container                    │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │           plumber HTTP Server                  │  │
│  │           (run_api.R, port 8000)               │  │
│  └──────────────────┬────────────────────────────┘  │
│                     │                               │
│  ┌──────────────────▼────────────────────────────┐  │
│  │              api.R                             │  │
│  │  POST /compute-biomass                        │  │
│  │                                               │  │
│  │  ┌─────────┐ ┌──────────┐ ┌───────────────┐  │  │
│  │  │ parse   │→│ compute  │→│  assemble     │  │  │
│  │  │ input   │ │ biomass  │ │  response     │  │  │
│  │  └─────────┘ └──────────┘ └───────────────┘  │  │
│  └──────────────────┬────────────────────────────┘  │
│                     │                               │
│  ┌──────────────────▼────────────────────────────┐  │
│  │         R Package: BIOMASS                     │  │
│  │  getWoodDensity() │ computeE() │ computeAGB() │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  R 4.x + plumber + BIOMASS + dépendances système   │
│  (GDAL, PROJ, GEOS via rocker/geospatial)           │
└─────────────────────────────────────────────────────┘
         ▲
         │ HTTP POST (JSON)
         │
┌────────┴────────┐
│  Client HTTP    │
│  (curl, Python, │
│   JS, etc.)     │
└─────────────────┘
```

### Architectural Pattern

**Pattern:** Monolithe simple (Single-container REST API)

**Rationale:** Pour un projet Level 2 avec un seul endpoint et aucune persistance, un monolithe simple est le choix optimal. Il n'y a aucun bénéfice à introduire des microservices, un API gateway ou une architecture event-driven. La simplicité maximise la fiabilité et la maintenabilité.

---

## Technology Stack

### Frontend

N/A — Ce projet est une API backend uniquement. Pas de frontend.

### Backend

**Choice:** R 4.x + plumber

**Rationale:** R est imposé par la dépendance au package BIOMASS. Plumber est le framework API REST standard pour R, activement maintenu et bien documenté. Aucune alternative viable en R (httpuv est trop bas niveau, OpenCPU est plus lourd).

**Trade-offs:**
- ✓ Gain : Accès natif au package BIOMASS, pas de réimplémentation
- ✗ Perte : R est single-threaded, performances limitées en concurrence. Acceptable pour le contexte recherche.

### Database

N/A — L'API est stateless. Aucune persistance. Les données de référence (wood density database) sont intégrées au package BIOMASS.

### Infrastructure

**Choice:** Docker (image basée sur `rocker/geospatial`)

**Rationale:** `rocker/geospatial` est l'image Docker officielle de la communauté R incluant R + RStudio + toutes les bibliothèques géospatiales système (GDAL, PROJ, GEOS, libudunits2). Elle résout la difficulté majeure d'installation des dépendances système de BIOMASS.

**Trade-offs:**
- ✓ Gain : Toutes les dépendances géospatiales pré-installées, image maintenue par la communauté
- ✗ Perte : Image de base volumineuse (~2-3 GB). Acceptable car le déploiement se fait une seule fois.

### Third-Party Services

Aucun service tiers. L'API est entièrement autonome.

### Development & Deployment

| Outil | Choix | Justification |
|-------|-------|---------------|
| Runtime | R 4.x | Requis par BIOMASS |
| Framework API | plumber | Standard R pour REST |
| Conteneur | Docker | Contrainte projet |
| Image de base | rocker/geospatial | Dépendances géospatiales incluses |
| Packages R | BIOMASS, plumber, jsonlite | Core du projet |

---

## System Components

### Component 1: Serveur HTTP plumber (run_api.R)

**Purpose:** Point d'entrée HTTP, gestion du cycle de vie du serveur.

**Responsibilities:**
- Charger la définition de l'API (api.R)
- Configurer le host (0.0.0.0) et le port (8000)
- Démarrer le serveur plumber

**Interfaces:**
- HTTP sur port 8000 (configurable via variable d'environnement `API_PORT`)

**Dependencies:**
- Package plumber
- Fichier api.R

**FRs Addressed:** FR-009

---

### Component 2: Route API (api.R - POST /compute-biomass)

**Purpose:** Traiter les requêtes de calcul de biomasse.

**Responsibilities:**
- Recevoir et parser le payload JSON
- Valider les données d'entrée
- Orchestrer le workflow BIOMASS
- Assembler et retourner la réponse JSON
- Capturer et logger les erreurs

**Interfaces:**
- Entrée : JSON payload via HTTP POST body
- Sortie : JSON response

**Dependencies:**
- Package BIOMASS (getWoodDensity, computeE, computeAGB)
- Package jsonlite (sérialisation JSON)

**FRs Addressed:** FR-001, FR-002, FR-007, FR-008, FR-011

---

### Component 3: Module de parsing des espèces

**Purpose:** Séparer `speciesName` en `genus` et `species`.

**Responsibilities:**
- Extraire le premier mot comme genus
- Extraire le deuxième mot comme species
- Gérer les cas limites (nom simple, vide, NA)

**Interfaces:**
- Entrée : vecteur character `speciesName`
- Sortie : deux vecteurs `genus` et `species`

**Dependencies:** Aucune (base R)

**FRs Addressed:** FR-003

---

### Component 4: Module de calcul BIOMASS

**Purpose:** Exécuter le pipeline scientifique BIOMASS.

**Responsibilities:**
- Appeler `getWoodDensity(genus, species)` → WD
- Appeler `computeE(longitude, latitude)` → E (optimisé par coordonnées uniques)
- Appeler `computeAGB(D, WD, H)` ou `computeAGB(D, WD, coord)` → AGB
- Collecter les warnings pour chaque arbre

**Interfaces:**
- Entrée : data frame avec genus, species, longitude, latitude, diameter, height
- Sortie : data frame enrichi avec WD, E, AGB, warnings

**Dependencies:**
- Package BIOMASS

**FRs Addressed:** FR-004, FR-005, FR-006, FR-012

---

### Component 5: Conteneur Docker (Dockerfile)

**Purpose:** Encapsuler l'ensemble du système dans une image Docker reproductible.

**Responsibilities:**
- Installer les packages R (plumber, BIOMASS et dépendances)
- Copier les fichiers sources (api.R, run_api.R)
- Exposer le port 8000
- Définir la commande de démarrage

**Interfaces:**
- Port 8000 exposé
- Variable d'environnement `API_PORT` (optionnel)

**Dependencies:**
- Image de base rocker/geospatial

**FRs Addressed:** FR-010

---

## Data Architecture

### Data Model

L'API est stateless. Pas de modèle de données persistant. Les données sont traitées en flux (request → compute → response).

**Entités en transit :**

```
TreeInput {
    longitude: float     // coordonnée GPS
    latitude: float      // coordonnée GPS
    diameter: float      // cm
    height: float|null   // mètres (optionnel)
    speciesName: string  // nom scientifique complet
}

TreeResult {
    longitude: float
    latitude: float
    diameter: float
    height: float|null
    speciesName: string
    genus: string
    species: string|null
    wood_density: float|null   // g/cm³
    E: float|null              // paramètre environnemental
    AGB_kg: float|null         // biomasse aérienne en kg
    warnings: string[]         // messages d'avertissement
}

ResponseSummary {
    total_AGB_kg: float
    n_trees: int
    n_warnings: int
    n_failed: int
}
```

### Database Design

N/A — Pas de base de données.

### Data Flow

```
Client POST JSON
  │
  ▼
[1] Parse JSON → data.frame R
  │   Validation des types et champs
  │
  ▼
[2] Split speciesName → genus + species
  │   "Symphonia globulifera" → ("Symphonia", "globulifera")
  │
  ▼
[3] getWoodDensity(genus, species) → WD vector
  │   Fallback: moyenne genre si espèce non trouvée
  │
  ▼
[4] computeE(longitude, latitude) → E vector
  │   Optimisé: une seule fois par coordonnées uniques
  │
  ▼
[5] computeAGB(D=diameter, WD=WD, H=height) → AGB vector
  │   Si height=NA: utilise coord=(longitude,latitude) au lieu de H
  │
  ▼
[6] Assemble response JSON
  │   results[] + summary + warnings
  │
  ▼
HTTP 200 + JSON Response
```

---

## API Design

### API Architecture

- **Style:** REST (unique endpoint)
- **Format:** JSON (entrée et sortie)
- **Versioning:** Pas de versioning (v1 implicite, projet simple)
- **Encoding:** UTF-8

### Endpoints

#### POST /compute-biomass

**Description:** Calcule la biomasse aérienne pour un inventaire d'arbres.

**Request:**

```json
{
  "trees": [
    {
      "longitude": -52.68,
      "latitude": 4.08,
      "diameter": 46.2,
      "height": 25.5,
      "speciesName": "Symphonia globulifera"
    },
    {
      "longitude": -52.68,
      "latitude": 4.08,
      "diameter": 31.0,
      "height": null,
      "speciesName": "Dicorynia guianensis"
    }
  ]
}
```

**Response (200 OK):**

```json
{
  "results": [
    {
      "longitude": -52.68,
      "latitude": 4.08,
      "diameter": 46.2,
      "height": 25.5,
      "speciesName": "Symphonia globulifera",
      "genus": "Symphonia",
      "species": "globulifera",
      "wood_density": 0.58,
      "E": -0.0468,
      "AGB_kg": 1543.21,
      "warnings": []
    },
    {
      "longitude": -52.68,
      "latitude": 4.08,
      "diameter": 31.0,
      "height": null,
      "speciesName": "Dicorynia guianensis",
      "genus": "Dicorynia",
      "species": "guianensis",
      "wood_density": 0.72,
      "E": -0.0468,
      "AGB_kg": 892.45,
      "warnings": ["height is NA, using E-based model (Chave 2014)"]
    }
  ],
  "summary": {
    "total_AGB_kg": 2435.66,
    "n_trees": 2,
    "n_warnings": 1,
    "n_failed": 0
  }
}
```

**Response (400 Bad Request):**

```json
{
  "error": true,
  "message": "Invalid payload: 'trees' must be a non-empty array",
  "details": null
}
```

### Authentication & Authorization

N/A — Hors scope (pas d'authentification). L'API est ouverte. La sécurisation sera gérée en amont par un reverse proxy si nécessaire en phase future.

---

## Non-Functional Requirements Coverage

### NFR-001: Performance - Temps de réponse

**Requirement:** < 5s pour 1000 arbres, < 1s pour 100 arbres

**Architecture Solution:**
- Vectorisation native R : toutes les fonctions BIOMASS acceptent des vecteurs, pas de boucle for arbre par arbre
- Optimisation de `computeE()` : dédupliquer les coordonnées uniques avant l'appel (FR-012), puis mapper les résultats
- Le package BIOMASS charge ses données de référence en mémoire au premier appel (cold start). Les appels suivants sont rapides.

**Validation:** Mesurer avec `curl` + `time` sur des inventaires de 100 et 1000 arbres.

---

### NFR-002: Fiabilité - Stabilité

**Requirement:** L'API ne crashe jamais, retourne toujours du JSON valide.

**Architecture Solution:**
- `tryCatch()` global englobant tout le traitement dans le handler plumber
- Chaque étape du workflow BIOMASS est encapsulée dans son propre `tryCatch()`
- Les erreurs sont converties en réponses HTTP structurées (400 ou 500 avec message JSON)
- Les warnings R sont capturés via `withCallingHandlers()` et ajoutés au champ `warnings` de chaque arbre

**Validation:** Envoyer des payloads invalides, vides, avec des types incorrects et vérifier la stabilité.

---

### NFR-003: Portabilité Docker

**Requirement:** Image Docker auto-suffisante, déployable sur toute machine Docker.

**Architecture Solution:**
- Image de base `rocker/geospatial` : inclut R + GDAL + PROJ + GEOS + libudunits2
- Installation des packages R avec versions figées dans le Dockerfile
- `EXPOSE 8000` et `CMD ["Rscript", "run_api.R"]`
- Aucune dépendance réseau au runtime (données de référence embarquées dans le package BIOMASS)

**Validation:** Build + run sur une machine vierge avec uniquement Docker installé.

---

### NFR-004: Compatibilité HTTP standard

**Requirement:** Consommable depuis n'importe quel client HTTP.

**Architecture Solution:**
- Plumber gère nativement les headers Content-Type application/json
- Sérialisation JSON via `jsonlite::toJSON()` avec `auto_unbox=TRUE` pour un JSON propre
- Codes HTTP standards : 200 (succès), 400 (erreur client), 500 (erreur serveur)

**Validation:** Tester avec curl, Python requests, et JavaScript fetch.

---

### NFR-005: Précision scientifique

**Requirement:** Résultats identiques au package BIOMASS en R.

**Architecture Solution:**
- Utilisation directe des fonctions du package BIOMASS sans wrapper ni modification
- Aucune transformation mathématique des résultats
- Les données de référence (Global Wood Density Database) sont celles embarquées dans le package
- Le modèle allométrique est celui de Chave et al. (2014), implémenté dans `computeAGB()`

**Validation:** Comparer les résultats API avec un script R exécuté localement sur le même jeu de données.

---

### NFR-006: Maintenabilité

**Requirement:** Code lisible et organisé.

**Architecture Solution:**
- `api.R` : définition des routes plumber avec annotations
- Fonctions helper séparées dans le même fichier (parse_species, compute_biomass_workflow)
- Commentaires aux points clés du workflow BIOMASS
- `run_api.R` : script de démarrage minimal (~10 lignes)

**Validation:** Revue de code par un développeur R.

---

### NFR-007: Validation des entrées

**Requirement:** Validation des types et plages des données reçues.

**Architecture Solution:**
- Validation en entrée du handler plumber avant tout calcul :
  - `trees` doit être un tableau non vide
  - `longitude` : numérique, [-180, +180]
  - `latitude` : numérique, [-90, +90]
  - `diameter` : numérique, > 0
  - `height` : numérique > 0 ou NULL/NA
  - `speciesName` : string non vide ou NULL/NA
- Les arbres invalides ne bloquent pas les arbres valides (traitement partiel)
- Les erreurs de validation sont retournées dans le champ `warnings` de chaque arbre

**Validation:** Envoyer des valeurs hors plage et vérifier les warnings retournés.

---

## Security Architecture

### Authentication

N/A — Hors scope. L'API est ouverte dans cette version.

### Authorization

N/A — Pas de rôles ni permissions.

### Data Encryption

- **En transit :** Non géré par l'API elle-même (HTTP). TLS/HTTPS sera géré par un reverse proxy (nginx, traefik) en production si nécessaire.
- **Au repos :** N/A (pas de persistance).

### Security Best Practices

- **Validation des entrées** : Tous les champs sont validés côté serveur (NFR-007)
- **Pas d'injection** : Les données utilisateur ne sont jamais utilisées dans des appels système ou des requêtes SQL
- **Limitation implicite** : R est single-threaded, ce qui limite naturellement la charge
- **Pas de secrets** : L'API n'a aucun secret, credential ou API key à protéger

---

## Scalability & Performance

### Scaling Strategy

**Approche : Scaling horizontal simple via Docker.**

- Chaque conteneur gère une requête à la fois (R single-threaded)
- Pour augmenter la capacité : lancer plusieurs conteneurs derrière un load balancer
- Pas de state partagé → scaling horizontal trivial

### Performance Optimization

- **Vectorisation R** : Les fonctions BIOMASS sont vectorisées nativement. Pas de boucle sur chaque arbre.
- **Déduplication des coordonnées** : `computeE()` n'est appelé qu'une fois par jeu de coordonnées uniques.
- **Sérialisation JSON optimisée** : `jsonlite` est le sérialiseur JSON le plus rapide en R.

### Caching Strategy

Pas de cache en v1. Le cold start du package BIOMASS (chargement de la wood density database en mémoire) se fait au premier appel. Les appels suivants réutilisent les données en mémoire du même processus R.

**Phase future :** Cache des résultats de `getWoodDensity()` par espèce si les performances le justifient.

### Load Balancing

N/A en v1 (conteneur unique). En phase future, un load balancer (nginx, traefik, ou cloud LB) peut distribuer les requêtes entre plusieurs conteneurs.

---

## Reliability & Availability

### High Availability Design

N/A en v1 — Conteneur unique, contexte recherche. L'API est redémarrable avec `docker restart`.

### Disaster Recovery

N/A — Pas de données persistantes. La reconstruction est un simple `docker build`.

### Backup Strategy

N/A — Pas de données à sauvegarder. Le code source est la seule chose à versionner (git).

### Monitoring & Alerting

**V1 (minimal) :**
- Logging console via `message()` dans R : timestamp, nombre d'arbres, temps de traitement
- Les logs sont visibles via `docker logs <container_id>`

**Phase future :** Endpoint GET `/health` retournant le statut du serveur.

---

## Integration Architecture

### External Integrations

Le package BIOMASS accède à des données de référence embarquées :
- **Global Wood Density Database** (Chave et al.) : incluse dans le package
- **Rasters bioclimatiques** pour `computeE()` : inclus dans le package ou téléchargés au premier appel

**Important :** `computeE()` peut nécessiter un accès réseau au premier appel pour télécharger les rasters. Le Dockerfile devra soit pré-télécharger ces données, soit s'assurer que le conteneur a un accès réseau au démarrage.

### Internal Integrations

Aucune — Système autonome.

### Message/Event Architecture

N/A — Requête/réponse HTTP synchrone uniquement.

---

## Development Architecture

### Code Organization

```
BIOMASS/
├── api.R               # Définition des routes plumber + logique métier
├── run_api.R           # Script de démarrage du serveur
├── Dockerfile          # Image Docker de production
├── .dockerignore       # Fichiers exclus du build Docker
└── docs/               # Documentation BMAD
    ├── product-brief-biomass-api-2026-02-23.md
    ├── prd-biomass-api-2026-02-23.md
    └── architecture-biomass-api-2026-02-23.md
```

### Module Structure

Le projet est volontairement plat (pas de sous-dossiers R/) car il n'y a que 2 fichiers R :

| Fichier | Responsabilité |
|---------|----------------|
| `api.R` | Décoration plumber, parsing, validation, workflow BIOMASS, assemblage réponse |
| `run_api.R` | Chargement de l'API, configuration host/port, démarrage serveur |

### Testing Strategy

Hors scope pour v1 (défini dans le PRD). En phase future :
- Tests manuels avec curl et des payloads de référence
- Comparaison des résultats API vs résultats R locaux
- Script R de test de non-régression

### CI/CD Pipeline

Hors scope pour v1. En phase future :
- `docker build` automatique sur push
- Tests de non-régression dans le pipeline

---

## Deployment Architecture

### Environments

| Environnement | Description |
|----------------|-------------|
| **Développement** | R local avec `Rscript run_api.R` |
| **Production** | Conteneur Docker : `docker run -p 8000:8000 biomass-api` |

### Deployment Strategy

```bash
# Build
docker build -t biomass-api .

# Run
docker run -d -p 8000:8000 --name biomass-api biomass-api

# Test
curl -X POST http://localhost:8000/compute-biomass \
  -H "Content-Type: application/json" \
  -d '{"trees": [{"longitude": -52.68, "latitude": 4.08, "diameter": 46.2, "height": 25.5, "speciesName": "Symphonia globulifera"}]}'
```

### Infrastructure as Code

Le Dockerfile EST l'infrastructure as code pour ce projet.

---

## Requirements Traceability

### Functional Requirements Coverage

| FR ID | FR Name | Component | Status |
|-------|---------|-----------|--------|
| FR-001 | Endpoint POST /compute-biomass | api.R (route plumber) | Covered |
| FR-002 | Parsing payload JSON | api.R (parse_input) | Covered |
| FR-003 | Séparation genus/species | api.R (parse_species) | Covered |
| FR-004 | Estimation wood density | api.R → BIOMASS::getWoodDensity() | Covered |
| FR-005 | Extraction paramètre E | api.R → BIOMASS::computeE() | Covered |
| FR-006 | Calcul AGB | api.R → BIOMASS::computeAGB() | Covered |
| FR-007 | Réponse JSON structurée | api.R (assemble_response) | Covered |
| FR-008 | Gestion erreurs/NA | api.R (tryCatch global + par étape) | Covered |
| FR-009 | Script run_api.R | run_api.R | Covered |
| FR-010 | Dockerfile production | Dockerfile | Covered |
| FR-011 | Logging requêtes | api.R (message() avec timestamp) | Covered |
| FR-012 | Optimisation coordonnées parcelle | api.R (dédup avant computeE) | Covered |

**Couverture : 12/12 FRs (100%)**

### Non-Functional Requirements Coverage

| NFR ID | NFR Name | Solution | Validation |
|--------|----------|----------|------------|
| NFR-001 | Performance < 5s/1000 arbres | Vectorisation R + dédup coordonnées | curl + time |
| NFR-002 | Fiabilité (no crash) | tryCatch global + par étape | Tests payloads invalides |
| NFR-003 | Portabilité Docker | rocker/geospatial + packages figés | Build + run machine vierge |
| NFR-004 | Compatibilité HTTP | plumber + jsonlite + codes HTTP standards | Multi-client tests |
| NFR-005 | Précision scientifique | Appel direct BIOMASS, 0 transformation | Comparaison R local |
| NFR-006 | Maintenabilité | Code commenté, fonctions nommées | Revue de code |
| NFR-007 | Validation entrées | Validation pré-calcul dans handler | Tests hors plage |

**Couverture : 7/7 NFRs (100%)**

---

## Trade-offs & Decision Log

### Decision 1 : Image Docker rocker/geospatial

**Trade-off :**
- ✓ Gain : Toutes les dépendances géospatiales pré-installées, pas de compilation longue
- ✗ Perte : Image volumineuse (~2-3 GB)
**Rationale :** Le gain de fiabilité et de simplicité justifie la taille de l'image. Les dépendances géospatiales sont notoirement difficiles à installer manuellement.

### Decision 2 : Fichier api.R unique (pas de package R)

**Trade-off :**
- ✓ Gain : Simplicité, démarrage rapide, pas de complexité de structure package
- ✗ Perte : Pas de documentation roxygen, pas de tests intégrés natifs
**Rationale :** Pour 2 fichiers R, créer un package formel serait de l'over-engineering.

### Decision 3 : R single-threaded sans async

**Trade-off :**
- ✓ Gain : Simplicité, pas de race conditions, comportement prévisible
- ✗ Perte : Une seule requête traitée à la fois par conteneur
**Rationale :** En contexte recherche, le volume de requêtes est faible. Le scaling horizontal (plusieurs conteneurs) est la solution si le besoin évolue.

### Decision 4 : Pas de cache

**Trade-off :**
- ✓ Gain : Pas de complexité de gestion du cache, résultats toujours frais
- ✗ Perte : `getWoodDensity()` recalculé à chaque requête
**Rationale :** Le cold start BIOMASS est le seul coût significatif, et il ne se produit qu'au premier appel du processus R.

---

## Open Issues & Risks

1. **Téléchargement des rasters E :** `computeE()` peut nécessiter un téléchargement réseau au premier appel. Solution : pré-charger les données dans le Dockerfile si possible, ou documenter la nécessité d'un accès réseau initial.
2. **Taille mémoire :** Pour de très grands inventaires (>10 000 arbres), la consommation mémoire pourrait être importante. À tester et documenter.
3. **Versions des packages :** Les versions de BIOMASS et plumber doivent être figées pour garantir la reproductibilité.

---

## Assumptions & Constraints

**Contraintes :**
- Déploiement Docker uniquement
- R comme runtime (imposé par BIOMASS)
- API stateless
- Single-threaded (limitation R)

**Hypothèses :**
- Volume de requêtes modéré (contexte recherche)
- Coordonnées GPS en zones tropicales
- Package BIOMASS disponible et stable sur CRAN
- Accès réseau au moins au premier démarrage (pour les rasters de computeE)

---

## Future Considerations

- Endpoint GET `/health` pour monitoring
- Authentification API key
- Documentation Swagger via plumber::pr_set_docs()
- Cache en mémoire pour getWoodDensity
- Multi-conteneur + load balancer pour la montée en charge
- Tests automatisés et CI/CD
- Pré-chargement des rasters bioclimatiques dans l'image Docker

---

## Approval & Sign-off

**Review Status:**
- [ ] Technical Lead
- [ ] Product Owner
- [ ] Security Architect (if applicable)
- [ ] DevOps Lead

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-23 | User | Initial architecture |

---

## Next Steps

### Phase 4: Sprint Planning & Implementation

Run `/sprint-planning` to:
- Break epics into detailed user stories
- Estimate story complexity
- Plan sprint iterations
- Begin implementation following this architectural blueprint

**Key Implementation Principles:**
1. Follow component boundaries defined in this document
2. Implement NFR solutions as specified (tryCatch, vectorisation, dédup)
3. Use technology stack as defined (rocker/geospatial, plumber, BIOMASS)
4. Follow API contract exactly (request/response JSON format above)
5. Adhere to security and performance guidelines

---

**This document was created using BMAD Method v6 - Phase 3 (Solutioning)**

*To continue: Run `/workflow-status` to see your progress and next recommended workflow.*

---

## Appendix A: Technology Evaluation Matrix

| Critère | plumber (R) | FastAPI (Python) | Express (Node) |
|---------|------------|-----------------|----------------|
| Accès direct BIOMASS | ✓ Natif | ✗ Réimplémentation | ✗ Réimplémentation |
| Précision scientifique | ✓ Identique | ✗ Risque d'écart | ✗ Risque d'écart |
| Performance | ○ Correcte | ✓ Supérieure | ✓ Supérieure |
| Concurrence | ✗ Single-thread | ✓ Async | ✓ Event loop |
| Écosystème Docker | ✓ rocker/* | ✓ python:slim | ✓ node:alpine |
| **Verdict** | **Choisi** | Rejeté | Rejeté |

**Conclusion :** Le choix de R+plumber est imposé par le driver architectural NFR-005 (précision scientifique). Aucune alternative ne permet d'utiliser le package BIOMASS nativement.

---

## Appendix B: Capacity Planning

| Scénario | Arbres/requête | Temps estimé | Mémoire estimée |
|----------|----------------|-------------|-----------------|
| Petit inventaire | 10-50 | < 0.5s | ~100 MB |
| Inventaire moyen | 100-500 | < 2s | ~200 MB |
| Grand inventaire | 1000 | < 5s | ~500 MB |
| Très grand | 5000+ | ~15-25s | ~1-2 GB |

**Recommandation :** Limiter à 10 000 arbres par requête. Au-delà, recommander le découpage en lots côté client.

---

## Appendix C: Cost Estimation

| Ressource | Coût estimé |
|-----------|-------------|
| Développement (api.R + run_api.R + Dockerfile) | 2-3 jours |
| Tests et validation | 1-2 jours |
| Image Docker (stockage) | ~3 GB |
| Runtime (conteneur) | ~512 MB - 2 GB RAM selon charge |
| Infrastructure serveur | Variable (VM cloud à partir de ~$5/mois) |
