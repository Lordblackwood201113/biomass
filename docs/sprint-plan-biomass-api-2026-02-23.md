# Sprint Plan: BIOMASS API

**Date:** 2026-02-23
**Scrum Master:** User
**Project Level:** 2
**Total Stories:** 12
**Total Points:** 33
**Planned Sprints:** 2
**Sprint Length:** 1 semaine

---

## Executive Summary

Plan d'implémentation de l'API BIOMASS en 2 sprints d'une semaine. Le Sprint 1 couvre le squelette API et le workflow scientifique complet (parsing → WD → E → AGB). Le Sprint 2 couvre l'assemblage de la réponse, la robustesse (erreurs, logging), la conteneurisation Docker et la validation d'intégration.

**Key Metrics:**
- Total Stories: 12
- Total Points: 33
- Sprints: 2 (1 semaine chacun)
- Team Capacity: 30 points/sprint (1 dev senior)
- Target Completion: ~2 semaines

---

## Story Inventory

### STORY-001: Setup projet et squelette plumber

**Epic:** EPIC-001 (API Core)
**Priority:** Must Have
**Points:** 2

**User Story:**
As a developer
I want a working plumber server skeleton with run_api.R
So that I have the foundation to build the API endpoints

**Acceptance Criteria:**
- [ ] Fichier `run_api.R` créé, lance plumber sur 0.0.0.0:8000
- [ ] Fichier `api.R` créé avec un endpoint POST `/compute-biomass` (stub)
- [ ] Le serveur démarre avec `Rscript run_api.R` sans erreur
- [ ] Le port est configurable via variable d'environnement `API_PORT`

**Technical Notes:**
- Utiliser `plumber::pr()` pour charger api.R
- Configurer host="0.0.0.0" pour accessibilité Docker

**Dependencies:** Aucune (première story)

**FRs:** FR-001, FR-009

---

### STORY-002: Parsing du payload JSON et validation des entrées

**Epic:** EPIC-001 (API Core)
**Priority:** Must Have
**Points:** 3

**User Story:**
As a client developer
I want the API to parse my JSON tree inventory and validate inputs
So that I get clear error messages if my data is malformed

**Acceptance Criteria:**
- [ ] Le payload JSON est parsé en data.frame R
- [ ] Les champs obligatoires sont vérifiés (longitude, latitude, diameter, speciesName)
- [ ] Les types numériques sont validés (longitude, latitude, diameter, height)
- [ ] Les plages sont validées (longitude [-180,+180], latitude [-90,+90], diameter > 0)
- [ ] Un payload invalide retourne HTTP 400 avec message d'erreur JSON
- [ ] Un payload vide (`trees: []`) retourne HTTP 400

**Technical Notes:**
- Utiliser `jsonlite::fromJSON()` pour le parsing
- Créer une fonction `validate_input()` dédiée

**Dependencies:** STORY-001

**FRs:** FR-002, FR-008 (partiel)

---

### STORY-003: Séparation speciesName en genus/species

**Epic:** EPIC-002 (Workflow BIOMASS)
**Priority:** Must Have
**Points:** 2

**User Story:**
As a forest engineer
I want the API to automatically split species names into genus and species
So that I can send full scientific names without manual preprocessing

**Acceptance Criteria:**
- [ ] "Symphonia globulifera" → genus="Symphonia", species="globulifera"
- [ ] "Symphonia" (un seul mot) → genus="Symphonia", species=NA
- [ ] "" ou NA → genus=NA, species=NA
- [ ] Espaces multiples et trailing spaces gérés correctement

**Technical Notes:**
- Utiliser `strsplit()` ou `tidyr::separate()` sur le premier espace
- Créer une fonction `parse_species(speciesName_vector)`

**Dependencies:** STORY-002

**FRs:** FR-003

---

### STORY-004: Estimation de la densité du bois (Wood Density)

