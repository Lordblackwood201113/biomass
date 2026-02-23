# Product Brief: BIOMASS API

**Date:** 2026-02-23
**Author:** User
**Version:** 1.0
**Project Type:** API REST / Backend analytique
**Project Level:** 2 (Projet moyen)

---

## Executive Summary

Un backend analytique en R exposant une API REST (via le package plumber) pour calculer la biomasse forestière à partir d'inventaires d'arbres, en s'appuyant sur le package scientifique BIOMASS. Destinée aux ingénieurs forestiers dans un contexte de recherche, cette API découple le calcul scientifique en R de l'application cliente, rendant les estimations de biomasse accessibles depuis n'importe quelle technologie (applications web, mobile, scripts Python, etc.) via de simples requêtes HTTP POST.

---

## Problem Statement

### The Problem

Le package R BIOMASS est l'outil de référence pour estimer la biomasse aérienne (AGB) des arbres tropicaux, mais son utilisation est confinée à l'écosystème R. Les ingénieurs forestiers et chercheurs qui travaillent avec des applications web, des dashboards ou d'autres langages ne peuvent pas exploiter directement ces calculs. Ils doivent soit installer R localement, soit dupliquer la logique scientifique dans un autre langage, avec un risque d'erreurs et d'incohérences.

### Why Now?

Le besoin d'intégrer les calculs de biomasse dans des workflows multi-technologiques (applications web, pipelines de données) est croissant dans le domaine de la recherche forestière. Exposer le package BIOMASS via une API standardisée permet de répondre à ce besoin immédiatement.

### Impact if Unsolved

Sans cette API, chaque projet nécessitant des calculs de biomasse devra réimplémenter la logique du package BIOMASS ou imposer R comme dépendance, freinant l'adoption et augmentant le risque d'erreurs dans les estimations scientifiques.

---

## Target Audience

### Primary Users

- **Ingénieurs forestiers** : Professionnels réalisant des inventaires forestiers et ayant besoin de calculer la biomasse aérienne (AGB) à partir de données de terrain (diamètre, hauteur, espèce, coordonnées GPS).
- **Chercheurs en écologie forestière** : Scientifiques intégrant les calculs de biomasse dans des projets de recherche et des publications.

### Secondary Users

- **Développeurs d'applications web/mobile** : Intégrateurs techniques qui consommeront l'API depuis des applications clientes (frontends, dashboards, pipelines de données).
- **Data scientists** : Utilisateurs travaillant en Python ou d'autres langages souhaitant accéder aux calculs BIOMASS sans installer R.

### User Needs

- Calculer la biomasse aérienne (AGB) à partir de données d'inventaire forestier de manière fiable et reproductible
- Obtenir automatiquement la densité du bois (wood density) à partir du nom scientifique de l'espèce
- Intégrer facilement les calculs de biomasse dans des workflows existants (web apps, scripts, pipelines) sans dépendance à R

---

## Solution Overview

### Proposed Solution

Une API REST construite en R avec le package plumber, conteneurisée via Docker, exposant un endpoint POST `/compute-biomass`. L'API reçoit un inventaire d'arbres en JSON (longitude, latitude, diameter, height, speciesName) et retourne les résultats de biomasse calculés via le workflow complet du package BIOMASS.

### Key Features

- **Endpoint POST `/compute-biomass`** : Reçoit un JSON d'inventaire d'arbres et retourne les résultats
- **Parsing automatique des espèces** : Séparation du nom scientifique (speciesName) en genre (genus) et espèce (species)
- **Estimation de la densité du bois** : Utilisation de `getWoodDensity()` pour obtenir la wood density (WD) par espèce
- **Extraction du paramètre environnemental E** : Utilisation des coordonnées GPS (longitude/latitude) pour affiner le modèle allométrique
- **Calcul de la biomasse aérienne (AGB)** : Utilisation de `computeAGB()` avec diamètre, hauteur et densité du bois
- **Gestion robuste des erreurs** : Traitement des espèces non trouvées, valeurs manquantes (NA), avec messages d'avertissement dans la réponse
- **Réponse JSON structurée** : AGB calculé, densité du bois estimée, warnings éventuels
- **Conteneurisation Docker** : Dockerfile prêt pour la production

### Value Proposition

Permettre à n'importe quelle application, quel que soit son langage ou sa stack technique, d'accéder aux calculs scientifiques de biomasse forestière du package BIOMASS via une simple requête HTTP, sans installer R ni connaître sa syntaxe.

---

## Business Objectives

### Goals

- Fournir une API fonctionnelle et fiable pour le calcul de biomasse forestière
- Permettre l'intégration du calcul de biomasse dans des applications web et des pipelines de données
- Garantir la reproductibilité des calculs scientifiques via une API standardisée
- Conteneuriser l'API pour un déploiement facile et portable (Docker)

### Success Metrics

- L'API retourne des résultats corrects et cohérents avec le package BIOMASS utilisé directement en R
- Temps de réponse acceptable pour des inventaires de taille raisonnable (< 5s pour 1000 arbres)
- Le Dockerfile construit et démarre l'API sans intervention manuelle
- L'API gère gracieusement les cas limites (espèces inconnues, données manquantes)

