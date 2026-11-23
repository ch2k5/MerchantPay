# Description du Jeu de Données Synthétique • MERCHANT PAY

Livrable de modélisation des données pour le hackathon **FINOVIA × ENSM × SATIM**.

Le fichier généré est disponible à l'emplacement : `data/transactions_seed.csv`.

---

## 1. Paramètres & Méthodologie de Génération

Le jeu de données reproduit fidèlement la réalité des flux de paiement électronique en Algérie sur la période récente (90 jours d'historique jusqu'au 23/11/2026).

### A. Répartition Géographique (Wilayas)
Les commerçants sont distribués sur des pôles commerciaux représentatifs :
- 16 - Alger
- 31 - Oran
- 25 - Constantine
- 19 - Sétif
- 06 - Béjaïa
- 15 - Tizi Ouzou
- 09 - Blida
- 23 - Annaba
- 30 - Ouargla
- 13 - Tlemcen

### B. Canaux de Paiement & Répartition
- **CIB (Carte Interbancaire SATIM) :** ~50% des transactions, montant moyen ~5 500 DZD.
- **EDAHABIA (Algérie Poste) :** ~50% des transactions, montant moyen ~3 800 DZD.
- Le ratio varie naturellement selon le secteur d'activité (MCC).

### C. Secteurs Commerciaux (MCC)
- `5411` : Supermarchés & Alimentation générale (Panier 1 500 – 12 000 DZD)
- `5812` : Restaurants, Cafés & Fast-food (Panier 500 – 4 500 DZD)
- `5732` : Magasins d'Électronique & Informatique (Panier 8 000 – 95 000 DZD)
- `5651` : Prêt-à-porter & Habillement (Panier 3 000 – 25 000 DZD)
- `5912` : Pharmacies & Santé (Panier 800 – 6 500 DZD)
- `5541` : Stations-service & Carburant (Panier 1 000 – 4 000 DZD)
- `7011` : Hôtellerie & Hébergement (Panier 15 000 – 120 000 DZD)
- `4789` : Transport & Billetterie (Panier 1 200 – 15 000 DZD)

---

## 2. Scénarios Métier Spécifiques Injectés

Pour garantir une démonstration probante sans manipulation manuelle, des motifs comportementaux précis ont été introduits dans le générateur (`backend/apps/core/management/commands/seed_demo.py`) :

1. **Compte Commerçant Démo (`demo@merchantpay.dz` - Café El Bahdja, Alger) :**
   - **Baisse de Chiffre d'Affaires :** Chute de 30% des encaissements sur la dernière quinzaine par rapport aux 15 jours précédents (déclenche `REVENUE_DROP`).
   - **Pic de Rejets Techniques :** Série de 8 rejets bancaires consécutifs le 22/11/2026 (déclenche `REJECTION_SPIKE`).
   - **Objectif Mensuel :** Objectif fixé à 450 000 DZD avec avancement à ~75% (déclenche `GOAL_PROGRESS`).
2. **Scénario Fraude Aiguë (`TechZone Algérie`, Oran) :**
   - Commerçant informatique avec panier moyen habituel de 3 500 DZD.
   - Une vague soudaine de 12 transactions consécutives de 48 000 DZD chacune, réalisées entre 02h15 et 02h40 du matin.
   - **Résultat de détection :** Score de risque de **95 / 100** (déclenche simultanément `R_VELOCITY`, `R_AMOUNT_HIGH`, `R_FREQUENCY_ABNORMAL`, `R_HISTORY_DEVIATION`).
3. **Commerçant Inactif (`Librairie En-Nadjah`, Constantine) :**
   - Compte désactivé par SATIM pour illustrer le verrouillage de connexion avec message en français explicatif : `« Votre compte est désactivé. Contactez SATIM. »`.
   - Déclenche l'alerte `NO_ACTIVITY` côté supervision.
4. **Commerçants à Risque Modéré :**
   - Plusieurs commerçants présentant des scores entre 45 et 65 pour illustrer la segmentation visuelle (jauge orange, surveillance requise).

---

## 3. Schéma des Colonnes CSV (`data/transactions_seed.csv`)

| Colonne | Type | Exemple | Description |
|---|---|---|---|
| `reference` | Chaîne | `TX-20261123-A1B2` | Référence unique de la transaction |
| `merchant_id` | Entier | `1` | Identifiant du commerçant |
| `merchant_name` | Chaîne | `Café El Bahdja` | Raison sociale de l'enseigne |
| `terminal_id` | Chaîne | `TID-ALG-001` | Identifiant du TPE ou de la passerelle e-commerce |
| `channel` | Chaîne | `CIB` ou `EDAHABIA` | Réseau de la carte |
| `amount` | Décimal | `4800.00` | Montant brut en DZD |
| `status` | Chaîne | `COMPLETED` ou `REJECTED` | Résultat de la transaction |
| `response_code` | Chaîne | `00`, `05`, `51` | Code retour de l'autorisation SATIM |
| `timestamp` | ISO-8601 | `2026-11-23T14:35:10Z` | Date et heure de la transaction (UTC) |
