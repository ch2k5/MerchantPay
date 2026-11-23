# Hypothèses et Choix de Conception — MERCHANT PAY

Ce document consigne les choix d'architecture et de conception retenus pour le projet **MERCHANT PAY** (FINOVIA × ENSM × SATIM Hackathon) conformément aux directives de la spécification.

### 1. Temporalité et Fuseau Horaire
- **Fuseau horaire applicatif :** `Africa/Algiers` (UTC+1). Tous les horodatages en base sont stockés en UTC et convertis lors de la présentation ou du regroupement journalier.
- **Début de semaine :** Fixé au **Dimanche** (standard en Algérie et pour le système financier national), constant dans `core/dates.py`.
- **Date d'ancrage pour les démos :** L'évaluation des règles d'alertes et la détection des risques fonctionnent de manière dynamique par rapport à la date courante (ou date maximale du dataset). La commande `seed_demo` injecte des transactions relatives à la date courante afin que les scénarios (baisse de CA, pic de rejet, burst de risque) soient immédiatement visibles quel que soit le moment d'évaluation.

### 2. Modèle de Données & Monnaie
- **Monnaie :** Dinar Algérien (`DZD`), stocké strictement via `DecimalField(max_digits=14, decimal_places=2)`. Aucun calcul monétaire n'est réalisé en virgule flottante (`float`).
- **Canaux de paiement :** Deux cartes interbancaires autorisées : `CIB` et `EDAHABIA`.
- **Statuts de transaction :** `ACCEPTED`, `REJECTED`, `CANCELLED`, `REFUNDED`.
- **Taux de succès & échec :** Formule unifiée : `succès = acceptées / (acceptées + rejetées) * 100`. Les transactions annulées (`CANCELLED`) ne pénalisent pas le taux de réussite technique. Retourne 0 si le dénominateur est nul.

### 3. Rôles et Autorisations
- Deux rôles principaux : `MERCHANT` et `ADMIN`.
- Les commerçants n'ont accès qu'à leurs propres données, déduites automatiquement de `request.user.merchant`. Aucun identifiant `merchant_id` fourni par le client n'est pris en compte.
- Administrateurs SATIM :
  - `SUPER_ADMIN` : Tous droits, y compris activation/désactivation commerçant, gestion des utilisateurs admin et consultation des journaux d'audit.
  - `ANALYST` : Consultation globale, modification du statut des alertes de risque, ajout de notes d'investigation, génération de rapports.
  - `VIEWER` : Lecture seule sur l'ensemble de la plateforme administrative.

### 4. Moteur d'Alertes Commerçant
- Déduplication garantie par clé composite `(merchant, dedupe_key)` évitant toute alerte en double sur une même période.
- Horaires d'ouverture par défaut pour les créneaux creux : 08:00 à 22:00.

### 5. Moteur de Détection des Risques (Explainable Rule Engine)
- Rapprochement explicable par score cumulatif (0 à 100), seuil d'alerte fixé à 40.
- Aucun terme stigmatisant (« fraudeur ») n'est affiché : seul le terme « Activité suspecte détectée » est utilisé, accompagné de la mention de rappel légal/opérationnel.

### 6. Interface Utilisateur (Flutter)
- Monocodebase responsive (Mobile, Tablette, Web).
- Langue 100% français (`fr_FR`), formatage des devises avec séparateurs d'espace et virgule (ex: `48 000,00 DZD`).
- Charte graphique alignée sur SATIM : Rouge primaire `#E53A2F`, gris foncé `#1F1F1F`, vert succès `#1E9E5A`, orange alerte `#F5A524`.
