# Architecture du Système • MERCHANT PAY

Ce document décrit l'architecture technique, les flux de données et les choix de conception du projet **MERCHANT PAY**, développé dans le cadre du hackathon FINOVIA × ENSM × SATIM.

---

## 1. Vue d'Ensemble & Composants

MERCHANT PAY est une couche d'intelligence commerçante construite sur les flux d'encaissement des cartes interbancaires algériennes (**CIB**) et de la carte monétique d'Algérie Poste (**EDAHABIA**). 

Le système est découplé en deux tiers principaux :
1. **Frontend Universel (Flutter Mobile + Web Responsive) :** Une base de code Dart unique offrant deux espaces distincts et étanches (Espace Commerçant & Espace Administrateur SATIM).
2. **Backend d'Intelligence (Django 5 REST Framework + Pandas + NumPy) :** Une API REST haute performance avec architecture "Thin Views, Fat Services", isolant 100% de la logique métier dans des modules de services purs.

```mermaid
graph TD
    subgraph Clients["Frontend Flutter (Multi-Plateforme)"]
        MC["Espace Commerçant<br/>(Mobile & Web)"]
        SA["Espace Administrateur SATIM<br/>(Desktop Web & Tablet)"]
    end

    subgraph API_GW["API Django REST Framework (Port 8000)"]
        Auth["Authentification JWT<br/>(SimpleJWT + Role Guard)"]
        CORS["CORS & Whitenoise"]
        Docs["OpenAPI / Swagger (/api/docs/)"]
    end

    subgraph Core_Services["Services Métier Purs (Fat Services)"]
        AnalyticsSvc["analytics.services<br/>(KPIs, Trends, Heatmap 7x24, Comparaisons)"]
        AlertsEngine["alerts.rules & services<br/>(Moteur de Règles & Déduplication)"]
        RiskEngine["risk.rules & services<br/>(Détection Heuristique 0-100 & Explicabilité)"]
        SimSvc["simulator.services<br/>(Modélisation Volume & Panier)"]
        ReportsSvc["reports.services<br/>(Génération PDF ReportLab & CSV)"]
    end

    subgraph Data_Layer["Persistance & Stockage"]
        PG[("PostgreSQL 16 / SQLite<br/>(Transactions, Commerçants, Audit)")]
        SeedCSV["data/transactions_seed.csv<br/>(Générateur Synthétique Calibré)"]
    end

    MC -->|HTTPS / JSON / JWT| Auth
    SA -->|HTTPS / JSON / JWT| Auth
    Auth --> Core_Services
    Core_Services --> PG
    Core_Services --> ReportsSvc
    ReportsSvc --> PG
```

---

## 2. Diagramme de Séquence • Consultation du Tableau de Bord Commerçant

Lorsqu'un commerçant se connecte et consulte ses encaissements :

```mermaid
sequenceDiagram
    autonumber
    actor Commerçant
    participant App as Flutter App (Riverpod)
    participant API as Django REST View
    participant Svc as analytics.services
    participant DB as Base de Données

    Commerçant->>App: Sélectionne la période (ex: 30 jours)
    App->>API: GET /api/v1/merchant/dashboard/?preset=30d
    Note over API: Validation JWT & extraction de merchant_id
    API->>DB: Queryset Transactions (période courante & période précédente)
    DB-->>API: Enregistrements bruts
    API->>Svc: compute_kpis() + compute_trends() + compute_heatmap()
    Note over Svc: Calculs vectoriels Pandas/NumPy sans requêtes SQL additionnelles
    Svc-->>API: KPIs consolidés, deltas %, matrice 7x24, distribution canaux
    API-->>App: Réponse JSON 200 OK
    App->>Commerçant: Affichage réactif (Cartes KPIs, Graphes fl_chart, Matrice)
```

---

## 3. Diagramme de Séquence • Moteur de Détection du Risque SATIM

Détection heuristique et explicable de comportements suspects ou atypiques :

```mermaid
sequenceDiagram
    autonumber
    actor Analyste as Analyste SATIM
    participant Cron as Scanner Automatique / Tâche
    participant Engine as risk.rules & services
    participant DB as Base de Données
    participant UI as Flutter Espace Risque

    Cron->>Engine: evaluate_all_merchants(window_minutes=60)
    Engine->>DB: Extraction des transactions récentes + historique
    loop Pour chaque commerçant
        Engine->>Engine: Évaluation des 5 règles de risque
        Note over Engine: R_VELOCITY (+35)<br/>R_AMOUNT_HIGH (+30)<br/>R_REJECTION_SPIKE (+25)<br/>R_FREQUENCY_ABNORMAL (+15)<br/>R_HISTORY_DEVIATION (+15)
        alt Score >= 40 (Modéré ou Élevé)
            Engine->>DB: Création ou mise à jour du RiskFlag (déduplication active)
        end
    end
    Analyste->>UI: Ouvre l'espace "Risque & Fraude"
    UI->>DB: GET /api/v1/admin/risk/ (Trié par score décroissant)
    DB-->>UI: Dossiers avec règles déclenchées et métriques
    UI->>Analyste: Jauge de risque, tags explicatifs, avertissement déontologique
    Analyste->>UI: Ajoute une note et passe le statut à "UNDER_REVIEW"
    UI->>DB: POST /api/v1/admin/risk/{id}/status/
    DB->>DB: Enregistrement AuditLog (SUPER_ADMIN / Analyste)
```

---

## 4. Choix d'Architecture Frontend

1. **Clean Feature-First Architecture :**
   - Chaque fonctionnalité (`merchant_dashboard`, `transactions`, `analytics`, `alerts`, `simulator`, `admin/*`) regroupe ses vues, composants et états.
2. **Gestion d'État & DI avec Riverpod :**
   - `apiClientProvider` : Singleton Dio avec intercepteur JWT automatique et réessai transparent sur 401 via refresh token.
   - `authStateProvider` : Gestion du profil utilisateur, de son rôle et persistance sécurisée.
3. **Routage Déclaratif & Isolation des Rôles (GoRouter) :**
   - Redirection automatique selon le rôle (`/m/*` strict pour les commerçants, `/a/*` pour l'administration SATIM).
   - Protection 404 unifiée en français.
4. **Design System SATIM :**
   - Palette institutionnelle : Rouge SATIM `#E53A2F`, Bleu CIB `#1D70B8`, Doré EDAHABIA `#D97706`.
   - Responsive Shell : Barre latérale permanente sur Desktop Web, NavigationRail sur tablette, BottomNavigationBar sur mobile.
   - Formatage 100% français (`fr_FR`) : montants monétaires en `DZD`, dates au format `23/11/2026`, séparateurs d'espaces pour les milliers.