### Business Value

Accélérer les projets de recherche forestière en éliminant la barrière technique de R pour les calculs de biomasse. Réduire les erreurs liées à la réimplémentation manuelle de la logique scientifique dans d'autres langages.

---

## Scope

### In Scope

- Script `api.R` avec plumber : route POST `/compute-biomass`
- Script `run_api.R` pour lancer le serveur
- Workflow complet BIOMASS : parsing espèces, `getWoodDensity()`, paramètre E, `computeAGB()`
- Gestion des erreurs et valeurs manquantes (NA)
- Réponse JSON structurée (AGB, wood density, warnings)
- Dockerfile complet pour conteneurisation et déploiement
- Installation de toutes les dépendances R nécessaires (plumber, BIOMASS, dépendances système)

### Out of Scope

- Interface utilisateur (frontend/dashboard)
- Authentification et autorisation sur l'API
- Base de données persistante
- Endpoints supplémentaires (GET, DELETE, etc.)
- Monitoring et logging avancé
- Load balancing et haute disponibilité
- Tests automatisés (unitaires, intégration)
- Documentation OpenAPI/Swagger automatisée

### Future Considerations

- Ajout de l'authentification (API key, JWT)
- Endpoint GET `/health` pour le monitoring
- Documentation Swagger/OpenAPI automatique
- Support du traitement par lots (batch processing) pour de très grands inventaires
- Cache des résultats de `getWoodDensity()` pour optimiser les performances
- Tests automatisés et CI/CD pipeline
- Endpoints additionnels (estimation d'incertitude, résultats agrégés par parcelle)

---

## Key Stakeholders

- **Ingénieurs forestiers (Utilisateurs finaux)** - Influence: High. Utilisateurs principaux qui valideront la pertinence scientifique des résultats.
- **Développeurs d'applications clientes (Intégrateurs)** - Influence: Medium. Consommeront l'API et valideront l'ergonomie du contrat d'interface.
- **Porteur du projet (Vous)** - Influence: High. Définit les priorités, valide les livrables et pilote le projet.

---

## Constraints and Assumptions

### Constraints

- Déploiement via Docker uniquement
- Le package BIOMASS et ses dépendances système (libgdal, libproj, etc.) doivent être installables dans un conteneur Docker
- L'API doit fonctionner en mode stateless (pas de persistance entre les requêtes)

### Assumptions

- Les utilisateurs enverront des données d'inventaire valides (longitude, latitude, diameter, height, speciesName)
- Le package BIOMASS est disponible sur CRAN et compatible avec la version de R utilisée
- Les espèces fournies correspondent aux noms scientifiques reconnus par la base de données du package BIOMASS
- Les coordonnées GPS sont dans des zones tropicales (domaine de validité du package BIOMASS)
- Le volume de requêtes sera modéré (contexte recherche, pas production à haute charge)

---

## Success Criteria

- L'API démarre correctement dans un conteneur Docker avec `docker build` + `docker run`
- L'endpoint POST `/compute-biomass` accepte un JSON d'inventaire et retourne les résultats correctement
- Les valeurs d'AGB retournées sont cohérentes avec celles obtenues directement via le package BIOMASS en R
- Les espèces non trouvées ou données manquantes génèrent des warnings clairs sans faire crasher l'API
- L'API est utilisable depuis n'importe quel client HTTP (curl, Python requests, JavaScript fetch, etc.)

---

## Timeline and Milestones

### Target Launch

Livraison en quelques semaines (projet de niveau 2).

### Key Milestones

- **M1** : Script `api.R` fonctionnel avec le workflow BIOMASS complet
- **M2** : Script `run_api.R` et tests manuels de l'API
- **M3** : Dockerfile fonctionnel, build et run validés
- **M4** : Tests d'intégration avec un client HTTP externe
- **M5** : Documentation d'utilisation de l'API

---

## Risks and Mitigation

- **Risk:** Le package BIOMASS a des dépendances système lourdes (GDAL, PROJ, etc.) difficiles à installer dans Docker
  - **Likelihood:** Medium
  - **Mitigation:** Utiliser l'image de base `rocker/geospatial` qui inclut déjà ces dépendances

- **Risk:** Certaines espèces d'arbres ne sont pas reconnues par `getWoodDensity()`
  - **Likelihood:** High
  - **Mitigation:** Utiliser les valeurs moyennes par genre ou par famille, et retourner un warning explicite dans la réponse JSON

- **Risk:** Temps de réponse élevé pour de grands inventaires
  - **Likelihood:** Medium
  - **Mitigation:** Documenter les limites de taille, envisager du batch processing en phase future

- **Risk:** Incompatibilité de version entre R, plumber et BIOMASS
  - **Likelihood:** Low
  - **Mitigation:** Figer les versions dans le Dockerfile

---

## Next Steps

1. Create Product Requirements Document (PRD) - `/prd`
2. Conduct user research (optional) - `/research`
3. Create UX design (if UI-heavy) - `/create-ux-design`

---

**This document was created using BMAD Method v6 - Phase 1 (Analysis)**

*To continue: Run `/workflow-status` to see your progress and next recommended workflow.*