**Epic:** EPIC-002 (Workflow BIOMASS)
**Priority:** Must Have
**Points:** 3

**User Story:**
As a forest engineer
I want the API to estimate wood density from species names
So that I don't have to look up WD values manually

**Acceptance Criteria:**
- [ ] `BIOMASS::getWoodDensity(genus, species)` appelée correctement
- [ ] Les espèces trouvées retournent une WD numérique > 0
- [ ] Les espèces non trouvées utilisent le fallback (moyenne genre/famille)
- [ ] Les cas sans correspondance (ni espèce ni genre) retournent WD=NA avec warning
- [ ] Les warnings de BIOMASS sont capturés et stockés par arbre

**Technical Notes:**
- `getWoodDensity()` retourne un data.frame avec les colonnes meanWD et sdWD
- Capturer les messages du package avec `withCallingHandlers()`

**Dependencies:** STORY-003

**FRs:** FR-004

---

### STORY-005: Extraction du paramètre environnemental E

**Epic:** EPIC-002 (Workflow BIOMASS)
**Priority:** Must Have
**Points:** 3

**User Story:**
As a forest engineer
I want the API to use GPS coordinates to extract the E parameter
So that the allometric model is calibrated for my study site

**Acceptance Criteria:**
- [ ] `BIOMASS::computeE()` appelée avec les coordonnées (longitude, latitude)
- [ ] Les valeurs E retournées sont numériques
- [ ] Les coordonnées hors couverture retournent E=NA avec warning
- [ ] Les coordonnées identiques ne déclenchent qu'un seul calcul (optimisation)

**Technical Notes:**
- `computeE()` prend un data.frame avec colonnes `longitude` et `latitude`
- Peut nécessiter un téléchargement réseau au premier appel (rasters bioclimatiques)
- Dédupliquer les coordonnées uniques pour optimiser (FR-012 intégré ici)

**Dependencies:** STORY-002

**FRs:** FR-005, FR-012

---

### STORY-006: Calcul de la biomasse aérienne (AGB)

**Epic:** EPIC-002 (Workflow BIOMASS)
**Priority:** Must Have
**Points:** 3

**User Story:**
As a forest engineer
I want the API to compute above-ground biomass for each tree
So that I get scientifically accurate AGB estimates

**Acceptance Criteria:**
- [ ] `BIOMASS::computeAGB(D, WD, H)` appelée quand height est disponible
- [ ] Quand height=NA, utiliser le modèle basé sur coord via `computeAGB(D, WD, coord=coords)`
- [ ] Les AGB sont en kg, valeurs numériques >= 0
- [ ] Les arbres avec diameter=NA ou WD=NA retournent AGB=NA avec warning
- [ ] Les résultats sont cohérents avec un calcul R local direct

**Technical Notes:**
- `computeAGB()` accepte D (diameter), WD (wood density), H (height) ou coord (coordinates)
- Si H est fourni, il est utilisé en priorité. Sinon, coord + E sont utilisés.
- Vérifier la doc BIOMASS pour la signature exacte

**Dependencies:** STORY-004, STORY-005

**FRs:** FR-006

---

### STORY-007: Assemblage de la réponse JSON structurée

**Epic:** EPIC-001 (API Core)
**Priority:** Must Have
**Points:** 3

**User Story:**
As a client developer
I want a well-structured JSON response with results, summary and warnings
So that I can easily parse and display biomass results in my application

**Acceptance Criteria:**
- [ ] Le champ `results` contient un tableau d'objets (un par arbre)
- [ ] Chaque objet contient : longitude, latitude, diameter, height, speciesName, genus, species, wood_density, E, AGB_kg, warnings
- [ ] Le champ `summary` contient : total_AGB_kg, n_trees, n_warnings, n_failed
- [ ] Content-Type: application/json avec JSON valide UTF-8
- [ ] `auto_unbox=TRUE` pour un JSON propre (pas de tableaux pour les scalaires)

