# MERCHANT PAY • Couche d'Intelligence Commerçants CIB & EDAHABIA

> **Projet Hackathon FINOVIA × ENSM × SATIM (Novembre 2026)**  
> Solution d'analyse, d'alertes proactives, de simulation d'activité et de détection explicable du risque pour les paiements électroniques en Algérie.

---

## Démarrage Rapide en 5 Commandes

```bash
# 1. Cloner et se placer dans le projet
cd merchant-pay

# 2. Démarrer les services (PostgreSQL & Backend Django)
make up

# 3. Initialiser la base de données et charger le jeu de données calibré
make seed

# 4. Exécuter l'ensemble des tests (Backend Django + Frontend Flutter)
make test

# 5. Lancer l'application Web & Mobile responsive
make run-web
```

- **Application Web Flutter :** [http://localhost:8080](http://localhost:8080)
- **API REST Django :** [http://localhost:8000/api/v1/](http://localhost:8000/api/v1/)
- **Documentation OpenAPI / Swagger :** [http://localhost:8000/api/docs/](http://localhost:8000/api/docs/)

---

## Comptes & Accès de Démonstration

Des puces de pré-remplissage rapide sont disponibles directement sur l'écran de connexion :

| Espace | Email | Mot de passe | Rôle & Permissions |
|---|---|---|---|
| **Espace Commerçant** | `demo@merchantpay.dz` | `Demo@2026` | Commerçant (Café El Bahdja, Alger) - Baisse de CA, pic de rejets, objectif |
| **Espace SATIM** | `admin@satim.dz` | `Admin@2026` | Administrateur Principal (`SUPER_ADMIN`) - Gestion globale, blocage, audit |
| **Espace SATIM** | `analyste@satim.dz` | `Admin@2026` | Analyste Risque (`ANALYST`) - Instruction des dossiers de risque, notes |
| **Espace SATIM** | `viewer@satim.dz` | `Admin@2026` | Observateur (`VIEWER`) - Consultation & Rapports |

---

## Documentation Complète

L'ensemble des livrables documentaires est structuré dans le dossier `docs/` :
- [`docs/ARCHITECTURE.md`](file:///home/ch2k5/Documents/finovia%20hackathon/merchant-pay/docs/ARCHITECTURE.md) : Diagrammes Mermaid des flux, architecture en couches "Thin Views, Fat Services" et responsivité Flutter.
- [`docs/TECHNICAL.md`](file:///home/ch2k5/Documents/finovia%20hackathon/merchant-pay/docs/TECHNICAL.md) : Modèle de données, règles d'alerte, moteur de détection heuristique explicable 0-100 et formulation mathématique du simulateur.
- [`docs/API.md`](file:///home/ch2k5/Documents/finovia%20hackathon/merchant-pay/docs/API.md) : Catalogue exhaustif des endpoints DRF avec permissions et formats.
- [`docs/DATASET.md`](file:///home/ch2k5/Documents/finovia%20hackathon/merchant-pay/docs/DATASET.md) : Méthodologie du jeu de données synthétique, répartition 50/50 CIB vs EDAHABIA et scénarios injectés (TechZone 95/100, etc.).
- [`docs/DEMO_SCRIPT.md`](file:///home/ch2k5/Documents/finovia%20hackathon/merchant-pay/docs/DEMO_SCRIPT.md) : Scénario chronométré pas à pas pour la présentation au jury (≈ 5 minutes).
- [`docs/ASSUMPTIONS.md`](file:///home/ch2k5/Documents/finovia%20hackathon/merchant-pay/docs/ASSUMPTIONS.md) : Choix de conception et hypothèses retenues.
- [`data/transactions_seed.csv`](file:///home/ch2k5/Documents/finovia%20hackathon/merchant-pay/data/transactions_seed.csv) : Fichier de données brutes synthétiques généré.

---

## Commandes Utiles (Makefile)

```bash
make test         # Lance pytest (29 tests) et flutter test (22 tests)
make test-cov     # Rapport de couverture de code (Coverage > 85%)
make seed         # Génération déterministe avec seed 42
make lint         # Vérification du code avec ruff et flutter analyze
make format       # Formatage automatique ruff, black et dart format
make clean        # Nettoyage des caches et artefacts temporaires
```
