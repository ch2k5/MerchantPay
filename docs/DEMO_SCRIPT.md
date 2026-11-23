# Scénario de Démonstration • MERCHANT PAY (≈ 5 minutes)

Guide pas à pas pour le jury du hackathon **FINOVIA × ENSM × SATIM**.

---

## 0. Préparation de la Démo

S'assurer que le backend et l'application web sont lancés :
```bash
# Dans le terminal 1 (Backend Django) :
cd backend && source ../venv/bin/activate && python manage.py runserver 8000

# Dans le terminal 2 (Frontend Flutter Web) :
cd mobile && flutter run -d chrome --web-port 3000
```
*(Le jeu de données est déjà initialisé avec `python manage.py seed_demo --seed 42`)*.

---

## 1. Connexion Commerçant (30 secondes)
1. Ouvrir l'application dans le navigateur (`http://localhost:3000`).
2. Sur la page de connexion, cliquer sur la puce de raccourci : **« Commerçant Démo (Café El Bahdja) »**.
   - Email : `demo@merchantpay.dz`
   - Mot de passe : `Demo@2026`
3. Cliquer sur **« Se connecter »**.
4. L'application redirige automatiquement vers l'**Espace Commerçant** (`/m/dashboard`).

---

## 2. Tableau de Bord & Encaissements (1 minute)
1. Observer les 4 cartes d'indicateurs clés :
   - Chiffre d'Affaires en Dinars Algériens (`formatDzd`, ex: `48 000,00 DZD`) avec delta % par rapport aux 30 jours précédents.
   - Volume de transactions traitées.
   - Taux d'acceptation du terminal.
   - Panier moyen.
2. Découvrir la courbe d'évolution temporelle avec la superposition de la période précédente en trait pointillé.
3. Observer l'anneau d'avancement de l'**Objectif Mensuel** (ex: 75% de 450 000 DZD).
4. Naviguer vers l'écran **« Encaissements »** (`/m/collections`) :
   - Présenter le tableau comparatif Période Actuelle vs Période Précédente avec les deltas calculés.
   - Lire la synthèse textuelle d'analyse automatique.

---

## 3. Transactions & Export Certifié (45 secondes)
1. Cliquer sur l'onglet **« Transactions »** (`/m/transactions`).
2. Dans le filtre par statut, sélectionner **« Rejetée »**.
   - La liste se met à jour instantanément pour afficher les transactions en échec avec leurs codes réponse SATIM (ex: `05` Refus bancaire, `51` Provision insuffisante).
3. Cliquer sur l'icône de détails d'une transaction pour ouvrir la fiche modale avec les métadonnées (TID, MID, Horodatage).
4. Cliquer sur **« Exporter PDF »** ou **« Exporter CSV »** pour démontrer la génération du bordereau comptable certifié.

---

## 4. Alertes Intelligentes & Explicabilité (45 secondes)
1. Naviguer vers l'onglet **« Alertes »** (`/m/alerts`).
2. Mettre en valeur les alertes générées par le moteur de règles :
   - Alerte critique **« Baisse de chiffre d'affaires détectée »**.
   - Alerte critique **« Hausse anormale des rejets de paiement »**.
3. Cliquer sur une alerte pour la déplier :
   - Montrer l'**action recommandée** concrète pour le commerçant.
   - Mettre en avant le bloc **« Pourquoi cette alerte ? »** affichant le snapshot des métriques exactes au déclenchement.
4. Cliquer sur **« Marquer comme lu »** ou utiliser le bouton **« Actualiser les règles »**.

---

## 5. Simulateur d'Activité Commerciale (1 minute)
1. Cliquer sur l'onglet **« Simulateur »** (`/m/simulator`).
2. Déplacer le curseur de volume à **+15 %** et le panier moyen à **+200 DZD**.
3. Constater la mise à jour réactive (débouncée à 300 ms) :
   - Comparaison côte à côte : *Carte Actuel* vs *Carte Simulé*.
   - Phrase de synthèse générée : *« Une progression de +15% du volume et de +200 DZD du panier générerait... »*.
   - Impact direct sur le franchissement de l'objectif mensuel.
   - Graphe de projection prédictive en 12 points.

---

## 6. Bascule Espace Administrateur SATIM & Gestion du Risque (1 minute 30)
1. Se déconnecter depuis le menu profil.
2. Sur la page de connexion, cliquer sur la puce **« Administrateur SATIM »** (`admin@satim.dz` / `Admin@2026`).
3. Découvrir la **Supervision Globale SATIM** (`/a/dashboard`) :
   - Volume total réseau, commerçants actifs, taux de succès global.
   - Donut de répartition du risque national (Faible, Modéré, Élevé).
   - Top commerçants par volume et commerçants à fort taux de rejet.
4. Ouvrir l'espace **« Risque & Fraude »** (`/a/risk`) :
   - Attirer l'attention du jury sur l'**avertissement légal et déontologique** obligatoire en haut d'écran.
   - Sélectionner le dossier prioritaire **TechZone Algérie** avec score **95 / 100** (Jauge rouge).
   - Cliquer sur **« Instruire le dossier »** :
     - Montrer l'explication transparente des règles déclenchées (`R_VELOCITY`, `R_AMOUNT_HIGH`, `R_FREQUENCY_ABNORMAL`, `R_HISTORY_DEVIATION`).
     - Modifier le statut en **« En cours d'instruction par SATIM »**.
     - Ajouter une note d'analyste : *« Contact téléphonique pris avec le gérant. Vérification des bordereaux en cours. »*.
5. Aller dans l'onglet **« Commerçants »** (`/a/merchants`) :
   - Rechercher un commerçant suspect et cliquer sur l'action de suspension.
   - Saisir le motif obligatoire : *« Suspicion de fraude avérée »*.
6. Aller dans le **« Journal d'audit »** (`/a/audit`) :
   - Constater que chaque action (changement de statut, note d'instruction, désactivation) a été inscrite de manière infalsifiable avec horodatage et adresse IP.