**Technical Notes:**
- Utiliser `jsonlite::toJSON(result, auto_unbox=TRUE, pretty=TRUE)`
- Créer une fonction `assemble_response(results_df)` qui structure la sortie

**Dependencies:** STORY-006

**FRs:** FR-007

---

### STORY-008: Gestion globale des erreurs (tryCatch)

**Epic:** EPIC-001 (API Core)
**Priority:** Must Have
**Points:** 3

**User Story:**
As a client developer
I want the API to never crash and always return a valid JSON response
So that my application can handle errors gracefully

**Acceptance Criteria:**
- [ ] Un tryCatch global entoure tout le traitement dans le handler plumber
- [ ] Chaque étape BIOMASS (WD, E, AGB) a son propre tryCatch
- [ ] Les erreurs R internes retournent HTTP 500 avec message JSON structuré
- [ ] Les warnings R sont capturés via `withCallingHandlers()` et ajoutés aux résultats
- [ ] L'API reste fonctionnelle après une erreur (pas besoin de redémarrer)

**Technical Notes:**
- Pattern: `tryCatch({ ... }, error = function(e) { return error response })`
- Capturer les warnings avec `withCallingHandlers(warning = function(w) { ... })`

**Dependencies:** STORY-007

**FRs:** FR-008

---

### STORY-009: Logging des requêtes

**Epic:** EPIC-001 (API Core)
**Priority:** Should Have
**Points:** 2

**User Story:**
As a DevOps engineer
I want the API to log each request with timestamp and processing time
So that I can monitor API usage and debug issues

**Acceptance Criteria:**
- [ ] Chaque requête POST génère un log avec timestamp ISO 8601
- [ ] Le nombre d'arbres dans l'inventaire est loggé
- [ ] Le temps de traitement (en secondes) est loggé
- [ ] Les erreurs sont loggées avec le détail de l'erreur
- [ ] Les logs sont visibles via `docker logs`

**Technical Notes:**
- Utiliser `message()` pour le logging (stdout de plumber)
- Mesurer le temps avec `system.time()` ou `proc.time()`

**Dependencies:** STORY-001

**FRs:** FR-011

---

### STORY-010: Dockerfile de production

**Epic:** EPIC-003 (Docker)
**Priority:** Must Have
**Points:** 5

**User Story:**
As a DevOps engineer
I want a production-ready Dockerfile
So that I can build and deploy the API with docker build + docker run

**Acceptance Criteria:**
- [ ] `docker build -t biomass-api .` construit l'image sans erreur
- [ ] `docker run -p 8000:8000 biomass-api` démarre l'API
- [ ] L'API est accessible depuis l'hôte via curl
- [ ] Image basée sur `rocker/geospatial` (dépendances géo incluses)
- [ ] Les packages R (plumber, BIOMASS, jsonlite) sont installés
- [ ] Les fichiers api.R et run_api.R sont copiés dans l'image
- [ ] Le port 8000 est exposé
- [ ] Un `.dockerignore` exclut les fichiers non nécessaires (docs/, .git/)

**Technical Notes:**
- Base: `rocker/geospatial:latest` (ou version figée)
- Installer les packages R avec `install.packages()` dans le Dockerfile
- CMD: `["Rscript", "run_api.R"]`
- WORKDIR: `/app`

**Dependencies:** STORY-001, STORY-007, STORY-008

**FRs:** FR-010

---

### STORY-011: Tests d'intégration manuels

**Epic:** Transversal
**Priority:** Must Have
**Points:** 3

**User Story:**
As a developer
I want to validate the API end-to-end with real test data
So that I confirm the API produces correct results

**Acceptance Criteria:**
- [ ] Un jeu de données test avec 5-10 arbres (espèces connues, coordonnées tropicales)
- [ ] Les résultats API sont comparés aux résultats R locaux (BIOMASS direct)
- [ ] Les cas limites sont testés : espèce inconnue, height=NA, champs manquants
- [ ] Un payload invalide retourne HTTP 400
- [ ] L'API ne crashe sur aucun cas test

