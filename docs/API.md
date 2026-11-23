# Référentiel des Endpoints API • MERCHANT PAY

Toutes les routes sont préfixées par `/api/v1/`. Les dates sont au format ISO-8601 et les montants en Dinars Algériens (DZD).

---

## 1. Authentification (`/auth/`)

| Méthode | Route | Permission | Description | Corps / Paramètres |
|---|---|---|---|---|
| `POST` | `/auth/login/` | Public | Authentification par email & mot de passe | `{"email": "...", "password": "..."}` |
| `POST` | `/auth/register/` | Public | Inscription autonome d'un nouveau commerçant | `{"email": "...", "password": "...", "business_name": "...", "legal_id": "...", "wilaya": "...", "mcc": "..."}` |
| `POST` | `/auth/refresh/` | Public | Renouvellement du token JWT d'accès | `{"refresh": "..."}` |
| `GET` | `/auth/me/` | Authentifié | Profil de l'utilisateur connecté | - |
| `POST` | `/auth/password/change/` | Authentifié | Modification du mot de passe | `{"old_password": "...", "new_password": "..."}` |

---

## 2. Espace Commerçant (`/merchant/`)

*Toutes les routes commerçant vérifient automatiquement l'appartenance au rôle `MERCHANT` et isolent les données du commerçant connecté.*

| Méthode | Route | Paramètres | Description |
|---|---|---|---|
| `GET` | `/merchant/dashboard/` | `preset=7d\|30d\|90d\|ytd` | Synthèse : KPIs, comparaison période précédente, tendances, mix cartes, alertes récentes |
| `GET` | `/merchant/transactions/` | `search`, `status`, `channel`, `start_date`, `end_date`, `page` | Liste paginée et filtrable des transactions |
| `GET` | `/merchant/transactions/{id}/` | - | Détail complet d'une transaction avec statut et code réponse |
| `GET` | `/merchant/transactions/export/` | `format=csv\|pdf`, filtres | Export certifié des transactions |
| `GET` | `/merchant/analytics/` | `preset`, `granularity=daily\|weekly\|monthly` | Évolution temporelle, répartition CIB/EDAHABIA, matrice heatmap 7j/24h |
| `GET` | `/merchant/collections/` | `preset` | Analyse des encaissements : montants nets, rejets, ticket moyen, comparaison |
| `GET` | `/merchant/alerts/` | `severity`, `status`, `rule_code` | Liste des alertes et recommandations générées |
| `POST` | `/merchant/alerts/{id}/read/` | - | Marquer une alerte comme lue |
| `POST` | `/merchant/alerts/read-all/` | - | Marquer l'ensemble des alertes comme lues |
| `POST` | `/merchant/alerts/evaluate/` | - | Déclencher une réévaluation manuelle des règles |
| `POST` | `/merchant/simulator/` | `volume_pct`, `ticket_delta` | Simulation d'impact sur le CA et projection temporelle 12 points |
| `GET` | `/merchant/profile/` | - | Données de l'établissement, statut et objectif mensuel |
| `PATCH`| `/merchant/profile/` | Coordonnées, `monthly_goal` | Mise à jour des informations et de l'objectif |

---

## 3. Espace Administrateur SATIM (`/admin/`)

*Réservé aux utilisateurs ayant le rôle `ADMIN` (`SUPER_ADMIN`, `ANALYST`, `VIEWER`).*

| Méthode | Route | Permission minimale | Description |
|---|---|---|---|
| `GET` | `/admin/dashboard/` | `VIEWER` | Supervision globale réseau : volume total, taux de succès, répartition du risque, tops commerçants |
| `GET` | `/admin/merchants/` | `VIEWER` | Registre national des commerçants, recherche multi-critères et filtres statut/MCC |
| `GET` | `/admin/merchants/{id}/` | `VIEWER` | Fiche détaillée commerçant avec historique et indicateurs |
| `POST` | `/admin/merchants/{id}/toggle-active/` | `SUPER_ADMIN` | Activation / désactivation avec saisie obligatoire d'un motif |
| `GET` | `/admin/transactions/` | `VIEWER` | Explorateur global de toutes les transactions du réseau |
| `GET` | `/admin/transactions/export/` | `VIEWER` | Export consolidé CSV de l'ensemble du réseau |
| `GET` | `/admin/risk/` | `VIEWER` | File des alertes de risque ordonnées par score de gravité décroissant |
| `GET` | `/admin/risk/{id}/` | `VIEWER` | Dossier d'investigation : score, règles déclenchées, snapshot et historique des notes |
| `POST` | `/admin/risk/{id}/status/` | `ANALYST` | Décision d'instruction (`NEW` ➔ `UNDER_REVIEW` ➔ `CONFIRMED` / `DISMISSED`) |
| `POST` | `/admin/risk/{id}/notes/` | `ANALYST` | Ajout d'une note qualitative d'investigation |
| `POST` | `/admin/reports/generate/` | `VIEWER` | Génération à la demande de rapports institutionnels (PDF ou CSV) |
| `GET` | `/admin/audit/` | `SUPER_ADMIN` | Journal infalsifiable d'audit des opérations sensibles |
| `GET` | `/admin/users/` | `SUPER_ADMIN` | Liste des comptes administrateurs SATIM |
| `POST` | `/admin/users/` | `SUPER_ADMIN` | Création d'un nouvel administrateur avec attribution de rôle |

---

## 4. Documentation OpenAPI
L'interface Swagger interactive est accessible en direct sur `/api/docs/`.
Le schéma OpenAPI brut au format JSON est disponible sur `/api/schema/`.
