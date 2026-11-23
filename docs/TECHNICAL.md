# Documentation Technique • MERCHANT PAY

Livrable technique officiel pour le hackathon **FINOVIA × ENSM × SATIM (Novembre 2026)**.

---

## 1. Présentation du Produit

**MERCHANT PAY** est une couche d'intelligence et de supervision monétique conçue pour valoriser les flux d'encaissement électroniques par cartes interbancaires (**CIB**) et carte **EDAHABIA** (Algérie Poste). 

Le produit ne traite pas les paiements (non-processeur) ; il ingère, modélise et transforme les données transactionnelles synthétiques pour délivrer :
- Une visibilité financière complète pour les commerçants algériens.
- Un moteur d'alertes proactives et de recommandations de croissance.
- Un simulateur d'activité commerciale interactif.
- Un système de surveillance du risque et de détection de comportements anormaux explicable pour les analystes de la SATIM.

---

## 2. Modèle de Données & Schéma Relationnel

### Entités Principales
- **`User` (`accounts_user`) :**
  - Authentification par email unique.
  - Rôles : `MERCHANT` ou `ADMIN`.
  - Niveaux d'administration : `SUPER_ADMIN`, `ANALYST`, `VIEWER`.
- **`Merchant` (`merchants_merchant`) :**
  - Raison sociale, numéro d'enregistrement (`legal_id` : RC ou NIF), nom de contact, téléphone.
  - Répartition géographique : Wilaya (58 wilayas), Commune.
  - Secteur d'activité : code MCC (Alimentation, Restauration, Électronique, Habillement, Santé, Transport, etc.).
  - Objectif mensuel de chiffre d'affaires (`monthly_goal` en DZD).
  - Statut : `ACTIVE` ou `INACTIVE`.
- **`Transaction` (`transactions_transaction`) :**
  - Référence unique alphanumérique (ex: `TX-20261123-8A7B`).
  - Terminal ID (`TID`), Merchant ID (`MID`).
  - Canal : `CIB` ou `EDAHABIA`.
  - Montant en Dinars Algériens (`amount`).
  - Statut : `COMPLETED`, `REJECTED`, `PENDING`.
  - Code réponse SATIM (ex: `00` Succès, `05` Refus bancaire, `51` Provision insuffisante).
  - Horodatage précis (`timestamp`).
- **`Alert` (`alerts_alert`) :**
  - Commerçant ciblé, sévérité (`INFO`, `WARNING`, `CRITICAL`), statut (`NEW`, `READ`, `DISMISSED`).
  - Code règle, titre explicite, message, recommandation d'action concrète.
  - Clé de déduplication temporelle (`dedupe_key`).
  - Snapshot JSON des métriques ayant déclenché l'alerte.
- **`RiskFlag` & `RiskNote` (`risk_riskflag`, `risk_risknote`) :**
  - Score heuristique consolidé de 0 à 100.
  - Statut : `NEW`, `UNDER_REVIEW`, `CONFIRMED`, `DISMISSED`.
  - Règles déclenchées (`triggered_rules` en JSON avec code, nom, description, points).
  - Thread d'investigation avec horodatage, auteur SATIM et notes qualitatives.