**Technical Notes:**
- Préparer un script `test_api.sh` avec des appels curl
- Ou un script R `test_api.R` avec httr/httr2

**Dependencies:** STORY-010

**FRs:** Validation transversale de toutes les FRs

---

### STORY-012: Validation scientifique des résultats

**Epic:** EPIC-002 (Workflow BIOMASS)
**Priority:** Must Have
**Points:** 2

**User Story:**
As a forest engineer
I want to verify that the API results match direct R BIOMASS calculations
So that I can trust the API for scientific work

**Acceptance Criteria:**
- [ ] Un script R local exécute le workflow BIOMASS sur le jeu de données test
- [ ] Les résultats (WD, E, AGB) sont identiques entre l'API et le script local
- [ ] Les warnings sont cohérents
- [ ] Au moins 3 espèces tropicales courantes sont testées

**Technical Notes:**
- Créer un script `validate_results.R` qui compare les sorties
- Utiliser `all.equal()` pour la comparaison numérique (tolérance flottante)

**Dependencies:** STORY-011

**FRs:** Validation NFR-005 (Précision scientifique)

---

## Sprint Allocation

### Sprint 1 (Semaine 1) — 19/30 points

**Goal:** Implémenter le squelette API et le workflow scientifique BIOMASS complet de bout en bout

**Stories:**

| # | Story | Points | Priority | Epic |
|---|-------|--------|----------|------|
| 1 | STORY-001: Setup projet + plumber skeleton | 2 | Must | API Core |
| 2 | STORY-002: Parsing JSON + validation | 3 | Must | API Core |
| 3 | STORY-003: Séparation genus/species | 2 | Must | Workflow BIOMASS |
| 4 | STORY-004: Wood density (getWoodDensity) | 3 | Must | Workflow BIOMASS |
| 5 | STORY-005: Paramètre E (computeE) + dédup | 3 | Must | Workflow BIOMASS |
| 6 | STORY-006: Calcul AGB (computeAGB) | 3 | Must | Workflow BIOMASS |
| 7 | STORY-007: Réponse JSON structurée | 3 | Must | API Core |

**Total:** 19 points / 30 capacity (63% — buffer de 37% pour les imprévus et le cold start BIOMASS)

**Sprint 1 Deliverable:** L'API fonctionne localement (`Rscript run_api.R`), accepte un inventaire JSON et retourne les résultats de biomasse complets.

**Risks:**
- `computeE()` peut nécessiter un téléchargement réseau au premier appel
- Première utilisation du package BIOMASS : courbe d'apprentissage possible

---

### Sprint 2 (Semaine 2) — 15/30 points

**Goal:** Robustifier l'API (erreurs, logging), conteneuriser avec Docker, et valider l'intégration

**Stories:**

| # | Story | Points | Priority | Epic |
|---|-------|--------|----------|------|
| 1 | STORY-008: Gestion globale erreurs (tryCatch) | 3 | Must | API Core |
| 2 | STORY-009: Logging des requêtes | 2 | Should | API Core |
| 3 | STORY-010: Dockerfile production | 5 | Must | Docker |
| 4 | STORY-011: Tests d'intégration manuels | 3 | Must | Transversal |
| 5 | STORY-012: Validation scientifique | 2 | Must | Workflow BIOMASS |

**Total:** 15 points / 30 capacity (50% — buffer confortable pour debug Docker)

**Sprint 2 Deliverable:** L'API est robuste, conteneurisée, testée et validée scientifiquement. Prête pour utilisation.

**Risks:**
- Les dépendances système de BIOMASS dans Docker (GDAL/PROJ) peuvent poser problème
- La taille de l'image Docker rocker/geospatial (~2-3 GB) peut ralentir le build

