# Product Requirements Document: BIOMASS API

**Date:** 2026-02-23
**Author:** User
**Version:** 1.0
**Project Type:** API REST / Backend analytique
**Project Level:** 2 (Projet moyen)
**Status:** Draft

---

## Document Overview

This Product Requirements Document (PRD) defines the functional and non-functional requirements for BIOMASS API. It serves as the source of truth for what will be built and provides traceability from requirements through implementation.

**Related Documents:**
- Product Brief: `docs/product-brief-biomass-api-2026-02-23.md`

---

## Executive Summary

Un backend analytique en R exposant une API REST (via le package plumber) pour calculer la biomasse forestière à partir d'inventaires d'arbres, en s'appuyant sur le package scientifique BIOMASS. Destinée aux ingénieurs forestiers dans un contexte de recherche, cette API découple le calcul scientifique en R de l'application cliente, rendant les estimations de biomasse accessibles depuis n'importe quelle technologie via de simples requêtes HTTP POST.

---

## Product Goals

### Business Objectives

- Fournir une API fonctionnelle et fiable pour le calcul de biomasse forestière
- Permettre l'intégration du calcul de biomasse dans des applications web et des pipelines de données
- Garantir la reproductibilité des calculs scientifiques via une API standardisée
- Conteneuriser l'API pour un déploiement facile et portable (Docker)

### Success Metrics

- L'API retourne des résultats corrects et cohérents avec le package BIOMASS utilisé directement en R
- Temps de réponse < 5s pour un inventaire de 1000 arbres
- Le Dockerfile construit et démarre l'API sans intervention manuelle (`docker build` + `docker run`)
- L'API gère gracieusement 100% des cas limites (espèces inconnues, données manquantes) sans crash

---

## Functional Requirements

Functional Requirements (FRs) define **what** the system does - specific features and behaviors.

Each requirement includes:
- **ID**: Unique identifier (FR-001, FR-002, etc.)
- **Priority**: Must Have / Should Have / Could Have / Won't Have (MoSCoW)
- **Description**: What the system should do
- **Acceptance Criteria**: How to verify it's complete

---

### FR-001: Endpoint POST /compute-biomass

**Priority:** Must Have

**Description:**
L'API expose un endpoint HTTP POST `/compute-biomass` qui accepte un payload JSON contenant un inventaire d'arbres et retourne les résultats de calcul de biomasse.

**Acceptance Criteria:**
- [ ] L'endpoint accepte les requêtes POST avec Content-Type application/json
- [ ] L'endpoint retourne un code HTTP 200 avec les résultats en JSON en cas de succès
- [ ] L'endpoint retourne un code HTTP 400 avec un message d'erreur si le payload est invalide
- [ ] L'endpoint est accessible sur le port configuré du serveur plumber

**Dependencies:** Aucune

---

### FR-002: Parsing du payload JSON d'inventaire

**Priority:** Must Have

**Description:**
L'API extrait et parse le payload JSON reçu contenant un tableau d'arbres. Chaque arbre possède les champs : `longitude` (float), `latitude` (float), `diameter` (float, cm), `height` (float, mètres), `speciesName` (string, nom scientifique complet).

**Acceptance Criteria:**
- [ ] Le JSON est correctement parsé en data frame R
- [ ] Chaque champ (longitude, latitude, diameter, height, speciesName) est extrait
- [ ] Les types numériques sont validés (longitude, latitude, diameter, height)
- [ ] Un inventaire vide retourne une erreur explicite

**Dependencies:** FR-001

---

### FR-003: Séparation genus/species depuis speciesName

**Priority:** Must Have

**Description:**
Le champ `speciesName` (ex: "Symphonia globulifera") est séparé en deux vecteurs distincts : `genus` (premier mot) et `species` (deuxième mot). Ces vecteurs alimentent la fonction `getWoodDensity()`.

**Acceptance Criteria:**
- [ ] "Symphonia globulifera" produit genus="Symphonia", species="globulifera"
- [ ] Les noms avec un seul mot produisent genus=mot, species=NA
- [ ] Les espaces multiples ou trailing spaces sont gérés correctement
- [ ] Les noms vides ou NULL produisent genus=NA, species=NA

**Dependencies:** FR-002