- **`AuditLog` (`audit_auditlog`) :**
  - Traçabilité des actions sensibles (connexion, changement de statut commerçant, décision de risque, export de rapport, création d'admin).

---

## 3. Moteurs Métier (Services Purs)

### A. Moteur d'Alertes Commerçant (`apps/alerts/rules.py`)
Le moteur évalue les écarts de performance sur des fenêtres glissantes et applique des règles déterministes :
1. **`REVENUE_DROP` (CRITICAL) :** Baisse du chiffre d'affaires ≥ 25% par rapport à la période précédente équivalente.
2. **`NO_ACTIVITY` (WARNING) :** Absence totale de transaction validée depuis plus de 48 heures pour un commerçant actif.
3. **`REJECTION_SPIKE` (CRITICAL) :** Taux de rejet ≥ 20% sur les 7 derniers jours (minimum 5 tentatives).
4. **`GOAL_PROGRESS` (INFO / WARNING) :** Atteinte remarquable (≥ 90%) ou retard significatif (< 50% après le 20 du mois) sur l'objectif mensuel défini.
5. **`PEAK_ACTIVITY` (INFO) :** Dépassement de 150% du volume habituel sur une plage horaire donnée.
6. **`CHANNEL_SHIFT` (INFO) :** Bascule soudaine de plus de 30 points de part entre paiements CIB et EDAHABIA.

*Déduplication :* Chaque alerte génère une clé canonique `{merchant_id}_{rule_code}_{window}` empêchant le spam d'alertes identiques.

### B. Moteur de Surveillance du Risque SATIM (`apps/risk/rules.py`)
Moteur heuristique déterministe et **100% explicable** attribuant des points selon des motifs transactionnels suspects :
1. **`R_VELOCITY` (+35 pts) :** Fréquence anormale de transactions rapprochées (≥ 5 transactions en moins de 10 minutes).
2. **`R_AMOUNT_HIGH` (+30 pts) :** Montant unitaire supérieur à 3 fois le panier moyen historique du commerçant ou ≥ 40 000 DZD.
3. **`R_REJECTION_SPIKE` (+25 pts) :** Plus de 3 rejets consécutifs ou taux de rejet supérieur à 40% sur la fenêtre.
4. **`R_FREQUENCY_ABNORMAL` (+15 pts) :** Activité inhabituelle en horaires nocturnes creux (01h00 - 05h00).
5. **`R_HISTORY_DEVIATION` (+15 pts) :** Volume cumulé sur 1 heure supérieur à la moyenne journalière standard.

**Interprétation du score (0 à 100) :**
- `0 - 39` : Risque Faible (Vert). Comportement nominal.
- `40 - 69` : Risque Modéré (Orange). Surveillance recommandée.
- `70 - 100` : Risque Élevé (Rouge). Alerte prioritaire, instruction d'analyste requise.

> **Avertissement déontologique :** Tout affichage du risque dans l'interface SATIM s'accompagne obligatoirement de la mention légale rappelant le caractère strictement indicatif de la détection et l'exigence d'une validation humaine avant toute décision.

### C. Simulateur d'Activité (`apps/simulator/services.py`)
Le simulateur permet au commerçant de tester des hypothèses de croissance :
$$\text{Chiffre d'Affaires Simulé} = (\text{Volume Actuel} \times (1 + \Delta_{\text{vol}})) \times (\text{Panier Moyen Actuel} + \Delta_{\text{panier}})$$
Il projette une courbe comparative en 12 points réguliers et calcule l'impact sur l'objectif mensuel.

---

## 4. Sécurité & Contrôle d'Accès

- **Authentification :** JWT (`access` valide 30 min, `refresh` valide 7 jours).
- **Contrôle d'accès basé sur les rôles (RBAC) :**
  - Commerçants cantonnés exclusivement aux données de leur propre `Merchant`.
  - Administrateurs SATIM accédant aux vues globales.
  - Actions destructives ou sensibles (activation/désactivation de commerçant, consultation du journal d'audit) strictement restreintes au rôle `SUPER_ADMIN`.
- **Auditabilité :** Chaque écriture sensible journalise l'adresse IP, le courriel de l'acteur, l'action normalisée et la cible dans `AuditLog`.

---

## 5. Exécution & Validation des Tests

- **Backend (Pytest) :**
  ```bash
  cd backend && pytest tests/ -v
  ```
  *Résultat : 29/29 tests passés (Coverage > 85%).*
- **Frontend (Flutter Test) :**
  ```bash
  cd mobile && flutter test
  ```
  *Résultat : 22/22 tests unitaires et widgets passés.*