---

## Epic Traceability

| Epic ID | Epic Name | Stories | Total Points | Sprint |
|---------|-----------|---------|--------------|--------|
| EPIC-001 | API Core | STORY-001, 002, 007, 008, 009 | 13 | Sprint 1-2 |
| EPIC-002 | Workflow BIOMASS | STORY-003, 004, 005, 006, 012 | 13 | Sprint 1-2 |
| EPIC-003 | Docker | STORY-010 | 5 | Sprint 2 |
| Transversal | Validation | STORY-011 | 3 | Sprint 2 |

---

## Functional Requirements Coverage

| FR ID | FR Name | Story | Sprint |
|-------|---------|-------|--------|
| FR-001 | Endpoint POST /compute-biomass | STORY-001 | 1 |
| FR-002 | Parsing payload JSON | STORY-002 | 1 |
| FR-003 | Séparation genus/species | STORY-003 | 1 |
| FR-004 | Estimation wood density | STORY-004 | 1 |
| FR-005 | Extraction paramètre E | STORY-005 | 1 |
| FR-006 | Calcul AGB | STORY-006 | 1 |
| FR-007 | Réponse JSON structurée | STORY-007 | 1 |
| FR-008 | Gestion erreurs/NA | STORY-002, STORY-008 | 1-2 |
| FR-009 | Script run_api.R | STORY-001 | 1 |
| FR-010 | Dockerfile production | STORY-010 | 2 |
| FR-011 | Logging requêtes | STORY-009 | 2 |
| FR-012 | Optimisation coordonnées parcelle | STORY-005 | 1 |

**Couverture : 12/12 FRs (100%)**

---

## Risks and Mitigation

**High:**
- **Dépendances BIOMASS dans Docker** : GDAL, PROJ, GEOS sont complexes à installer.
  - Mitigation : Utiliser `rocker/geospatial` qui les inclut.

**Medium:**
- **Téléchargement rasters computeE()** : Premier appel peut être lent ou échouer sans réseau.
  - Mitigation : Pré-télécharger les données dans le Dockerfile si possible, sinon documenter.
- **Espèces non reconnues** : `getWoodDensity()` peut ne pas trouver certaines espèces.
  - Mitigation : Fallback sur moyenne genre/famille (comportement natif BIOMASS).

**Low:**
- **Performance pour grands inventaires** : > 5000 arbres pourrait dépasser les 5s.
  - Mitigation : Documenter la limite, optimiser la dédup des coordonnées.

---

## Dependencies

- Package BIOMASS sur CRAN (stable, dernière version)
- Package plumber sur CRAN
- Image Docker rocker/geospatial disponible sur Docker Hub
- Accès réseau pour le téléchargement des rasters bioclimatiques (premier appel computeE)

---

## Definition of Done

For a story to be considered complete:
- [ ] Code implémenté et fonctionnel
- [ ] L'endpoint retourne les résultats attendus pour les cas normaux
- [ ] Les cas limites sont gérés (NA, erreurs)
- [ ] Le code est commenté aux points clés
- [ ] Test manuel validé avec curl ou script R

---

## Next Steps

**Immediate:** Begin Sprint 1

Run `/bmad:dev-story STORY-001` pour commencer l'implémentation de la première story.

**Ordre d'implémentation recommandé :**
1. STORY-001 → Setup projet
2. STORY-002 → Parsing JSON
3. STORY-003 → Parse species
4. STORY-004 → Wood density
5. STORY-005 → Paramètre E
6. STORY-006 → Compute AGB
7. STORY-007 → Réponse JSON

**Sprint cadence :**
- Sprint length: 1 semaine
- Sprint 1: Semaine 1
- Sprint 2: Semaine 2

---

**This plan was created using BMAD Method v6 - Phase 4 (Implementation Planning)**

*To continue: Run `/bmad:dev-story STORY-001` to start implementing.*