---

### FR-004: Estimation de la densité du bois (Wood Density)

**Priority:** Must Have

**Description:**
Utiliser la fonction `BIOMASS::getWoodDensity()` avec les vecteurs genus et species pour estimer la densité du bois (WD) de chaque arbre. En cas d'espèce non trouvée, le package utilise la moyenne du genre ou de la famille.

**Acceptance Criteria:**
- [ ] `getWoodDensity()` est appelée avec les vecteurs genus et species
- [ ] Les WD retournées sont des valeurs numériques > 0 pour les espèces trouvées
- [ ] Les espèces non trouvées reçoivent un fallback (moyenne genre/famille) sans erreur
- [ ] Les cas où ni l'espèce ni le genre ne sont trouvés retournent NA avec un warning

**Dependencies:** FR-003

---

### FR-005: Extraction du paramètre environnemental E

**Priority:** Must Have

**Description:**
Utiliser les coordonnées GPS (longitude, latitude) pour extraire le paramètre environnemental E via la fonction `BIOMASS::computeE()`. Ce paramètre E affine le modèle allométrique pantropical de Chave et al. (2014).

**Acceptance Criteria:**
- [ ] `computeE()` est appelée avec les vecteurs de coordonnées GPS
- [ ] Les valeurs de E retournées sont numériques
- [ ] Les coordonnées hors zone de couverture retournent NA avec un warning
- [ ] Les coordonnées identiques (même parcelle) produisent le même E

**Dependencies:** FR-002

---

### FR-006: Calcul de la biomasse aérienne (AGB)

**Priority:** Must Have

**Description:**
Utiliser la fonction `BIOMASS::computeAGB()` avec le diamètre (D), la hauteur (H) et la densité du bois (WD) pour calculer la biomasse aérienne (AGB) de chaque arbre en kg. Si la hauteur est fournie, utiliser le modèle avec hauteur ; sinon utiliser le paramètre E comme proxy.

**Acceptance Criteria:**
- [ ] `computeAGB()` est appelée avec D, WD et H (si disponible)
- [ ] Si H est NA pour certains arbres, le paramètre E est utilisé en remplacement via le modèle de Chave
- [ ] Les AGB retournées sont en kg, valeurs numériques >= 0
- [ ] Les arbres avec diameter=NA retournent AGB=NA avec un warning

**Dependencies:** FR-004, FR-005

---

### FR-007: Réponse JSON structurée

**Priority:** Must Have

**Description:**
L'API retourne un JSON structuré contenant pour chaque arbre : l'AGB calculé, la densité du bois estimée (WD), le paramètre E utilisé, et d'éventuels warnings. Un résumé global est également inclus.

**Acceptance Criteria:**
- [ ] La réponse contient un tableau `results` avec un objet par arbre
- [ ] Chaque objet contient au minimum : `AGB_kg`, `wood_density`, `E`, `genus`, `species`
- [ ] Un champ `warnings` (tableau de strings) liste les avertissements par arbre
- [ ] Un objet `summary` contient : `total_AGB_kg`, `n_trees`, `n_warnings`, `n_failed`
- [ ] La réponse est du JSON valide avec Content-Type application/json

**Dependencies:** FR-006

---

### FR-008: Gestion des erreurs et valeurs manquantes

**Priority:** Must Have

**Description:**
L'API gère proprement les cas d'erreur : espèce non trouvée dans la base, valeurs manquantes (NA) dans les champs, payload mal formé. L'API ne doit jamais crasher ; elle retourne toujours une réponse JSON exploitable.

**Acceptance Criteria:**
- [ ] Un payload JSON invalide retourne HTTP 400 avec message d'erreur descriptif
- [ ] Une espèce non trouvée ne bloque pas le calcul des autres arbres
- [ ] Les champs manquants (NA) sont signalés dans les warnings de chaque arbre
- [ ] L'API ne retourne jamais une erreur 500 non gérée (try/catch global)
- [ ] Les arbres avec des données insuffisantes ont AGB=NA et un warning explicatif

**Dependencies:** FR-001, FR-002

---

### FR-009: Script de lancement run_api.R

**Priority:** Must Have

**Description:**
Un script `run_api.R` configure et lance le serveur plumber. Il charge `api.R`, configure le host (0.0.0.0 pour Docker) et le port, puis démarre le serveur.

**Acceptance Criteria:**
- [ ] Le script lance le serveur plumber sur le port 8000 (ou configurable via variable d'environnement)
- [ ] Le serveur écoute sur 0.0.0.0 (accessible depuis l'extérieur du conteneur)
- [ ] Le serveur démarre sans erreur avec un message de confirmation dans la console
- [ ] Le script peut être exécuté avec `Rscript run_api.R`

**Dependencies:** FR-001

---

### FR-010: Dockerfile de production

**Priority:** Must Have

**Description:**
Un Dockerfile complet et fonctionnel pour conteneuriser l'API. Il installe R, les dépendances système (GDAL, PROJ, etc.), les packages R (plumber, BIOMASS) et expose le port de l'API.

**Acceptance Criteria:**
- [ ] `docker build -t biomass-api .` construit l'image sans erreur
- [ ] `docker run -p 8000:8000 biomass-api` démarre l'API
- [ ] L'API est accessible depuis l'hôte sur le port mappé
- [ ] L'image utilise une base adaptée (rocker/geospatial ou équivalent)
- [ ] Les packages R sont installés et fonctionnels dans le conteneur

**Dependencies:** FR-009

---

### FR-011: Logging des requêtes

**Priority:** Should Have

**Description:**
L'API log dans la console les requêtes reçues (timestamp, nombre d'arbres, temps de traitement) pour faciliter le debugging et le monitoring basique.

**Acceptance Criteria:**
- [ ] Chaque requête POST génère une ligne de log avec timestamp
- [ ] Le nombre d'arbres dans l'inventaire est loggé
- [ ] Le temps de traitement de la requête est loggé
- [ ] Les erreurs sont loggées avec le détail de l'erreur

**Dependencies:** FR-001

---

### FR-012: Support des coordonnées par parcelle

**Priority:** Should Have

**Description:**
Si tous les arbres partagent les mêmes coordonnées GPS (même parcelle), le paramètre E n'est calculé qu'une seule fois pour optimiser les performances.

**Acceptance Criteria:**
- [ ] Les coordonnées uniques sont identifiées et E est calculé une seule fois par jeu de coordonnées
- [ ] Le résultat est identique à un calcul individuel par arbre
- [ ] Le temps de traitement est réduit pour les inventaires mono-parcelle

**Dependencies:** FR-005

---

## Non-Functional Requirements

Non-Functional Requirements (NFRs) define **how** the system performs - quality attributes and constraints.

---

### NFR-001: Performance - Temps de réponse

**Priority:** Must Have

**Description:**
L'API doit traiter un inventaire de 1000 arbres en moins de 5 secondes (hors premier appel à froid).

**Acceptance Criteria:**
- [ ] Temps de réponse < 5s pour 1000 arbres (mesuré avec curl)
- [ ] Temps de réponse < 1s pour 100 arbres
- [ ] Le premier appel (cold start) peut être plus lent (chargement des données du package)

**Rationale:**
Un temps de réponse raisonnable est nécessaire pour l'intégration dans des workflows interactifs (applications web).

---

### NFR-002: Fiabilité - Stabilité de l'API

**Priority:** Must Have

**Description:**
L'API ne doit jamais crasher, quel que soit l'input reçu. Elle doit retourner une réponse JSON valide dans tous les cas.

**Acceptance Criteria:**
- [ ] Aucun crash serveur sur payload invalide, vide ou mal formé
- [ ] Les erreurs R internes sont capturées et retournées comme erreurs HTTP structurées
- [ ] L'API reste fonctionnelle après une erreur (pas besoin de redémarrer)

**Rationale:**
En contexte de recherche, la fiabilité est critique pour la confiance dans les résultats.

---

### NFR-003: Portabilité - Déploiement Docker

**Priority:** Must Have

**Description:**
L'API doit être entièrement conteneurisable et déployable via Docker sur n'importe quelle machine supportant Docker, sans dépendance externe.

**Acceptance Criteria:**
- [ ] L'image Docker est auto-suffisante (toutes les dépendances incluses)
- [ ] L'image fonctionne sur Linux x86_64 (architecture standard des serveurs)
- [ ] Aucune configuration manuelle nécessaire après `docker run`

**Rationale:**
Le déploiement Docker est une contrainte projet pour assurer la portabilité et la reproductibilité.

---

### NFR-004: Compatibilité - Interface HTTP standard

**Priority:** Must Have

**Description:**
L'API doit être consommable depuis n'importe quel client HTTP standard (curl, Python requests, JavaScript fetch, Postman, etc.).

**Acceptance Criteria:**
- [ ] L'API accepte et retourne du JSON standard (UTF-8)
- [ ] Les headers HTTP sont corrects (Content-Type: application/json)
- [ ] Les codes HTTP sont standards (200 succès, 400 erreur client, 500 erreur serveur)

**Rationale:**
L'API doit être intégrable dans n'importe quelle stack technique sans adaptateur spécifique.

---

### NFR-005: Précision scientifique

**Priority:** Must Have

**Description:**
Les résultats d'AGB calculés par l'API doivent être identiques à ceux obtenus en exécutant le même workflow directement dans R avec le package BIOMASS.

**Acceptance Criteria:**
- [ ] Les valeurs d'AGB correspondent exactement aux résultats du package BIOMASS en R
- [ ] Les densités de bois correspondent aux valeurs de `getWoodDensity()`
- [ ] Le paramètre E correspond aux valeurs de `computeE()`

**Rationale:**
C'est un outil de recherche scientifique ; la précision des résultats est non négociable.

---

### NFR-006: Maintenabilité - Code lisible

**Priority:** Should Have

**Description:**
Le code R doit être lisible, commenté aux points clés, et organisé en fonctions claires pour faciliter la maintenance.

**Acceptance Criteria:**
- [ ] Les fonctions principales sont nommées de manière descriptive
- [ ] Les étapes du workflow BIOMASS sont clairement séparées
- [ ] Les commentaires expliquent les choix non évidents

**Rationale:**
Le projet sera maintenu par des chercheurs/ingénieurs qui doivent comprendre la logique.

---

### NFR-007: Sécurité - Validation des entrées

**Priority:** Should Have

**Description:**
L'API valide les types et plages des données reçues pour éviter les injections ou traitements aberrants.

**Acceptance Criteria:**
- [ ] Les coordonnées sont validées (longitude: -180/+180, latitude: -90/+90)
- [ ] Le diamètre est validé (> 0)
- [ ] La hauteur est validée (> 0 ou NA)
- [ ] Le speciesName est une string non vide ou NA

**Rationale:**
Même en contexte recherche, la validation des entrées prévient les résultats aberrants.

---

## Epics

Epics are logical groupings of related functionality that will be broken down into user stories during sprint planning (Phase 4).

Each epic maps to multiple functional requirements and will generate 2-10 stories.

---

### EPIC-001: API Core

**Description:**
Mise en place du serveur plumber, de l'endpoint POST `/compute-biomass`, du parsing JSON et de la structure de réponse. C'est le squelette de l'application.

**Functional Requirements:**
- FR-001: Endpoint POST /compute-biomass
- FR-002: Parsing du payload JSON
- FR-007: Réponse JSON structurée
- FR-008: Gestion des erreurs et valeurs manquantes
- FR-009: Script de lancement run_api.R
- FR-011: Logging des requêtes

**Story Count Estimate:** 5-6

**Priority:** Must Have

**Business Value:**
Fondation technique sans laquelle aucune fonctionnalité scientifique ne peut être exposée.

---

### EPIC-002: Workflow BIOMASS

**Description:**
Implémentation du pipeline scientifique complet : parsing des espèces, estimation de la densité du bois, extraction du paramètre E, et calcul de l'AGB via le package BIOMASS.

**Functional Requirements:**
- FR-003: Séparation genus/species
- FR-004: Estimation de la densité du bois (WD)
- FR-005: Extraction du paramètre environnemental E
- FR-006: Calcul de la biomasse aérienne (AGB)
- FR-012: Support des coordonnées par parcelle

**Story Count Estimate:** 5-6

**Priority:** Must Have

**Business Value:**
C'est la valeur scientifique core du produit : le calcul de biomasse fiable et reproductible.

---

### EPIC-003: Conteneurisation Docker

**Description:**
Création du Dockerfile de production, configuration de l'image avec toutes les dépendances, et validation du build/run.

**Functional Requirements:**
- FR-010: Dockerfile de production

**Story Count Estimate:** 2-3

**Priority:** Must Have

**Business Value:**
Permet le déploiement portable et reproductible de l'API sur n'importe quelle infrastructure.

---

## User Stories (High-Level)

User stories follow the format: "As a [user type], I want [goal] so that [benefit]."

These are preliminary stories. Detailed stories will be created in Phase 4 (Implementation).

---

### EPIC-001: API Core

- **US-001:** As a client developer, I want to send a POST request with a JSON tree inventory to `/compute-biomass` so that I can compute biomass without knowing R.
- **US-002:** As a client developer, I want to receive a structured JSON response with AGB, wood density, and warnings so that I can display results in my application.
- **US-003:** As a client developer, I want clear error messages (HTTP 400) when my payload is invalid so that I can debug my integration quickly.

### EPIC-002: Workflow BIOMASS

- **US-004:** As a forest engineer, I want the API to automatically resolve wood density from species names so that I don't have to look up WD manually.
- **US-005:** As a forest engineer, I want the API to use GPS coordinates to improve allometric model accuracy so that my AGB estimates are scientifically sound.
- **US-006:** As a forest engineer, I want warnings when a species is not found (with fallback to genus average) so that I know which results may be less precise.

### EPIC-003: Conteneurisation Docker

- **US-007:** As a DevOps engineer, I want to build and run the API with `docker build` + `docker run` so that I can deploy it on any server without installing R.

---

## User Personas

### Persona 1: Dr. Aminata - Ingénieure forestière

- **Rôle:** Ingénieure forestière en ONG environnementale
- **Contexte:** Réalise des inventaires forestiers tropicaux, calcule l'AGB pour des rapports de recherche
- **Besoin:** Intégrer les calculs de biomasse dans un dashboard web partagé avec son équipe
- **Niveau technique:** Connaît R mais ne souhaite pas l'imposer à ses collègues développeurs web
- **Frustration actuelle:** Doit exporter les données, ouvrir R, exécuter le script, puis transmettre les résultats

### Persona 2: Marc - Développeur fullstack

- **Rôle:** Développeur d'une application web d'inventaire forestier
- **Contexte:** Construit un frontend en JavaScript/Python, a besoin des calculs BIOMASS
- **Besoin:** Une API HTTP simple qu'il peut appeler depuis son backend
- **Niveau technique:** Expert web, ne connaît pas R
- **Frustration actuelle:** Impossible d'intégrer le package BIOMASS sans installer R côté serveur

---

## User Flows

### Flow 1: Calcul de biomasse standard

```
Client HTTP → POST /compute-biomass (JSON inventaire)
  → API parse le JSON
  → Sépare speciesName en genus + species
  → getWoodDensity(genus, species) → WD
  → computeE(longitude, latitude) → E
  → computeAGB(D, WD, H ou E) → AGB
  → Assemble la réponse JSON
  ← Retourne 200 + JSON (results + summary + warnings)
```

### Flow 2: Gestion d'erreur (espèce inconnue)

```
Client HTTP → POST /compute-biomass (avec espèce inconnue)
  → API parse le JSON
  → getWoodDensity() → fallback sur moyenne du genre
  → computeAGB() → AGB (avec WD approximative)
  ← Retourne 200 + JSON (results avec warning "species not found, genus average used")
```

### Flow 3: Payload invalide

```
Client HTTP → POST /compute-biomass (JSON mal formé ou champs manquants)
  → API tente de parser
  → Détecte l'erreur de format
  ← Retourne 400 + JSON (error message descriptif)
```

---

## Dependencies

### Internal Dependencies

- Aucune dépendance interne (projet autonome)

### External Dependencies

- **Package R BIOMASS** (CRAN) : Moteur de calcul scientifique. Doit être disponible et compatible.
- **Package R plumber** (CRAN) : Framework API REST pour R.
- **Dépendances système** : GDAL, PROJ, GEOS (requis par les packages géospatiaux de BIOMASS).
- **Image Docker rocker/geospatial** : Image de base recommandée incluant R + dépendances géospatiales.
- **Base de données de densité du bois** : Intégrée au package BIOMASS (Chave et al., Global Wood Density Database).

---

## Assumptions

- Les utilisateurs enverront des données d'inventaire valides (longitude, latitude, diameter, height, speciesName)
- Le package BIOMASS est disponible sur CRAN et compatible avec la version de R utilisée dans l'image Docker
- Les espèces fournies correspondent aux noms scientifiques reconnus par la Global Wood Density Database
- Les coordonnées GPS sont dans des zones tropicales (domaine de validité du package BIOMASS et du modèle de Chave 2014)
- Le volume de requêtes sera modéré (contexte recherche, pas production à haute charge)
- L'API fonctionne en mode stateless (pas de persistance entre les requêtes)

---

## Out of Scope

- Interface utilisateur (frontend/dashboard)
- Authentification et autorisation sur l'API
- Base de données persistante
- Endpoints supplémentaires (GET pour récupérer des résultats passés, DELETE, etc.)
- Monitoring et logging avancé (ELK, Prometheus, etc.)
- Load balancing et haute disponibilité
- Tests automatisés (unitaires, intégration)
- Documentation OpenAPI/Swagger automatisée
- CORS configuration (sera géré par l'application cliente ou un reverse proxy)
- HTTPS/TLS (sera géré par un reverse proxy en production)

---

## Open Questions

1. **Taille maximale d'inventaire** : Faut-il limiter le nombre d'arbres par requête ? (ex: max 10 000 arbres)
2. **Version du package BIOMASS** : Figer une version spécifique ou utiliser la dernière disponible ?
3. **Format de sortie** : Le format JSON proposé convient-il ou faut-il un format alternatif (CSV, etc.) ?

---

## Approval & Sign-off

### Stakeholders

- **Ingénieurs forestiers (Utilisateurs finaux)** - Influence: High. Valident la pertinence scientifique.
- **Développeurs d'applications clientes (Intégrateurs)** - Influence: Medium. Valident l'ergonomie de l'API.
- **Porteur du projet** - Influence: High. Valide les priorités et livrables.

### Approval Status

- [ ] Product Owner
- [ ] Engineering Lead
- [ ] Design Lead
- [ ] QA Lead

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-23 | User | Initial PRD |

---

## Next Steps

### Phase 3: Architecture

Run `/architecture` to create system architecture based on these requirements.

The architecture will address:
- All functional requirements (FRs)
- All non-functional requirements (NFRs)
- Technical stack decisions
- Data models and APIs
- System components

### Phase 4: Sprint Planning

After architecture is complete, run `/sprint-planning` to:
- Break epics into detailed user stories
- Estimate story complexity
- Plan sprint iterations
- Begin implementation

---

**This document was created using BMAD Method v6 - Phase 2 (Planning)**

*To continue: Run `/workflow-status` to see your progress and next recommended workflow.*

---

## Appendix A: Requirements Traceability Matrix

| Epic ID | Epic Name | Functional Requirements | Story Count (Est.) |
|---------|-----------|-------------------------|-------------------|
| EPIC-001 | API Core | FR-001, FR-002, FR-007, FR-008, FR-009, FR-011 | 5-6 |
| EPIC-002 | Workflow BIOMASS | FR-003, FR-004, FR-005, FR-006, FR-012 | 5-6 |
| EPIC-003 | Conteneurisation Docker | FR-010 | 2-3 |

---

## Appendix B: Prioritization Details

### Summary

| Priority | FRs | NFRs | Total |
|----------|-----|------|-------|
| Must Have | 10 | 5 | 15 |
| Should Have | 2 | 2 | 4 |
| Could Have | 0 | 0 | 0 |
| **Total** | **12** | **7** | **19** |

### Must Have FRs
FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010

### Should Have FRs
FR-011 (Logging), FR-012 (Optimisation coordonnées par parcelle)

### Must Have NFRs
NFR-001 (Performance), NFR-002 (Fiabilité), NFR-003 (Portabilité Docker), NFR-004 (Compatibilité HTTP), NFR-005 (Précision scientifique)

### Should Have NFRs
NFR-006 (Maintenabilité), NFR-007 (Validation des entrées)
